class_name Game
extends Node2D

var bg_texture: Texture2D = null
var _spawn_marker_tex: Texture2D = null
var _goal_marker_tex: Texture2D = null

# Core gameplay (maze TD). Attach to the root Node2D of Game.tscn.
# HIGH GROUND cells are fixed terrain that BLOCK movement AND are the only spots
# habits can be built on. Distractions pathfind (AStarGrid2D) around high ground
# from spawn ZONES to the Focus core (objective).
#
# Build & SWHAOP Aiming flow:
#   Left-click with habit selected        → build habit & enter Aiming Mode
#   Aiming Mode (mouse move)              → orientation (facing_angle) & dynamic cone width (arc_angle 10°..125°)
#   Left-click while Aiming               → lock in orientation and complete placement
#   Right-click while Aiming              → cancel build & refund Dopamine
#   Left-click with intervention selected → cast intervention at mouse location
#   Left-click with no selection          → open upgrade/sell/re-aim panel on built cell
#   Right-click                           → close any panel/overlay, deselect habit & intervention

var level: LevelData

var astar: AStarGrid2D
var objective_cell: Vector2i
var objective_pos: Vector2
var high_ground := {}            # Vector2i -> true (blocking + buildable)
var build_spots: Dictionary = {} # Vector2i -> BuildSpot
var spawn_zone_cells: Array = [] # Array[Array[Vector2i]] — open cells per zone
var decor_layer: DecorLayer = null

## Ground-layer draw order. These used to be three competing move_child(..., 0) calls,
## whose result depended on which layer happened to be built first — and it came out
## backwards: the path layer landed on TOP, hiding the terrain, the decor and the
## background under 718 cells of floor tile. Explicit z_index cannot be reordered by
## construction order, so the stack stays what it says here.
const Z_BACKGROUND := -40  ## the plate everything else sits on
const Z_PATH := -30      ## walkable floor, the bottom of the world
const Z_WALL_SHADOW := -25  ## contact shadow the walls cast onto the floor
const Z_WALL_FACE := -22 ## the wall's front face, standing on the floor below it
const Z_TERRAIN := -20   ## raised walls
const Z_DECOR := -10     ## props lying on the floor, above it and below every unit
var path_layer: TileMapLayer = null

var _distractions: Array[Distraction] = []

# Y-sorted container for every field entity (habits, distractions, allies). Sorting by
# global Y means whatever stands lower on screen draws in front, which is the 2.5D depth
# cue from `01`. It works on plain _draw() shapes, so this is real now and not merely
# groundwork for future sprite art. Projectiles and VFX stay direct children of Game,
# added later in the tree, so they always render above the field.
var entities: Node2D

var projectile_pool: ObjectPool
var impact_fx_pool: ObjectPool
var burst_pool: ObjectPool

# Wave state
var wave_index := 0
var wave_spawning := false
var between_waves := false
var started := false
var game_ended := false
var spawn_queue: Array = []
var wave_time := 0.0

var _hover_cell := Vector2i(-999, -999)

# Aiming mode state (SWHAOP Mechanics)
var is_aiming := false
var aiming_habit: Habit = null
var aiming_spot: BuildSpot = null
## Which kind of aim is in progress. Right-click means "undo this purchase" on a fresh
## build (full refund, habit removed) but only "keep what I had" on a re-aim — the two
## used to share one branch, so backing out of a re-aim on an upgraded tower DEMOLISHED
## it and refunded only the tier-2 base cost.
var _aiming_is_fresh_build := false
## Angle/arc as they were before aiming started, so any exit path that isn't an explicit
## left-click lock can put them back. Without this, _cancel_aiming() silently committed
## whatever the cursor happened to be over — and it is called by Start Wave, which sits in
## the far bottom-right corner, so calling a wave mid-aim locked a 10° cone at the corner.
var _pre_aim_facing := 0.0
var _pre_aim_arc := 60.0

# Intervention state
var selected_intervention = null  # String key or null
var intervention_cooldowns := {
	"screen_break": 0.0,
	"deep_breath": 0.0,
	"call_a_friend": 0.0
}
var _shake_amount: float = 0.0

# HUD references
var _hud_layer: CanvasLayer
## Themed root inside the CanvasLayer — every HUD widget and overlay hangs off this, so
## they all inherit UI.theme() instead of styling themselves one property at a time.
var _hud_root: Control
var _dopamine_label: Label
var _insight_label: Label
var _focus_meter: UIMeter
var _tolerance_meter: UIMeter
var _wave_label: Label
var _enemy_stats_label: Label
var _message_label: Label
var _start_wave_button: Button = null
var _habit_buttons := {}
var _intervention_buttons := {}

# Upgrade/sell panel
var _active_panel: Control = null
var _panel_cell := Vector2i(-999, -999)

# Draft overlay
var _draft_overlay: Control = null
## 1-based count of drafts opened this level — it indexes the odds curve, so it rises
## with progress rather than with the wave number. A level that drafts on a different
## cadence still walks the same rarity ramp.
var _draft_number := 0
var _draft_rerolls_left := 0
## Insight spent on cards this run. Reported on the end screen so the player can see the
## trade they made — "you bought 3 cards and banked 24" is the whole mechanic in a line.
var _insight_spent_this_run := 0
## Titles of the cards drafted this run, for the telemetry row.
var _cards_taken: Array[String] = []

var _run_log := RunLog.new()
## Per-level cooldown scale from the Recovery branch, folded in once at level start.
var _intervention_cooldown_scale := 1.0

# Kill feedback. In a horde a "+3" per corpse is both unreadable and hundreds of Labels a
# second, so rewards are summed over a short window into one popup and the kill rate is
# shown as a combo instead.
var _reward_accum := 0
var _reward_pos := Vector2.ZERO
var _reward_flush := 0.0
var _combo := 0
var _combo_timer := 0.0
var _combo_label: Label = null

const _REWARD_FLUSH_TIME := 0.28
const _COMBO_HOLD_TIME := 1.1

# Glitch overlay — sits above the field and below the HUD.
var _glitch_rect: ColorRect = null
var _glitch_mat: ShaderMaterial = null
var _glitch_hit := 0.0   # transient spike from a distraction reaching the core

func _ready() -> void:
	# Before anything reads current_level_index: an editor Playtest launch may be
	# redirecting this boot to the level that was just baked.
	_consume_playtest_request()
	# _draw() paints the background and the vector walls on this node itself, so the node's
	# own filter decides how they scale. The background is authored at 320x152 and blown up
	# x6 to the 1920x912 field — under the default linear filter that arrives as mush.
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var bg_path := "res://assets/background.jpg"
	if not FileAccess.file_exists(bg_path):
		bg_path = "res://assets/background.png"
	if FileAccess.file_exists(bg_path):
		var img := Image.new()
		if img.load(bg_path) == OK:
			bg_texture = ImageTexture.create_from_image(img)
	# Volitelné ručně kreslené značky; bez souborů se hra kreslí postaru (vektorově).
	if ResourceLoader.exists("res://assets/markers/spawn_portal.png"):
		_spawn_marker_tex = load("res://assets/markers/spawn_portal.png")
	if ResourceLoader.exists("res://assets/markers/goal_core.png"):
		_goal_marker_tex = load("res://assets/markers/goal_core.png")
	level = Data.get_level(GameState.current_level_index)
	level = level.duplicate(true)
	level.waves = Data.build_waves(level)
	# Perks mutate the level's Focus/Dopamine, so they must land on this duplicate BEFORE
	# GameState snapshots it — and on the duplicate, never on Data's shared resource.
	MetaProgression.apply_level_perks(level)
	GameState.reset_for_level(level)
	ModifierManager.reset()         # clear any leftover cards from a previous run
	MetaProgression.apply_growth_modifiers()  # apply permanent Growth Tree unlocked modifiers
	_apply_intervention_perks()
	between_waves = true
	started = false
	wave_index = 0
	entities = Node2D.new()
	entities.name = "Entities"
	entities.y_sort_enabled = true
	add_child(entities)
	# After entities, so the placement preview draws above terrain AND units. The corner
	# terrain tiles overhang half a cell past their vertex, so anything painted in
	# Game._draw() — which renders below every child — gets clipped by tissue near walls;
	# that is exactly where towers get placed.
	_placement_overlay = PlacementOverlay.new()
	_placement_overlay.name = "PlacementOverlay"
	_placement_overlay.game = self
	add_child(_placement_overlay)
	_init_pools()
	_build_field()
	_build_glitch_overlay()
	_build_hud()

	SignalBus.game_over.connect(_on_bus_game_over)
	GameState.defeat_reward_granted.connect(_on_defeat_reward_granted)
	# Designer runs never open the log: every RunLog method no-ops until begin() is
	# called, and a run with F1 money in it would poison the balance dataset.
	if not GameState.designer_mode:
		_run_log.begin("Level_%02d" % (GameState.current_level_index + 1))
	SignalBus.level_started.emit(level.id)

	# The initial build phase is entered before the HUD exists, so the first preview
	# refresh happens here rather than in _enter_build_phase().
	_build_wave_preview()
	_refresh_wave_preview()

	# Toast layer for one-shot hints and enemy introductions — added after the bars and
	# the wave preview so it draws above them; the pause menu, added dynamically later,
	# still lands on top of everything.
	_hints = HintLayer.new()
	_hud_root.add_child(_hints)

	# The opening build phase pays the early-call bonus too, so a confident player is
	# rewarded from wave 1 rather than learning the mechanic halfway through.
	_begin_build_timer()

	queue_redraw()
	_flash("Build Phase — build habits, set angles, then call the wave. Sooner pays more.")

# ---------------------------------------------------------------- field + pathfinding

func _build_field() -> void:
	var g = Data.GRID
	astar = AStarGrid2D.new()
	astar.region = Rect2i(0, 0, g.cols, g.rows)
	astar.cell_size = Vector2(g.tile, g.tile)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar.update()

	objective_cell = level.objective
	objective_pos = cell_center(objective_cell)

	high_ground = {}
	build_spots = {}
	for cell: Vector2i in level.high_ground:
		if cell == objective_cell:
			continue
		high_ground[cell] = true
		if astar.is_in_bounds(cell.x, cell.y):
			astar.set_point_solid(cell, true)
		var bs := BuildSpot.new()
		add_child(bs)
		bs.setup(self, cell)
		build_spots[cell] = bs

	_apply_path_weights()
	_build_path_layer()
	_build_terrain_layer()

	spawn_zone_cells = []
	# (populated just below; the decor pass at the end of this function needs it)
	for zone: Rect2i in level.spawn_zones:
		var cells: Array = []
		for cx in range(zone.position.x, zone.position.x + zone.size.x):
			for cy in range(zone.position.y, zone.position.y + zone.size.y):
				var c := Vector2i(cx, cy)
				if _in_bounds(c) and not high_ground.has(c) and c != objective_cell:
					cells.append(c)
		if not cells.is_empty():
			spawn_zone_cells.append(cells)

	_build_background_layer()
	_build_wall_shadow_layer()
	_build_wall_face_layer()
	_build_decor_layer()
	_compute_path_previews()

## Makes the designer's painted lanes actually attract the horde.
##
## Every walkable cell that is NOT on a lane costs `path_off_lane_cost` times as much to
## cross, so A* takes the lane whenever the detour is worth it and spills off only when
## the lane is blocked or wildly longer. A hard block would have been simpler and wrong:
## walling a lane off would leave the level unsolvable, and the game's whole premise is
## routing around fixed high ground rather than following a fixed track.
##
## No lanes painted means no weights touched, so existing levels path exactly as before.
func _apply_path_weights() -> void:
	if level.path_cells.is_empty() or level.path_off_lane_cost <= 1.0:
		return
	var g = Data.GRID
	var lane := {}
	for c: Vector2i in level.path_cells:
		lane[c] = true
	for y in range(int(g.rows)):
		for x in range(int(g.cols)):
			var c := Vector2i(x, y)
			if not lane.has(c) and astar.is_in_bounds(c.x, c.y):
				astar.set_point_weight_scale(c, level.path_off_lane_cost)

## Floor scenery. Sits directly above the terrain and below `entities`, so props are
## painted over by anything that walks onto them. Built after the spawn zones exist,
## because it deliberately leaves those cells clear.
## The field's bottom plate. Its own node rather than a _draw() call, because _draw()
## paints at THIS node's z_index and would sit on top of the path, terrain and decor
## layers, hiding all three.
func _build_background_layer() -> void:
	var g = Data.GRID
	var w: int = int(g.cols) * int(g.tile)
	var h: int = int(g.rows) * int(g.tile)

	var plate := ColorRect.new()
	plate.name = "BackgroundPlate"
	plate.color = Color("11141f")
	plate.position = Vector2(g.origin_x, g.origin_y)
	plate.size = Vector2(w, h)
	plate.z_index = Z_BACKGROUND
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(plate)

	if bg_texture == null:
		return
	var art := Sprite2D.new()
	art.name = "Background"
	art.texture = bg_texture
	art.centered = false
	art.position = Vector2(g.origin_x, g.origin_y)
	# Authored at 320x152; the field is 1920x912, so this is an exact x6. NEAREST keeps
	# the art pixels square instead of smearing them.
	art.scale = Vector2(float(w) / bg_texture.get_width(), float(h) / bg_texture.get_height())
	art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	art.z_index = Z_BACKGROUND
	add_child(art)


## The shadow a wall drops onto the floor at its foot. Without it a wall does not sit on
## the ground, it hovers over it — the corridors read as cut out of a flat sheet rather
## than sunk between raised masses. It cannot live in the terrain atlas, because the
## shadow belongs to the cell BELOW the wall, which is floor and may be walked on.
##
## Length is constant regardless of how tall the wall is. That is a convention, not
## physics: a shadow that grew with height would swallow the units standing next to it.
## How far a wall's front face hangs into the cell below it. 8 art pixels at the x3
## raster — half a cell, the usual proportion for this view. Shared by WallFace and
## WallShadow, because the shadow has to start where the face ends.
const WALL_FACE_H := 24


## The wall's front face: what turns a flat top-down slab into a raised mass you can see
## the side of. Three-quarter view (Zelda, Stardew): the floor is seen from above, the
## characters from the front, and a raised block shows its south side.
##
## This was tried once before and rejected (docs/ART_PIPELINE.md), but the thing that
## failed was asking PixelLab to extrude the wall INSIDE the 16px tile — top and face
## sharing sixteen art pixels came back as a two-colour strip with the top eaten away.
## Here the face is not part of the tile at all: the geometry is drawn by code into the
## cell below, and only the material comes from the generator. Same split that makes the
## wall atlas work.
##
## Only the southern rim of a wall mass gets a face — a cell with solid ground below it
## is looking at its neighbour, not at open floor.
class WallFace extends Node2D:
	var solid: Dictionary = {}
	var variants: Array[Texture2D] = []
	var ox := 0
	var oy := 0
	var tile := 48
	var rows := 0
	var seed_val := 0
	## Set from Game.WALL_FACE_H at build time — an inner class cannot read the outer
	## script's constants directly.
	var face_h := 24

	func _draw() -> void:
		if variants.is_empty():
			return
		var rng := RandomNumberGenerator.new()
		var keys: Array = solid.keys()
		keys.sort()          # deterministic order, so the same seed lays out identically
		for cell: Vector2i in keys:
			var below := cell + Vector2i.DOWN
			if solid.has(below) or below.y >= rows:
				continue
			# One variant per cell, keyed off the cell itself: a long wall picks a mix
			# instead of repeating one strip every 48 px.
			rng.seed = hash(Vector2i(cell.x, cell.y)) ^ seed_val
			var tex: Texture2D = variants[rng.randi() % variants.size()]
			draw_texture_rect(tex, Rect2(ox + cell.x * tile, oy + below.y * tile,
				tile, face_h), false)


class WallShadow extends Node2D:
	const DEPTH := 12          ## 4 art pixels at the x3 raster
	const SIDE := 4            ## ambient occlusion where a wall meets floor sideways

	var solid: Dictionary = {}
	var ox := 0
	var oy := 0
	var tile := 48
	var cols := 0
	var rows := 0
	## The wall now has a visible front face standing in this cell, so the shadow starts
	## at the FOOT of that face rather than at the top edge of the cell. Left at the old
	## position it would fall across the face itself and read as a smear on the wall.
	var face_h := 24

	func _draw() -> void:
		# Cool and translucent, never black: a neutral black shadow reads as a hole,
		# a blue-shifted one reads as shade.
		var near := Color(0.016, 0.027, 0.063, 0.62)
		var far := Color(0.016, 0.027, 0.063, 0.30)
		for cell: Vector2i in solid.keys():
			var below := cell + Vector2i.DOWN
			if not solid.has(below) and below.y < rows:
				var x := ox + cell.x * tile
				var y := oy + below.y * tile + face_h
				draw_rect(Rect2(x, y, tile, DEPTH * 0.5), near)
				draw_rect(Rect2(x, y + DEPTH * 0.5, tile, DEPTH * 0.5), far)
			for dx in [-1, 1]:
				var side := cell + Vector2i(dx, 0)
				if solid.has(side) or side.x < 0 or side.x >= cols:
					continue
				# The strip hugs the wall: on the wall's left neighbour it sits against
				# that cell's right edge, and vice versa.
				var inset := tile - SIDE if dx < 0 else 0
				draw_rect(Rect2(ox + side.x * tile + inset, oy + side.y * tile,
					SIDE, tile), far)


## Built only for the tilemap terrain; the vector fallback paints its own shadow pass.
func _build_wall_shadow_layer() -> void:
	if terrain_layer == null or level == null:
		return
	var g = Data.GRID
	var sh := WallShadow.new()
	sh.name = "WallShadow"
	sh.z_index = Z_WALL_SHADOW
	sh.ox = int(g.origin_x)
	sh.oy = int(g.origin_y)
	sh.tile = int(g.tile)
	sh.cols = int(g.cols)
	sh.rows = int(g.rows)
	sh.face_h = WALL_FACE_H if _has_wall_faces() else 0
	for c: Vector2i in level.high_ground:
		if c != level.objective:
			sh.solid[c] = true
	add_child(sh)


const WALL_FACE_DIR := "res://assets/terrain/face"

## Face art is optional. With no files the game keeps the flat top-down look it had
## before, shadow included — so this can be reverted by deleting a folder.
func _load_wall_face_variants() -> Array[Texture2D]:
	var out: Array[Texture2D] = []
	var dir := DirAccess.open(WALL_FACE_DIR)
	if dir == null:
		return out
	var files := dir.get_files()
	files.sort()
	for f in files:
		var base := f.trim_suffix(".remap").trim_suffix(".import")
		if not base.ends_with(".png"):
			continue
		var p := "%s/%s" % [WALL_FACE_DIR, base]
		if not ResourceLoader.exists(p):
			continue
		var tex = load(p)
		if tex is Texture2D and not out.has(tex):
			out.append(tex)
	return out


func _has_wall_faces() -> bool:
	return not _load_wall_face_variants().is_empty()


func _build_wall_face_layer() -> void:
	if terrain_layer == null or level == null:
		return
	var variants := _load_wall_face_variants()
	if variants.is_empty():
		return
	var g = Data.GRID
	var wf := WallFace.new()
	wf.name = "WallFace"
	wf.z_index = Z_WALL_FACE
	wf.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	wf.ox = int(g.origin_x)
	wf.oy = int(g.origin_y)
	wf.tile = int(g.tile)
	wf.rows = int(g.rows)
	wf.face_h = WALL_FACE_H
	wf.variants = variants
	wf.seed_val = hash(level.id)
	for c: Vector2i in level.high_ground:
		if c != level.objective:
			wf.solid[c] = true
	add_child(wf)


func _build_decor_layer() -> void:
	decor_layer = DecorLayer.new()
	decor_layer.name = "Decor"
	add_child(decor_layer)
	decor_layer.z_index = Z_DECOR
	# Seeded from the level so a restart lays out identically; hash keeps it stable
	# across runs, unlike randi() which would rearrange the world every load.
	decor_layer.build(self, hash(level.id))

## Predicted walking routes shown during the build phase: a few faint polylines from
## each spawn zone to the objective, so the player can see where the pressure will come
## from BEFORE paying for anything. Computed once per level — towers only ever stand on
## already-solid high ground, so nothing changes path solidity mid-level. (Recompute
## here if anything ever starts toggling solidity mid-level.)
var _spawn_path_previews: Array[PackedVector2Array] = []

func _compute_path_previews() -> void:
	_spawn_path_previews = []
	for zone: Array in spawn_zone_cells:
		var samples: Array[int] = [0]
		if zone.size() >= 3:
			samples = [0, zone.size() / 2, zone.size() - 1]
		elif zone.size() == 2:
			samples = [0, 1]
		for i: int in samples:
			var cells := astar.get_id_path(zone[i], objective_cell)
			if cells.is_empty():
				continue
			var line := PackedVector2Array()
			for c: Vector2i in cells:
				line.append(cell_center(c))
			_spawn_path_previews.append(line)

## Path to the shared terrain TileSet. load()ed rather than preload()ed so a checkout
## without the generated tileset still runs (and simply falls back to vector walls)
## instead of failing to parse.
const TERRAIN_TILESET_PATH := "res://data/terrain/high_ground_tileset.tres"

## Corner-based (Wang) atlas from PixelLab. When this file exists it wins over the legacy
## side-mask tileset above; delete or rename it to fall back.
# TENTYŽ soubor, který zapisuje tools/tiles.py a čte náhled v editoru. Dřív tu bylo
# high_ground_corner_atlas.png — hra pak tiše kreslila starý atlas, zatímco editor nový,
# a nebylo z čeho poznat proč.
const CORNER_ATLAS_PATH := "res://assets/terrain/high_ground_atlas.png"

var terrain_layer: TileMapLayer = null

## Builds the painted terrain, if a level has any. Moved to child index 0 so it draws
## above the background that Game._draw() paints and below every unit.
##
## The move is not cosmetic. _build_field() runs after `entities` and the BuildSpots are
## already children, so a plain add_child() puts the terrain LAST and Godot paints it over
## every habit, soldier and distraction on the field. That stayed invisible only while the
## placeholder atlas was a plus-shaped block with transparent corners — the moment the
## tiles became solid 48px squares, towers built on high ground vanished behind them.
func _build_terrain_layer() -> void:
	if ResourceLoader.exists(CORNER_ATLAS_PATH) and not level.high_ground.is_empty():
		_build_corner_terrain()
		return

	# Legacy path: per-cell side-mask tiles authored in the map editor (terrain_tiles).
	if level.terrain_tiles.is_empty():
		return
	if not ResourceLoader.exists(TERRAIN_TILESET_PATH):
		push_warning("Game: level has painted tiles but %s is missing — "
			% TERRAIN_TILESET_PATH + "run tools/build_terrain_tileset.gd")
		return

	var g = Data.GRID
	terrain_layer = TileMapLayer.new()
	terrain_layer.name = "Terrain"
	terrain_layer.tile_set = load(TERRAIN_TILESET_PATH)
	terrain_layer.position = Vector2(g.origin_x, g.origin_y)
	add_child(terrain_layer)
	terrain_layer.z_index = Z_TERRAIN

	for key in level.terrain_tiles:
		var cell: Vector2i = key
		var t: Vector3i = level.terrain_tiles[key]
		terrain_layer.set_cell(cell, t.x, Vector2i(t.y, t.z))

## Corner-based ("dual grid") terrain. The PixelLab tileset stores terrain on tile
## CORNERS, not in tile centres — one tile straddles four game cells. So the layer is
## shifted half a cell up-left and its cells sit on grid VERTICES: vertex (i,j) looks at
## the four cells that touch it and picks the atlas slot whose bits mark which of them
## are high ground. This is what makes inner corners round — the tile at a concave bend
## exists in this atlas, whereas the 16-slot side atlas had no such piece.
##
## Slot layout: bit 1 = NW cell solid, 2 = NE, 4 = SW, 8 = SE; x = mask % 4, y = mask / 4.
## Derived from high_ground directly; terrain_tiles is only read by the legacy path.
const PATH_TILES_DIR := "res://assets/terrain/path"

## Share of lane cells that carry a synapse, and how long one strand may run.
## 6 % clustered reads far calmer than 10 % scattered, for the same pixel count.
const ACCENT_SHARE := 0.06
const ACCENT_STRAND := 4

## Painted lanes, drawn as their own floor under the walls. Cell-level, not corner-level:
## a lane is a surface the designer paints, not a mass that has to fit its neighbours, so
## it needs no autotiling — variants are picked per cell just for texture variety.
func _build_path_layer() -> void:
	if level.path_cells.is_empty():
		return
	# Two pools by filename: path_*.png is quiet floor, accent_*.png carries a synapse.
	# They are placed by different rules (see below), so they cannot share one list.
	var calm: Array[Texture2D] = []
	var accent: Array[Texture2D] = []
	var dir := DirAccess.open(PATH_TILES_DIR)
	if dir != null:
		var files := dir.get_files()
		files.sort()
		for f in files:
			var base := f.trim_suffix(".remap").trim_suffix(".import")
			if not base.ends_with(".png"):
				continue
			var p := "%s/%s" % [PATH_TILES_DIR, base]
			if not ResourceLoader.exists(p):
				continue
			var tex = load(p)
			if tex is Texture2D:
				if base.begins_with("accent_"):
					if not accent.has(tex):
						accent.append(tex)
				elif not calm.has(tex):
					calm.append(tex)
	if calm.is_empty():
		return
	var variants: Array[Texture2D] = calm + accent

	var g = Data.GRID
	var tile: int = int(g.tile)
	var ts := TileSet.new()
	ts.tile_size = Vector2i(tile, tile)
	# Blown up to the cell size once, here, instead of scaling the layer: a scaled layer
	# would put every lane cell's coordinates in art units rather than game cells, which
	# is a conversion waiting to be got wrong. NEAREST, so pixel art stays crisp.
	for i in range(variants.size()):
		var img := variants[i].get_image()
		img.resize(tile, tile, Image.INTERPOLATE_NEAREST)
		var src := TileSetAtlasSource.new()
		src.texture = ImageTexture.create_from_image(img)
		src.texture_region_size = Vector2i(tile, tile)
		src.create_tile(Vector2i.ZERO)
		ts.add_source(src, i)

	path_layer = TileMapLayer.new()
	path_layer.name = "Paths"
	path_layer.tile_set = ts
	path_layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	path_layer.position = Vector2(g.origin_x, g.origin_y)
	add_child(path_layer)
	path_layer.z_index = Z_PATH

	var rng := RandomNumberGenerator.new()
	rng.seed = hash(level.id) ^ 0x9a71

	# Quiet floor everywhere first.
	for c: Vector2i in level.path_cells:
		path_layer.set_cell(c, rng.randi() % calm.size(), Vector2i.ZERO)
	if accent.is_empty():
		return

	# Then the synapses in CLUSTERS, not as an even sprinkle.
	#
	# Picking a variant per cell out of one mixed pool is a uniform scatter, and a uniform
	# scatter of bright marks reads as confetti — the field looks busy however low the
	# ratio goes, because nothing in a real place is evenly spaced. DecorLayer already
	# learned this and seeds piles; the lane floor was still sprinkling. A few short
	# strands with bare floor between them read as something that grew there.
	var cells: Array[Vector2i] = level.path_cells.duplicate()
	var strands: int = maxi(1, int(cells.size() * ACCENT_SHARE / float(ACCENT_STRAND)))
	for _s in range(strands):
		var head: Vector2i = cells[rng.randi() % cells.size()]
		var pick: int = calm.size() + rng.randi() % accent.size()
		for _i in range(rng.randi_range(2, ACCENT_STRAND)):
			if not level.path_cells.has(head) or high_ground.has(head):
				break
			path_layer.set_cell(head, pick, Vector2i.ZERO)
			# Walk on, so a strand trails across a few cells like a fibre rather than
			# stamping the same tile in a blob.
			head += [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP][rng.randi() % 4]

func _build_corner_terrain() -> void:
	var g = Data.GRID
	var tile: int = int(g.tile)

	# Mirror the vector renderer: the objective cell is never drawn as terrain.
	var solid := {}
	for c: Vector2i in level.high_ground:
		if c != level.objective:
			solid[c] = true
	if solid.is_empty():
		return

	# The TileSet is assembled at runtime instead of generated into a .tres — plain tiles
	# need no terrain sets or peering bits, only atlas coordinates.
	#
	# The atlas may stack several VARIANTS of the same sixteen slots: a 192x192 sheet is
	# one variant, 192x384 is two, and so on. Sixteen shapes alone tile visibly — a long
	# wall repeats the identical texture every cell — so each cell rolls its own variant.
	var atlas_tex: Texture2D = load(CORNER_ATLAS_PATH)
	var variants: int = maxi(1, int(atlas_tex.get_height() / float(tile * 4)))

	var ts := TileSet.new()
	ts.tile_size = Vector2i(tile, tile)
	var src := TileSetAtlasSource.new()
	src.texture = atlas_tex
	src.texture_region_size = Vector2i(tile, tile)
	for v in range(variants):
		for m in range(16):
			src.create_tile(Vector2i(m % 4, v * 4 + int(m / 4.0)))
	ts.add_source(src, 0)

	terrain_layer = TileMapLayer.new()
	terrain_layer.name = "Terrain"
	terrain_layer.tile_set = ts
	terrain_layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	terrain_layer.position = Vector2(g.origin_x - tile / 2.0, g.origin_y - tile / 2.0)
	add_child(terrain_layer)
	terrain_layer.z_index = Z_TERRAIN

	# Seeded from the level, like the decor: the same level must look the same on every
	# load, or the walls would re-texture themselves under the player on each restart.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(level.id) ^ 0x7e44a1

	# One vertex more than cells in each axis, or the outermost walls lose their rim.
	for j in range(g.rows + 1):
		for i in range(g.cols + 1):
			var m := 0
			if solid.has(Vector2i(i - 1, j - 1)): m |= 1
			if solid.has(Vector2i(i, j - 1)): m |= 2
			if solid.has(Vector2i(i - 1, j)): m |= 4
			if solid.has(Vector2i(i, j)): m |= 8
			if m != 0:
				var v: int = rng.randi() % variants
				terrain_layer.set_cell(Vector2i(i, j), 0,
					Vector2i(m % 4, v * 4 + int(m / 4.0)))

## True while a level has no painted terrain, so Game._draw() should render the vector
## walls instead. Both renderers must never run at once or the capsules show through.
func _uses_vector_walls() -> bool:
	return terrain_layer == null

var _placement_overlay: Node2D = null

## Thin canvas that only paints the build preview. It must be a separate node: Game's own
## _draw() renders below every child including the terrain layer, and the overhanging
## corner tiles were clipping the marker right where building happens.
class PlacementOverlay extends Node2D:
	var game
	func _process(_dt: float) -> void:
		queue_redraw()
	func _draw() -> void:
		game._draw_placement_preview(self)

func _draw_placement_preview(cv: CanvasItem) -> void:
	var sel = GameState.selected_habit
	if sel == null or not _in_bounds(_hover_cell):
		return
	var g = Data.GRID
	var tile: int = g.tile
	var ok: bool = _can_build(_hover_cell) and GameState.can_afford(Data.get_habit(sel).build_cost)
	var tint := Color(0.35, 1.0, 0.55) if ok else Color(1.0, 0.4, 0.4)
	var r := Rect2(g.origin_x + _hover_cell.x * tile, g.origin_y + _hover_cell.y * tile, tile, tile)
	_draw_pixel_frame(cv, r, tint)
	# Every habit previews its reach BEFORE the player pays — attack range, patrol
	# zone, or Routine radius. It used to be pay-first-see-later for everything but
	# barracks. A circle, not a cone: facing is chosen in the aiming step after.
	var sel_def := Data.get_habit(sel)
	var pr: float = _preview_radius(sel_def)
	if pr > 0.0:
		var centre := r.get_center()
		cv.draw_circle(centre, pr, Color(tint.r, tint.g, tint.b, 0.07))
		PixelDraw.arc(cv, centre, pr, Color(tint.r, tint.g, tint.b, 0.6))

## Rounded chunky frame in the terrain's raster (1 art pixel = 3 screen px), so the cell
## marker reads as part of the pixel world instead of a vector rectangle floating over it.
## Each edge stops two units short of the corner and a single diagonal step closes it —
## the same silhouette the tissue tiles use.
func _draw_pixel_frame(cv: CanvasItem, r: Rect2, tint: Color) -> void:
	var u := 3.0
	cv.draw_rect(Rect2(r.position.x + u, r.position.y + u, r.size.x - 2 * u, r.size.y - 2 * u),
		Color(tint.r, tint.g, tint.b, 0.16))
	cv.draw_rect(Rect2(r.position.x + 2 * u, r.position.y, r.size.x - 4 * u, u), tint)
	cv.draw_rect(Rect2(r.position.x + 2 * u, r.end.y - u, r.size.x - 4 * u, u), tint)
	cv.draw_rect(Rect2(r.position.x, r.position.y + 2 * u, u, r.size.y - 4 * u), tint)
	cv.draw_rect(Rect2(r.end.x - u, r.position.y + 2 * u, u, r.size.y - 4 * u), tint)
	cv.draw_rect(Rect2(r.position.x + u, r.position.y + u, u, u), tint)
	cv.draw_rect(Rect2(r.end.x - 2 * u, r.position.y + u, u, u), tint)
	cv.draw_rect(Rect2(r.position.x + u, r.end.y - 2 * u, u, u), tint)
	cv.draw_rect(Rect2(r.end.x - 2 * u, r.end.y - 2 * u, u, u), tint)

func cell_center(cell: Vector2i) -> Vector2:
	var g = Data.GRID
	return Vector2(cell.x * g.tile + g.tile / 2.0 + g.origin_x, cell.y * g.tile + g.tile / 2.0 + g.origin_y)

func world_to_cell(pos: Vector2) -> Vector2i:
	var g = Data.GRID
	var col := int(floor((pos.x - g.origin_x) / float(g.tile)))
	var row := int(floor((pos.y - g.origin_y) / float(g.tile)))
	return Vector2i(clampi(col, 0, g.cols - 1), clampi(row, 0, g.rows - 1))

func _in_bounds(c: Vector2i) -> bool:
	var g = Data.GRID
	return c.x >= 0 and c.x < g.cols and c.y >= 0 and c.y < g.rows

# ---------------------------------------------------------------- line of sight
#
# Walls shade fire. One cast routine serves the wedge preview, target picking and the
# projectile's wall death, so what the player sees shadowed IS what cannot be hit —
# three separate implementations would drift apart the first time one gets tweaked.

## Distance from `from` along normalized `dir` to the first wall cell, capped at
## `max_dist`. The cell the ray STARTS in never blocks: towers stand on high ground and
## shoot outward. 6px sampling; both gameplay and preview use the same granularity.
func cast_to_wall(from: Vector2, dir: Vector2, max_dist: float) -> float:
	var start_cell := world_to_cell(from)
	var d := 6.0
	while d < max_dist:
		var c := world_to_cell(from + dir * d)
		if c != start_cell and high_ground.has(c):
			return d
		d += 6.0
	return max_dist

func has_line_of_sight(from: Vector2, to: Vector2) -> bool:
	var delta := to - from
	var dist := delta.length()
	if dist < 0.001:
		return true
	return cast_to_wall(from, delta / dist, dist) >= dist

func assign_path(d: Distraction) -> void:
	if d.is_flying:
		return  # flyers ignore the maze and steer straight at the objective themselves
	var from := world_to_cell(d.position)
	if not astar.is_in_boundsv(from):
		return
	var p := astar.get_id_path(from, objective_cell)
	if not p.is_empty():
		d.set_cell_path(p)

func _random_spawn_cell() -> Vector2i:
	var zone: Array = spawn_zone_cells[randi() % spawn_zone_cells.size()]
	return zone[randi() % zone.size()]

# ---------------------------------------------------------------- drawing

func _draw() -> void:
	var g = Data.GRID
	var tile: int = g.tile
	var ox: int = g.origin_x
	var oy: int = g.origin_y
	var w: int = g.cols * tile
	var h: int = g.rows * tile

	# The background is NOT painted here — a node's own _draw() lands at its own z_index,
	# so anything drawn here would cover every ground layer below it. It lives in
	# _build_background_layer() at Z_BACKGROUND instead.

	for cells: Array in spawn_zone_cells:
		for c: Vector2i in cells:
			draw_rect(Rect2(ox + c.x * tile, oy + c.y * tile, tile, tile), Color(0.9, 0.3, 0.4, 0.12))

	# Jedna brána na zónu, ne dlaždice děr v každé buňce — hráč má vidět "tady to leze
	# ven", ne vzorek. Slabý nádech nad ní nechává zónu čitelnou celou.
	if _spawn_marker_tex != null and level != null:
		for zone: Rect2i in level.spawn_zones:
			var zc := Vector2(ox + (zone.position.x + zone.size.x * 0.5) * tile,
				oy + (zone.position.y + zone.size.y * 0.5) * tile)
			var msz := Vector2(_spawn_marker_tex.get_size()) \
				* maxf(1.0, floorf(float(tile) / _spawn_marker_tex.get_width()))
			draw_texture_rect(_spawn_marker_tex, Rect2(zc - msz / 2.0, msz), false)

	# Predicted enemy routes were drawn here as faint trails; cut entirely — the player
	# reads routes from the corridors themselves and the trails just dirtied the field.
	# _spawn_path_previews stays computed in case the hint returns as a toggle.

	# Dotted background grid instead of hard lines
	for c in range(g.cols + 1):
		for r in range(g.rows + 1):
			draw_circle(Vector2(ox + c * tile, oy + r * tile), 1.5, Color("1e2333", 0.6))

	# Vector walls are the fallback for levels with no painted terrain yet. Once tiles
	# exist the TileMapLayer draws them instead — running both would double up.
	if _uses_vector_walls():
		var thickness := float(tile - 20)
		var hg_dict := {}
		for c in high_ground:
			hg_dict[c] = true

		# Shadow pass
		_draw_wall_layer(ox, oy, tile, thickness, Vector2(0, 4), Color("121520"), hg_dict)
		# Base pass
		_draw_wall_layer(ox, oy, tile, thickness, Vector2.ZERO, Color("2d334a"), hg_dict)
		# Inner glowing highlight line
		_draw_wall_layer(ox, oy, tile, thickness - 6, Vector2(0, -1.5), Color("454f73"), hg_dict)

	# Dynamic Animated Focus Core Rendering (Sleek & Living Reactor)
	var t := Time.get_ticks_msec() / 1000.0
	var base_radius := tile * 0.3

	# Podstavec pod jádrem — kreslený PŘED pulzy, aby vektorové jádro stálo na něčem
	# hmotném místo aby viselo na holé podlaze.
	if _goal_marker_tex != null:
		var gsz := Vector2(_goal_marker_tex.get_size()) \
			* maxf(1.0, floorf(float(tile) / _goal_marker_tex.get_width()))
		draw_texture_rect(_goal_marker_tex, Rect2(objective_pos - gsz / 2.0, gsz), false)
	var max_f := float(max(1, level.focus)) if level != null else 30.0
	var focus_ratio := clampf(float(GameState.focus) / max_f, 0.0, 1.0)
	
	# Determine core theme color based on health ratio
	var core_color: Color
	if focus_ratio > 0.7:
		core_color = Color("2bd6c0") # Calm Cyan / Teal
	elif focus_ratio > 0.3:
		core_color = Color("ffd479") # Amber Warning
	else:
		core_color = Color("ff4455") # Critical Alert Red
		
	# Damage glitch flash effect
	if _glitch_hit > 0.01:
		core_color = core_color.lerp(Color.WHITE, min(1.0, _glitch_hit * 2.0))

	# Fast living pulse animation
	var pulse_speed := 4.0 if focus_ratio > 0.7 else (7.0 if focus_ratio > 0.3 else 11.0)
	var pulse_scale := 1.0 + sin(t * pulse_speed) * 0.08
	
	# Multiple concentric pulse waves radiating outward (Offset phases)
	for w_i in range(2):
		var phase_offset := float(w_i) * 0.5
		var wave_phase := fmod(t * (pulse_speed * 0.25) + phase_offset, 1.0)
		var wave_r := base_radius * (1.0 + wave_phase * 0.9)
		var wave_alpha := (1.0 - wave_phase) * 0.3
		PixelDraw.arc(self, objective_pos, wave_r, Color(core_color.r, core_color.g, core_color.b, wave_alpha), 1.0, 1.5)
	
	# Outer Slim Health Arc (Progress Ring) — raster blocks; the filled part is denser
	# than the faint track so the ratio stays readable.
	var ring_r := base_radius + 7.0
	PixelDraw.arc(self, objective_pos, ring_r, Color(1, 1, 1, 0.1), 1.0, 2.0)
	if focus_ratio > 0.0:
		var start_angle := -PI / 2.0
		var end_angle := start_angle + (TAU * focus_ratio)
		PixelDraw.arc(self, objective_pos, ring_r, core_color, 1.0, 1.2, start_angle, end_angle)

	# Orbiting energy block around ring
	var orbit_angle := t * 2.5
	var orbit_pos := objective_pos + Vector2(cos(orbit_angle), sin(orbit_angle)) * ring_r
	draw_rect(Rect2((orbit_pos / 3.0).floor() * 3.0, Vector2(3.0, 3.0)), core_color.lightened(0.5))

	# Main Inner Glowing Core
	draw_circle(objective_pos, base_radius * pulse_scale * 1.2, Color(core_color.r, core_color.g, core_color.b, 0.2))
	draw_circle(objective_pos, base_radius * pulse_scale * 0.65, core_color)
	draw_circle(objective_pos, base_radius * pulse_scale * 0.3, Color.WHITE) # Bright core center

	# Sleek Minimalist Text Label
	var text_col := core_color.lightened(0.2)
	draw_string(ThemeDB.fallback_font, objective_pos + Vector2(-22, base_radius + 20.0), "FOCUS",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, text_col)

	# Habit build preview lives on _placement_overlay (drawn above terrain) — see
	# _draw_placement_preview().

	# Routine links — each working habit draws a line back to whatever holds it in place,
	# the Focus core or the nearest Anchor. Seeing what a habit hangs on is the point.
	for spot in build_spots.values():
		if is_instance_valid(spot) and spot.state == BuildSpot.State.BUILT and is_instance_valid(spot.current_habit):
			var hb = spot.current_habit
			if hb.in_routine:
				var closest_src: Vector2 = objective_pos
				var min_d: float = hb.global_position.distance_to(objective_pos)
				for spot2 in build_spots.values():
					if is_instance_valid(spot2) and spot2.state == BuildSpot.State.BUILT and is_instance_valid(spot2.current_habit):
						var hb2 = spot2.current_habit
						if hb2.type_key == ANCHOR_HABIT and hb2 != hb:
							var d: float = hb.global_position.distance_to(hb2.global_position)
							if d < min_d:
								min_d = d
								closest_src = hb2.global_position
				
				# Routine tether: marching blocks over a dark underlay (readable even on
				# pink tissue), plus a glowing energy packet that runs the length of the
				# line INTO the habit — the delivery is the point, the dash just connects.
				var t_ms := Time.get_ticks_msec()
				var flow := t_ms * 0.02
				PixelDraw.line(self, closest_src, hb.global_position,
					Color(0.02, 0.09, 0.14, 0.85), 1.66, 2.5, flow)
				PixelDraw.line(self, closest_src, hb.global_position,
					Color(0.25, 0.95, 1.0, 0.7), 1.0, 2.5, flow)
				# Per-habit phase so packets on different tethers don't arrive in sync;
				# the pause after each arrival gives the eye a beat between deliveries.
				var tether_len: float = hb.global_position.distance_to(closest_src)
				var phase: float = hb.global_position.x * 7.3 + hb.global_position.y * 3.1
				PixelDraw.packet(self, closest_src, hb.global_position,
					Color(0.45, 1.0, 1.0, 0.95),
					fposmod(t_ms * 0.001 * 110.0 + phase, tether_len + 90.0))

	# Intervention targeting preview
	if selected_intervention != null and Data.get_intervention(selected_intervention) != null:
		var idef := Data.get_intervention(selected_intervention)
		var mouse_pos = get_global_mouse_position()
		var tint = Color(idef.color)
		draw_circle(mouse_pos, idef.radius, Color(tint.r, tint.g, tint.b, 0.2))
		PixelDraw.arc(self, mouse_pos, idef.radius, tint)

	# SWHAOP Aiming mode: Sniper crosshair reticle & laser sight
	if is_aiming and aiming_habit != null and is_instance_valid(aiming_habit):
		var mouse_pos: Vector2 = get_global_mouse_position()
		var habit_pos: Vector2 = aiming_habit.global_position

		# Laser sight as a dashed pixel trail, denser than the Routine tether so it still
		# reads as a straight beam.
		PixelDraw.line(self, habit_pos, mouse_pos, Color(1.0, 0.3, 0.3, 0.6), 1.0, 2.0)

		# Sniper crosshair reticle in raster blocks
		var r_size := 12.0
		var r_col := Color("ff4455")
		draw_rect(Rect2(mouse_pos.x - 3.0, mouse_pos.y - 3.0, 6.0, 6.0), r_col)
		PixelDraw.arc(self, mouse_pos, r_size, r_col, 1.0, 1.5)
		PixelDraw.line(self, mouse_pos + Vector2(-r_size - 6, 0), mouse_pos + Vector2(-4, 0), r_col, 1.0, 1.5)
		PixelDraw.line(self, mouse_pos + Vector2(4, 0), mouse_pos + Vector2(r_size + 6, 0), r_col, 1.0, 1.5)
		PixelDraw.line(self, mouse_pos + Vector2(0, -r_size - 6), mouse_pos + Vector2(0, -4), r_col, 1.0, 1.5)
		PixelDraw.line(self, mouse_pos + Vector2(0, 4), mouse_pos + Vector2(0, r_size + 6), r_col, 1.0, 1.5)

		# Dynamic cone angle tag next to reticle
		var arc_text := "%d°" % int(aiming_habit.arc_angle)
		draw_string(ThemeDB.fallback_font, mouse_pos + Vector2(16, 5), arc_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("ffd479"))

# ---------------------------------------------------------------- render utils

func _draw_wall_layer(ox: int, oy: int, tile: int, thickness: float, offset: Vector2, color: Color, hg_dict: Dictionary) -> void:
	var half := tile / 2.0
	var radius := thickness / 2.0
	
	# Draw capsule connections
	for cell in hg_dict.keys():
		var cx = ox + cell.x * tile + half
		var cy = oy + cell.y * tile + half
		var p1 = Vector2(cx, cy) + offset
		
		# Connect to right
		var right_cell = cell + Vector2i.RIGHT
		if hg_dict.has(right_cell):
			var nx = ox + right_cell.x * tile + half
			var ny = oy + right_cell.y * tile + half
			var p2 = Vector2(nx, ny) + offset
			draw_line(p1, p2, color, thickness)
			
		# Connect to down
		var down_cell = cell + Vector2i.DOWN
		if hg_dict.has(down_cell):
			var nx = ox + down_cell.x * tile + half
			var ny = oy + down_cell.y * tile + half
			var p2 = Vector2(nx, ny) + offset
			draw_line(p1, p2, color, thickness)
			
	# Draw circular caps
	for cell in hg_dict.keys():
		var cx = ox + cell.x * tile + half
		var cy = oy + cell.y * tile + half
		draw_circle(Vector2(cx, cy) + offset, radius, color)

# ---------------------------------------------------------------- input / build / aiming

func _unhandled_input(event: InputEvent) -> void:
	if game_ended:
		return

	if event is InputEventKey and event.pressed and not event.echo:
		if GameState.designer_mode and _handle_designer_key(event.keycode):
			get_viewport().set_input_as_handled()
			return
		if _handle_hotkey():
			get_viewport().set_input_as_handled()
			return

	if event is InputEventMouseButton and event.pressed:
		# The event's own position, not _hover_cell — that is only refreshed from
		# _process(), so a fast flick-and-click acted on the previous frame's cell.
		var click_cell := world_to_cell(get_global_mouse_position())

		if is_aiming:
			if event.button_index == MOUSE_BUTTON_LEFT:
				# Lock in directional cone aim!
				_end_aiming()
				_flash("Direction set!", Color("7cffb2"))
				queue_redraw()
				return
			elif event.button_index == MOUSE_BUTTON_RIGHT:
				if _aiming_is_fresh_build:
					# Undoing a purchase, so a FULL refund — unlike selling a committed
					# habit (50%); nothing was ever fired. sell_habit() runs purely for
					# its teardown and its own 50% return is intentionally discarded.
					if aiming_habit and aiming_spot:
						var cost: int = Data.get_habit(aiming_habit.type_key).build_cost
						GameState.add_dopamine(cost)
						aiming_spot.sell_habit()
					SignalBus.build_canceled.emit()
					_end_aiming()
					_flash("Build canceled — refunded in full", Color("ff6b6b"))
				else:
					# Backing out of a re-aim keeps the tower and its old cone.
					_restore_pre_aim()
					_end_aiming()
					_flash("Re-aim canceled", Color("9bd0ff"))
				queue_redraw()
				return

		if event.button_index == MOUSE_BUTTON_RIGHT:
			_close_panel()
			GameState.select_habit(null)
			_select_intervention(null)
			return

		if event.button_index == MOUSE_BUTTON_LEFT:
			_close_panel()
			if selected_intervention != null:
				_cast_intervention(selected_intervention, get_global_mouse_position())
			elif GameState.selected_habit != null:
				_build_on(click_cell)
			else:
				_try_open_panel(click_cell)

## Everything the telemetry row needs about the current board state. Counting towers by
## walking build_spots rather than keeping a running tally means it can't drift out of
## sync with sells, upgrades and refunds.
func _telemetry_snapshot() -> Dictionary:
	var by_type := {}
	var total := 0
	var anchors := 0
	var in_routine := 0
	for cell: Vector2i in build_spots:
		var bs: BuildSpot = build_spots[cell]
		if bs.state != BuildSpot.State.BUILT or not is_instance_valid(bs.current_habit):
			continue
		var key: String = bs.current_habit.type_key
		by_type[key] = int(by_type.get(key, 0)) + 1
		total += 1
		if key == ANCHOR_HABIT:
			anchors += 1
		if bs.current_habit.in_routine:
			in_routine += 1

	var parts: Array[String] = []
	for key in by_type:
		parts.append("%s=%d" % [key, by_type[key]])
	parts.sort()

	return {
		"focus": GameState.focus,
		"max_focus": GameState.max_focus,
		"focus_lost_total": GameState.max_focus - GameState.focus,
		"dopamine": GameState.dopamine,
		"run_insight": GameState.run_insight,
		"insight_spent": _insight_spent_this_run,
		"kills_total": GameState.kills,
		"tolerance": GameState.tolerance,
		"tolerance_floor": GameState.tolerance_floor,
		"towers_total": total,
		"anchors": anchors,
		"towers_in_routine": in_routine,
		"towers_by_type": ";".join(parts),
		"cards_taken": ";".join(_cards_taken),
	}

## Keyboard shortcuts. Returns true if the key was consumed. The whole game was
## mouse-only, with every habit a 132px target at the bottom of a 1080px screen and
## ~40 full-screen cursor traversals per level.
func _handle_hotkey() -> bool:
	if Input.is_action_just_pressed("td_pause"):
		_toggle_pause()
		return true
	if Input.is_action_just_pressed("td_speed_up"):
		set_speed_index(_speed_index + 1)
		return true
	if Input.is_action_just_pressed("td_speed_down"):
		set_speed_index(_speed_index - 1)
		return true
	if Input.is_action_just_pressed("td_cancel"):
		# One key that always means "back out", whatever mode you're in — and when there
		# is nothing left to back out of, it opens the pause menu. (Resume-while-paused
		# is handled by PauseMenu itself: this node is PAUSABLE and deaf while paused.)
		if is_aiming:
			_cancel_aiming()
			_flash("Aim canceled", Color("9bd0ff"))
		elif _active_panel != null or GameState.selected_habit != null \
				or selected_intervention != null:
			_close_panel()
			GameState.select_habit(null)
			_select_intervention(null)
		elif _draft_overlay == null or not is_instance_valid(_draft_overlay):
			_open_pause_menu()
		return true
	if Input.is_action_just_pressed("td_start_wave"):
		if between_waves and not _start_wave_button.disabled:
			_on_start_wave_pressed()
		return true

	for i in range(Data.HABIT_ORDER.size()):
		if Input.is_action_just_pressed("td_habit_%d" % (i + 1)):
			_select_habit(String(Data.HABIT_ORDER[i]))
			return true
	for i in range(Data.INTERVENTION_ORDER.size()):
		if Input.is_action_just_pressed("td_intervention_%d" % (i + 1)):
			_select_intervention(String(Data.INTERVENTION_ORDER[i]))
			return true
	return false

# ---------------------------------------------------------------- editor playtest / designer mode
#
# The map editor's Playtest button bakes the level, writes a one-shot marker file and
# launches this scene. The marker carries WHICH level to boot into and whether to enable
# designer mode; it is consumed (deleted) on first read, so it can redirect exactly one
# boot and a crashed launch can never hijack a later, normal run.

const PLAYTEST_MARKER := "user://editor_playtest.cfg"
## Markers older than this are discarded: the click→boot gap is seconds, anything more
## means the launch it belonged to never happened.
const PLAYTEST_MARKER_MAX_AGE := 60

## Reads AND deletes the playtest marker. Returns {} when there is none, it is broken,
## or it is stale; otherwise {level_path: String, designer: bool}. Static so the map
## editor (which writes the file — keep formats in sync) and tests can reach it without
## a Game instance.
static func read_playtest_marker() -> Dictionary:
	if not FileAccess.file_exists(PLAYTEST_MARKER):
		return {}
	var cfg := ConfigFile.new()
	var err := cfg.load(PLAYTEST_MARKER)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PLAYTEST_MARKER))
	if err != OK:
		return {}
	var stamp := int(cfg.get_value("playtest", "stamp", 0))
	if absi(int(Time.get_unix_time_from_system()) - stamp) > PLAYTEST_MARKER_MAX_AGE:
		return {}
	return {
		"level_path": String(cfg.get_value("playtest", "level_path", "")),
		"designer": bool(cfg.get_value("playtest", "designer", true)),
	}

func _consume_playtest_request() -> void:
	var req := read_playtest_marker()
	if req.is_empty():
		return
	GameState.designer_mode = bool(req.designer)
	var path := String(req.level_path)
	for i in range(Data.get_level_count()):
		if Data.get_level(i).resource_path == path:
			GameState.current_level_index = i
			return
	push_warning("Playtest marker points at unknown level '%s' — playing the current one." % path)

## Designer-mode cheats, reachable only on runs the map editor launched. They exist so a
## level's SHAPE can be judged in minutes — sketch towers without grinding the economy,
## fast-forward the dead time, wipe a wave to reach the next layout question. None of it
## runs outside designer mode, and designer runs never write telemetry.
func _handle_designer_key(keycode: int) -> bool:
	if not GameState.designer_mode:
		return false
	match keycode:
		KEY_F1:
			GameState.add_dopamine(500)
			_flash("Designer: +500 Dopamine", Color("ffb454"))
			return true
		KEY_F2:
			GameState.add_run_insight(10)
			_flash("Designer: +10 Insight", Color("ffb454"))
			return true
		KEY_F3:
			_designer_turbo = not _designer_turbo
			_apply_time_scale()
			_flash("Designer: turbo %s" % ("ON — 5×" if _designer_turbo else "off"), Color("ffb454"))
			return true
		KEY_F4:
			_designer_clear_wave()
			return true
	return false

## Kills every distraction on the field via the shield-bypassing damage channel, so even
## a boss goes down. Defeat signals fire normally — the wave completes, rewards pay out —
## because the point is to skip to the NEXT wave's layout question, not to break the run.
func _designer_clear_wave() -> void:
	var alive := get_tree().get_nodes_in_group("distractions")
	for d in alive:
		if is_instance_valid(d) and d.has_method("take_direct_damage"):
			d.take_direct_damage(999999)
	_flash("Designer: cleared %d distractions" % alive.size(), Color("ffb454"))

## Leaves aiming mode without touching the habit's angle — the caller decides whether the
## current aim is committed (left-click lock) or rolled back first (_restore_pre_aim).
func _end_aiming() -> void:
	if aiming_habit and is_instance_valid(aiming_habit):
		aiming_habit.show_range_indicator = false
	is_aiming = false
	aiming_habit = null
	aiming_spot = null
	_aiming_is_fresh_build = false

func _restore_pre_aim() -> void:
	if aiming_habit and is_instance_valid(aiming_habit):
		aiming_habit.facing_angle = _pre_aim_facing
		aiming_habit.set_arc_angle(_pre_aim_arc)
		aiming_habit.queue_redraw()

func _build_on(cell: Vector2i) -> void:
	if not build_spots.has(cell):
		_flash_error("Build only on high ground")
		return
	var bs := build_spots[cell] as BuildSpot
	if bs.state == BuildSpot.State.BUILT:
		_flash_error("Already built — right-click to deselect, then click to manage")
		return
	var type_key = GameState.selected_habit
	var def := Data.get_habit(type_key)
	# Affordability is a GATE, not a reaction: it has to be able to abort the build
	# before anything is created. This is why habit_built below is notification-only
	# and never the thing that triggers the payment.
	if not GameState.spend_dopamine(def.build_cost):
		_flash_error("Not enough Dopamine")
		return

	var default_arc: float = def.arc_angle
	var habit := bs.build_habit(type_key, 0.0, default_arc)
	SignalBus.habit_built.emit(habit, def.build_cost)
	if _hints != null:
		_hints.show_hint("first_build")

	if def.is_blocker:
		# No cone to aim — Allies deploy immediately around the rally point. The habit
		# stays selected so several can be placed in a row (see _build_on's caller).
		_flash("Allies deployed!", Color("2bd6c0"))
		return

	if def.is_support():
		# Anchors have no cone either — placing one used to drop the player into aiming
		# mode for a tower that will never fire. Place, extend the Routine, move on.
		_flash("Anchor set — Routine reaches %dpx around it" % int(def.range), Color("7ef2e6"))
		return

	# Enter Aiming Mode for SWHAOP Directional Cone setup
	_begin_aiming(habit, bs, true)
	SignalBus.build_requested.emit(bs)
	_flash("Aim cone with mouse (distance = arc width) — Left Click to lock, Right Click to cancel")

## Shared entry point for both aim paths, so the rollback snapshot can never be forgotten
## by one of them. `fresh_build` decides what a right-click means (see _aiming_is_fresh_build).
func _begin_aiming(habit: Habit, spot: BuildSpot, fresh_build: bool) -> void:
	is_aiming = true
	aiming_habit = habit
	aiming_spot = spot
	_aiming_is_fresh_build = fresh_build
	_pre_aim_facing = habit.facing_angle
	_pre_aim_arc = habit.arc_angle
	habit.show_range_indicator = true
	if fresh_build and _hints != null:
		_hints.show_hint("first_aim")

func _can_build(cell: Vector2i) -> bool:
	return build_spots.has(cell) and build_spots[cell].state == BuildSpot.State.EMPTY

## Radius previewed at the hover cell before a habit is bought. Attack habits go
## through ModifierManager so the circle matches what the tower will ACTUALLY get with
## this run's drafted cards, not the .tres base value.
func _preview_radius(def: HabitData) -> float:
	if def.is_blocker:
		return def.guard_radius
	if def.is_support():
		return def.range   # the Routine radius it will project
	return ModifierManager.get_modified_stat(def.range, ModifierManager.STAT_RANGE, def.id)

# ---------------------------------------------------------------- interventions

func _select_intervention(key) -> void:
	_close_panel()
	_cancel_aiming()
	if selected_intervention == key:
		selected_intervention = null
	else:
		selected_intervention = key
		GameState.select_habit(null)
	_update_intervention_buttons()
	queue_redraw()

func _cast_intervention(key: String, target_pos: Vector2) -> void:
	var idef := Data.get_intervention(key)
	if idef == null:
		return
	if intervention_cooldowns.get(key, 0.0) > 0.0:
		_flash_error("Ability on cooldown!")
		return

	intervention_cooldowns[key] = idef.cooldown * _intervention_cooldown_scale
	selected_intervention = null
	_update_intervention_buttons()
	queue_redraw()

	var start_pos := Vector2(target_pos.x, -40.0)
	var col := Color(idef.color)

	# Spawn falling sky-strike projectile
	var strike := Node2D.new()
	strike.global_position = start_pos
	add_child(strike)

	var cur_pos: Vector2 = start_pos
	var tw := create_tween()
	tw.tween_method(func(pos_val: Vector2):
		cur_pos = pos_val
		strike.global_position = pos_val
		strike.queue_redraw()
	, start_pos, target_pos, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	strike.draw.connect(func():
		# Sky trail streak, chunky
		PixelDraw.line(strike, Vector2(0, -50), Vector2.ZERO, Color(col.r, col.g, col.b, 0.6), 1.5, 1.2)
		strike.draw_circle(Vector2.ZERO, 8.0, Color.WHITE)
		strike.draw_circle(Vector2.ZERO, 12.0, Color(col.r, col.g, col.b, 0.4))
	)

	tw.tween_callback(func():
		strike.queue_free()
		_trigger_intervention_impact(idef, target_pos)
	)

func _trigger_intervention_impact(idef: InterventionData, target_pos: Vector2) -> void:
	add_shake(12.0)
	var radius: float = idef.radius
	var col := Color(idef.color)

	# Expanding shockwave visual
	var wave := Node2D.new()
	wave.global_position = target_pos
	add_child(wave)

	var cur_r: float = 0.0
	var cur_a: float = 1.0
	var tw := wave.create_tween()
	tw.set_parallel(true)
	tw.tween_method(func(r_val: float):
		cur_r = r_val
		wave.queue_redraw()
	, 0.0, radius, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(a_val: float):
		cur_a = a_val
		wave.queue_redraw()
	, 1.0, 0.0, 0.35)

	wave.draw.connect(func():
		wave.draw_circle(Vector2.ZERO, cur_r, Color(col.r, col.g, col.b, cur_a * 0.25))
		PixelDraw.arc(wave, Vector2.ZERO, cur_r, Color(col.r, col.g, col.b, cur_a * 0.9), 1.0, 1.5)
	)

	tw.set_parallel(false)
	tw.tween_callback(wave.queue_free)

	# Execute mechanical gameplay logic
	if idef.type == "damage_aoe":
		var count := 0
		for d in _distractions:
			if is_instance_valid(d) and not d.dead:
				if d.global_position.distance_to(target_pos) <= radius:
					d.take_damage(idef.willpower_damage, idef.awareness_damage)
					count += 1
		_pop_text(target_pos, "%s! (%d hit)" % [idef.name, count], col)
		_flash("%s triggered!" % idef.name, col)
	elif idef.type == "freeze_aoe":
		var count := 0
		for d in _distractions:
			if is_instance_valid(d) and not d.dead:
				if d.global_position.distance_to(target_pos) <= radius:
					d.apply_slow(0.0, idef.freeze_duration)
					count += 1
		_pop_text(target_pos, "PAUSE! (%d frozen)" % count, col)
		_flash("%s triggered! Distractions paused." % idef.name, col)
	elif idef.type == "summon_allies":
		# Temporary Allies — same unit as the Accountability barracks (06), but they
		# expire on ally_lifetime instead of holding a rally slot.
		var count: int = idef.ally_count
		for i: int in range(count):
			var a := Ally.new()
			entities.add_child(a)
			var angle: float = TAU * float(i) / float(count)
			a.setup(self, target_pos + Vector2.RIGHT.rotated(angle) * radius,
				idef.ally_health, idef.ally_damage, idef.ally_attack_cooldown,
				idef.guard_radius, idef.ally_lifetime)
		_pop_text(target_pos, "%s! (%d Allies)" % [idef.name, count], col)
		_flash("%s! Allies hold the line for %.0fs." % [idef.name, idef.ally_lifetime], col)

## Folded in once at level start rather than read per cast — the perk cannot change
## mid-level, and a cooldown that silently re-derives itself every cast is a bug waiting
## to happen. Floored at 25% of the original so no amount of stacking makes a
## cooldown effectively zero.
func _apply_intervention_perks() -> void:
	var reduction := MetaProgression.get_perk(MetaProgression.PERK_INTERVENTION_COOLDOWN)
	_intervention_cooldown_scale = clampf(1.0 - reduction, 0.25, 1.0)

func _update_interventions(delta: float) -> void:
	var updated := false
	for key: String in intervention_cooldowns:
		if intervention_cooldowns[key] > 0.0:
			intervention_cooldowns[key] = maxf(0.0, intervention_cooldowns[key] - delta)
			updated = true
	if updated:
		_update_intervention_buttons()

func _update_intervention_buttons() -> void:
	for key: String in Data.INTERVENTION_ORDER:
		if not _intervention_buttons.has(key):
			continue
		var btn: Button = _intervention_buttons[key]
		var idef := Data.get_intervention(key)
		var cd: float = intervention_cooldowns.get(key, 0.0)
		var tint := Color(idef.color)
		if cd > 0.0:
			btn.text = "%s\n%.1fs" % [idef.short, cd]
			btn.disabled = true
			btn.remove_theme_stylebox_override("normal")
			btn.remove_theme_color_override("font_color")
		else:
			btn.text = idef.short
			btn.disabled = false
			# Ready is a coloured outline in the ability's own colour; selected fills it.
			# Both live in the stylebox so nothing fights over `modulate`.
			if selected_intervention == key:
				btn.add_theme_stylebox_override("normal",
					UI.flat(Color(tint.r * 0.3, tint.g * 0.3, tint.b * 0.3), tint, 2,
						UI.RADIUS_SM, 10))
				btn.add_theme_color_override("font_color", Color.WHITE)
			else:
				btn.add_theme_stylebox_override("normal",
					UI.flat(UI.PANEL, Color(tint.r, tint.g, tint.b, 0.55), 1,
						UI.RADIUS_SM, 10))
				btn.add_theme_color_override("font_color", tint)

# ---------------------------------------------------------------- upgrade/sell/re-aim panel

func _try_open_panel(cell: Vector2i) -> void:
	if not build_spots.has(cell):
		return
	var bs := build_spots[cell] as BuildSpot
	if bs.state != BuildSpot.State.BUILT:
		return
	_open_panel(cell, bs)

func _open_panel(cell: Vector2i, bs: BuildSpot) -> void:
	var type_key := bs.get_current_type_key()
	var def := Data.get_habit(type_key)
	var g = Data.GRID

	if bs.current_habit:
		bs.current_habit.show_range_indicator = true

	var panel := UI.panel(UI.BORDER_HI, 1)
	panel.position = Vector2(
		clampf(cell_center(cell).x - 100.0, 10.0, 1920.0 - 270.0),
		clampf(cell_center(cell).y - g.tile * 2.2, g.tile * 0.5, 1080.0 - 320.0)
	)
	panel.custom_minimum_size = Vector2(240, 0)
	_hud_root.add_child(panel)
	_active_panel = panel
	_panel_cell = cell

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)

	box.add_child(UI.label(def.name, UI.FS_HEAD, UI.ACCENT))

	var stats := Label.new()
	# Live current_* values when a Habit sits here, so drafted cards show their work.
	stats.text = _habit_stats_line(def,
		bs.current_habit as Habit if bs.current_habit is Habit else null)
	stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stats.custom_minimum_size = Vector2(210, 0)
	stats.add_theme_font_size_override("font_size", UI.FS_SMALL)
	stats.add_theme_color_override("font_color", UI.TEXT_DIM)
	box.add_child(stats)

	# Combat record — what this specific tower has actually done. Support projects
	# Routine rather than damage, so the line would only ever read zero there.
	if bs.current_habit != null and not def.is_support():
		var record := UI.label("Defeated %d  ·  %d damage dealt"
			% [bs.current_habit.kills, bs.current_habit.damage_dealt],
			UI.FS_SMALL, UI.TEXT_FAINT)
		record.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(record)

	box.add_child(HSeparator.new())

	# Targeting mode — the panel's only cycling control. Attack habits only: barracks
	# hold ground and support fires nothing, so a mode would be a lie on both.
	if bs.current_habit is Habit and not def.is_support() and not def.is_blocker:
		var habit_ref: Habit = bs.current_habit
		var tgt := UI.button("Target: %s" % habit_ref.target_mode_name(), UI.FS_SMALL)
		tgt.tooltip_text = ("Which distraction the barrel picks inside its cone:\n"
			+ "Nearest — closest to the tower (default)\n"
			+ "First — furthest along its route toward your Focus\n"
			+ "Strongest — highest health (breaks the tank first)\n"
			+ "Weakest — lowest health (finishes wounded ones off)")
		tgt.pressed.connect(func():
			habit_ref.cycle_target_mode()
			tgt.text = "Target: %s" % habit_ref.target_mode_name())
		box.add_child(tgt)

	# Pomodoro rest button — a short break now instead of a long burnout later.
	if def.has_work_cycle and bs.current_habit:
		var brk := UI.button("Take a break (%.0fs)" % def.break_short, UI.FS_SMALL)
		brk.tooltip_text = "Rest it now for %.0fs. Let it run to empty instead and it burns out for %.0fs." \
			% [def.break_short, def.break_long]
		brk.disabled = bs.current_habit.is_resting()
		brk.pressed.connect(func():
			bs.current_habit.take_break()
			_close_panel()
		)
		box.add_child(brk)

	# Re-aim Cone direction button — not applicable to blockers or support (no cone)
	if not def.is_blocker and not def.is_support():
		var reaim := UI.button("Re-aim cone", UI.FS_SMALL)
		reaim.pressed.connect(_do_reaim.bind(bs))
		box.add_child(reaim)

	for up_key: StringName in def.upgrades:
		var up_def := Data.get_habit(up_key)
		var affordable := GameState.can_afford(up_def.build_cost)
		var btn := UI.primary_button("↑ %s — %d ◆" % [up_def.name, up_def.build_cost],
			UI.DOPAMINE, UI.FS_SMALL) if affordable \
			else UI.button("↑ %s — %d ◆" % [up_def.name, up_def.build_cost], UI.FS_SMALL)
		# Description plus the actual numbers changing — "what do I get for 50 ◆"
		# answered with a delta, not prose.
		var delta := _upgrade_delta_text(def,
			bs.current_habit as Habit if bs.current_habit is Habit else null, up_def)
		btn.tooltip_text = up_def.description + (("\n" + delta) if delta != "" else "")
		btn.disabled = not affordable
		btn.pressed.connect(_do_upgrade.bind(cell, up_key, up_def.build_cost))
		box.add_child(btn)

	var sell_refund := int(def.build_cost * 0.5)
	var sell := UI.button("Sell — refund %d ◆" % sell_refund, UI.FS_SMALL)
	sell.add_theme_color_override("font_color", UI.TEXT_DIM)
	sell.pressed.connect(_do_sell.bind(cell, sell_refund))
	box.add_child(sell)

func _do_reaim(bs: BuildSpot) -> void:
	_close_panel()
	if bs.current_habit == null:
		return
	_begin_aiming(bs.current_habit, bs, false)
	_flash("Re-aiming cone — Left click to lock, Right click to keep the old one",
		Color("9bd0ff"))

func _close_panel() -> void:
	if _panel_cell != Vector2i(-999, -999) and build_spots.has(_panel_cell):
		var bs: BuildSpot = build_spots[_panel_cell]
		if bs.current_habit and bs.current_habit != aiming_habit:
			bs.current_habit.show_range_indicator = false
	if _active_panel != null and is_instance_valid(_active_panel):
		_active_panel.queue_free()
	_active_panel = null
	_panel_cell = Vector2i(-999, -999)

func _do_upgrade(cell: Vector2i, new_type_key: String, cost: int) -> void:
	# Same gate-not-reaction rule as _build_on(): pay first, or nothing happens.
	if not GameState.spend_dopamine(cost):
		_flash_error("Not enough Dopamine")
		return
	var spot: BuildSpot = build_spots[cell]
	var habit := spot.upgrade_habit(new_type_key)
	SignalBus.habit_upgraded.emit(habit, cost)
	_close_panel()
	_flash("Upgraded to %s" % Data.get_habit(new_type_key).name, Color("9bd0ff"))

## Selling a committed habit refunds 50% (computed by the caller from the panel).
## Contrast the aiming-cancel path in _unhandled_input(), which refunds 100%.
func _do_sell(cell: Vector2i, refund: int) -> void:
	var spot: BuildSpot = build_spots[cell]
	spot.sell_habit()
	GameState.add_dopamine(refund)
	SignalBus.habit_sold.emit(spot, refund)
	_close_panel()
	_flash("+%d Dopamine (sold)" % refund, Color("7cffb2"))

## Bail out of aiming from somewhere that isn't the aim itself — clicking a habit button,
## an intervention, Start Wave, or opening the draft. It ROLLS BACK to the pre-aim angle:
## every one of those callers involves moving the cursor far away first, and the aim
## tracks the cursor, so committing would lock whatever the button happened to sit under.
## Start Wave lives in the bottom-right corner, which is how a freshly built tower ended
## up as a 10° cone pointed off the map.
func _cancel_aiming() -> void:
	if not is_aiming:
		return
	_restore_pre_aim()
	_end_aiming()
	queue_redraw()

# ---------------------------------------------------------------- waves

func _start_wave() -> void:
	if wave_index >= level.waves.size():
		return
	var wave: WaveData = level.waves[wave_index]
	GameState.set_wave(wave_index + 1)
	# Lean wave ("no cash"): defeats pay nothing until the wave clears. The preview
	# already warned; the flash + hint land the point the moment it becomes real.
	GameState.lean_wave_active = (wave_index + 1) in level.lean_waves
	if GameState.lean_wave_active:
		if _hints != null:
			_hints.show_hint("first_lean")
		_flash("Wave %d — LEAN: defeats pay no Dopamine" % (wave_index + 1), UI.DANGER)
	else:
		_flash("Wave %d" % (wave_index + 1))
	spawn_queue = []
	for group: SpawnBatchData in wave.groups:
		for k in range(group.count):
			var sc: Vector2i = _random_spawn_cell()
			spawn_queue.append({"time": (k + 1) * group.spacing, "type": group.distraction.id, "spawn": sc})
	spawn_queue.sort_custom(func(a, b): return a.time < b.time)
	wave_time = 0.0
	wave_spawning = true
	_update_enemy_stats()
	SignalBus.wave_started.emit(wave_index + 1)

func _process(delta: float) -> void:
	if game_ended:
		return
	_update_interventions(delta)
	_update_aiming_process()
	if wave_spawning:
		wave_time += delta
		var spawned_any := false
		while spawn_queue.size() > 0 and spawn_queue[0].time <= wave_time:
			var entry = spawn_queue.pop_front()
			spawn_distraction(entry.type, entry.spawn)
			spawned_any = true
		if spawned_any:
			_update_enemy_stats()
		if spawn_queue.is_empty():
			wave_spawning = false
	_run_log.tick(delta)
	_update_tolerance(delta)
	_update_wave_bonus(delta)
	_update_glitch(delta)
	_update_kill_feedback(delta)
	_update_routine_reach()
	_check_wave_progress()
	queue_redraw()
	_update_hover()

	# Screen Shake decay
	if _shake_amount > 0.05:
		_shake_amount = lerpf(_shake_amount, 0.0, 12.0 * delta)
		position = Vector2(randf_range(-_shake_amount, _shake_amount), randf_range(-_shake_amount, _shake_amount))
	else:
		_shake_amount = 0.0
		position = Vector2.ZERO

func _update_aiming_process() -> void:
	if not is_aiming or aiming_habit == null or not is_instance_valid(aiming_habit):
		return
	var mouse_pos: Vector2 = get_global_mouse_position()
	var habit_pos: Vector2 = aiming_habit.global_position
	var dir_vec: Vector2 = mouse_pos - habit_pos
	if dir_vec.length_squared() > 1.0:
		aiming_habit.facing_angle = dir_vec.angle()
		var dist: float = dir_vec.length()
		var max_r: float = aiming_habit.current_attack_range
		# Sniper distance mapping:
		# Closer cursor (dist near 20px) -> Wide cone (125.0°)
		# Farther cursor (dist near max_r) -> Tight sniper cone (10.0°)
		var norm_dist: float = clampf((dist - 20.0) / (max_r - 20.0), 0.0, 1.0)
		var calc_arc: float = lerpf(125.0, 10.0, norm_dist)
		aiming_habit.set_arc_angle(calc_arc)
		aiming_habit.queue_redraw()
		queue_redraw()

## Recomputes which habits are inside the player's Routine. A habit only runs if it
## falls within reach of the Focus core or of an Anchor — the mechanical claim being
## that habits hold where they attach to something already in your day, and stall where
## they don't. Anchors are how you extend that reach out to the edges of the field.
func _update_routine_reach() -> void:
	var habits := []
	var anchor_habits := []
	for spot in build_spots.values():
		if is_instance_valid(spot) and spot.state == BuildSpot.State.BUILT and is_instance_valid(spot.current_habit):
			var h = spot.current_habit
			habits.append(h)
			if h.type_key == ANCHOR_HABIT:
				anchor_habits.append(h)

	var anchor_positions := compute_routine_sources(anchor_habits)

	var any_stalled := false
	for h in habits:
		h.in_routine = is_position_in_routine(h.global_position, anchor_positions)
		if not h.in_routine:
			any_stalled = true
	if any_stalled and _hints != null:
		_hints.show_hint("no_routine")

## Grows the set of Routine sources outward from the Focus core: an Anchor only projects
## Routine once it is ITSELF inside Routine, so coverage has to be built as a chain.
##
## The previous version added every Anchor to the source list before testing any of them,
## which meant one dropped anywhere on the map worked instantly — nine of them (180
## Dopamine) covered all of Level 1, and the mechanic constrained nothing. Chaining is
## what makes it mean what it says: a habit holds where it attaches to something already
## established, and you extend that outward one step at a time.
##
## Takes the anchor NODES and returns positions, so callers that only have candidate
## points (the map editor's metrics) can reuse the same rule. O(anchors²) worst case,
## which at realistic anchor counts is nothing.
func compute_routine_sources(anchor_habits: Array) -> Array:
	var sources: Array[Vector2] = [objective_pos]
	var pending := anchor_habits.duplicate()
	var grew := true
	while grew:
		grew = false
		var still_pending := []
		for a in pending:
			if is_position_in_routine(a.global_position, sources):
				sources.append(a.global_position)
				grew = true
			else:
				still_pending.append(a)
		pending = still_pending
	return sources

## True if `pos` sits inside the reach of the core or of any already-established source.
func is_position_in_routine(pos: Vector2, sources: Array) -> bool:
	for src_pos: Vector2 in sources:
		var r: float = CORE_ROUTINE_RADIUS if src_pos == objective_pos else ANCHOR_ROUTINE_RADIUS
		if pos.distance_to(src_pos) <= r:
			return true
	return false

func _update_hover() -> void:
	var should_redraw := false
	if selected_intervention != null or is_aiming:
		should_redraw = true
	# Always track the hovered cell, not just while a habit is selected — a
	# left-click with nothing selected opens that cell's panel (_try_open_panel),
	# which needs a live _hover_cell to have anything to open.
	var c := world_to_cell(get_global_mouse_position())
	if c != _hover_cell:
		_hover_cell = c
		should_redraw = true

	if should_redraw:
		queue_redraw()

func _check_wave_progress() -> void:
	if not started or wave_spawning or between_waves:
		return
	if _distractions.size() > 0:
		return
	SignalBus.wave_completed.emit(wave_index + 1)
	_run_log.write_wave(wave_index + 1, _telemetry_snapshot())
	if wave_index < level.waves.size() - 1:
		between_waves = true
		if _should_draft_now():
			_show_draft_screen()
		else:
			_enter_build_phase()
	else:
		SignalBus.game_over.emit(true)

## Drafts fire on the level's interval AND always right before the final wave. The
## guaranteed pre-final draft is not a special case bolted on — it is the original
## design intent (a fresh card facing the level's hardest wave), and leaving it to the
## interval would mean it lands or not depending on how many waves the level happens to
## have. `or` rather than `elif` so the two rules can never double-fire on one wave.
func _should_draft_now() -> bool:
	var cleared := wave_index + 1
	if cleared == level.waves.size() - 1:
		return true
	if level.draft_interval > 0 and cleared % level.draft_interval == 0:
		return true
	return false

# Early-call bonus. The build phase used to be untimed with no reason to ever leave it,
# which is both slow and the thing that made Quick Hit farming free. Calling the wave
# early now pays Dopamine proportional to the time left — the standard modern TD carrot
# (Kingdom Rush, BTD6, Orcs Must Die), and a real decision: another habit built, or the
# bonus that would have paid for most of one.
#
# Deliberately a carrot and not a stick: the timer runs out and the bonus reaches zero,
# but the wave never auto-starts. A maze builder who wants to think for two minutes keeps
# that right; they just don't get paid for it.
const WAVE_BONUS_WINDOW := 30.0
const WAVE_BONUS_PER_SEC := 1.0

var _wave_bonus_left := 0.0

func _pending_wave_bonus() -> int:
	return int(floor(_wave_bonus_left * WAVE_BONUS_PER_SEC))

func _begin_build_timer() -> void:
	_wave_bonus_left = WAVE_BONUS_WINDOW
	_refresh_start_wave_button()

func _refresh_start_wave_button() -> void:
	if _start_wave_button == null:
		return
	var bonus := _pending_wave_bonus()
	var label := "▶ Start Wave %d" % (wave_index + 1)
	if between_waves and bonus > 0:
		label += "   +%d" % bonus
	_start_wave_button.text = label

func _update_wave_bonus(delta: float) -> void:
	if not between_waves or _wave_bonus_left <= 0.0:
		return
	var before := _pending_wave_bonus()
	_wave_bonus_left = maxf(0.0, _wave_bonus_left - delta)
	if _pending_wave_bonus() != before:
		_refresh_start_wave_button()

func _enter_build_phase() -> void:
	wave_index += 1
	between_waves = true
	GameState.lean_wave_active = false
	if _start_wave_button:
		_start_wave_button.disabled = false
		_start_wave_button.modulate = Color("7cffb2")
	_begin_build_timer()
	_refresh_wave_preview()
	queue_redraw()   # path previews come back for the build phase
	_flash("Build Phase — call Wave %d early for bonus Dopamine!" % (wave_index + 1),
		Color("9bd0ff"))

# ---------------------------------------------------------------- next-wave preview
#
# The composition of the coming wave was always sitting in level.waves and never shown —
# the player met a flyer or the boss only when it was already on the field. Standard TD
# affordance: during the build phase, a small panel lists what is about to arrive.

var _wave_preview_panel: PanelContainer = null
var _wave_preview_box: VBoxContainer = null

var _hints: HintLayer = null
## Distraction type_keys already introduced THIS run — intros repeat per run by design
## (they carry tactical info), unlike the persisted one-shot hints.
var _intro_seen := {}

## Aggregated contents of the wave about to start: [{def, count, is_new, is_boss}].
## `is_new` = this distraction type appears in no earlier wave — pure data, testable
## without spawning anything. The boss is always its own warning entry, never a count
## row, so the panel warns rather than spoils.
func upcoming_wave_summary() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if level == null or wave_index >= level.waves.size():
		return out
	var counts := {}   # StringName -> {def, count}
	var boss_def: DistractionData = null
	for group: SpawnBatchData in level.waves[wave_index].groups:
		if group.distraction.is_boss:
			boss_def = group.distraction
			continue
		var id: StringName = group.distraction.id
		if counts.has(id):
			counts[id].count += group.count
		else:
			counts[id] = {"def": group.distraction, "count": group.count}
	for id: StringName in counts:
		var is_new := true
		for k in range(wave_index):
			for g2: SpawnBatchData in level.waves[k].groups:
				if g2.distraction.id == id:
					is_new = false
					break
			if not is_new:
				break
		out.append({"def": counts[id].def, "count": int(counts[id].count),
			"is_new": is_new, "is_boss": false})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.count > b.count)
	if boss_def != null:
		out.append({"def": boss_def, "count": 1, "is_new": true, "is_boss": true})
	return out

func _build_wave_preview() -> void:
	_wave_preview_panel = UI.panel(UI.BORDER, 1)
	# Right edge, just under the top bar — clear of the tower panel's clamp range and
	# the Start Wave corner.
	_wave_preview_panel.position = Vector2(1920.0 - 286.0, float(_HUD_TOP_H) + 10.0)
	_wave_preview_panel.custom_minimum_size = Vector2(266, 0)
	_hud_root.add_child(_wave_preview_panel)
	_wave_preview_box = VBoxContainer.new()
	_wave_preview_box.add_theme_constant_override("separation", 4)
	_wave_preview_panel.add_child(_wave_preview_box)

func _refresh_wave_preview() -> void:
	if _wave_preview_panel == null:
		return
	for child in _wave_preview_box.get_children():
		child.queue_free()
	var entries := upcoming_wave_summary()
	if entries.is_empty():
		_wave_preview_panel.visible = false
		return
	_wave_preview_panel.visible = true
	_wave_preview_box.add_child(UI.label("Next: Wave %d / %d"
		% [wave_index + 1, level.waves.size()], UI.FS_BODY, UI.ACCENT))
	if (wave_index + 1) in level.lean_waves:
		_wave_preview_box.add_child(UI.label("LEAN — defeats pay no Dopamine",
			UI.FS_SMALL, UI.DANGER))
	for e: Dictionary in entries:
		if e.is_boss:
			_wave_preview_box.add_child(UI.wrapped("⚠ BOSS: %s — shields up periodically"
				% e.def.display_name, 240, UI.FS_SMALL, UI.DANGER))
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var swatch := ColorRect.new()
		swatch.color = Color(e.def.color)
		swatch.custom_minimum_size = Vector2(12, 12)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(swatch)
		row.add_child(UI.label("%s × %d" % [e.def.display_name, e.count],
			UI.FS_SMALL, UI.TEXT))
		if e.is_new:
			row.add_child(UI.spacer(Vector2.ZERO, true))
			row.add_child(UI.label("NEW", UI.FS_MICRO, UI.ACCENT))
		_wave_preview_box.add_child(row)

func _hide_wave_preview() -> void:
	if _wave_preview_panel != null:
		_wave_preview_panel.visible = false

func _on_start_wave_pressed() -> void:
	if not between_waves and started:
		return
	_close_panel()
	_cancel_aiming()
	_hide_wave_preview()
	queue_redraw()   # path previews disappear with the build phase
	var bonus := _pending_wave_bonus()
	between_waves = false
	started = true
	_wave_bonus_left = 0.0
	if _start_wave_button:
		_start_wave_button.disabled = true
		_start_wave_button.modulate = Color(0.6, 0.6, 0.6)
		_refresh_start_wave_button()
	if bonus > 0:
		GameState.add_dopamine(bonus)
		_pop_text(objective_pos, "+%d Early Call" % bonus, Color("7cffb2"))
	_start_wave()

func spawn_distraction(type_key: String, spawn_cell: Vector2i) -> Distraction:
	var d: Distraction
	if Data.get_distraction(type_key).is_boss:
		var boss := Boss.new()
		boss.shield_toggled.connect(func(active: bool):
			Sfx.play(&"shield_up" if active else &"shield_down")
			if active and _hints != null:
				_hints.show_hint("boss_shield")
			_flash("⚠ Denial Shield up — Boredom still lands" if active else "Shield down — hit it now!",
				Color("ffd479") if active else Color("7cffb2")))
		d = boss
		_flash("⚠ BOSS INCOMING", Color("ff6b6b"))
	else:
		d = Distraction.new()
	entities.add_child(d)
	d.setup(self, type_key)
	d.position = cell_center(spawn_cell)
	d.global_position = d.position
	assign_path(d)
	d.defeated.connect(_on_distraction_defeated)
	d.reached_core.connect(_on_distraction_reached_core)
	_distractions.append(d)
	SignalBus.distraction_spawned.emit(d)
	_update_enemy_stats()
	if not _intro_seen.has(type_key):
		_intro_seen[type_key] = true
		if _hints != null:
			_hints.show_enemy_intro(d.def)
	return d

func spawn_directional_projectile(pos: Vector2, dir_angle: float, max_dist: float,
		wp: int, aw: int, color: Color, source: Object = null) -> void:
	var p: Projectile = projectile_pool.acquire()
	if p != null:
		p.global_position = pos
		p.setup_directional(self, dir_angle, max_dist, wp, aw, color, source)

## Presentation half of a defeat. The economy half (tolerance-scaled reward, card
## bonuses, kill count) lives in GameState, driven by SignalBus.distraction_defeated
## which Distraction._die() emits alongside this per-instance signal.
func _on_distraction_defeated(d: Distraction) -> void:
	_distractions.erase(d)
	_update_enemy_stats()
	_reward_pos = d.position
	_combo += 1
	_combo_timer = _COMBO_HOLD_TIME
	_spawn_dopamine_burst(d.position)
	# Death burst in the enemy's own colour — bigger and slower than a shot impact
	# (see ImpactFX), fired here because the dying node is freed right after this.
	var fx = impact_fx_pool.acquire()
	if fx != null:
		fx.global_position = d.global_position
		fx.play(Color(d.def.color), 1.8)

## The paid-out amount arrives separately from GameState, because only GameState knows
## the economy rules and only the distraction knows where it died. Both write to
## independent buffers that _update_kill_feedback() flushes together, so the two
## handlers can fire in either order.
func _on_defeat_reward_granted(amount: int) -> void:
	_reward_accum += amount
	_reward_flush = _REWARD_FLUSH_TIME

## Presentation half of a core breach. Focus loss and the resulting game-over live in
## GameState, driven by SignalBus.distraction_escaped.
func _on_distraction_reached_core(d: Distraction) -> void:
	_distractions.erase(d)
	_update_enemy_stats()
	_glitch_hit = 0.85   # the screen lurches when your attention takes a hit
	add_shake(9.0)
	_pop_text(objective_pos, "-%d FOCUS" % d.def.focus_damage, Color("ff4455"))

# ---------------------------------------------------------------- tolerance / quick hit

## How far the Routine reaches. Named constants rather than magic numbers scattered
## across the draw and update paths, which is where they used to drift apart.
const CORE_ROUTINE_RADIUS := 330.0
const ANCHOR_ROUTINE_RADIUS := 260.0
## Habit id that extends the Routine. One place to change if the id ever moves.
const ANCHOR_HABIT := "anchor"

const _TOLERANCE_DECAY_PER_SEC := 4.0

# Quick Hit — signature mechanic 2 (see 00_overview). It used to be an unlimited money
# button: no cooldown, a flat payout immune to Tolerance, and a spike that decayed away
# for free during the untimed build phase, when no kills were being penalised anyway.
# Clicking it thirty times cost nothing and paid more than a third of a level's economy.
#
# Three rules make it teach what it claims instead:
#   1. A cooldown, so it is a decision rather than a click-speed contest.
#   2. The payout is scaled by Tolerance exactly like an honest kill. The cheap source
#      has to be the one that dries up — that IS downregulation.
#   3. Every use raises the Tolerance FLOOR a little. The spike still decays; the
#      baseline does not. That is what "borrowed, and you pay it back" means, and it is
#      the same asymmetry the two-sided cards already use.
const QUICK_HIT_BASE := 15
const QUICK_HIT_COOLDOWN := 6.0
const QUICK_HIT_SPIKE := 18.0
const QUICK_HIT_FLOOR_GAIN := 2.0

var _quick_hit_cd := 0.0
var _quick_hit_button: Button = null

func _update_tolerance(delta: float) -> void:
	if GameState.tolerance > 0.0:
		var rate := _TOLERANCE_DECAY_PER_SEC \
			* (1.0 + MetaProgression.get_perk(MetaProgression.PERK_TOLERANCE_DECAY))
		GameState.set_tolerance(GameState.tolerance - delta * rate)
	if _quick_hit_cd > 0.0:
		_quick_hit_cd = maxf(0.0, _quick_hit_cd - delta)
		_update_quick_hit_button()

## What one Quick Hit would actually pay right now. Same tolerance curve the economy
## applies to a defeat, so the two sources shrink together and the player can watch the
## cheap one stop being worth it.
func quick_hit_payout() -> int:
	var ratio: float = GameState.tolerance / 100.0
	return maxi(1, int(round(QUICK_HIT_BASE * (1.0 - 0.6 * ratio))))

func do_quick_hit() -> void:
	if game_ended or not GameState.quick_hit_enabled or _quick_hit_cd > 0.0:
		return
	if _hints != null:
		_hints.show_hint("quick_hit")
	var payout := quick_hit_payout()
	GameState.add_dopamine(payout)
	GameState.set_tolerance(GameState.tolerance + QUICK_HIT_SPIKE)
	GameState.raise_tolerance_floor(QUICK_HIT_FLOOR_GAIN)
	_quick_hit_cd = QUICK_HIT_COOLDOWN
	_update_quick_hit_button()
	_flash("+%d Cheap Dopamine… baseline Tolerance +%d" % [payout, int(QUICK_HIT_FLOOR_GAIN)],
		Color("ffcc00"))
	_pop_text(Vector2(1920 - 150, 1080 - 100), "+%d Cheap Dopamine" % payout, Color("ffcc00"))

## The shrinking number on the button is the lesson made visible — the player watches
## their own cheap source pay less every time they reach for it.
func _update_quick_hit_button() -> void:
	if _quick_hit_button == null:
		return
	if _quick_hit_cd > 0.0:
		_quick_hit_button.text = "Quick Hit (%.1fs)" % _quick_hit_cd
		_quick_hit_button.disabled = true
		_quick_hit_button.modulate = Color(0.6, 0.6, 0.6)
	else:
		_quick_hit_button.text = "Quick Hit +%d" % quick_hit_payout()
		_quick_hit_button.disabled = false
		_quick_hit_button.modulate = Color(1, 1, 1)

# ---------------------------------------------------------------- card draft screen

## Draws one card by rolling a rarity first and a card second. Rolling in that order is
## what makes the pool scalable: a card's chance depends on its rarity band, not on how
## many cards share the pool, so adding twenty commons never dilutes the legendaries.
##
## Rarities with nothing left to offer (exhausted, or gated by min_draft) are dropped
## from the roll before it happens rather than producing a failed draw — otherwise a
## thin Diamond pool would silently turn into "no card" instead of a lesser one.
func _draw_one_card(odds: Dictionary, exclude_ids: Array) -> CardData:
	var pools := {}
	var total_weight := 0.0
	for rarity: StringName in odds:
		var weight: float = maxf(0.0, float(odds[rarity]))
		if weight <= 0.0:
			continue
		var available := Data.get_draftable_cards(rarity, _draft_number, exclude_ids)
		if available.is_empty():
			continue
		pools[rarity] = available
		total_weight += weight
	if total_weight <= 0.0:
		return null

	var roll := randf() * total_weight
	var chosen_rarity: StringName = pools.keys()[0]
	for rarity: StringName in pools:
		roll -= float(odds[rarity])
		if roll <= 0.0:
			chosen_rarity = rarity
			break

	# Second roll, this time over the cards inside the band, weighted by CardData.weight
	# so a band can hold both staples and spice.
	var candidates: Array[CardData] = pools[chosen_rarity]
	var card_total := 0.0
	for c: CardData in candidates:
		card_total += maxf(0.0, c.weight)
	if card_total <= 0.0:
		return candidates[randi() % candidates.size()]
	var card_roll := randf() * card_total
	for c: CardData in candidates:
		card_roll -= maxf(0.0, c.weight)
		if card_roll <= 0.0:
			return c
	return candidates[candidates.size() - 1]

## The hand offered by one draft. Cards already drafted this level are excluded, and so
## are the other cards in this same hand — no duplicate choices.
func _roll_draft_options() -> Array[CardData]:
	var count: int = Data.DRAFT_OPTIONS_BASE \
		+ int(MetaProgression.get_perk(MetaProgression.PERK_DRAFT_OPTIONS))
	var odds := Data.draft_odds_for(_draft_number)
	# Growth Tree perks nudge the curve. Perk values are in the same percentage-point
	# units as DRAFT_ODDS, so a +5.0 Breakthrough perk turns a 10% row into 15%.
	for rarity: StringName in odds.keys():
		odds[rarity] = float(odds[rarity]) \
			+ MetaProgression.get_perk(MetaProgression.rarity_odds_perk(rarity))

	var taken: Array = ModifierManager.drafted_ids.duplicate()
	var out: Array[CardData] = []
	for i in range(maxi(1, count)):
		var card := _draw_one_card(odds, taken)
		if card == null:
			break
		out.append(card)
		taken.append(card.id)
	return out

func _show_draft_screen() -> void:
	# Building is allowed mid-wave, so the last kill can land while the player is aiming.
	# The aim tracks the cursor every frame regardless of overlays, so without this the
	# tower would follow the mouse across the card UI and lock onto whichever card was
	# clicked.
	_cancel_aiming()
	_hide_wave_preview()   # _enter_build_phase() re-shows it once the draft closes
	if _hints != null:
		_hints.show_hint("first_draft")
	_draft_number += 1
	_draft_rerolls_left = int(MetaProgression.get_perk(MetaProgression.PERK_DRAFT_REROLLS))
	var options := _roll_draft_options()
	# Nothing left to offer (every card already taken) — skip the screen entirely rather
	# than showing an empty one.
	if options.is_empty():
		_enter_build_phase()
		return
	_build_draft_overlay(options)

func _build_draft_overlay(options: Array[CardData]) -> void:
	_close_draft()

	var overlay := ColorRect.new()
	overlay.color = Color(UI.BG.r, UI.BG.g, UI.BG.b, 0.95)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hud_root.add_child(overlay)
	_draft_overlay = overlay

	# Centred with anchors instead of a hand-measured position/size, so the layout holds
	# whether the draft offers three cards or the four a Clear Sight player gets.
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 18)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	overlay.add_child(vbox)

	vbox.add_child(UI.label("Wave cleared — Draft %d" % _draft_number, UI.FS_TITLE,
		UI.ACCENT, HORIZONTAL_ALIGNMENT_CENTER))
	vbox.add_child(UI.label(
		"Paid with Insight ◆ — the same currency the Growth Tree runs on. Anything you don't spend, you keep.",
		UI.FS_BODY, UI.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER))

	# The live balance, big, right above the prices it has to cover.
	vbox.add_child(UI.label("%d ◆ available" % GameState.run_insight, UI.FS_HEAD,
		UI.INSIGHT, HORIZONTAL_ALIGNMENT_CENTER))

	vbox.add_child(UI.spacer(Vector2(0, 8)))

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 26)
	vbox.add_child(row)

	for card: CardData in options:
		row.add_child(_make_card_ui(card))

	vbox.add_child(UI.spacer(Vector2(0, 8)))

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 16)
	vbox.add_child(buttons)

	if _draft_rerolls_left > 0:
		var reroll := UI.button("↻ Reroll (%d left)" % _draft_rerolls_left, UI.FS_BODY,
			Vector2(220, 48))
		reroll.pressed.connect(_on_draft_reroll)
		buttons.add_child(reroll)

	# The skip button names what skipping is worth. A saving decision the player can't
	# see the value of isn't a decision — it just reads as "no thanks".
	var skip := UI.button("Skip — keep %d ◆ for the Growth Tree" % GameState.run_insight,
		UI.FS_BODY, Vector2(340, 48))
	skip.pressed.connect(_on_draft_skip)
	buttons.add_child(skip)

const _CARD_W := 380
const _CARD_BODY_W := 316

func _make_card_ui(card: CardData) -> PanelContainer:
	var card_color := Data.card_color(card)
	var price := Data.card_price(card)
	var affordable := GameState.can_afford_insight(price)

	# Rarity is carried by the frame as well as the text — at a glance across three cards
	# the border is what reads, not a word in 14px. An unaffordable card keeps its colour
	# but loses its glow: still legible, clearly out of reach.
	var panel := UI.panel(card_color if affordable else UI.BORDER, 2)
	panel.custom_minimum_size = Vector2(_CARD_W, 0)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	# Header: rarity on the left, price on the right — the two things being traded, on
	# one line, before anything else.
	var header := HBoxContainer.new()
	box.add_child(header)
	header.add_child(UI.label(String(Data.rarity_meta(card.rarity).display).to_upper(),
		UI.FS_MICRO, card_color))
	header.add_child(UI.spacer(Vector2.ZERO, true))
	header.add_child(UI.label("%d ◆" % price, UI.FS_SMALL,
		UI.INSIGHT if affordable else UI.DANGER))

	box.add_child(UI.wrapped(card.title, _CARD_BODY_W, UI.FS_HEAD, card_color))
	box.add_child(HSeparator.new())

	# What the card DOES comes first, directly under the name. The flavour line moves
	# below it, smaller and dimmer: a player deciding between three cards is reading for
	# the effect, and burying it under a 140px block of prose made them hunt for it.
	# One line per effect, coloured by whether it helps or costs — a two-sided card is
	# only a real decision if both halves are legible at a glance.
	for effect: CardEffectData in card.effects:
		box.add_child(UI.wrapped(_effect_label(effect), _CARD_BODY_W, UI.FS_BODY,
			UI.FOCUS if _effect_is_upside(effect) else UI.DANGER))

	# A burst is instant and one-off, so it gets its own line rather than being mixed in
	# with the ongoing modifiers above — "right now" and "from now on" must not look alike.
	if card.burst != null:
		box.add_child(UI.wrapped("◈ " + _burst_label(card.burst), _CARD_BODY_W,
			UI.FS_BODY, UI.INSIGHT))

	if card.tolerance_cost > 0:
		box.add_child(UI.wrapped(
			"▼ +%d baseline Tolerance — permanent this level; every Dopamine reward shrinks"
				% int(card.tolerance_cost), _CARD_BODY_W, UI.FS_SMALL, UI.DANGER))

	# Flavour last: it explains WHY the card is called what it is, which matters only
	# after the player has decided the effect is interesting.
	box.add_child(UI.wrapped(card.description, _CARD_BODY_W, UI.FS_SMALL, UI.TEXT_DIM))

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.custom_minimum_size = Vector2(0, 6)
	box.add_child(spacer)

	if affordable:
		var btn := UI.primary_button("Buy — %d ◆" % price, card_color, UI.FS_BODY,
			Vector2(0, 44))
		btn.pressed.connect(_on_card_picked.bind(card))
		box.add_child(btn)
	else:
		# Unaffordable stays visible and readable — seeing the Breakthrough you can't
		# afford is what makes the next Insight drop matter.
		var btn := UI.button("%d ◆ short" % (price - GameState.run_insight), UI.FS_BODY,
			Vector2(0, 44))
		btn.disabled = true
		box.add_child(btn)
		panel.modulate = Color(1, 1, 1, 0.55)

	return panel

func get_live_distractions() -> Array[Distraction]:
	return _distractions

## Effect lines are written as sentences, not as raw stat names. Three rules, all of
## them things the old "%+d%% stat_name" format got wrong:
##
##  1. The scope is always stated. "+15% damage" doesn't say what it buffs; "All habits:"
##     or the habit's FULL name does. The old version used the habit's short label, which
##     is how "+5 Willpower dmg (Focus)" happened — unreadable as "the Focus Timer gets
##     +5", and readable as "+5 damage to your Focus", which is the opposite meaning.
##  2. Inverted stats are phrased so the wording carries the benefit. A cooldown cut is
##     "attack 18% faster", never "-18% cooldown" printed in green.
##  3. Damage and status names come from Data.TERM, so the whole game's vocabulary can be
##     retuned in one place.
func _effect_label(effect: CardEffectData) -> String:
	var v: float = effect.value
	var up: bool = v > 0.0
	var amount: String = ("%d%%" % absi(roundi(v * 100.0))) if effect.is_percentage \
		else str(absi(roundi(v)))
	var sign_str: String = "+" if up else "−"
	var scope: String = "All habits" if effect.target == "ALL" \
		else Data.get_habit(effect.target).name

	match effect.stat_type:
		"willpower":
			return "%s: %s%s %s" % [scope, sign_str, amount, Data.TERM.damage]
		"awareness":
			return "%s: %s%s %s" % [scope, sign_str, amount, Data.TERM.mind_damage]
		"range":
			return "%s: %s%s range" % [scope, sign_str, amount]
		"fire_cooldown":
			return "%s: attack %s %s" % [scope, amount, "slower" if up else "faster"]
		"distraction_speed":
			return "Distractions move %s %s" % [amount, "faster" if up else "slower"]
		"distraction_health":
			return "Distractions have %s %s health" % [amount, "more" if up else "less"]
		"dopamine_bonus":
			# Always flat, whatever the effect claims — a percentage of a per-kill bonus
			# is not a thing the economy supports, so never print one.
			return "%s%d Dopamine per kill" % [sign_str, absi(roundi(v))]
	return ""

## For most stats "more" is better, but a lower cooldown fires faster and slower/frailer
## distractions are good news — so those three read inverted.
func _effect_is_upside(effect: CardEffectData) -> bool:
	var v: float = effect.value
	match effect.stat_type:
		"fire_cooldown", "distraction_speed", "distraction_health":
			return v < 0.0
	return v > 0.0

## Player-facing one-liner for a burst. Kept beside _execute_burst() on purpose: the two
## match on the same type strings, so adding a burst type means touching both, and they
## are easier to keep honest when they sit together.
func _burst_label(burst: CardBurstData) -> String:
	match burst.type:
		"grant_dopamine":
			return "Instantly gain %d Dopamine" % burst.dopamine
		"restore_focus":
			if burst.focus_percent > 0.0 and burst.focus_amount > 0:
				return "Instantly restore %d%% + %d Focus" % [int(burst.focus_percent * 100.0), burst.focus_amount]
			if burst.focus_percent > 0.0:
				return "Instantly restore %d%% of max Focus" % int(burst.focus_percent * 100.0)
			return "Instantly restore %d Focus" % burst.focus_amount
		"clear_tolerance":
			return "Instantly wipe Tolerance and its baseline"
		"summon_allies":
			if burst.ally_lifetime > 0.0:
				return "Summon %d Allies for %.0fs" % [burst.ally_count, burst.ally_lifetime]
			return "Summon %d permanent Allies" % burst.ally_count
		"damage_field":
			return "Hit every distraction on the field for %d/%d" % [burst.willpower_damage, burst.awareness_damage]
		"freeze_field":
			return "Pause every distraction on the field for %.0fs" % burst.freeze_duration
	return ""

## Runs a card's one-shot payload. Bursts sit outside ModifierManager by design — it
## only understands continuous stat modifiers, and "give me 4 Allies now" is an action,
## not a stat. Adding a burst type is one arm here plus one in _burst_label().
func _execute_burst(burst: CardBurstData) -> void:
	match burst.type:
		"grant_dopamine":
			GameState.add_dopamine(burst.dopamine)
			_pop_text(objective_pos, "+%d Dopamine" % burst.dopamine, Color("ffd479"))
		"restore_focus":
			var amount: int = burst.focus_amount + int(round(GameState.max_focus * burst.focus_percent))
			GameState.restore_focus(amount)
			_pop_text(objective_pos, "+%d Focus" % amount, Color("7cffb2"))
		"clear_tolerance":
			GameState.clear_tolerance()
			_pop_text(objective_pos, "Tolerance reset", Color("7ef2e6"))
		"summon_allies":
			_summon_burst_allies(burst)
		"damage_field":
			var hit := 0
			for d in _distractions:
				if is_instance_valid(d) and not d.dead:
					d.take_damage(burst.willpower_damage, burst.awareness_damage)
					hit += 1
			add_shake(14.0)
			_pop_text(objective_pos, "Field cleared! (%d hit)" % hit, Color("ff6b6b"))
		"freeze_field":
			var frozen := 0
			for d in _distractions:
				if is_instance_valid(d) and not d.dead:
					d.apply_slow(0.0, burst.freeze_duration)
					frozen += 1
			_pop_text(objective_pos, "PAUSE! (%d frozen)" % frozen, Color("9bd0ff"))
		_:
			push_warning("Game: unknown card burst type '%s'" % burst.type)

## Allies ring the Focus core rather than a click position — a draft has no cursor
## target, and the core is the thing the reinforcements are there to defend.
func _summon_burst_allies(burst: CardBurstData) -> void:
	var count: int = maxi(1, burst.ally_count)
	for i in range(count):
		var a := Ally.new()
		entities.add_child(a)
		var angle: float = TAU * float(i) / float(count)
		a.setup(self, objective_pos + Vector2.RIGHT.rotated(angle) * burst.spawn_radius,
			burst.ally_health, burst.ally_damage, burst.ally_attack_cooldown,
			burst.guard_radius, burst.ally_lifetime)
	_pop_text(objective_pos, "+%d Allies" % count, Color("2bd6c0"))

func _on_card_picked(card: CardData) -> void:
	# Re-checked here, not just on the button's disabled state: the price is the rule,
	# and a rule enforced only by the UI is one bug away from being free.
	var price := Data.card_price(card)
	if not GameState.spend_insight(price):
		_flash("Not enough Insight — %d ◆ needed" % price, Color("ff6b6b"))
		return
	Sfx.play(&"card")
	ModifierManager.add_drafted_card(card)
	_insight_spent_this_run += price
	_cards_taken.append(card.title)
	var tol_cost: int = int(card.tolerance_cost)
	if tol_cost > 0:
		GameState.raise_tolerance_floor(float(tol_cost))
	_close_draft()
	if card.burst != null:
		_execute_burst(card.burst)
	var col := Data.card_color(card)
	if tol_cost > 0:
		_flash("Active: %s  —  Tolerance +%d" % [card.title, tol_cost], col)
	else:
		_flash("Active: %s" % card.title, col)
	_enter_build_phase()

## A reroll redraws the whole hand, not one slot. Rerolling a single card invites
## save-scumming one slot at a time; redrawing everything keeps it a real decision.
func _on_draft_reroll() -> void:
	if _draft_rerolls_left <= 0:
		return
	_draft_rerolls_left -= 1
	var options := _roll_draft_options()
	if options.is_empty():
		_on_draft_skip()
		return
	_build_draft_overlay(options)

func _on_draft_skip() -> void:
	_close_draft()
	_enter_build_phase()

func _close_draft() -> void:
	if _draft_overlay != null and is_instance_valid(_draft_overlay):
		_draft_overlay.queue_free()
	_draft_overlay = null

# ---------------------------------------------------------------- end states

## One signal, two genuinely asymmetric outcomes: victory awards Clarity Stars and
## writes the save before handing off to the insight card; defeat does neither. Both
## sides keep their own game_ended guard, because change_scene_to_file() frees this
## whole tree — a same-frame kill and core breach must not both fire.
func _on_bus_game_over(victory: bool) -> void:
	if victory:
		_level_complete()
	else:
		_game_over()

func _level_complete() -> void:
	if game_ended:
		return
	game_ended = true
	var focus_pct := float(GameState.focus) / float(GameState.max_focus)
	var stars := 3 if focus_pct >= 0.8 else (2 if focus_pct >= 0.4 else 1)
	var lvl_id := "Level_%02d" % (GameState.current_level_index + 1)
	var next_id := "Level_%02d" % (GameState.current_level_index + 2)
	_run_log.write_wave(level.waves.size(), _telemetry_snapshot(), "victory")
	_run_log.end()
	_reset_time_scale()
	GameState.last_run_stats = {"stars": stars, "kills": GameState.kills,
		"waves_cleared": level.waves.size(), "max_wave": level.waves.size(),
		"focus": GameState.focus, "max_focus": GameState.max_focus}
	# Banked BEFORE complete_level() because the first-clear bonus is keyed on
	# cleared_levels, which complete_level() has no part in — but keeping the order
	# explicit means the two can never start fighting over "was this level already beaten".
	GameState.last_run_insight = MetaProgression.bank_run(
		lvl_id, true, GameState.run_insight, _insight_spent_this_run)
	MetaProgression.complete_level(lvl_id, stars, next_id)
	get_tree().change_scene_to_file("res://scenes/Education.tscn")

## A lost run keeps every Insight it collected and didn't spend. Focus ran out, but the
## waves the player did hold are real progress — and a defeat screen that hands back
## nothing teaches that failing was wasted time, which is precisely the lesson this game
## exists to contradict. It also means hoarding is never punished by dying: the only
## cost of saving is the drops you didn't survive long enough to collect.
func _game_over() -> void:
	if game_ended:
		return
	game_ended = true
	var lvl_id := "Level_%02d" % (GameState.current_level_index + 1)
	_run_log.write_wave(wave_index + 1, _telemetry_snapshot(), "defeat")
	_run_log.end()
	_reset_time_scale()
	GameState.last_run_stats = {"stars": 0, "kills": GameState.kills,
		"waves_cleared": wave_index, "max_wave": level.waves.size(),
		"focus": 0, "max_focus": GameState.max_focus}
	GameState.last_run_insight = MetaProgression.bank_run(
		lvl_id, false, GameState.run_insight, _insight_spent_this_run)
	get_tree().change_scene_to_file("res://scenes/GameOver.tscn")

# ---------------------------------------------------------------- kill feedback

## Flushes the accumulated reward as a single popup and drives the combo readout. One
## Label per burst of kills instead of one per kill.
func _update_kill_feedback(delta: float) -> void:
	if _reward_flush > 0.0:
		_reward_flush -= delta
		if _reward_flush <= 0.0 and _reward_accum > 0:
			_pop_text(_reward_pos, "+%d Dopamine" % _reward_accum, Color("35ff8d"))
			_reward_accum = 0

	if _combo_timer > 0.0:
		_combo_timer -= delta
		if _combo_timer <= 0.0:
			_combo = 0
	if _combo_label:
		# Below 4 the number is noise; a horde only reads as a horde once it's rolling.
		if _combo >= 4:
			_combo_label.text = "x%d" % _combo
			_combo_label.modulate = Color("ffd479") if _combo < 25 else Color("ff8a3d")
		else:
			_combo_label.text = ""

# ---------------------------------------------------------------- dopamine particles

static var _dot_texture: ImageTexture = null
static var _burst_material: ParticleProcessMaterial = null

const _BURST_POOL_SIZE := 20
const _BURST_LIFETIME := 0.65
static func _get_dot_texture() -> ImageTexture:
	if _dot_texture == null:
		var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
		for y: int in range(8):
			for x: int in range(8):
				var d: float = Vector2(float(x) - 3.5, float(y) - 3.5).length() / 4.0
				img.set_pixel(x, y, Color(1, 1, 1, clampf(1.0 - d, 0.0, 1.0)))
		_dot_texture = ImageTexture.create_from_image(img)
	return _dot_texture

static func _get_burst_material() -> ParticleProcessMaterial:
	if _burst_material == null:
		var mat := ParticleProcessMaterial.new()
		mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		mat.emission_sphere_radius = 5.0
		mat.direction = Vector3(0, -1, 0)
		mat.spread = 32.0
		mat.initial_velocity_min = 45.0
		mat.initial_velocity_max = 95.0
		mat.gravity = Vector3(0, -110.0, 0)
		mat.scale_min = 0.5
		mat.scale_max = 1.2
		var ramp := Gradient.new()
		ramp.set_color(0, Color("7cffb2"))
		ramp.set_color(1, Color(0.49, 1.0, 0.70, 0.0))
		var ramp_tex := GradientTexture1D.new()
		ramp_tex.gradient = ramp
		mat.color_ramp = ramp_tex
		_burst_material = mat
	return _burst_material

func _init_pools() -> void:
	projectile_pool = ObjectPool.new(
		func():
			var p = Projectile.new()
			p.finished.connect(_on_projectile_finished)
			return p,
		40, self, 500)
		
	impact_fx_pool = ObjectPool.new(
		func():
			var fx = ImpactFX.new()
			fx.finished.connect(_on_impact_fx_finished)
			return fx,
		40, self, 500)
		
	burst_pool = ObjectPool.new(
		func():
			var p := GPUParticles2D.new()
			p.texture = _get_dot_texture()
			p.process_material = _get_burst_material()
			p.amount = 10
			p.lifetime = _BURST_LIFETIME
			p.one_shot = true
			p.explosiveness = 0.9
			p.emitting = false
			p.finished.connect(_on_burst_finished.bind(p))
			return p,
		_BURST_POOL_SIZE, self, 100)

func _on_projectile_finished(p: Projectile) -> void:
	projectile_pool.release(p)

func _on_impact_fx_finished(fx: ImpactFX) -> void:
	impact_fx_pool.release(fx)

func _on_burst_finished(p: GPUParticles2D) -> void:
	burst_pool.release(p)

func _spawn_dopamine_burst(pos: Vector2) -> void:
	var p: GPUParticles2D = burst_pool.acquire()
	if p == null:
		return
	p.position = pos
	p.restart()

# ------------------------------------------------------------- glitch overlay (shader)

## Explicit layer numbers: the world sits on the default canvas (0), the glitch reads the
## screen at 5, and the HUD draws untouched at 10. Leaving these implicit would let the
## HUD be distorted too, which makes the readouts unreadable exactly when Tolerance is
## high and the player most needs them.
func _build_glitch_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)

	_glitch_mat = ShaderMaterial.new()
	_glitch_mat.shader = load("res://shaders/distraction_glitch.gdshader")

	_glitch_rect = ColorRect.new()
	_glitch_rect.material = _glitch_mat
	# Anchors alone make it full-rect; setting size as well is overridden after _ready()
	# and warns. mouse_filter IGNORE is essential — a full-screen Control defaults to
	# STOP and would swallow every click on the play field.
	_glitch_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_glitch_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glitch_rect.visible = false
	layer.add_child(_glitch_rect)

## Tolerance is the sustained term, a core hit is a short spike. Hidden outright at rest
## so the screen-texture pass costs nothing during clean play.
func _update_glitch(delta: float) -> void:
	if _glitch_rect == null:
		return
	_glitch_hit = maxf(0.0, _glitch_hit - delta * 1.5)
	var amount: float = clampf(GameState.tolerance / 100.0 * 0.75 + _glitch_hit, 0.0, 1.0)
	_glitch_rect.visible = amount > 0.01
	if _glitch_rect.visible:
		_glitch_mat.set_shader_parameter("intensity", amount)

# ---------------------------------------------------------------- HUD (built in code)

const _HUD_TOP_H := 68
const _HUD_BOTTOM_H := 96

# ---------------------------------------------------------------- speed & pause
#
# A 12-wave level runs ~13 minutes at 1x, and the tail of every late wave is 20-30s of
# one slow Doomscroll crawling while the player has nothing to do. Fast-forward is table
# stakes for the genre; it is also what makes repeated playtesting affordable.

const SPEED_STEPS: Array[float] = [1.0, 2.0, 3.0]
## Designer-mode F3 override — above the normal ladder on purpose: 3× is tuned for
## players, a designer skimming dead time between layout decisions wants more.
const DESIGNER_TURBO_SPEED := 5.0

var _speed_index := 0
var _designer_turbo := false
var _paused := false
var _speed_button: Button = null
var _pause_button: Button = null
var _pause_menu: PauseMenu = null

func _cycle_speed() -> void:
	_designer_turbo = false   # touching the normal ladder always leaves turbo
	_speed_index = (_speed_index + 1) % SPEED_STEPS.size()
	_apply_time_scale()

func set_speed_index(i: int) -> void:
	_designer_turbo = false
	_speed_index = clampi(i, 0, SPEED_STEPS.size() - 1)
	_apply_time_scale()

## Pausing IS opening the menu — a bare freeze with nothing on screen read as a hang,
## and there was no way to abandon a run from inside it. While paused this game node
## (PAUSABLE) stops processing entirely; the menu lives under _hud_root (ALWAYS) and
## handles its own Resume input.
func _toggle_pause() -> void:
	if _paused:
		_close_pause_menu()
	else:
		_open_pause_menu()

func _open_pause_menu() -> void:
	if _paused:
		return
	_pause_menu = PauseMenu.new()
	_pause_menu.resume_requested.connect(_close_pause_menu)
	_pause_menu.restart_requested.connect(func():
		_reset_time_scale()
		get_tree().change_scene_to_file("res://scenes/Game.tscn"))
	_pause_menu.quit_requested.connect(func():
		_reset_time_scale()
		get_tree().change_scene_to_file("res://scenes/Menu.tscn"))
	_hud_root.add_child(_pause_menu)
	_paused = true
	get_tree().paused = true
	_apply_time_scale()

func _close_pause_menu() -> void:
	if _pause_menu != null and is_instance_valid(_pause_menu):
		_pause_menu.queue_free()
	_pause_menu = null
	_paused = false
	get_tree().paused = false
	_apply_time_scale()

## Engine.time_scale is global and survives a scene change, so it must be forced back to
## 1.0 on the way out — otherwise the menus inherit 3x and every tween there runs wrong.
func _apply_time_scale() -> void:
	var speed: float = DESIGNER_TURBO_SPEED if _designer_turbo else SPEED_STEPS[_speed_index]
	Engine.time_scale = 1.0 if _paused else speed
	if _speed_button:
		_speed_button.text = "%.0f×" % speed
	if _pause_button:
		_pause_button.text = "▶" if _paused else "❚❚"

func _reset_time_scale() -> void:
	Engine.time_scale = 1.0
	if get_tree() != null:
		get_tree().paused = false

func _exit_tree() -> void:
	_reset_time_scale()

## The HUD is laid out with containers rather than the hardcoded pixel positions it used
## to use. Those positions had already drifted into overlap (the Insight readout landed
## between Dopamine and Focus with no room reserved for it), and any new readout meant
## re-measuring the whole bar by hand.
func _build_hud() -> void:
	_hud_layer = CanvasLayer.new()
	_hud_layer.layer = 10
	add_child(_hud_layer)

	# One themed root; everything below inherits button/panel/label styling. IGNORE so a
	# full-rect Control can't swallow clicks meant for the play field — children still
	# receive their own input normally.
	_hud_root = Control.new()
	_hud_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hud_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_root.theme = UI.theme()
	# The HUD has to keep running while the tree is paused, or the pause button can't
	# un-pause itself and the draft overlay would freeze mid-decision.
	_hud_root.process_mode = Node.PROCESS_MODE_ALWAYS
	_hud_layer.add_child(_hud_root)

	_build_top_bar()
	_build_bottom_bar()

	# A designer run must LOOK different from a real one, or an F1-funded balance
	# impression sneaks into memory as a real result. The badge doubles as the cheat
	# sheet, so the hotkeys need no documentation trip.
	if GameState.designer_mode:
		var badge := UI.label(
			"DESIGNER MODE — F1 +500 Dopamine · F2 +10 Insight · F3 turbo 5× · F4 clear wave · telemetry off",
			UI.FS_SMALL, Color("ffb454"))
		badge.position = Vector2(24, _HUD_TOP_H + 4)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_hud_root.add_child(badge)

	# Smaller than it was: a full-width 46px banner across the middle of the field covered
	# the very thing the message is telling you to look at.
	_message_label = UI.label("", UI.FS_TITLE, UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	_message_label.position = Vector2(0, 150)
	_message_label.size = Vector2(1920, 80)
	_message_label.modulate.a = 0.0
	_hud_root.add_child(_message_label)

	# "Dopamine", never "Willpower". The currency and the damage channel are different
	# things, and labelling the currency Willpower quietly taught the ego-depletion model
	# (willpower as a finite tank you spend) — a theory whose large multi-lab replication
	# failed, and the opposite of this game's actual thesis: dopamine is EARNED and SPENT.
	GameState.dopamine_changed.connect(_on_dopamine_changed)
	GameState.focus_changed.connect(_on_focus_changed)
	GameState.wave_changed.connect(_on_wave_changed)
	GameState.tolerance_changed.connect(_on_tolerance_changed)
	GameState.selected_habit_changed.connect(_on_selected_habit_changed)
	GameState.run_insight_changed.connect(_on_run_insight_changed)
	GameState.insight_dropped.connect(_on_insight_dropped)

	_on_dopamine_changed(GameState.dopamine)
	_on_run_insight_changed(GameState.run_insight)
	_on_focus_changed(GameState.focus, GameState.max_focus)
	_on_wave_changed(GameState.wave, GameState.max_wave)
	_on_tolerance_changed(int(GameState.tolerance))
	_update_enemy_stats()

func _build_top_bar() -> void:
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel",
		UI.flat(Color(UI.SURFACE.r, UI.SURFACE.g, UI.SURFACE.b, 0.96), UI.BORDER, 0, 0))
	bar.position = Vector2.ZERO
	bar.size = Vector2(1920, _HUD_TOP_H)
	# STOP, not IGNORE: world_to_cell() clamps out-of-grid coordinates back into the grid,
	# so a click that fell through the bar resolved to row 0 and acted on the field.
	bar.mouse_filter = Control.MOUSE_FILTER_STOP
	_hud_root.add_child(bar)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	bar.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	row.alignment = BoxContainer.ALIGNMENT_BEGIN
	margin.add_child(row)

	# --- the two currencies, left, where the eye starts
	var dop_out: Array = []
	row.add_child(UI.stat_chip("Dopamine", UI.DOPAMINE, dop_out))
	_dopamine_label = dop_out[0]

	var ins_out: Array = []
	row.add_child(UI.stat_chip("Insight", UI.INSIGHT, ins_out))
	_insight_label = ins_out[0]

	row.add_child(UI.spacer(Vector2(8, 0)))

	# --- Focus, the thing you actually lose. A bar, and the widest element in the bar.
	_focus_meter = UIMeter.new()
	_focus_meter.caption = "Focus"
	_focus_meter.fill_color = UI.FOCUS
	_focus_meter.danger_below = 0.34
	_focus_meter.custom_minimum_size = Vector2(300, 40)
	row.add_child(_focus_meter)

	row.add_child(UI.spacer(Vector2.ZERO, true))

	_wave_label = UI.label("", UI.FS_HEAD, UI.ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
	row.add_child(_wave_label)

	_enemy_stats_label = UI.label("", UI.FS_SMALL, UI.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	_enemy_stats_label.custom_minimum_size = Vector2(230, 0)
	_enemy_stats_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_enemy_stats_label)

	row.add_child(UI.spacer(Vector2.ZERO, true))

	# --- Tolerance, right. Hidden entirely until it can actually move.
	_tolerance_meter = UIMeter.new()
	_tolerance_meter.caption = "Tolerance"
	_tolerance_meter.fill_color = UI.TOLERANCE
	_tolerance_meter.custom_minimum_size = Vector2(250, 40)
	_tolerance_meter.visible = false
	row.add_child(_tolerance_meter)

	_combo_label = UI.label("", UI.FS_TITLE, UI.DOPAMINE, HORIZONTAL_ALIGNMENT_RIGHT)
	_combo_label.custom_minimum_size = Vector2(110, 0)
	_combo_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_combo_label)

func _build_bottom_bar() -> void:
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel",
		UI.flat(Color(UI.SURFACE.r, UI.SURFACE.g, UI.SURFACE.b, 0.96), UI.BORDER, 0, 0))
	bar.position = Vector2(0, 1080 - _HUD_BOTTOM_H)
	bar.size = Vector2(1920, _HUD_BOTTOM_H)
	# Same reason as the top bar: the gaps between buttons used to build towers on row 18.
	bar.mouse_filter = Control.MOUSE_FILTER_STOP
	_hud_root.add_child(bar)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	bar.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	margin.add_child(row)

	for i in range(Data.HABIT_ORDER.size()):
		var key := String(Data.HABIT_ORDER[i])
		var d := Data.get_habit(key)
		var b := UI.button("%s\n%d ◆" % [d.short, d.build_cost], UI.FS_BODY, Vector2(132, 0))
		# Numbers, not just prose: a tooltip the player can compare against the enemy's
		# stats is a decision aid; flavor text alone is decoration.
		b.tooltip_text = "%s — %d Dopamine\n%s\n%s\nHotkey: %d" \
			% [d.name, d.build_cost, _habit_stats_line(d), d.description, i + 1]
		b.autowrap_mode = TextServer.AUTOWRAP_OFF
		row.add_child(b)
		b.pressed.connect(_select_habit.bind(key))
		_habit_buttons[key] = b
		b.add_child(_hotkey_badge(str(i + 1)))

	row.add_child(UI.spacer(Vector2(18, 0)))
	var sep := VSeparator.new()
	row.add_child(sep)
	row.add_child(UI.spacer(Vector2(18, 0)))

	var intervention_keys: Array[String] = ["Q", "W", "E"]
	for i in range(Data.INTERVENTION_ORDER.size()):
		var ikey := String(Data.INTERVENTION_ORDER[i])
		var idef := Data.get_intervention(ikey)
		var b := UI.button(idef.short, UI.FS_BODY, Vector2(126, 0))
		var hotkey: String = intervention_keys[i] if i < intervention_keys.size() else ""
		b.tooltip_text = "%s\n%s%s" % [idef.name, idef.description,
			("\nHotkey: " + hotkey) if hotkey != "" else ""]
		row.add_child(b)
		b.pressed.connect(_select_intervention.bind(ikey))
		_intervention_buttons[ikey] = b
		if hotkey != "":
			b.add_child(_hotkey_badge(hotkey))

	row.add_child(UI.spacer(Vector2.ZERO, true))

	_pause_button = UI.button("❚❚", UI.FS_HEAD, Vector2(64, 0))
	_pause_button.tooltip_text = "Pause / resume (Esc)"
	_pause_button.pressed.connect(_toggle_pause)
	row.add_child(_pause_button)

	_speed_button = UI.button("1×", UI.FS_HEAD, Vector2(72, 0))
	_speed_button.tooltip_text = "Game speed — click to cycle 1× / 2× / 3× (+ and −)"
	_speed_button.pressed.connect(_cycle_speed)
	row.add_child(_speed_button)

	row.add_child(UI.spacer(Vector2(14, 0)))

	if GameState.quick_hit_enabled:
		var q := UI.button("", UI.FS_BODY, Vector2(170, 0))
		q.tooltip_text = "Instant Dopamine on demand. Each use pays less than the last and " \
			+ "permanently raises your baseline Tolerance, which shrinks every reward for " \
			+ "the rest of the level."
		row.add_child(q)
		q.pressed.connect(do_quick_hit)
		_quick_hit_button = q
		_update_quick_hit_button()

	# The one call-to-action, filled and last in the reading order.
	_start_wave_button = UI.primary_button("▶ Start Wave 1", UI.FOCUS, UI.FS_HEAD,
		Vector2(260, 0))
	_start_wave_button.tooltip_text = "Call the wave now (Space). The sooner you call " \
		+ "it, the bigger the Dopamine bonus."
	row.add_child(_start_wave_button)
	_start_wave_button.pressed.connect(_on_start_wave_pressed)

	# Paint the ability buttons in their own colours immediately — otherwise they sit
	# plain grey until the first cooldown tick happens to refresh them.
	_update_intervention_buttons()

## Small corner label naming a button's hotkey — the keys existed for a full phase
## before anything on screen admitted it.
func _hotkey_badge(key_name: String) -> Label:
	var badge := UI.label(key_name, UI.FS_MICRO, UI.TEXT_FAINT)
	badge.position = Vector2(7, 3)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return badge

## One stats line for a habit, in player vocabulary (Data.TERM). With a live `habit`
## it reads the current_* values, so drafted cards and growth ranks show; with null it
## reads the .tres base — the form the build-bar tooltips use.
func _habit_stats_line(def: HabitData, habit: Habit = null) -> String:
	if def.is_blocker:
		return "%d Allies · %d HP · guards %dpx" % [def.ally_count,
			def.ally_health, int(def.guard_radius)]
	if def.is_support():
		return "Extends your Routine %dpx — habits inside it keep working" % int(def.range)
	var wp: int = habit.current_willpower_damage if habit != null else def.willpower_damage
	var aw: int = habit.current_awareness_damage if habit != null else def.awareness_damage
	var rng: float = habit.current_attack_range if habit != null else def.range
	var cd: float = habit.current_fire_cooldown if habit != null else def.fire_cooldown
	var parts: Array[String] = []
	if wp > 0:
		parts.append("%d %s" % [wp, Data.TERM.damage])
	if aw > 0:
		parts.append("%d %s" % [aw, Data.TERM.mind_damage])
	if def.reframe > 0:
		parts.append("−%d %s" % [def.reframe, Data.TERM.armor])
	if def.boredom > 0.0:
		# String.num, not "%g" — GDScript's format operator has no %g and errors on it.
		parts.append("%s/s %s" % [String.num(def.boredom, 1), Data.TERM.dot])
	if def.slow > 0.0:
		parts.append("%d%% %s" % [roundi((1.0 - def.slow) * 100.0), Data.TERM.slow])
	if cd > 0.0:
		parts.append(("pulses every %.2fs" if def.aoe else "fires every %.2fs") % cd)
	parts.append("range %d" % int(rng))
	return "  ·  ".join(parts)

## "damage 3 → 5 · range 360 → 460" for an upgrade button's tooltip: only the stats
## that actually change, and computed through ModifierManager on BOTH sides — family
## matching means this run's cards apply to the next tier too, so the player compares
## what they have against what they would get.
func _upgrade_delta_text(cur_def: HabitData, habit: Habit, up_def: HabitData) -> String:
	var parts: Array[String] = []
	if up_def.is_blocker:
		if up_def.ally_count != cur_def.ally_count:
			parts.append("Allies %d → %d" % [cur_def.ally_count, up_def.ally_count])
		if up_def.ally_health != cur_def.ally_health:
			parts.append("Ally HP %d → %d" % [cur_def.ally_health, up_def.ally_health])
		if up_def.ally_damage != cur_def.ally_damage:
			parts.append("Ally %s %d → %d" % [Data.TERM.damage,
				cur_def.ally_damage, up_def.ally_damage])
		if int(up_def.guard_radius) != int(cur_def.guard_radius):
			parts.append("guards %d → %d" % [int(cur_def.guard_radius), int(up_def.guard_radius)])
		return " · ".join(parts)

	var up_key := String(up_def.id)
	var wp_cur: int = habit.current_willpower_damage if habit != null else cur_def.willpower_damage
	var aw_cur: int = habit.current_awareness_damage if habit != null else cur_def.awareness_damage
	var rng_cur: float = habit.current_attack_range if habit != null else cur_def.range
	var cd_cur: float = habit.current_fire_cooldown if habit != null else cur_def.fire_cooldown
	var wp_new := int(ModifierManager.get_modified_stat(
		float(up_def.willpower_damage), ModifierManager.STAT_WILLPOWER, up_key))
	var aw_new := int(ModifierManager.get_modified_stat(
		float(up_def.awareness_damage), ModifierManager.STAT_AWARENESS, up_key))
	var rng_new := ModifierManager.get_modified_stat(
		up_def.range, ModifierManager.STAT_RANGE, up_key)
	var cd_new := maxf(0.02, ModifierManager.get_modified_stat(
		up_def.fire_cooldown, ModifierManager.STAT_FIRE_COOLDOWN, up_key))
	if wp_new != wp_cur:
		parts.append("%s %d → %d" % [Data.TERM.damage, wp_cur, wp_new])
	if aw_new != aw_cur:
		parts.append("%s %d → %d" % [Data.TERM.mind_damage, aw_cur, aw_new])
	if int(rng_new) != int(rng_cur):
		parts.append("range %d → %d" % [int(rng_cur), int(rng_new)])
	if absf(cd_new - cd_cur) >= 0.005:
		parts.append("every %.2fs → %.2fs" % [cd_cur, cd_new])
	if up_def.boredom != cur_def.boredom and up_def.boredom > 0.0:
		parts.append("%s %s/s → %s/s" % [Data.TERM.dot,
			String.num(cur_def.boredom, 1), String.num(up_def.boredom, 1)])
	return " · ".join(parts)

# ---------------------------------------------------------------- HUD readouts

func _on_dopamine_changed(v: int) -> void:
	if _dopamine_label:
		_dopamine_label.text = str(v)
	# Affordability is state the player would otherwise have to work out by reading a
	# cost and comparing it to a number at the far end of the screen.
	_refresh_habit_affordability()

func _on_run_insight_changed(v: int) -> void:
	if _insight_label:
		_insight_label.text = "%d ◆" % v

func _on_focus_changed(v: int, m: int) -> void:
	if _focus_meter:
		_focus_meter.update_meter(float(v), float(m), "%d / %d" % [v, m])

func _on_wave_changed(v: int, m: int) -> void:
	if _wave_label:
		_wave_label.text = "Wave %d / %d" % [v, m]

func _refresh_habit_affordability() -> void:
	for key: String in _habit_buttons:
		var d := Data.get_habit(key)
		if d == null:
			continue
		var b: Button = _habit_buttons[key]
		var affordable: bool = GameState.dopamine >= d.build_cost
		b.modulate = Color(1, 1, 1) if affordable else Color(1, 1, 1, 0.42)

## Left = not yet dealt with this wave (still queued to spawn, or alive on the field).
## Drops on a kill AND on a reached-core hit — both remove the distraction from the field.
func _update_enemy_stats() -> void:
	if _enemy_stats_label == null:
		return
	var left: int = spawn_queue.size() + _distractions.size()
	_enemy_stats_label.text = "%d left · %d on field · %d defeated" % [
		left, _distractions.size(), GameState.kills]

func _select_habit(key: String) -> void:
	_close_panel()
	_select_intervention(null)
	_cancel_aiming()
	if GameState.selected_habit == key:
		GameState.select_habit(null)
	else:
		GameState.select_habit(key)

## Selection is shown with a border, NOT with modulate — modulate is already carrying
## affordability (dimmed = can't afford), and two meanings on one property meant each
## update silently wiped the other.
func _on_selected_habit_changed(key) -> void:
	for k: String in _habit_buttons:
		var b: Button = _habit_buttons[k]
		if k == key:
			b.add_theme_stylebox_override("normal",
				UI.flat(UI.PANEL_HI, UI.ACCENT, 2, UI.RADIUS_SM, 10))
			b.add_theme_color_override("font_color", UI.ACCENT)
		else:
			b.remove_theme_stylebox_override("normal")
			b.remove_theme_color_override("font_color")

## A drop is rare enough (~1 in 20 defeats) to deserve its own popup rather than being
## folded into the batched Dopamine counter — being noticeable is the point. This is the
## variable-ratio hook the game is teaching about, aimed at the player.
func _on_insight_dropped(at_position: Vector2, amount: int) -> void:
	_pop_text(at_position, "+%d ◆" % amount, Color("7ef2e6"))

func _on_tolerance_changed(v: int) -> void:
	# Shown whenever Tolerance can actually move — Quick Hit levels, or any level where a
	# card has raised the baseline. Otherwise a card cost would be invisible to the player.
	var visible_now: bool = GameState.quick_hit_enabled or GameState.tolerance_floor > 0.0
	if _tolerance_meter:
		_tolerance_meter.visible = visible_now
		if visible_now:
			# The floor is drawn as a darker locked segment under the live fill: the
			# exposed part is what will decay, the rest never comes back. A permanent
			# cost the player cannot see reads as a temporary one.
			var readout := "%d%%" % v
			if GameState.tolerance_floor > 0.0:
				readout += "  ·  floor %d%%" % int(GameState.tolerance_floor)
			_tolerance_meter.update_meter(float(v), 100.0, readout, GameState.tolerance_floor)
	# The Quick Hit payout is tolerance-scaled, so its label moves whenever this does.
	_update_quick_hit_button()

var _flash_tween: Tween = null

func _flash(text: String, color: Color = Color(1, 1, 1)) -> void:
	if _message_label == null:
		return
	# Kill the previous tween first. Two flashes inside 1.3s used to leave two tweens
	# animating the same modulate:a, and the older one's fade wiped the newer message.
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_message_label.text = text
	_message_label.modulate = color
	_message_label.modulate.a = 1.0
	_flash_tween = create_tween()
	_flash_tween.tween_interval(0.7)
	_flash_tween.tween_property(_message_label, "modulate:a", 0.0, 0.6)

## Failure feedback. Separate from _flash() because every rejection used the default
## white, making "Not enough Dopamine" look identical to "Wave 3" — and it appears at the
## cursor as well as the banner, since the banner is 600-900px from where the player is
## actually looking.
func _flash_error(text: String) -> void:
	Sfx.play(&"error")
	_flash(text, UI.DANGER)
	_pop_text(get_global_mouse_position(), text, UI.DANGER)

func add_shake(amount: float) -> void:
	_shake_amount = maxf(_shake_amount, amount)

func _pop_text(pos: Vector2, text: String, color: Color) -> void:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", 16)
	l.modulate = color
	_hud_layer.add_child(l)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "position:y", pos.y - 36.0, 0.65).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.65).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.set_parallel(false)
	tw.tween_callback(l.queue_free)
