extends Node
# Autoload "Data": loads every .tres under res://data/ once at startup and exposes it
# through typed getters. Balancing now happens by editing .tres resources in the
# Inspector (or adding new ones) rather than editing this file.
# Target Canvas Resolution: 1920x1080 (1080p widescreen canvas)

## 40x19 grid = 1920x912px. origin_y must clear the top HUD bar, or row 0 renders behind
## it — and row 0 is a spawn row on both levels, so distractions would appear from under
## the chrome. Keep this >= Game._HUD_TOP_H; the grid then ends at 68+912 = 980, just
## above the bottom bar at 1080-96 = 984.
const GRID := {
	"cols": 24,
	"rows": 24,
	"tile": 32,
	"tile_w": 64,
	"tile_h": 32,
	"origin_x": 960,
	"origin_y": 120,
}

## Kolik BUNEK ma strana jednoho stavebniho bloku.
## Stavi se na BLOKY 3x3. Klic bloku je jeho PROSTREDNI bunka (3x+1, 3y+1).
const BUILD_BLOCK := 3


## Prostredni bunka bloku, do ktereho `cell` spada -- klic do Game.build_spots.
## Kdokoli prevadi pozici mysi na stavebni misto, musi projit tudy.
static func build_block(cell: Vector2i) -> Vector2i:
	var b := BUILD_BLOCK
	return Vector2i(
		int(floorf(float(cell.x) / b)) * b + b / 2,
		int(floorf(float(cell.y) / b)) * b + b / 2)

## Canonical grid <-> pixel converters (2:1 diamond isometric projection).
## Unified single source of truth for grid coordinate conversions.
static func cell_center(cell: Vector2i) -> Vector2:
	var g = GRID
	var tw: float = float(g.get("tile_w", 64))
	var th: float = float(g.get("tile_h", 32))
	var ox: float = float(g.origin_x)
	var oy: float = float(g.origin_y)
	return Vector2(
		ox + (cell.x - cell.y) * (tw * 0.5),
		oy + (cell.x + cell.y + 1) * (th * 0.5))

static func world_to_cell(pos: Vector2) -> Vector2i:
	var g = GRID
	var tw: float = float(g.get("tile_w", 64))
	var th: float = float(g.get("tile_h", 32))
	var dx: float = pos.x - float(g.origin_x)
	var dy: float = pos.y - float(g.origin_y)
	var col := int(floorf(dx / tw + dy / th))
	var row := int(floorf(dy / th - dx / tw))
	return Vector2i(clampi(col, 0, int(g.cols) - 1), clampi(row, 0, int(g.rows) - 1))

static func in_bounds(c: Vector2i) -> bool:
	var g = GRID
	return c.x >= 0 and c.x < int(g.cols) and c.y >= 0 and c.y < int(g.rows)

## Edge of one terrain tile in ART pixels. The tileset pipeline (tools/tiles.py) is built
## around this number; changing it means regenerating every tile.
##
## HISTORIE A JEDNA DULEZITA OPRAVA
##
## 16 (x3) -> 24 (x2) 17. 8. 2026 -> zpet 16 (x1) 18. 8. 2026, tentokrat i s bunkou.
##
## Ta prostredni zmena NIKDY NEPLATILA. Cislo se prepsalo na 24, ale nainstalovany
## `assets/terrain/high_ground_atlas.png` zustal 16px artem (tiles.py atlas uklada
## v pixelech OBRAZOVKY, takze 16px art lezi v souboru nafouknuty do 48 a na prvni
## pohled vypada jako 48px art). Teren tedy cely cas bezel na x3, zatimco sprity na x2
## -- presne ta nejednotnost, kterou tenhle komentar sliboval odstranit. Zmereno
## 18. 8. 2026: v atlasu je nejvetsi jednolity blok 3x3.
##
## PONAUCENI: tohle cislo se neda zmenit editaci teto radky. Musi se pri tom
## PREGENEROVAT ATLAS (tools/tiles.py instaluj), jinak se rozejde s tim, co je na disku.
##
## THE GOAL WAS A SMALLER PIXEL, NOT A BIGGER CREATURE. Measured against the 1623
## PixelLab originals in build/pixellab: a character there stands 59 art px tall, ours
## stood 29. But simply doubling the art (16 -> 32 art px per cell) keeps the SCREEN
## pixel at three physical pixels and makes every creature twice as large instead —
## the opposite of what was wanted. The screen pixel is what reads as "blocky", and it
## is GRID.tile / TERRAIN_ART_PX, not the sprite's own size.
##
## So the divisor moves and the cell does not:
##
##     cell        48 screen px   (unchanged, so the board stays 40x19)
##     art/cell    16 -> 24
##     scale       x3 -> x2       (a third finer)
##     character   2 cells = 48 art px = 96 screen px  (unchanged on screen)
##     boss        4 cells = 96 art px = 192 screen px (unchanged on screen)
##
## Nothing else in the game moves: every range, radius and speed is in screen pixels
## and the screen did not change. Neither did the HUD.
##
## WHY NOT x1.5 (which would have kept 16 art px and doubled nothing): non-integer
## scaling is the one thing pixel art cannot survive. Between x3 and x2 there is
## nothing, so x2 is as fine as a 1920px canvas allows without shrinking the board.
##
## WHY 48 px OF ART AND NOT 64: PixelLab delivers 64. Measured on 111 sprites, the
## chain NEAREST -> clean(24) -> outline_sprite takes 64 down to 48 at grade 9.00,
## noise 0.200 and outline +0.191 — ABOVE the reference bar. The same chain to 32 falls
## to 7.8. 64 -> 48 is the one reduction that survives, which is why the target is 48.
const TERRAIN_ART_PX := 16

## Screen pixels per ART pixel — the raster of the whole map, not of any one sprite.
##
## THE rule of pixel art, and the one this project was quietly breaking. The terrain draws
## 16px tiles into 48px cells, so one art pixel is three screen pixels on the ground.
## Anything drawn at a different scale has FINER pixels than the floor it stands on, and
## reads as pasted onto the picture instead of being in it — no amount of contact shadow
## or glow fixes that, because the mismatch is in the raster itself.
##
## Every creature, defender and tower head used to hardcode 2.0 in three separate files
## while the ground ran at 3.0. They all ask here now, so the world cannot drift apart
## again: move GRID.tile or TERRAIN_ART_PX and the art follows on its own.
static func pixel_scale() -> float:
	return maxf(1.0, floorf(float(GRID["tile"]) / float(TERRAIN_ART_PX)))

# UI display order — not gameplay balance data, so these stay plain id lists here
# rather than becoming their own Resource type.
## Build-panel order and hotkey assignment (index + 1). Every entry needs a matching
## `td_habit_<n>` action in project.godot — Input.is_action_just_pressed() on a missing
## action errors every frame, so the two lists must grow together.
const HABIT_ORDER: Array[StringName] = [&"focus_timer", &"mindfulness", &"exercise", &"real_hobby", &"zen_pulsar", &"accountability", &"anchor", &"focus_pillar"]

## Slot-cycling order for the Nutrition Guild's recipe buttons, and the default recipe
## a fresh guild opens with (one of each, in this order). Same contract as HABIT_ORDER:
## display/UX ordering lives here, balance lives in the .tres files.
const DEFENDER_ORDER: Array[StringName] = [&"broccoli_knight", &"avocado_monk",
	&"chilli_berserker", &"garlic_mage"]
const INTERVENTION_ORDER: Array[StringName] = [&"screen_break", &"deep_breath",
	&"call_a_friend", &"airplane_mode", &"moment_of_clarity"]

# ---------------------------------------------------------------- draft rarities
#
# The rarity ladder. `order` is the ranking used everywhere (sorting, "is this better
# than that" checks, odds-curve columns) so the dictionary's own key order never
# matters. Adding a tier = one entry here + one column in DRAFT_ODDS + cards carrying
# the new id; nothing else reads a hardcoded rarity name.
#
# `price` is the Insight a card of that band costs at the draft. Prices are calibrated
# against a full level-1 run's income (~81 Insight, see GameState): a Breakthrough is
# most of a level's earnings, a Common is pocket change. That spread is the whole point —
# Insight is also the Growth Tree's currency, so every card bought is tree progress
# given up, and the trade has to be steep enough to actually hurt sometimes.
const RARITIES := {
	&"common":    {"display": "Common",       "color": "9aa3b8", "order": 0, "price":  6},
	&"rare":      {"display": "Rare",         "color": "4aa3ff", "order": 1, "price": 12},
	&"legendary": {"display": "Legendary",    "color": "ffd479", "order": 2, "price": 20},
	&"diamond":   {"display": "Breakthrough", "color": "7ef2e6", "order": 3, "price": 32},
}

const DEFAULT_RARITY: StringName = &"common"

# Relative weights per draft number (1-based), rolled independently for each card slot
# so one draft can show a mixed hand — the same shape as TFT's stage-based augment odds.
# Later drafts skew rich: a Breakthrough pulled in draft 1 trivialises the level, the
# same card in the pre-boss draft is the run's best moment.
#
# Rows are looked up by draft number and CLAMPED to the last row, so a longer level
# just keeps rolling the final row — no need to extend this table when levels grow.
const DRAFT_ODDS: Array[Dictionary] = [
	{&"common": 70.0, &"rare": 28.0, &"legendary":  2.0, &"diamond":  0.0},
	{&"common": 45.0, &"rare": 42.0, &"legendary": 12.0, &"diamond":  1.0},
	{&"common": 25.0, &"rare": 45.0, &"legendary": 26.0, &"diamond":  4.0},
	{&"common": 10.0, &"rare": 40.0, &"legendary": 40.0, &"diamond": 10.0},
]

const DRAFT_OPTIONS_BASE := 3

# ---------------------------------------------------------------- player vocabulary
#
# The theme lives in the NOUNS — Habit, Distraction, Dopamine, Focus, Insight. Those a
# player picks up from context in one level and they carry the whole concept.
#
# The MECHANICS use the words every tower-defense player already knows. Bespoke names
# for damage types and status effects (Willpower/Awareness/Compulsion/Rationalization/
# Calm/Interrupt/Boredom/Reframe) cost the player a translation step on every single
# card, mid-fight, and paid nothing back — the theme was already carried by the nouns.
#
# One table, so redialing any of this is a one-line change and cannot drift between the
# card text, the habit panel and the tooltips the way the old hardcoded strings did.
const TERM := {
	"damage":       "damage",             # was "Willpower damage"
	"mind_damage":  "mind damage",        # was "Awareness damage"
	"armor":        "armor",              # was "Compulsion"
	"slow":         "slow",               # was "Calm"
	"dot":          "damage over time",   # was "Boredom"
	"stun":         "freeze",             # hard stun — plainer than "stun" for this game
	"dispel":       "clears speed boosts",
	"vulnerable":   "damage taken",
}

# ---------------------------------------------------------------- growth tree
#
# Branch metadata for the Growth Tree. Nodes declare which branch they belong to, so
# adding a node never means editing a list here — only adding a whole new branch does.
const GROWTH_BRANCHES := {
	&"discipline": {"display": "Discipline", "color": "ff8b6b", "order": 0,
		"blurb": "Habits that hit harder."},
	&"awareness":  {"display": "Awareness",  "color": "9bd0ff", "order": 1,
		"blurb": "See the distraction before it lands."},
	&"recovery":   {"display": "Recovery",   "color": "7cffb2", "order": 2,
		"blurb": "Dopamine, tolerance, and second chances."},
}

var _distractions: Dictionary = {}       # StringName -> DistractionData
var _habits: Dictionary = {}             # StringName -> HabitData
var _defenders: Dictionary = {}          # StringName -> DefenderData
var _cards: Dictionary = {}              # StringName -> CardData
var _interventions: Dictionary = {}      # StringName -> InterventionData
var _growth_nodes: Dictionary = {}       # StringName -> GrowthNodeData
var _insight_cards: Dictionary = {}      # int (level_id) -> InsightCardData
var _levels: Array[LevelData] = []       # sorted by .id ascending

var _cards_by_rarity: Dictionary = {}    # StringName -> Array[CardData]
var _growth_by_branch: Dictionary = {}   # StringName -> Array[GrowthNodeData], tier-sorted
var _habit_root: Dictionary = {}         # StringName -> StringName (tier-1 id of its upgrade line)

func _ready() -> void:
	_distractions = _load_indexed("res://data/distractions/")
	_habits = _load_indexed("res://data/habits/")
	_defenders = _load_indexed("res://data/defenders/")
	_cards = _load_indexed("res://data/cards/")
	_interventions = _load_indexed("res://data/interventions/")
	_growth_nodes = _load_indexed("res://data/growth/")
	_index_cards_by_rarity()
	_index_growth_by_branch()
	_index_habit_families()

	for res: InsightCardData in _list_files("res://data/insight_cards/"):
		_insight_cards[res.level_id] = res

	for res: LevelData in _list_files("res://data/levels/"):
		res.waves = build_waves(res)
		_levels.append(res)
	_levels.sort_custom(func(a: LevelData, b: LevelData): return a.id < b.id)

## Loads every .tres directly inside `dir_path`, keyed by each resource's `id` field.
func _load_indexed(dir_path: String) -> Dictionary:
	var out := {}
	for res: Resource in _list_files(dir_path):
		out[res.id] = res
	return out

## Loads every .tres directly inside `dir_path` as a plain list, no indexing assumed —
## for resource types that don't have a uniform `id` field (InsightCardData, LevelData).
func _list_files(dir_path: String) -> Array:
	var out := []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_warning("Data: no such directory %s" % dir_path)
		return out
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".tres"):
			out.append(load(dir_path + file_name))
		file_name = dir.get_next()
	dir.list_dir_end()
	return out

func get_distraction(id: StringName) -> DistractionData:
	return _distractions.get(id)

func get_habit(id: StringName) -> HabitData:
	return _habits.get(id)

func get_defender(id: StringName) -> DefenderData:
	return _defenders.get(id)

## Tier-1 root of a habit's upgrade line ("focus_timer_2" -> "focus_timer"), derived
## from the `upgrades` arrays in the .tres data — no separate family table to drift.
## Card targeting matches by FAMILY: a card aimed at a habit line keeps working after
## the habit upgrades, instead of silently dying the moment the type_key changes.
## Unknown ids come back unchanged, so non-habit contexts stay harmless.
func habit_family(id: StringName) -> StringName:
	return _habit_root.get(id, id)

func _index_habit_families() -> void:
	_habit_root = {}
	var parent_of := {}   # child id -> parent id, one edge per `upgrades` entry
	for habit: HabitData in _habits.values():
		for child: StringName in habit.upgrades:
			parent_of[child] = habit.id
	for id: StringName in _habits:
		var root: StringName = id
		while parent_of.has(root):
			root = parent_of[root]
		_habit_root[id] = root

func get_card(id: StringName) -> CardData:
	return _cards.get(id)

func get_all_cards() -> Array[CardData]:
	var out: Array[CardData] = []
	out.assign(_cards.values())
	return out

func get_intervention(id: StringName) -> InterventionData:
	return _interventions.get(id)

func get_growth_node(id: StringName) -> GrowthNodeData:
	return _growth_nodes.get(id)

# ---------------------------------------------------------------- rarity helpers

## Buckets every loaded card by rarity. A card naming a rarity that isn't in RARITIES
## lands in DEFAULT_RARITY rather than vanishing from the pool — a typo in a .tres
## should make a card common, not silently undraftable.
func _index_cards_by_rarity() -> void:
	_cards_by_rarity = {}
	for rarity: StringName in RARITIES:
		_cards_by_rarity[rarity] = ([] as Array[CardData])
	for card: CardData in _cards.values():
		var key: StringName = card.rarity
		if not RARITIES.has(key):
			push_warning("Data: card '%s' has unknown rarity '%s' — treating as %s" % [card.id, key, DEFAULT_RARITY])
			key = DEFAULT_RARITY
		_cards_by_rarity[key].append(card)

func rarity_meta(rarity: StringName) -> Dictionary:
	return RARITIES.get(rarity, RARITIES[DEFAULT_RARITY])

func rarity_color(rarity: StringName) -> Color:
	return Color(rarity_meta(rarity).color)

## A card's own `color` wins if it sets one, otherwise its rarity's. Keeping this in one
## place is what lets the draft UI stay honest — colour reads as rarity by default.
func card_color(card: CardData) -> Color:
	if card != null and card.color != "":
		return Color(card.color)
	return rarity_color(card.rarity if card != null else DEFAULT_RARITY)

## Insight price of a card. A card may override its band with `price_override` >= 0,
## which is how a deliberately cheap legendary or an expensive common stays possible
## without inventing a new rarity for it.
func card_price(card: CardData) -> int:
	if card == null:
		return 0
	if card.price_override >= 0:
		return card.price_override
	return int(rarity_meta(card.rarity).price)

func rarities_by_order() -> Array[StringName]:
	var out: Array[StringName] = []
	out.assign(RARITIES.keys())
	out.sort_custom(func(a: StringName, b: StringName) -> bool:
		return int(RARITIES[a].order) < int(RARITIES[b].order))
	return out

## Cards of one rarity that are legal in `draft_number`. Never returns cards the caller
## already owns — that's the caller's job via `exclude_ids`.
func get_draftable_cards(rarity: StringName, draft_number: int, exclude_ids: Array) -> Array[CardData]:
	var out: Array[CardData] = []
	for card: CardData in _cards_by_rarity.get(rarity, []):
		if card.min_draft > draft_number:
			continue
		if exclude_ids.has(card.id):
			continue
		out.append(card)
	return out

## Odds row for a draft, clamped to the last row so levels longer than the table just
## keep rolling its richest line. Returns a copy — callers (Growth Tree perks) mutate it.
func draft_odds_for(draft_number: int) -> Dictionary:
	var row_index: int = clampi(draft_number - 1, 0, DRAFT_ODDS.size() - 1)
	return DRAFT_ODDS[row_index].duplicate()

# ---------------------------------------------------------------- growth helpers

func _index_growth_by_branch() -> void:
	_growth_by_branch = {}
	for node: GrowthNodeData in _growth_nodes.values():
		if not _growth_by_branch.has(node.branch):
			_growth_by_branch[node.branch] = ([] as Array[GrowthNodeData])
		_growth_by_branch[node.branch].append(node)
	for branch: StringName in _growth_by_branch:
		_growth_by_branch[branch].sort_custom(func(a: GrowthNodeData, b: GrowthNodeData) -> bool:
			if a.tier != b.tier:
				return a.tier < b.tier
			return String(a.id) < String(b.id))

## Branch ids that actually have nodes, in GROWTH_BRANCHES order. Branches not declared
## there still show up, sorted last, so a new branch is playable before it is styled.
func growth_branches() -> Array[StringName]:
	var out: Array[StringName] = []
	out.assign(_growth_by_branch.keys())
	out.sort_custom(func(a: StringName, b: StringName) -> bool:
		var ao: int = int(GROWTH_BRANCHES[a].order) if GROWTH_BRANCHES.has(a) else 99
		var bo: int = int(GROWTH_BRANCHES[b].order) if GROWTH_BRANCHES.has(b) else 99
		if ao != bo:
			return ao < bo
		return String(a) < String(b))
	return out

func growth_branch_meta(branch: StringName) -> Dictionary:
	return GROWTH_BRANCHES.get(branch,
		{"display": String(branch).capitalize(), "color": "c7ccdf", "order": 99, "blurb": ""})

func growth_nodes_in_branch(branch: StringName) -> Array[GrowthNodeData]:
	var out: Array[GrowthNodeData] = []
	out.assign(_growth_by_branch.get(branch, []))
	return out

func get_all_growth_nodes() -> Array[GrowthNodeData]:
	var out: Array[GrowthNodeData] = []
	out.assign(_growth_nodes.values())
	return out

func get_insight_card(level_id: int) -> InsightCardData:
	return _insight_cards.get(level_id)

func get_level(index: int) -> LevelData:
	return _levels[index]

func get_level_count() -> int:
	return _levels.size()

## Expands a level's `wave_curve` into full WaveData/SpawnBatchData for every wave
## 1..wave_count. For each wave and each curve entry whose `from_wave` has been
## reached, count = round(base_count + growth_per_wave * (wave_index - from_wave)).
func build_waves(level: LevelData) -> Array[WaveData]:
	var waves: Array[WaveData] = []
	for wave_index in range(1, level.wave_count + 1):
		var wave := WaveData.new()
		for curve: WaveCurveEntryData in level.wave_curve:
			if wave_index < curve.from_wave:
				continue
			var batch := SpawnBatchData.new()
			batch.distraction = curve.distraction
			batch.count = roundi(curve.base_count + curve.growth_per_wave * (wave_index - curve.from_wave))
			batch.spacing = curve.spacing
			wave.groups.append(batch)
		# One-off elite unit, not curve-scaled — enters partway into the final wave,
		# after the player has already engaged the regular horde.
		if wave_index == level.wave_count and level.boss != null:
			var boss_batch := SpawnBatchData.new()
			boss_batch.distraction = level.boss
			boss_batch.count = 1
			boss_batch.spacing = 6.0
			wave.groups.append(boss_batch)
		waves.append(wave)
	return waves
