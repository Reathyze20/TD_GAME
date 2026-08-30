class_name SaveGame
extends Resource
# Serializable save resource storing meta progression, Insight & Clarity Stars.
# Stored at user://savegame.tres (never res:// which is read-only in builds).
#
# Adding an @export here is backwards compatible: a save written before the field
# existed simply loads it at its default. That's why `unlocked_growth` still exists —
# see migrate(), which folds old boolean unlocks into the ranked format.

## Spendable meta currency. Collected during a run (GameState.run_insight), partly spent
## there on draft cards, and whatever survives is banked here — won or lost. See
## MetaProgression.bank_run().
@export var insight: int = 0
## Lifetime Insight earned, never spent down. Display/achievement only.
@export var lifetime_insight: int = 0

## Growth node id (String) -> owned rank (int, >= 1). Absent key means not owned.
@export var growth_ranks: Dictionary = {}

## Legacy pre-rank unlock list. Read once by migrate(), then kept in sync for anything
## still asking "do I own this at all".
@export var unlocked_growth: Array[String] = []

@export var total_clarity_stars: int = 0
@export var unlocked_levels: Array[String] = ["Level_01", "Level_02", "Level_03"]
## Best stars (1-3) earned per level, keyed by id e.g. "Level_01". Separate from
## total_clarity_stars, which is cumulative and never decreases on replay.
@export var level_stars: Dictionary = {}
## Level ids already beaten at least once — gates the one-time first-clear Insight bonus
## so replaying a level can't farm it.
@export var cleared_levels: Array[String] = []

## MapSegmentData.unlock_condition flags the player has earned (P8, docs/refactor/
## PATHFINDING.MD). A set stored as a list, read only by MetaProgression.is_segment_
## unlocked(); a flag in here means every map segment carrying that condition is part of
## the board from now on.
##
## Its own list rather than a reuse of `cleared_levels` or `growth_ranks`, decided
## 2026-08-30: the map growing is meta progress that must survive a LOST run, so it
## cannot be per-level-completion, and it must not be something Insight buys, so it
## cannot be a Growth node. Empty by default, which means an untouched save composes
## every level down to its unconditional spine.
@export var unlocked_segments: Array[String] = []

## --- Settings (persisted preferences, not progression) ---
## Linear 0..1 master SFX volume, applied to the "Sfx" audio bus by the Sfx autoload.
@export var sfx_volume: float = 1.0
@export var sfx_muted: bool = false
## Linear 0..1 master music volume, applied to the "Music" bus by the Music autoload.
## Its own slider rather than a share of sfx_volume: the music carries Satisfaction and
## a player who mutes the soundscape would otherwise lose that channel silently.
@export var music_volume: float = 0.7
@export var music_muted: bool = false
@export var fullscreen: bool = false
## Contextual one-shot hints: master toggle + which hint ids have already been shown.
@export var hints_enabled: bool = true
@export var hints_seen: Array[String] = []

const SAVE_PATH := "user://savegame.tres"

static func save_exists() -> bool:
	return ResourceLoader.exists(SAVE_PATH)

static func load_save() -> SaveGame:
	if save_exists():
		# CACHE_MODE_IGNORE, not the default REUSE: ResourceLoader caches by path, so
		# once anything in this process has loaded SAVE_PATH once (MetaProgression's
		# own _ready() always does, at boot), a later load_save() call with the
		# default cache mode silently returns that SAME STALE object instead of
		# re-reading whatever write_savegame() most recently wrote to disk.
		#
		# CACHE_MODE_REPLACE looks like the fix but is NOT enough: it still hands back
		# the SAME cached object instance (verified — get_instance_id() matches across
		# calls) and only overwrites the fields the file explicitly mentions.
		# ResourceSaver omits any @export field that equals its script-declared
		# default (e.g. `sfx_muted = false` never appears in the .tres at all) — so a
		# field that goes from non-default to default between two saves keeps its
		# STALE prior value forever under REPLACE, silently. IGNORE is the one mode
		# that returns a genuinely fresh instance, so an omitted field correctly falls
		# back to its real script default instead of an old cached value.
		#
		# Both failure modes are invisible in normal play (one load_save() call per
		# process launch — nothing to be stale relative to yet) but are exactly what
		# saving and reloading within a single run does. Found by
		# scripts/_test_save_round_trip.gd (S8, docs/refactor/SYSTEMS.MD).
		var res = ResourceLoader.load(SAVE_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
		if res is SaveGame:
			var save: SaveGame = res
			save.migrate()
			return save
	return SaveGame.new()

## Brings an older save up to the current schema. Runs on every load and must stay
## idempotent — it is cheap and running it twice has to be harmless.
func migrate() -> void:
	# Pre-rank saves stored unlocks as a flat id list; every such unlock is rank 1.
	for id: String in unlocked_growth:
		if not growth_ranks.has(id):
			growth_ranks[id] = 1
	# Pre-Insight saves have stars but no Insight. Refund something rather than
	# wiping the player's progress: their old stars buy into the new tree.
	if insight == 0 and lifetime_insight == 0 and total_clarity_stars > 0:
		insight = total_clarity_stars * 40
		lifetime_insight = insight
	# level_stars keys are levels that were beaten, so first-clear bonuses are already
	# spent for them — otherwise an old save would re-earn every one of them.
	if cleared_levels.is_empty() and not level_stars.is_empty():
		for id in level_stars.keys():
			cleared_levels.append(String(id))
	# A hand-edited or corrupted volume outside 0..1 would silently blow out or kill
	# the mix — clamping here keeps migrate() idempotent and the audio path safe.
	sfx_volume = clampf(sfx_volume, 0.0, 1.0)
	music_volume = clampf(music_volume, 0.0, 1.0)

func write_savegame() -> void:
	ResourceSaver.save(self, SAVE_PATH)
