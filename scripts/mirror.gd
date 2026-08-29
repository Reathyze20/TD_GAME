extends Node
## AUTOLOAD: Mirror — the behavioural event log behind the post-level receipt.
##
## One append-only array of {t, ev, data}. Everything the receipt shows is a QUERY over
## that array, never a counter maintained by hand at the call site. That split is the
## whole point: adding a statistic later costs a query, not a new variable threaded
## through game.gd, and a statistic nobody thought of yet is still recoverable from a
## log that was already being written.
##
## NOT the same thing as RunLog (scripts/run_log.gd), which appends per-wave BOARD state
## to user://runlog.csv for balance tuning. This records what the PLAYER did — clicks,
## hesitations, reaches for the cheap button — because the lesson is about behaviour and
## behaviour is not visible in a wave summary.
##
## Everything stays on disk local to the machine (user://mirror.json) and the game says
## so on the final receipt. That sentence is itself the last lesson, so the promise has
## to be true.

const SAVE_PATH := "user://mirror.json"

## Per-level summaries, level_id -> Dictionary of the queries below. Kept across
## sessions so the receipt can pair "level 1 → now", which is what makes a number mean
## anything: a lone "prep phase 3s" says nothing, "22s → 3s" is the whole lesson.
var history: Dictionary = {}

var _events: Array[Dictionary] = []
var _t := 0.0
var _level_id := 0
var _recording := false

# Marks that need a paired "what happened next" lookup keep their own cursor rather than
# rescanning the log — a level ends with a few thousand events and the receipt runs
# several of these.
var _cue_pending_t := -1.0
var _threat_pending_t := -1.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load()

func _process(delta: float) -> void:
	if _recording:
		# Unscaled: the whole point of the speed statistic is that 2x buys more waves per
		# REAL minute. Measuring in scaled time would erase exactly the thing being taught.
		_t += delta / maxf(Engine.time_scale, 0.0001)

# ---------------------------------------------------------------- recording

## Designer runs never record, matching the RunLog rule in game.gd — cheat keys would
## make every statistic a lie, and the receipt's credibility is the product.
func begin_level(level_id: int) -> void:
	_events.clear()
	_t = 0.0
	_level_id = level_id
	_cue_pending_t = -1.0
	_threat_pending_t = -1.0
	_recording = not GameState.designer_mode

func mark(ev: StringName, data = null) -> void:
	if not _recording:
		return
	_events.append({"t": _t, "ev": ev, "data": data})
	match ev:
		&"cue_flash":
			_cue_pending_t = _t
		&"threat_shown":
			_threat_pending_t = _t

## A click resolves whichever reaction window is open. Recorded as its own event so the
## raw log stays complete, but the reaction time is computed here while the pairing is
## still cheap.
func mark_click(what: StringName = &"field") -> void:
	if not _recording:
		return
	if _cue_pending_t >= 0.0 and what == &"cue":
		_events.append({"t": _t, "ev": &"cue_reaction", "data": _t - _cue_pending_t})
		_cue_pending_t = -1.0
	if _threat_pending_t >= 0.0 and what == &"threat":
		_events.append({"t": _t, "ev": &"threat_reaction", "data": _t - _threat_pending_t})
		_threat_pending_t = -1.0
	_events.append({"t": _t, "ev": &"click", "data": what})

func end_level() -> void:
	if not _recording:
		return
	_recording = false
	var summary := summarise()
	# Keyed by level id, so replaying a level overwrites its row rather than appending a
	# second one — the receipt pairs level 1 against the LATEST run of the current level.
	history[str(_level_id)] = summary
	_save()

func is_recording() -> bool:
	return _recording

func level_time() -> float:
	return _t

# ---------------------------------------------------------------- queries

func count(ev: StringName) -> int:
	var n := 0
	for e in _events:
		if e["ev"] == ev:
			n += 1
	return n

## Mean of the payload of every occurrence of `ev`, or -1.0 when it never happened.
## -1.0 rather than 0.0 because "never reacted" and "reacted instantly" are opposite
## findings and the receipt must not print them the same way.
func mean(ev: StringName) -> float:
	var total := 0.0
	var n := 0
	for e in _events:
		if e["ev"] == ev and e["data"] != null:
			total += float(e["data"])
			n += 1
	return -1.0 if n == 0 else total / float(n)

## Payload of the LAST occurrence of `ev`, or -1.0 when it never happened.
##
## Needed for readings that are a running STATE rather than a rate: cue conditioning
## ends the level at whatever it grew to, and averaging it with its own early values
## would report a number the player never actually had.
func last(ev: StringName) -> float:
	for i in range(_events.size() - 1, -1, -1):
		var e: Dictionary = _events[i]
		if e["ev"] == ev and e["data"] != null:
			return float(e["data"])
	return -1.0

## Highest payload `ev` ever carried, or -1.0 when it never happened. For readings whose
## finding is the PEAK rather than the total or the average — the longest streak matters,
## the sum of every streak length along the way does not.
func peak(ev: StringName) -> float:
	var best := -1.0
	for e in _events:
		if e["ev"] == ev and e["data"] != null:
			best = maxf(best, float(e["data"]))
	return best

## Fraction of the level spent above 1x. Walks speed_changed marks pairwise and closes
## the final span at the current time, so an unfinished level still reports honestly.
func speed_fraction() -> float:
	if _t <= 0.0:
		return 0.0
	var fast := 0.0
	var last_t := 0.0
	var last_speed := 1.0
	for e in _events:
		if e["ev"] != &"speed_changed":
			continue
		if last_speed > 1.0:
			fast += e["t"] - last_t
		last_t = e["t"]
		last_speed = float(e["data"])
	if last_speed > 1.0:
		fast += _t - last_t
	return clampf(fast / _t, 0.0, 1.0)

## Mean seconds between a wave clearing and the player calling the next one — the
## boredom-tolerance number. Spans are recorded closed by game.gd, so this is a plain
## average of the payloads.
func prep_seconds() -> float:
	return mean(&"prep_span")

## Share of delay-discount offers where the player waited for the larger payout.
## 1.0 = always patient. -1.0 = never offered.
func patience() -> float:
	var now := count(&"offer_now")
	var later := count(&"offer_later")
	if now + later == 0:
		return -1.0
	return float(later) / float(now + later)

func summarise() -> Dictionary:
	return {
		"level": _level_id,
		"seconds": _t,
		"quick_hits": count(&"quick_hit"),
		"ads_shown": count(&"ad_shown"),
		"ads_tapped": count(&"ad_tapped"),
		"ad_seconds": _sum(&"ad_span"),
		"cue_flashes": count(&"cue_flash"),
		"cue_reactions": count(&"cue_reaction"),
		"cue_reaction_time": mean(&"cue_reaction"),
		"threat_reaction_time": mean(&"threat_reaction"),
		"prep_seconds": prep_seconds(),
		"speed_fraction": speed_fraction(),
		"patience": patience(),
		"clicks": count(&"click"),
		"leaks": count(&"leak"),
		# Taxonomy archetypes (docs/design/dopamine_mechanics.md 5.9). `bait_kills` is the
		# one worth the most: the damage those bodies would have done is not an estimate,
		# it is zero by definition, so the receipt can state it without arguing.
		# Where the cue association ENDED the level. Paired against Tolerance on the
		# receipt, because the two moving in opposite directions is the whole finding.
		"cue_pull": last(&"cue_pull"),
		# Effort discounting. `aim_surrendered` is the mean ArcProfile damage multiplier
		# the player's own aiming was worth at the moment they handed it over — 1.0 means
		# they were sitting at the home angle and gave up nothing at all.
		# The streak. `streak_lost` is the size of the BIGGEST one that broke, which is a
		# different number from the longest one held — a player who never leaked has a
		# best and no loss, and the receipt must not confuse the two.
		"streak_best": peak(&"streak"),
		"streak_breaks": count(&"streak_broken"),
		"streak_lost": peak(&"streak_broken"),
		"auto_aim_waves": count(&"auto_aim_wave"),
		"aim_surrendered": mean(&"auto_aim_on"),
		"cue_reinstatements": count(&"cue_reinstated"),
		"bait_kills": count(&"bait_kill"),
		"bait_expired": count(&"bait_expired"),
		"splits": count(&"split"),
		"autoplay_thefts": count(&"autoplay_stole_prep"),
	}

## The baseline every paired reading is measured against: the EARLIEST level this player
## has a record for, excluding the one they just finished.
##
## Deliberately not hardcoded to level 1. The campaign's level ids are not a promise —
## the isometric branch numbers its slice 99 and has no playable level 1 at all — and a
## receipt that silently shows nothing because it was looking for a row that will never
## exist is worse than one that admits it has no baseline yet. "Earliest played" is also
## the honest reading of the doc's "level 1 → now": what is being compared is the player
## then against the player now, not two particular level ids.
func baseline_row(exclude_level: int = -1) -> Dictionary:
	var best_id := -1
	for key in history.keys():
		var id := int(key)
		if id == exclude_level:
			continue
		if best_id < 0 or id < best_id:
			best_id = id
	return history.get(str(best_id), {}) if best_id >= 0 else {}

## The paired reading the receipt is built on: this level's value next to the same value
## from the baseline level. Returns {now, first, has_first}.
func paired(key: String) -> Dictionary:
	var now = summarise().get(key, 0.0)
	var first_row := baseline_row(_level_id)
	return {
		"now": now,
		"first": first_row.get(key, 0.0),
		"has_first": first_row.has(key),
	}

func _sum(ev: StringName) -> float:
	var total := 0.0
	for e in _events:
		if e["ev"] == ev and e["data"] != null:
			total += float(e["data"])
	return total

# ---------------------------------------------------------------- persistence

func _save() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(history))
	f.close()

func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		history = parsed

## Wipes the local history. Wired to the settings screen so the promise "this never
## leaves your machine" comes with the ability to delete it — a claim about data the
## player cannot act on is a slogan, not a guarantee.
func forget() -> void:
	history.clear()
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
