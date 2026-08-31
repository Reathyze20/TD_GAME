class_name Game
extends Node2D

var bg_texture: Texture2D = null
var _spawn_marker_tex: Texture2D = null
var _goal_marker_tex: Texture2D = null
## Kreslene jadro (assets/terrain/iso/props/core.png). Kdyz existuje, nahradi jak maly
## podstavec, tak vektorove kruhy uvnitr -- prstence kolem nej ale zustavaji, protoze
## nesou stav (zbyvajici Focus, tempo zasahu), ktery sprite ukazat neumi.
var _core_prop_tex: Texture2D = null

# Core gameplay (maze TD). Attach to the root Node2D of Game.tscn.
# HIGH GROUND cells are fixed terrain that BLOCK movement AND are the only spots
# habits can be built on. Distractions pathfind (AStarGrid2D) around high ground
# from spawn ZONES to the Focus core (objective).
#
# Build & SWHAOP Aiming flow:
#   Left-click with habit selected        → build habit & enter Aiming Mode
#   Aiming Mode (mouse move)              → orientation (facing_angle) & dynamic cone width (arc_angle 15°..120°)
#   Left-click while Aiming               → lock in orientation and complete placement
#   Right-click while Aiming              → cancel build & refund Dopamine
#   Left-click with intervention selected → cast intervention at mouse location
#   Left-click with no selection          → open upgrade/sell/re-aim panel on built cell
#   Mouse wheel with a habit panel open   → open/close that habit's cone live (see _adjust_arc)
#   Right-click                           → close any panel/overlay, deselect habit & intervention

var level: LevelData

var astar: AStarGrid2D
## Single shared BFS distance field FROM the objective (docs/refactor/PATHFINDING.MD P4,
## building on P1's scripts/flow_field.gd). Every live Distraction reads its next step
## from THIS field instead of solving (or being handed) its own route — `astar` above
## stays alive only for the WEIGHTED previews (_compute_path_previews) and dev/test
## probes that want lane-aware routing; live movement never calls astar.get_id_path()
## again. Rebuilt whenever `high_ground` changes (today: only _build_field() at level
## start and _set_sunk() during the sinking-walls spike) — see _rebuild_flow_field().
var flow_field: FlowField = null
var objective_cell: Vector2i
var objective_pos: Vector2
var high_ground := {}            # Vector2i -> true (blocking + buildable)
## The lane network AS IT IS RIGHT NOW — starts as level.path_cells and grows when a
## trod opens (see _open_trod).
##
## Deliberately separate from `level.path_cells` rather than appended to it. `level` is
## already a deep duplicate, so writing into it would be safe; keeping it read-only is
## about not confusing two different questions. `level.path_cells` answers "what did the
## designer paint", this answers "where does the horde prefer to walk right now", and
## _build_field rebuilds the second from the first. The sinking-walls spike below does
## mutate `level.high_ground` and consequently has to remember to put every cell back.
var lane_cells := {}             # Vector2i -> true
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
## The Brain Fog rect. Above every world child (entities top out at y-sort z 0, the
## placement overlay claims Z_FOG + 1 deliberately) and still on canvas 0, so the glitch
## shader (CanvasLayer 5) distorts the darkness together with the field it covers.
const Z_FOG := 60
var path_layer: TileMapLayer = null

var _distractions: Array[Distraction] = []

# Y-sorted container for every field entity (habits, distractions, allies). Sorting by
# global Y means whatever stands lower on screen draws in front, which is the 2.5D depth
# cue from `01`. It works on plain _draw() shapes, so this is real now and not merely
# groundwork for future sprite art. Projectiles and VFX stay direct children of Game,
# added later in the tree, so they always render above the field.
var entities: Node2D

## Batched horde body/glow/shadow renderer (P5, docs/refactor/PATHFINDING.MD) — a
## sibling of `entities`, not a child of it: see horde_renderer.gd's own Y-sort header
## for why a MultiMeshInstance2D batch cannot live inside a y-sorted container the same
## way an individual Distraction node did. Added to the tree right after `entities` so
## it draws above every z=0 main entity but below projectiles/world UI, which are added
## later still. Rebuilt once per frame from _process(), below.
var horde_renderer: HordeRenderer

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

## Rally-point placement mode — the Nutrition Guild's version of aiming. Entered from
## the guild panel; the next left-click plants the rally (clamped to the leash radius),
## right-click keeps the old one. Deliberately NOT merged with is_aiming: that mode
## drives a cone preview off a Habit and this one drives a flag off a Barracks, and the
## two null different references on exit.
var is_setting_rally := false
var rally_barracks: Barracks = null
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
	"call_a_friend": 0.0,
	"airplane_mode": 0.0,
	"moment_of_clarity": 0.0
}
var _shake_amount: float = 0.0
## Purely cosmetic screen-shake jitter draws from ITS OWN stream, never the shared
## global randf()/randf_range() — this decay stays on Godot's real, unscaled per-frame
## call by design (smooth at any speed, including 0.25x, where the fixed sim tick only
## fires once every ~4 frames), so it redraws a different number of times per unit of
## simulated time depending on real frame rate. A frame-count-dependent draw against the
## SAME global stream that seed(run_seed) seeds would desync every outcome-critical draw
## after it (Q1, docs/refactor/PATHFINDING.MD — same class of bug Sfx.gd's own _sim_ms
## comment already documents once for this project). Seed is arbitrary; nothing reads it.
var _shake_rng := RandomNumberGenerator.new()

# HUD references
var _hud_layer: CanvasLayer
## Themed root inside the CanvasLayer — every HUD widget and overlay hangs off this, so
## they all inherit UI.theme() instead of styling themselves one property at a time.
var _hud_root: Control
var _dopamine_label: Label
var _streak_label: Label
var _insight_label: Label
var _rush_label: Label
var _bandwidth_label: Label
var _focus_meter: UIMeter
var _burnout_meter: UIMeter
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
## The panel's cone-width readout, kept so the mouse wheel can refresh it in place
## instead of tearing the whole panel down and rebuilding it under the cursor.
var _panel_arc_label: Label = null
## Degrees per wheel notch. Twenty-one notches from the tightest beam to the widest fan:
## coarse enough to cross the range in one flick, fine enough to sit on a wall's edge.
const ARC_WHEEL_STEP := 5.0

# Draft overlay
var _draft_overlay: Control = null
## The hand currently on offer, alongside _draft_overlay — options rolled by
## _roll_draft_options() were previously only reachable via the overlay's Buy button
## Callables. Non-behavioral: read-only for external callers (S2's simulator driver),
## nothing here changes what a real player sees or can do.
var _draft_options: Array[CardData] = []
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
	# ALWAYS so build/sell/aim/Quick-Hit/intervention commands (_unhandled_input,
	# _process's cosmetic layer, _physics_process's fixed-tick accumulator) keep running
	# while the tree is paused (Q1, docs/refactor/PATHFINDING.MD) — the same reason
	# _hud_root is ALWAYS (see _build_hud()). The simulation itself still freezes,
	# because _physics_process()'s accumulator reads `_paused` and gains zero ticks; it
	# does not rely on Godot's own pause machinery to stop. `entities` is pinned back to
	# PAUSABLE right after it's created below, specifically so the purely cosmetic
	# automatic processing under it (walk-cycle animators, in-flight cosmetic tweens,
	# particles) still freezes on pause like it always did — only the command path needed
	# to change.
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Before anything reads current_level_index: an editor Playtest launch may be
	# redirecting this boot to the level that was just baked.
	_consume_playtest_request()
	# _draw() paints the background and the vector walls on this node itself, so the node's
	# own filter decides how they scale. The background is authored at 640x304 and blown up
	# x3 to the 1920x912 field — under the default linear filter that arrives as mush.
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
	if ResourceLoader.exists("res://assets/terrain/iso/props/core.png"):
		_core_prop_tex = load("res://assets/terrain/iso/props/core.png")
	# P8: composition replaces the plain duplicate(true) that used to stand here. For a
	# level with no `base` and no `segment` header — every level on disk today —
	# MapComposer.compose() IS that deep copy and nothing else changes; for a level built
	# on others it also unions in the geometry of whichever segments the save has
	# unlocked. Either way the result is a fresh, flat LevelData, so the perks and
	# sinking-walls edits below still land on a throwaway copy and never on Data's shared
	# resource.
	level = MapComposer.compose(Data.get_level(GameState.current_level_index))
	fog_enabled = level.fog
	shadow_enabled = level.shadows
	routine_gates_enabled = level.routine_gates
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
	_autoplay_left = -1.0   # a theft armed on the previous level must not follow you here
	_effort_offered = false
	entities = Node2D.new()
	entities.name = "Entities"
	entities.y_sort_enabled = true
	# Breaks the PROCESS_MODE_ALWAYS this node (Game) now carries — see _ready()'s own
	# header comment — so everything spawned under here (distractions, habits,
	# projectiles, defenders, and their cosmetic children like DistractionAnimator)
	# still freezes automatically on pause, the way it did before Q1.
	entities.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(entities)
	horde_renderer = HordeRenderer.new()
	horde_renderer.name = "HordeRenderer"
	add_child(horde_renderer)
	# After entities, so the placement preview draws above terrain AND units. The corner
	# terrain tiles overhang half a cell past their vertex, so anything painted in
	# Game._draw() — which renders below every child — gets clipped by tissue near walls;
	# that is exactly where towers get placed.
	_placement_overlay = PlacementOverlay.new()
	_placement_overlay.name = "PlacementOverlay"
	_placement_overlay.game = self
	# Above the Brain Fog: the build preview is UI, and a marker swallowed by the very
	# darkness that explains WHY the cell is invalid would leave the refusal unreadable.
	_placement_overlay.z_index = Z_FOG + 1
	add_child(_placement_overlay)
	# P7 (docs/refactor/PATHFINDING.MD): the spawn telegraph's pulse and countdown number
	# need to animate every real frame regardless of sim speed/pause (same cosmetic-vs-
	# gameplay split Q1 drew everywhere else), so this is built once here like
	# PlacementOverlay — NOT inside _build_field() like StaticOverlay, which is deliberately
	# redrawn only on specific triggers because its content never changes between them.
	_telegraph_overlay = TelegraphOverlay.new()
	_telegraph_overlay.name = "TelegraphOverlay"
	_telegraph_overlay.game = self
	# Above the fog for the same reason PlacementOverlay is: the hard rule is that a
	# telegraphed spawn is truthful, which requires it to be READABLE — swallowed by the
	# darkness the marker is trying to warn about would defeat the entire mechanic.
	_telegraph_overlay.z_index = Z_FOG + 2
	add_child(_telegraph_overlay)
	_init_pools()
	_build_field()
	_build_fog_layer()
	_build_shadow_light_layer()
	# The occluder geometry the lights cast against. This call was MISSING: the builder,
	# its layer, its counter and _apply_shadow_enabled's visibility toggle all existed,
	# but nothing ever ran it — so every lamp lit straight through every wall and
	# _test_shadow_occlusion could never find a blocked sample. Must come after
	# _build_field(), which is what fills high_ground.
	_build_shadow_occluders()
	_build_glitch_overlay()
	_build_hud()

	SignalBus.game_over.connect(_on_bus_game_over)
	GameState.defeat_reward_granted.connect(_on_defeat_reward_granted)
	GameState.satisfaction_changed.connect(_on_satisfaction_changed)
	# Designer runs never open the log: every RunLog method no-ops until begin() is
	# called, and a run with F1 money in it would poison the balance dataset.
	if not GameState.designer_mode:
		_run_log.begin("Level_%02d" % (GameState.current_level_index + 1))
	# Same designer rule, enforced inside Mirror: cheat keys would make every number on
	# the receipt a lie, and the receipt's credibility is the whole product.
	Mirror.begin_level(level.id)
	# After _build_hud(): the cue and the offer panel hang off _hud_root.
	_setup_attention()
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
	astar.cell_size = Vector2(1, 1)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar.update()

	objective_cell = level.objective
	objective_pos = cell_center(objective_cell)
	_routine_sources = [objective_pos]

	high_ground = {}
	build_spots = {}
	for cell: Vector2i in level.high_ground:
		if cell == objective_cell:
			continue
		high_ground[cell] = true
		if astar.is_in_bounds(cell.x, cell.y):
			astar.set_point_solid(cell, true)
	_rebuild_flow_field()

	var b: int = Data.BUILD_BLOCK
	for cell: Vector2i in high_ground:
		if cell.x % b != b / 2 or cell.y % b != b / 2:
			continue
		var whole := true
		for dy in range(-(b / 2), b / 2 + 1):
			for dx in range(-(b / 2), b / 2 + 1):
				if not high_ground.has(cell + Vector2i(dx, dy)):
					whole = false
					break
			if not whole:
				break
		if not whole:
			continue
		var bs := BuildSpot.new()
		add_child(bs)
		bs.setup(self, cell)
		build_spots[cell] = bs

	lane_cells = {}
	for c: Vector2i in level.path_cells:
		lane_cells[c] = true
	_trods_open = {}

	_build_platforms()
	_apply_path_weights()
	_build_path_layer()
	_build_wall_segments()

	spawn_zone_cells = []
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
	_build_camera()
	if _static_overlay != null and is_instance_valid(_static_overlay):
		_static_overlay.queue_free()
	_static_overlay = StaticOverlay.new()
	_static_overlay.game = self
	_static_overlay.z_index = Z_DECOR
	add_child(_static_overlay)
	_compute_path_previews()

## Rebuilds the shared movement field every live Distraction reads its direction from.
## The only two callers today: _build_field() (level start) and _set_sunk() (the sinking
## walls spike toggling `high_ground`) — those are the only two places this codebase
## mutates `high_ground` after level load. `_open_trod()` deliberately does NOT call
## this: a trod only reclassifies already-open cells as lane (see its own comment), it
## never touches `high_ground`, so the field a trod would produce is bit-identical to
## the one already live — rebuilding would just burn ~0.5ms proving nothing changed.
func _rebuild_flow_field() -> void:
	var g = Data.GRID
	flow_field = FlowField.build(int(g.cols), int(g.rows), objective_cell, high_ground)

## Makes the designer's painted lanes actually attract the horde.
##
## Sets the weight on EVERY cell, not just the off-lane ones. It used to skip lane cells
## on the assumption they were still at their default 1.0 — true when this ran once at
## level start, false the moment a trod opens and re-runs it: cells that just became
## lane would have kept the off-lane penalty they were given the first time, and the new
## route would have been ignored by the very pathfinder it was built for.
func _apply_path_weights() -> void:
	if lane_cells.is_empty() or level.path_off_lane_cost <= 1.0:
		return
	var g = Data.GRID
	for y in range(int(g.rows)):
		for x in range(int(g.cols)):
			var c := Vector2i(x, y)
			if astar.is_in_bounds(c.x, c.y):
				astar.set_point_weight_scale(
					c, 1.0 if lane_cells.has(c) else level.path_off_lane_cost)

func _build_background_layer() -> void:
	var plate := ColorRect.new()
	plate.name = "BackgroundPlate"
	plate.color = Color("0d1017")
	plate.position = Vector2.ZERO
	plate.size = Vector2(480, 270)
	plate.z_index = Z_BACKGROUND
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(plate)


## The shadow a wall drops onto the floor at its foot. Without it a wall does not sit on
## the ground, it hovers over it — the corridors read as cut out of a flat sheet rather
## than sunk between raised masses. It cannot live in the terrain atlas, because the
## shadow belongs to the cell BELOW the wall, which is floor and may be walked on.
##
## Length is constant regardless of how tall the wall is. That is a convention, not
## physics: a shadow that grew with height would swallow the units standing next to it.
## Jak hluboko visi celo zdi do bunky pod ni, v pixelech OBRAZOVKY.
##
## 24 px se pri zjemneni mrizky (18. 8. 2026) zamerne NEZMENILO: zed na obrazovce
## zustava presne tak vysoka, jak byla, meni se jen jemnost rastru. Drive to bylo
## 8 art px na x3, dnes 24 art px na x1 -- tytez pixely na obrazovce, trikrat vic
## kresby. Sdileno s WallShadow, protoze stin musi zacinat tam, kde celo konci.
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
## 32, not the old 48, because the drawn terrace block (see _build_terrace_blocks) has
## walls exactly one tile height tall — measured on the kit, not chosen. Everything that
## needs to stand on a plateau reads this one constant (base_habit.gd:72 sets _iso_lift
## from it, and the hover preview at _draw_placement_preview uses it), so the art and
## the things standing on it cannot drift apart.
const WALL_HEIGHT := 32.0
var _wall_nodes: Array[Node2D] = []
const WALL_MATERIAL_PATH := "res://assets/iso_pilot/wall_material.png"
const WALL_FALLBACK_PATH := "res://assets/iso_pilot/wall_material_placeholder.png"
const TERRACE_BLOCK_PATH := "res://assets/terrain/iso/terrace/block.png"
const TERRACE_CAP_PATH := "res://assets/terrain/iso/terrace/cap.png"

class IsoWallSegment extends Node2D:
	var pts: PackedVector2Array
	var tex: Texture2D
	var shade: float = 1.0

	func _draw() -> void:
		if pts.size() < 4 or tex == null:
			return
		var min_pt := pts[0]
		var max_pt := pts[0]
		for p in pts:
			min_pt = min_pt.min(p)
			max_pt = max_pt.max(p)
		var span := max_pt - min_pt
		if span.x == 0.0:
			span.x = 1.0
		if span.y == 0.0:
			span.y = 1.0
		var uvs := PackedVector2Array()
		for p in pts:
			uvs.append((p - min_pt) / span)
		draw_polygon(pts, PackedColorArray([Color(shade, shade, shade, 1.0)]), uvs, tex)


class IsoTopSegment extends Node2D:
	var pts: PackedVector2Array
	var tex: Texture2D
	var tint: Color = Color(0.85, 0.88, 0.95, 1.0)

	func _draw() -> void:
		if pts.size() < 4 or tex == null:
			return
		var min_pt := pts[0]
		var max_pt := pts[0]
		for p in pts:
			min_pt = min_pt.min(p)
			max_pt = max_pt.max(p)
		var span := max_pt - min_pt
		if span.x == 0.0:
			span.x = 1.0
		if span.y == 0.0:
			span.y = 1.0
		var uvs := PackedVector2Array()
		for p in pts:
			uvs.append((p - min_pt) / span)
		draw_polygon(pts, PackedColorArray([tint]), uvs, tex)


## Iso walls, as y-sorted objects in `entities` rather than a background layer — a unit
## north of a wall must draw behind it. Nodes are TRACKED in _wall_nodes (rather than
## just parented and forgotten) so the set can be rebuilt when the maze changes shape:
## the sinking-walls spike erodes a block at runtime and the art has to follow.
##
## They stay DIRECT children of `entities`; a grouping container would sort as one unit
## and every segment inside it would share a single depth.
func _build_wall_segments() -> void:
	if level == null:
		return
	for n in _wall_nodes:
		if is_instance_valid(n):
			n.queue_free()
	_wall_nodes.clear()
	# MODE_SQUARE has no terrace art to fall back to: TERRACE_BLOCK_PATH/CAP are
	# diamond-shaped iso sprites (docs/art/iso_bible.md §5's building kit) and do not
	# fit a square cell. See _build_square_terrain()'s own doc comment.
	if GridProjection.active_mode == GridProjection.MODE_SQUARE:
		_build_square_terrain()
		return
	# Drawn terrace block (PixelLab building kit) if installed, else the old
	# code-drawn parallelograms. See _spawn_terrace_block for why the drawn kit is
	# allowed to supply geometry here when docs/art/iso_bible.md §5 otherwise forbids it.
	if ResourceLoader.exists(TERRACE_BLOCK_PATH) and ResourceLoader.exists(TERRACE_CAP_PATH):
		_build_terrace_blocks()
		return

	var mat_path := WALL_MATERIAL_PATH if ResourceLoader.exists(WALL_MATERIAL_PATH) else WALL_FALLBACK_PATH
	if not ResourceLoader.exists(mat_path):
		return
	var tex: Texture2D = load(mat_path)
	var floor_tex: Texture2D = load("res://assets/iso_pilot/floor_tile.png") if ResourceLoader.exists("res://assets/iso_pilot/floor_tile.png") else tex
	var solid := {}
	for c: Vector2i in level.high_ground:
		if c != level.objective:
			solid[c] = true

	var corners := GridProjection.diamond_corners()
	var lift := Vector2(0.0, WALL_HEIGHT)

	for c: Vector2i in solid:
		var pos := Data.cell_center(c)

		# Top plateau cap
		var top := IsoTopSegment.new()
		top.pts = PackedVector2Array([
			corners[0] - lift,
			corners[1] - lift,
			corners[2] - lift,
			corners[3] - lift
		])
		top.tex = floor_tex
		top.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		top.position = pos
		entities.add_child(top)
		_wall_nodes.append(top)

		# South-East face (facing down-right) exposed when c + (1, 0) is not solid
		if not solid.has(c + Vector2i(1, 0)):
			_spawn_wall_segment(pos, corners[1], corners[2], tex, 1.0)

		# South-West face (facing down-left) exposed when c + (0, 1) is not solid
		if not solid.has(c + Vector2i(0, 1)):
			_spawn_wall_segment(pos, corners[3], corners[2], tex, 0.72)

		# Back walls if at boundaries
		if c.y == 0 and not solid.has(c + Vector2i(0, -1)):
			_spawn_wall_segment(pos, corners[0], corners[1], tex, 1.0)
		if c.x == 0 and not solid.has(c + Vector2i(-1, 0)):
			_spawn_wall_segment(pos, corners[0], corners[3], tex, 0.72)


## One drawn block per solid cell, y-sorted, back to front.
##
## WHY THE GENERATOR IS ALLOWED TO SUPPLY GEOMETRY HERE
##
## docs/art/iso_bible.md §5 says the generator supplies material and the code supplies
## shape, because two independently-generated pieces never agree on a shared edge (the
## pilot measured 3px of drift). A building KIT is the documented exception and it was
## verified by measurement, not by opinion: every piece is drawn against one lattice on
## one shared 102x83 canvas, and the floor diamond measures 64x33 widening exactly 4px
## per row — a grid-exact 2:1 diamond. (`create_tiles_pro` is NOT: its diamonds came
## back 64x28..30 with ragged widths and tiled with visible holes.)
##
## No neighbour test is needed. Drawing a full block on every solid cell would leave
## interior walls showing, except that the cell in FRONT (higher x+y, so drawn later)
## covers exactly the parallelogram its neighbour's wall occupies. Only the walls on
## the real edge of the mass survive — the sort does the culling for free.
## Stín, který terasa vrhá na podlahu — v ISO prostoru.
##
## PROČ NOVÁ TŘÍDA A NE `WallShadow`
##
## `WallShadow` je psaná pro čtvercovou mřížku: slučuje vodorovné běhy buněk a kreslí
## `draw_rect`. Na kosočtvercové desce by z toho byly obdélníky ležící napříč mřížkou.
## Tohle je táž myšlenka přeložená do iso — místo obdélníku kosočtverec, místo „jižní
## hrany" posun o buňku ve směru, kam padá stín.
##
## PROČ TO TEPRVE TEĎ DÁVÁ SMYSL
##
## Dokud měla podlaha texturu, stín na ní nebyl k rozeznání od vzoru — playtest 18. 8.
## přesně to řekl o Light2D verzi („textury čtou jako rozbité", docs/core/15). Na ploché
## podlaze je to naopak JEDINÁ věc, která říká, že blok na zemi stojí a neplave nad ní.
## Ploché plochy čtou jako těleso díky vrženému stínu, ne díky textuře.
##
## Směr: bible má světlo ZLEVA (levý bok terasy 70 %, pravý 45 %), takže stín padá
## doprava — v naší mřížce +x, což je na obrazovce doprava dolů. Kdyby se to někdy
## otočilo, musí se otočit obojí naráz, jinak si blok a jeho stín odporují.
class TerraceShadow extends Node2D:
	## buňka -> průhlednost. Dva kroky místo přechodu: plochý styl nemá gradienty.
	var steps: Dictionary = {}

	func _draw() -> void:
		# Studený a průsvitný, nikdy černý — neutrálně černý stín čte jako díra v desce,
		# modře posunutý jako stín. Převzato z WallShadow, kde to stálo playtest.
		for cell: Vector2i in steps:
			draw_colored_polygon(GridProjection.cell_diamond(cell), Color(0.016, 0.027, 0.063, float(steps[cell])))


## Kolik buněk daleko stín dosáhne a jak silný je v každém kroku. První krok zhruba
## odpovídá výšce boku terasy (33 px proti posunu o buňku, tedy 32×16 px), druhý je jen
## doznění, aby hrana nebyla useknutá.
const TERRACE_SHADOW_STEPS := [0.55, 0.26]
const TERRACE_SHADOW_DIR := Vector2i(1, 0)

func _build_terrace_shadow(solid: Dictionary) -> void:
	var steps := {}
	for c: Vector2i in solid:
		for i in range(TERRACE_SHADOW_STEPS.size()):
			var t: Vector2i = c + TERRACE_SHADOW_DIR * (i + 1)
			# Na buňku, kde stojí další blok, se stín kreslit nemá — zakryje ho, a kdyby
			# se dvě průhledné vrstvy překryly, vznikly by tmavší fleky uvnitř masivu.
			if solid.has(t) or not _in_bounds(t):
				continue
			if not steps.has(t) or float(steps[t]) < TERRACE_SHADOW_STEPS[i]:
				steps[t] = TERRACE_SHADOW_STEPS[i]
	if steps.is_empty():
		return
	var sh := TerraceShadow.new()
	sh.name = "TerraceShadow"
	sh.steps = steps
	sh.z_index = Z_WALL_SHADOW
	add_child(sh)
	_wall_nodes.append(sh)

func _build_terrace_blocks() -> void:
	var block: Texture2D = load(TERRACE_BLOCK_PATH)
	var cap: Texture2D = load(TERRACE_CAP_PATH)

	# The anchor is DERIVED from the art, never hardcoded. The cap is the kit's plain
	# floor diamond, so its lowest opaque row is the base diamond's bottom vertex, which
	# by construction sits tile_h/2 below the cell centre; its horizontal midpoint is the
	# cell centre. Reading it from the pixels means a future art swap cannot silently
	# desync placement — the same reasoning as get_used_rect() in iso_pilot.gd, and the
	# same trap that a hardcoded constant sprang on the first placeholder wall.
	var used := cap.get_image().get_used_rect()
	var th: float = float(Data.GRID.get("tile_h", 32))
	var anchor := Vector2(
		float(used.position.x) + float(used.size.x) * 0.5,
		float(used.position.y + used.size.y - 1) - th * 0.5)

	var solid := {}
	for c: Vector2i in level.high_ground:
		if c != level.objective:
			solid[c] = true
	_build_terrace_shadow(solid)

	for c: Vector2i in solid:
		var spr := Sprite2D.new()
		spr.texture = block
		spr.centered = false
		spr.offset = -anchor
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		spr.position = Data.cell_center(c)
		entities.add_child(spr)
		_wall_nodes.append(spr)


## Flat top-down fill for MODE_SQUARE — a first-pass placeholder standing in for a real
## art pass, per the visual-judgment call BLOCKED.md's T5 entry stops on. Colors are not
## invented here: GROUND/TOP are the exact RGB values tools/flat_terrain.py already
## paints onto the live iso terrain's own TOP FACE (docs/art/iso_bible.md §2b) — a
## top-down view only ever shows a top face, so reusing them keeps continuity with art
## already shipped instead of guessing fresh. Same colors scripts/_shot_topdown_mockup.gd
## already put in front of the user for this exact decision.
const SQUARE_GROUND_COLOR := Color8(20, 17, 41)
const SQUARE_TOP_COLOR := Color8(184, 165, 135)

class SquareTerrain extends Node2D:
	var solid: Dictionary = {}
	var ox := 0
	var oy := 0
	var tile := 16
	var cols := 0
	var rows := 0

	func _draw() -> void:
		draw_rect(Rect2(ox, oy, cols * tile, rows * tile), Game.SQUARE_GROUND_COLOR)
		for c: Vector2i in solid.keys():
			draw_rect(Rect2(ox + c.x * tile, oy + c.y * tile, tile, tile), Game.SQUARE_TOP_COLOR)


func _build_square_terrain() -> void:
	var g = Data.GRID
	var solid := {}
	for c: Vector2i in level.high_ground:
		if c != level.objective:
			solid[c] = true

	var terrain := SquareTerrain.new()
	terrain.name = "SquareTerrain"
	terrain.z_index = Z_TERRAIN
	terrain.solid = solid
	terrain.ox = int(g.origin_x)
	terrain.oy = int(g.origin_y)
	terrain.tile = int(g.tile)
	terrain.cols = int(g.cols)
	terrain.rows = int(g.rows)
	add_child(terrain)
	_wall_nodes.append(terrain)


func _spawn_wall_segment(world_pos: Vector2, p1: Vector2, p2: Vector2, tex: Texture2D, shade: float) -> void:
	var seg := IsoWallSegment.new()
	seg.pts = PackedVector2Array([
		p1,
		p2,
		p2 - Vector2(0.0, WALL_HEIGHT),
		p1 - Vector2(0.0, WALL_HEIGHT)
	])
	seg.tex = tex
	seg.shade = shade
	seg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	seg.position = world_pos
	entities.add_child(seg)
	_wall_nodes.append(seg)


class WallFace extends Node2D:
	var solid: Dictionary = {}
	var variants: Array[Texture2D] = []
	var ox := 0
	var oy := 0
	var tile := 48
	var rows := 0
	var seed_val := 0
	var face_h := 24

	func _draw() -> void:
		pass


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

	## Drawn once (nothing calls queue_redraw() on this node after _build_wall_shadow_
	## layer() adds it), so a real, always-on visual bug was worth a real fix rather
	## than a per-cell shortcut: this used to draw one south-shadow rect and one
	## side-AO rect PER SOLID CELL, so a long wall's shadow was many small same-colour
	## rects only touching at their edges, not one shape. With 2D MSAA at 8x
	## (project.godot, anti_aliasing/quality/msaa_2d), two separate rects that only
	## touch can leave a thin, periodic seam exactly where they meet — each rect's
	## edge is anti-aliased independently, and the coverage does not necessarily add
	## up to "solid" right on the shared boundary. Measured directly (a one-off
	## diagnostic script, deleted after use): a repeating bright line every 16px down
	## a wall's side-AO strip, present even with the whole cast-shadow system OFF —
	## so this was always here, just too dim to notice until a nearby Light2D
	## brightened the area enough to make it visible (see
	## docs/core/15_cast_shadows.md). Same fix as the shadow-occluder geometry above:
	## run-length merge before drawing, so there is no internal edge for a seam to
	## appear on.
	func _draw() -> void:
		# Cool and translucent, never black: a neutral black shadow reads as a hole,
		# a blue-shifted one reads as shade.
		var near := Color(0.016, 0.027, 0.063, 0.62)
		var far := Color(0.016, 0.027, 0.063, 0.30)

		# South-facing floor shadow: horizontal runs of south-exposed wall cells,
		# merged per row before drawing.
		var south_runs := {}   # int (wall cell's row) -> Array[int] (wall cell's x)
		for cell: Vector2i in solid.keys():
			var below := cell + Vector2i.DOWN
			if not solid.has(below) and below.y < rows:
				if not south_runs.has(cell.y):
					south_runs[cell.y] = []
				south_runs[cell.y].append(cell.x)
		for wy: int in south_runs.keys():
			var xs: Array = south_runs[wy]
			xs.sort()
			var run_start: int = xs[0]
			var prev: int = xs[0]
			for i in range(1, xs.size()):
				var x: int = xs[i]
				if x == prev + 1:
					prev = x
					continue
				_draw_south_shadow(near, far, run_start, prev, wy)
				run_start = x
				prev = x
			_draw_south_shadow(near, far, run_start, prev, wy)

		# Side ambient occlusion: vertical runs of cells open to the west/east,
		# merged per column — the strip hugs the wall, so on the wall's left
		# neighbour it sits against that cell's right edge, and vice versa.
		for dx in [-1, 1]:
			var side_runs := {}   # int (side column's x) -> Array[int] (cell's y)
			for cell: Vector2i in solid.keys():
				var side := cell + Vector2i(dx, 0)
				if solid.has(side) or side.x < 0 or side.x >= cols:
					continue
				if not side_runs.has(side.x):
					side_runs[side.x] = []
				side_runs[side.x].append(cell.y)
			var inset := tile - SIDE if dx < 0 else 0
			for sx: int in side_runs.keys():
				var ys: Array = side_runs[sx]
				ys.sort()
				var run_start: int = ys[0]
				var prev: int = ys[0]
				for i in range(1, ys.size()):
					var y: int = ys[i]
					if y == prev + 1:
						prev = y
						continue
					draw_rect(Rect2(ox + sx * tile + inset, oy + run_start * tile,
						SIDE, (prev - run_start + 1) * tile), far)
					run_start = y
					prev = y
				draw_rect(Rect2(ox + sx * tile + inset, oy + run_start * tile,
					SIDE, (prev - run_start + 1) * tile), far)

	func _draw_south_shadow(near: Color, far: Color, x0: int, x1: int, wall_y: int) -> void:
		var x := ox + x0 * tile
		var y := oy + (wall_y + 1) * tile + face_h
		var w := (x1 - x0 + 1) * tile
		draw_rect(Rect2(x, y, w, DEPTH * 0.5), near)
		draw_rect(Rect2(x, y + DEPTH * 0.5, w, DEPTH * 0.5), far)


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


## Container for the LightOccluder2D geometry _build_shadow_occluders() below builds —
## the shadow-casting half of the cast-shadow system (see the big block comment above
## has_visible_distraction for the light-source half and why the two are separate from
## Brain Fog). Freed-before-rebuilt the same defensive way as _static_overlay: _build_field()
## only runs once today, but the guard costs nothing and saves a rediscovery later.
var _shadow_occluder_layer: Node2D = null
var _shadow_occluder_count := 0

## Occluder geometry for the cast-shadow system. Deliberately built from the SAME solid-cell
## dictionary WallFace/WallShadow above already read out of level.high_ground — reusing the
## established "code draws wall geometry from the solid dict" pattern instead of hand-authoring
## occluders from scratch.
##
## One real difference from WallFace/WallShadow, on purpose: those two only care about a wall
## mass's SOUTH-facing rim, because that is the only side a top-down camera ever sees. A light
## can sit on ANY side of a wall, so occlusion needs the wall's full footprint, not just its rim
## — every high-ground cell contributes here, not only the ones with open floor to their south.
##
## Two merges on top of "one occluder per solid cell". First, cells are run-length merged
## along each ROW into horizontal strips. Second — and this part did NOT ship in the first
## pass, see below — a strip is merged DOWN into the strip below it whenever the two share
## the exact same (x_start, x_end), so a solid rectangular wall mass becomes ONE occluder
## no matter how many rows tall it is, not one occluder per row.
##
## THE SECOND MERGE IS NOT OPTIONAL POLISH — a real, reproducible bug proved it. The
## row-only version shipped first and read in `docs/core/15_cast_shadows.md` as "left as a
## documented option if the measured cost ever demands it". What actually demanded it was
## correctness, not cost: separate LightOccluder2D polygons that only TOUCH along a shared
## edge are a known shadow-rendering failure mode. The shadow pass tests each occluder's
## edges independently, and floating-point/angular quantization at the exact seam between
## two touching-but-separate polygons can let a sliver of light leak through in the narrow
## band of angle that lands exactly on the seam. Measured directly (`scripts/
## _check_occluder_seams.gd`, a one-off diagnostic, deleted after use) against a real
## 6-row wall on level 1: three ~1px bright spikes, one at EVERY row boundary, not
## randomly placed — the exact "regular horizontal banding on a tall wall" a live
## playtest reported as "textures look broken". Merging the rows away removes the seam
## instead of trying to soften it.
func _build_shadow_occluders() -> void:
	if level == null:
		return
	if _shadow_occluder_layer != null and is_instance_valid(_shadow_occluder_layer):
		_shadow_occluder_layer.queue_free()
	_shadow_occluder_layer = Node2D.new()
	_shadow_occluder_layer.name = "ShadowOccluders"
	add_child(_shadow_occluder_layer)

	var g = Data.GRID
	var ox := int(g.origin_x)
	var oy := int(g.origin_y)
	var tile := int(g.tile)

	var rows := {}   # int (cell.y) -> Array[int] (cell.x), sorted below before use
	var min_y := 999999
	var max_y := -999999
	for c: Vector2i in level.high_ground:
		if c == level.objective:
			continue
		if not rows.has(c.y):
			rows[c.y] = []
		rows[c.y].append(c.x)
		min_y = mini(min_y, c.y)
		max_y = maxi(max_y, c.y)

	var occluder_count := 0
	# Rectangles still growing downward from an earlier row: [{"span": Vector2i(x0,x1),
	# "y0": int}, ...]. Walked row by row (including empty rows, which close everything
	# still open) rather than jumping between `rows.keys()`, or a gap row would silently
	# let two unrelated wall masses above and below it merge into one tall occluder.
	var open_rects: Array = []
	for y in range(min_y, max_y + 1):
		var strips: Array[Vector2i] = []
		if rows.has(y):
			var xs: Array = rows[y]
			xs.sort()
			var run_start: int = xs[0]
			var prev: int = xs[0]
			for i in range(1, xs.size()):
				var x: int = xs[i]
				if x == prev + 1:
					prev = x
					continue
				strips.append(Vector2i(run_start, prev))
				run_start = x
				prev = x
			strips.append(Vector2i(run_start, prev))

		var used := {}
		var new_open: Array = []
		for rect in open_rects:
			var span: Vector2i = rect["span"]
			var hit := -1
			for i in range(strips.size()):
				if not used.has(i) and strips[i] == span:
					hit = i
					break
			if hit >= 0:
				used[hit] = true
				new_open.append(rect)   # keeps growing, same span, same y0
			else:
				_add_shadow_occluder_rect(ox + span.x * tile, oy + rect["y0"] * tile,
					(span.y - span.x + 1) * tile, (y - rect["y0"]) * tile)
				occluder_count += 1
		for i in range(strips.size()):
			if not used.has(i):
				new_open.append({"span": strips[i], "y0": y})
		open_rects = new_open

	for rect in open_rects:
		var span: Vector2i = rect["span"]
		_add_shadow_occluder_rect(ox + span.x * tile, oy + rect["y0"] * tile,
			(span.y - span.x + 1) * tile, (max_y + 1 - rect["y0"]) * tile)
		occluder_count += 1
	_shadow_occluder_count = occluder_count

## One rectangular occluder covering [x, y, w, h] in world pixels. LightOccluder2D wants its
## polygon CLOSED (a solid loop, not an open line) so a shadow is cast regardless of which side
## of the rectangle the light sits on.
func _add_shadow_occluder_rect(x: int, y: int, w: int, h: int) -> void:
	var occ := LightOccluder2D.new()
	occ.position = Vector2(x, y)
	var poly := OccluderPolygon2D.new()
	poly.closed = true
	poly.polygon = PackedVector2Array([
		Vector2(0, 0), Vector2(w, 0), Vector2(w, h), Vector2(0, h)])
	occ.occluder = poly
	_shadow_occluder_layer.add_child(occ)


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
	# The whole function below paints an isometric DIAMOND_DOWN floor from
	# assets/terrain/iso/ground+lane art, positioned by GridProjection.layer_origin()'s
	# iso formula. Found 2026-08-29 while giving MapEditor square-mode support: this
	# function has no MODE_SQUARE guard, so the live square-mode game was ALSO calling
	# it — painting a real, mispositioned diamond-shaped iso floor layer underneath
	# _build_square_terrain()'s flat-color ground rect on every level. There is no
	# square equivalent to paint yet (square terrain art doesn't exist — see
	# _build_square_terrain()'s own doc comment), so square mode just skips this
	# entirely, the same way _build_wall_segments() already skips its own iso branch.
	if GridProjection.active_mode == GridProjection.MODE_SQUARE:
		return
	var g = Data.GRID
	var tw: int = int(g.get("tile_w", 64))
	var th: int = int(g.get("tile_h", 32))
	var ts := TileSet.new()
	ts.tile_shape = TileSet.TILE_SHAPE_ISOMETRIC
	ts.tile_layout = TileSet.TILE_LAYOUT_DIAMOND_DOWN
	ts.tile_size = Vector2i(tw, th)

	# The ground is TWO sets, not one: quiet grey-matter tissue everywhere, and the
	# dopamine tract on the cells the designer actually painted.
	#
	# Until 2026-08-21 this function painted every cell with the same three tiles and
	# never read `level.path_cells` at all, so the player could not see where the wave
	# would walk — the most expensive missing information on the board. That was a bug
	# HERE, not in the art, which is why new tiles alone would not have fixed it.
	var ground_sources: Array[int] = []
	var accent_sources: Array[int] = []
	var next_src := 0
	for i in range(64):
		var p := "res://assets/terrain/iso/ground/ground_%02d.png" % i
		if not ResourceLoader.exists(p):
			break
		ground_sources.append(_add_tile_source(ts, p, next_src))
		next_src += 1
	# Tiles carrying a lit synapse live in their own pool, installed under a different
	# name by tools/install_iso_art.py (which classifies them by MEASURING the share of
	# saturated bright pixels). Two pools exist so accents can be CLUSTERED below —
	# rolling one mixed pool uniformly is confetti at any ratio, which the top-down board
	# already proved the expensive way, and which the first iso build reproduced exactly.
	for i in range(64):
		var p := "res://assets/terrain/iso/ground/ground_accent_%02d.png" % i
		if not ResourceLoader.exists(p):
			break
		accent_sources.append(_add_tile_source(ts, p, next_src))
		next_src += 1

	# Fall back to the pilot tiles on an older checkout so the board still draws.
	if ground_sources.is_empty():
		for p in ["res://assets/iso_pilot/floor_tile.png",
				"res://assets/iso_pilot/floor_tile_v2.png",
				"res://assets/iso_pilot/floor_tile_v3.png"]:
			if ResourceLoader.exists(p):
				ground_sources.append(_add_tile_source(ts, p, next_src))
				next_src += 1
	if ground_sources.is_empty():
		return

	# Lane tiles are named by the neighbour MASK they belong to, so there is no
	# mask -> filename table anywhere to drift out of sync with the files on disk
	# (tools/install_iso_art.py does the renaming). Bits: 1=N 2=E 4=S 8=W, with
	# N=(0,-1) E=(1,0) S=(0,1) W=(-1,0) — measured off the single-bit tiles, not
	# assumed; see docs/art/iso_bible.md.
	var lane_sources := {}
	for mask in range(16):
		var variants: Array[int] = []
		for suffix in ["", "a", "b"]:
			var p := "res://assets/terrain/iso/lane/lane_%02d%s.png" % [mask, suffix]
			if ResourceLoader.exists(p):
				variants.append(_add_tile_source(ts, p, next_src))
				next_src += 1
		if not variants.is_empty():
			lane_sources[mask] = variants
	var lane_fill := -1
	if ResourceLoader.exists("res://assets/terrain/iso/lane/lane_fill.png"):
		lane_fill = _add_tile_source(ts, "res://assets/terrain/iso/lane/lane_fill.png", next_src)
		next_src += 1

	var on_lane := lane_cells.duplicate()

	# Ručně vybrané dlaždice: každá použitá textura dostane vlastní zdroj. Načítá se jen
	# to, co level opravdu používá — ne celý adresář.
	var override_src := {}
	if level != null and not level.tile_overrides.is_empty():
		var by_name := {}
		for key in level.tile_overrides:
			var rel := String(level.tile_overrides[key])
			if not by_name.has(rel):
				var p := "res://assets/terrain/iso/%s.png" % rel
				if not ResourceLoader.exists(p):
					continue
				by_name[rel] = _add_tile_source(ts, p, next_src)
				next_src += 1
			override_src[key] = by_name[rel]

	path_layer = TileMapLayer.new()
	path_layer.name = "Floor"
	path_layer.tile_set = ts
	path_layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# PŮL DLAŽDICE DOLEVA, A NENÍ TO KOSMETIKA.
	#
	# Godot vrací pro izometrický DIAMOND_DOWN střed dlaždice jako
	# `((x-y+1)*w/2, (x+y+1)*h/2)`, kdežto kanonický převod hry `Data.cell_center()`
	# počítá `((x-y)*w/2, (x+y+1)*h/2)`. V ose y se shodují, v ose x se liší o w/2.
	#
	# Bez téhle korekce ležela podlaha o 32 px vpravo od VŠEHO ostatního: terasa
	# (`_build_terrace_blocks` staví na `Data.cell_center`), věže, jádro, nepřátelé
	# i trasy. Nebylo to vidět, protože podlaha je opakující se textura a posun byl
	# všude stejný — jenže logická mřížka a vizuální podlaha se rozcházely, což je
	# tikající bomba pro všechno, co se o polohu buňky opírá: dosah střelby, zásahy,
	# náhledy stavění, indikátory.
	#
	# Změřeno 21. 8. 2026 (`scripts/_probe_align.gd`): rozdíl (32, 0) u každé buňky.
	# Vzorec teď žije v `GridProjection.layer_origin()` — `tools/map_editor.gd` počítá
	# tentýž posun stejnou funkcí, takže se ty dvě kopie nemůžou rozejít.
	path_layer.position = GridProjection.layer_origin()
	path_layer.z_index = Z_PATH
	add_child(path_layer)

	var rng := RandomNumberGenerator.new()
	var seed_val: int = hash(level.id if level != null else 99) ^ 0x9a71

	# Synapse accents are seeded as short STRANDS, not sprinkled per cell: ~6 % of the
	# tissue in runs of ACCENT_STRAND reads far calmer than the same pixel count spread
	# evenly, because the eye groups a run into one shape and a sprinkle into noise.
	# Same constants and same reasoning as the top-down lane accents above.
	var accent_cells := {}
	if not accent_sources.is_empty():
		var arng := RandomNumberGenerator.new()
		arng.seed = seed_val ^ 0x5A17
		var field: int = int(g.rows) * int(g.cols)
		var strands: int = maxi(1, int(float(field) * ACCENT_SHARE / float(ACCENT_STRAND)))
		for _s in range(strands):
			var c := Vector2i(arng.randi_range(0, int(g.cols) - 1), arng.randi_range(0, int(g.rows) - 1))
			var step: Vector2i = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, -1)][arng.randi() % 4]
			for _k in range(arng.randi_range(2, ACCENT_STRAND)):
				if Data.in_bounds(c) and not on_lane.has(c):
					accent_cells[c] = true
				c += step

	for y in range(int(g.rows)):
		for x in range(int(g.cols)):
			var cell := Vector2i(x, y)
			var src_id := -1
			if on_lane.has(cell) and not lane_sources.is_empty():
				var mask := 0
				if on_lane.has(cell + Vector2i(0, -1)): mask |= 1
				if on_lane.has(cell + Vector2i(1, 0)): mask |= 2
				if on_lane.has(cell + Vector2i(0, 1)): mask |= 4
				if on_lane.has(cell + Vector2i(-1, 0)): mask |= 8
				# A lane painted three cells wide makes its interior cells mask 15, and
				# the mask-15 art is a CROSSROADS with its corners cut away — laid side
				# by side that punched holes down the middle of the lane. A cell whose
				# diagonals are lane too is interior, so it takes the solid slab instead.
				var interior: bool = mask == 15 and lane_fill >= 0 \
					and on_lane.has(cell + Vector2i(1, 1)) and on_lane.has(cell + Vector2i(-1, -1)) \
					and on_lane.has(cell + Vector2i(1, -1)) and on_lane.has(cell + Vector2i(-1, 1))
				if interior:
					src_id = lane_fill
				else:
					var pool: Array = lane_sources.get(mask, lane_sources.get(0, []))
					if not pool.is_empty():
						rng.seed = hash(cell) ^ seed_val
						src_id = pool[rng.randi() % pool.size()]
			if src_id < 0 and accent_cells.has(cell):
				rng.seed = hash(cell) ^ seed_val ^ 0x5A17
				src_id = accent_sources[rng.randi() % accent_sources.size()]
			if src_id < 0:
				# Variant rolled per BUILD BLOCK, not per cell: the grid is three times
				# finer than a build block, so a per-cell roll makes the ground fizz.
				var blk: int = Data.BUILD_BLOCK
				rng.seed = hash(Vector2i(int(floorf(float(x) / blk)), int(floorf(float(y) / blk)))) ^ seed_val
				src_id = ground_sources[rng.randi() % ground_sources.size()]
			# Ruční přepis vyhrává nad odvozenou dlaždicí. Čistě vzhled — `high_ground`
			# a `path_cells` rozhodly o zdech a chůzi o kus výš a tohle na ně nesahá.
			if override_src.has(cell):
				src_id = override_src[cell]
			path_layer.set_cell(cell, src_id, Vector2i.ZERO)


## Adds one whole PNG as a single-tile atlas source and returns its id.
##
## The region is the texture's FULL size, not tile_size: the ground art is a 64x64 canvas
## carrying a 64x32 diamond plus the slab skirt that hangs into the cell in front. Godot
## centres an oversized region on the cell, which is exactly what the skirt needs — and
## that skirt is the whole reason this set tiles at all (measured: 0 enclosed holes,
## against 1143 for the flat diamonds; see docs/art/iso_bible.md §4).
func _add_tile_source(ts: TileSet, path: String, id: int) -> int:
	var tex: Texture2D = load(path)
	var src := TileSetAtlasSource.new()
	src.texture = tex
	src.texture_region_size = tex.get_size()
	src.create_tile(Vector2i.ZERO)
	ts.add_source(src, id)
	return id

## True while a level has no painted terrain, so Game._draw() should render the vector
## walls instead. Both renderers must never run at once or the capsules show through.
func _uses_vector_walls() -> bool:
	return false

var _placement_overlay: Node2D = null
var _static_overlay: Node2D = null
var _telegraph_overlay: Node2D = null


## Teckovana mrizka a nadech spawn zon. Obojí se za celou hru NEZMENI, takze to ma vlastni
## uzel, ktery se prekresli jednou pri stavbe pole -- ne v Game._draw().
##
## PROC TO NENI V Game._draw(): _process() vola queue_redraw() kazdy snimek (jadro pulzuje),
## takze cokoli v _draw() se kresli 60x za vterinu. Pri bunce 48 px to bylo 41x20 = 820
## draw_circle a nikomu to nevadilo. Po zjemneni mrizky na 16 px (18. 8. 2026) to bylo
## 121x58 = 7018 volani na snimek a hra spadla na 6 FPS I NA PRAZDNEM POLI. Nasobek byl
## 8,5x, ne 3x, protoze rostou obe osy.
##
## Tecka je po BLOKU (Data.BUILD_BLOCK), ne po bunce: znaci, kam se da stavet, a to je
## porad ctverec 48 px. Tecka na kazdou bunku by krome ceny byla i jina informace.
class StaticOverlay extends Node2D:
	var game: Game
	func _draw() -> void:
		game._draw_static_field(self)

## Thin canvas that only paints the build preview. It must be a separate node: Game's own
## _draw() renders below every child including the terrain layer, and the overhanging
## corner tiles were clipping the marker right where building happens.
class PlacementOverlay extends Node2D:
	var game: Game
	func _process(_dt: float) -> void:
		queue_redraw()
	func _draw() -> void:
		game._draw_placement_preview(self)

## P7 (docs/refactor/PATHFINDING.MD): the spawn telegraph marker — a pulsing ring, an
## optional compass arrow and a countdown number over every SpawnPointData currently
## pending (Game._pending_spawn_points()). Same shape as PlacementOverlay above: a
## separate node so the pulse can redraw every real frame independent of the fixed sim
## tick, cosmetic-only per Q1's split (it reads wave_time/wave_index, never writes them —
## the actual gate that withholds production lives in _active_spawn_point_cells() /
## _sim_tick(), not here).
class TelegraphOverlay extends Node2D:
	var game: Game
	func _process(_dt: float) -> void:
		queue_redraw()
	func _draw() -> void:
		game._draw_spawn_telegraph(self)

## Axis-aligned square bounds of a single grid cell in screen space -- the MODE_SQUARE
## equivalent of GridProjection.cell_diamond(), which stays iso-only on purpose (see its
## own doc comment: "no square equivalent implemented yet"). This is that equivalent,
## scoped to the two call sites below plus the hover preview, all of which used to draw
## a diamond on what is now a plain top-down board.
func _cell_rect(cell: Vector2i) -> Rect2:
	var t: float = float(Data.GRID.get("tile", 32))
	var top_left := Data.cell_center(cell) - Vector2(t, t) * 0.5
	return Rect2(top_left, Vector2(t, t))

## Kresli se JEDNOU, z _build_field(). Kdyz sem neco pribude, musi to byt taky staticke.
func _draw_static_field(cv: CanvasItem) -> void:
	var g = Data.GRID

	for cells: Array in spawn_zone_cells:
		for c: Vector2i in cells:
			cv.draw_rect(_cell_rect(c), Color(0.9, 0.3, 0.4, 0.18))

	# Telegraf: trod, ktery se otevre PRISTI vlnu. Kresli se v barve pruhu, ale skoro
	# pruhledne -- ma se to cist jako "tudy to zacina prosvitat", ne jako hotova cesta.
	# Cela pointa je, aby to hrac videl o vlnu driv a stejne to nestihl zavrit.
	var soon := pending_trod()
	if soon != null:
		for c: Vector2i in soon.cells:
			if lane_cells.has(c) or high_ground.has(c) or not _in_bounds(c):
				continue
			cv.draw_rect(_cell_rect(c), Color(0.85, 0.66, 0.31, 0.16))

	# Tecky po blocich 3x3 v isometricem prostoru
	var b: int = Data.BUILD_BLOCK
	for y in range(int(g.rows)):
		for x in range(int(g.cols)):
			if x % b == b / 2 and y % b == b / 2:
				var cpos := Data.cell_center(Vector2i(x, y))
				cv.draw_circle(cpos, 2.0, Color("3b4561", 0.7))


func _draw_placement_preview(cv: CanvasItem) -> void:
	var sel = GameState.selected_habit
	if sel == null or not _in_bounds(_hover_cell):
		return
	var ok: bool = _can_build(_hover_cell) and GameState.can_afford(Data.get_habit(sel).build_cost) \
		and GameState.can_reserve_bandwidth(Data.get_habit(sel).bandwidth_cost)
	var tint := Color(0.35, 1.0, 0.55) if ok else Color(1.0, 0.4, 0.4)

	# Hover block b x b square, centered on _hover_cell (was 4 diamond vertices via
	# GridProjection.diamond_corners() -- iso-only, and the exact shape a live
	# top-down screenshot caught floating over the board; see _cell_rect() above).
	var b: int = Data.BUILD_BLOCK
	var elevation := Vector2(0.0, WALL_HEIGHT) if high_ground.has(_hover_cell) else Vector2.ZERO
	var t: float = float(Data.GRID.get("tile", 32))
	var top_left := Data.cell_center(_hover_cell - Vector2i(b / 2, b / 2)) - Vector2(t, t) * 0.5 - elevation
	var block_rect := Rect2(top_left, Vector2(t, t) * float(b))
	cv.draw_rect(block_rect, Color(tint.r, tint.g, tint.b, 0.20))
	cv.draw_rect(block_rect, tint, false, 2.5)

	var sel_def := Data.get_habit(sel)
	var pr: float = _preview_radius(sel_def)
	if pr > 0.0:
		var centre := Data.cell_center(_hover_cell) - elevation
		PixelDraw.ellipse(cv, centre, pr, pr / GridProjection.GROUND_Y_SCALE, Color(tint.r, tint.g, tint.b, 0.6))

## Compass label -> screen-space angle (0 rad = +X/right, increasing clockwise since Y
## grows downward) for a SpawnPointData.direction_id. NAN for empty/unrecognized values
## (every real level today — see that field's own doc comment) so the caller can just
## skip the arrow rather than guess a fallback direction that would itself be a lie.
const _TELEGRAPH_DIRECTIONS := {
	&"N": -PI / 2.0, &"NE": -PI / 4.0, &"E": 0.0, &"SE": PI / 4.0,
	&"S": PI / 2.0, &"SW": 3.0 * PI / 4.0, &"W": PI, &"NW": -3.0 * PI / 4.0,
}
func _telegraph_direction_angle(direction_id: StringName) -> float:
	return _TELEGRAPH_DIRECTIONS.get(direction_id, NAN)

## P7: draws every currently-pending spawn point (Game._pending_spawn_points()) — a
## pulsing ring AT `sp.cell` (the position half of "telegraf musí být pravdivý": this is
## drawn at the EXACT cell _sim_tick() will later spawn from, read off the SAME
## SpawnPointData, never a separate "warning position"), an optional compass arrow for
## `sp.direction_id`, and a countdown in seconds until the gate in
## _active_spawn_point_cells() actually opens. Purely cosmetic — see TelegraphOverlay's
## own header for why reading wave_time/wave_index here is safe (never written).
func _draw_spawn_telegraph(cv: CanvasItem) -> void:
	if level == null or game_ended:
		return
	for sp: SpawnPointData in _pending_spawn_points(wave_index + 1, wave_time):
		var center := cell_center(sp.cell)
		var remaining := maxf(0.0, sp.telegraph_lead_time - wave_time)
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * TAU * 1.2)
		var col := Color(0.95, 0.25, 0.25, 0.35 + 0.35 * pulse)
		cv.draw_arc(center, 22.0 + 4.0 * pulse, 0.0, TAU, 28, col, 3.0)
		var dir_ang := _telegraph_direction_angle(sp.direction_id)
		if not is_nan(dir_ang):
			var tip := center + Vector2.RIGHT.rotated(dir_ang) * 36.0
			var back := center + Vector2.RIGHT.rotated(dir_ang) * 16.0
			cv.draw_line(back, tip, col, 3.0)
			cv.draw_line(tip, tip + Vector2.RIGHT.rotated(dir_ang + PI * 0.85) * 8.0, col, 3.0)
			cv.draw_line(tip, tip + Vector2.RIGHT.rotated(dir_ang - PI * 0.85) * 8.0, col, 3.0)
		var label := "%.1fs" % remaining
		cv.draw_string(ThemeDB.fallback_font, center + Vector2(-14, -30), label,
			HORIZONTAL_ALIGNMENT_CENTER, -1, 14, UI.DANGER)

func cell_center(cell: Vector2i) -> Vector2:
	return Data.cell_center(cell)

func world_to_cell(pos: Vector2) -> Vector2i:
	return Data.world_to_cell(pos)

func _in_bounds(c: Vector2i) -> bool:
	return Data.in_bounds(c)

# ---------------------------------------------------------------- line of sight
#
# Walls shade fire. One cast routine serves the wedge preview, target picking and the
# projectile's wall death, so what the player sees shadowed IS what cannot be hit —
# three separate implementations would drift apart the first time one gets tweaked.

## Which contiguous slab of high ground each cell belongs to; -1 for everything else.
## Cells touching only at a corner count as the same slab, because a ray squeezing
## diagonally between two corners is not a gap the player can see.
var _platform_id := {}

## YOUR OWN PLATFORM MUST NOT BLOCK YOU.
##
## The exemption used to be a single cell (`c != start_cell`), written for "towers stand
## on high ground and shoot outward". That is the right intent and the wrong scope: every
## build spot in the game sits on high ground, and the slabs are 48 cells each, so a
## habit aiming along the very band it stands on was shadowed by that band. Measured on
## level 1: the ray died after 24 px against a ~300 px reach, in 7 of 8 directions.
##
## It had already been noticed once and patched in the wrong place — projectile.gd carried
## a "24px grace ... to clear the muzzle", which is this bug seen from the other end. One
## slab-aware cast now serves both, so the cone and the shot agree again.
func _build_platforms() -> void:
	_platform_id.clear()
	var next_id := 0
	for start: Vector2i in high_ground:
		if _platform_id.has(start):
			continue
		var stack: Array = [start]
		_platform_id[start] = next_id
		while not stack.is_empty():
			var cur: Vector2i = stack.pop_back()
			for dy in [-1, 0, 1]:
				for dx in [-1, 0, 1]:
					if dx == 0 and dy == 0:
						continue
					var n: Vector2i = cur + Vector2i(dx, dy)
					if high_ground.has(n) and not _platform_id.has(n):
						_platform_id[n] = next_id
						stack.push_back(n)
		next_id += 1

## Slab index under a world position, or -1 when it is not on high ground. Callers hold
## this to say "the wall I am standing on", which is the only wall that does not stop them.
func platform_at(pos: Vector2) -> int:
	return _platform_id.get(world_to_cell(pos), -1)

## Distance from `from` along normalized `dir` to the first blocking wall cell, capped at
## `max_dist`. High ground belonging to the SAME slab the ray starts on never blocks —
## see _build_platforms(). 6px sampling; gameplay and preview share the granularity.
func cast_to_wall(from: Vector2, dir: Vector2, max_dist: float) -> float:
	var own := platform_at(from)
	var d := 6.0
	while d < max_dist:
		var c := world_to_cell(from + GridProjection.to_screen(dir) * d)
		if high_ground.has(c) and _platform_id.get(c, -1) != own:
			return d
		d += 6.0
	return max_dist

func has_line_of_sight(from: Vector2, to: Vector2) -> bool:
	var ground_vec := GridProjection.to_ground(to - from)
	var dist := ground_vec.length()
	if dist < 0.001:
		return true
	var dir := ground_vec / dist
	return cast_to_wall(from, dir, dist) >= dist

## Whether a SpawnPointData.requires_segment names something that is actually part of
## the board this level was composed into (P8). Empty — the default, and every spawn
## point authored today — means "belongs to the base map", always true. The single
## source of truth for both gates below, so they can never disagree about it.
func _segment_is_live(required: StringName) -> bool:
	if required == &"":
		return true
	return level != null and level.active_segments.has(required)

## Spawn points in `level.spawn_points` active for wave `wave_number` (1-based, matching
## LevelData.lean_waves/bait_waves' own convention): active_from_wave <= wave_number AND
## the point's segment is actually part of this board.
##
## `requires_segment` (P8, docs/refactor/PATHFINDING.MD) names a MapSegmentData id, and
## the point is eligible only while that id is in `level.active_segments` — the list
## MapComposer.compose() fills in with the segments whose geometry it really composed in.
## Gating on the COMPOSED BOARD rather than on the save flag directly is what keeps the
## spawn honest: a segment that was unlocked but refused (it did not fit the screen) is
## not on the board, so nothing may spawn from it. `active_segments` is empty for every
## level that was never composed, which reproduces P6's original "a non-empty
## requires_segment is never active" exactly.
##
## `wave_elapsed` (P7): seconds of SIM-TICK time (Game.wave_time — reset to 0.0 by
## _start_wave(), advanced only by _sim_tick(), never real/Engine.time_scale-scaled time)
## since `wave_number` itself began. Defaults to INF ("this wave has been running
## forever") so every call site that only cares about wave-level ELIGIBILITY — including
## every call before P7 existed, e.g. _test_multispawn.gd's direct
## game._active_spawn_point_cells(wave) calls — keeps getting the exact same set it
## always did; the telegraph gate below is opt-in via this second argument, not a change
## to what this function already answered. A point only gets held back by it on its OWN
## activation wave (active_from_wave == wave_number, and active_from_wave > 0 so a point
## already active from wave 1 — SpawnPointData.active_from_wave's own comment — is never
## gated, there being no activation moment to telegraph): every later wave, the equality
## fails and the point is unconditionally active regardless of wave_elapsed, exactly the
## "goes live for the rest of that wave, no re-telegraphing" reading documented on
## SpawnPointData.telegraph_lead_time.
func _active_spawn_point_cells(wave_number: int, wave_elapsed: float = INF) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for sp: SpawnPointData in level.spawn_points:
		if sp.active_from_wave > wave_number:
			continue
		if not _segment_is_live(sp.requires_segment):
			continue
		if sp.active_from_wave > 0 and sp.active_from_wave == wave_number \
				and wave_elapsed < sp.telegraph_lead_time:
			continue
		cells.append(sp.cell)
	return cells

## The complement of _active_spawn_point_cells()'s telegraph gate: points that ARE
## eligible for `wave_number` (by active_from_wave/requires_segment) but whose own
## telegraph_lead_time has not yet elapsed since that wave began — i.e. exactly what the
## marker should be shown for (Game.TelegraphOverlay / _draw_spawn_telegraph()) and what
## _test_telegraph.gd checks directly rather than re-deriving. A point can never appear
## both here and in _active_spawn_point_cells()'s result for the same (wave_number,
## wave_elapsed) — same underlying comparison, opposite side.
##
## Gated on `wave_spawning` too: once this wave's entire spawn_queue has drained, nothing
## further will produce this wave regardless of how the countdown reads, so continuing to
## show a marker would be a promise this wave itself can no longer keep — it just goes
## live, silently, at the start of whichever wave finally does produce it.
func _pending_spawn_points(wave_number: int, wave_elapsed: float) -> Array[SpawnPointData]:
	var pending: Array[SpawnPointData] = []
	if level == null or not wave_spawning:
		return pending
	for sp: SpawnPointData in level.spawn_points:
		if not _segment_is_live(sp.requires_segment):
			continue
		if sp.active_from_wave <= 0 or sp.active_from_wave != wave_number:
			continue
		if wave_elapsed < sp.telegraph_lead_time:
			pending.append(sp)
	return pending

## `wave_number` defaults to 1 so every pre-P6 call site (spawn_distraction test
## harnesses that call this with no arguments, outside of an actual wave) keeps compiling
## and behaving exactly as before — those levels never populate spawn_points, so the
## branch below falls straight through to the unchanged spawn_zones behaviour regardless
## of which wave number they'd have passed.
##
## Prefers LevelData.spawn_points (P6) when the level has any point active for this wave;
## otherwise falls back to the pre-P6 spawn_zones behaviour completely unchanged, which is
## also what every level with an empty spawn_points array does today.
##
## `wave_elapsed` (P7) defaults to INF, same reasoning as _active_spawn_point_cells()'s
## own default — see that function's comment. _sim_tick() is the one real caller that
## ever passes something other than the default, using the live Game.wave_time so the
## telegraph gate applies to ACTUAL production, not just to callers that ask for it.
func _random_spawn_cell(wave_number: int = 1, wave_elapsed: float = INF) -> Vector2i:
	if not level.spawn_points.is_empty():
		var active := _active_spawn_point_cells(wave_number, wave_elapsed)
		if not active.is_empty():
			return active[randi() % active.size()]
	var zone: Array = spawn_zone_cells[randi() % spawn_zone_cells.size()]
	return zone[randi() % zone.size()]

# ---------------------------------------------------------------- brain fog
#
# The field sits under a purple-black darkness and the player's Routine is the light in
# it — the SAME circles: the core lights CORE_ROUTINE_RADIUS, an established Anchor
# lights ANCHOR_ROUTINE_RADIUS, so "where you can build" and "where you can see" are one
# rule the eye reads directly. Working habits and defenders carry smaller lights of
# their own; a habit that falls out of Routine goes dark in both senses at once.
#
# Two halves, deliberately separate:
#   VISUAL — _build_fog_layer(): a full-screen rect whose shader erases darkness where
#     `light_mask` (a SubViewport of additive radial sprites) is bright. Projectiles
#     glow here too; at up to 500 live shots this is why there is no Light2D anywhere.
#   GAMEPLAY — _lit_cells: a cell dictionary rebuilt each frame from the SIGHT sources
#     only (core, Anchors, working habits, defenders — a bullet is light, not eyes).
#     is_pos_visible() is the O(1) lookup the combat hot paths gate on: is_point_in_cone
#     (AoE pulses, Pomodoro work check), the projectile hit loop, and board_live.

## All three halved at P8b with CORE_ROUTINE_RADIUS -- same cause, same factor, see that
## constant's block for the derivation (T5 halved the build block from 96 px to 48 px).
const TOWER_LAMP_RADIUS := 28.0       ## the glow a habit casts on its own tile, so it is
									  ## not a silhouette standing in its own darkness.
									  ## Sight down-range comes from the WEDGE below.
									  ## Under 48 (the block pitch) it now lights EXACTLY
									  ## the block it stands on, which is what the line
									  ## above always claimed; at 56 on a 48 px lattice
									  ## it was quietly handing out four free neighbours.
const DEFENDER_LIGHT_RADIUS := 45.0   ## likewise under the 48 px block pitch: a defender
									  ## lights the block it stands on, not the next one.
const PROJECTILE_LIGHT_RADIUS := 13.0 ## cosmetic only, never grants sight

# A HABIT LIGHTS THE WEDGE IT SHOOTS INTO.
#
# This replaces the older rule, which gave every working habit a 150 px circular lamp
# deliberately shorter than its reach, so that hitting anything far away required the
# Routine's light rather than the tower's own. That was a real trade, but it was a trade
# between two circles, and the player could not read it off the board.
#
# Lighting the cone instead ties sight to the one control the player already turns. The
# arc dial (ArcProfile) trades width against damage; now it trades width against how much
# of the board you can SEE. One dial, two consequences, both visible at a glance:
#
#     narrow arc   hard-hitting, sees far down a corridor, blind to the sides
#     wide arc     softer, sees broadly, no reach into the dark
#
# The wedge is the same shape combat already uses (Tower.is_point_in_cone: same centre,
# same facing, same arc, same range), so what is lit is exactly what can be shot. Keeping
# those two in step matters more than the shape being pretty — a light that promises reach
# the tower does not have is worse than no light.
#
# One honest gap, inherited rather than introduced: the light does NOT stop at walls,
# while is_point_in_cone() does (it raycasts). A cell behind high ground can therefore be
# lit and still unshootable. That was already true of the old circular lamps; fixing it
# means a raycast per cell per frame, which is a different order of cost than the cell
# loop below. Left as is, on purpose, and written down so it is not rediscovered as a bug.
const WEDGE_LIGHT_SCALE := 1.0        ## fraction of attack range the wedge lights

# WHY THE LIGHT IS WIDER THAN THE GUN.
#
# A wedge cut exactly at the firing angle ends in a knife edge, which no lamp does. Real
# light has a penumbra, so the beam is drawn WIDER than the cone and fades across the
# extra — full brightness out to the firing edge, then down to nothing.
#
# The skirt goes OUTSIDE the cone rather than eating into it, and that direction is the
# whole point. The rule this fog has always kept is:
#
#     the tower must never shoot something the player cannot at least glimpse
#
# Fading inward would break it — the outermost degrees a habit can hit would go dark.
# Fading outward keeps sight ⊇ fire, so the penumbra is a place you can see into and not
# shoot into, which is what seeing more than you can hit looks like anyway.
const LIGHT_SKIRT := 1.35             ## beam half-angle vs firing half-angle


## One light source. Dictionary rather than a packed Vector because five numbers do not
## fit in a Vector4 and the alternatives (parallel arrays, bit-packing) trade a real cost
## for an imagined one: there are a handful of towers, while _mark_lit_* below walks
## hundreds of CELLS per light. The allocation is noise next to the loop it feeds.
##
## `half` is the half-angle in radians; PI or more means "all the way round", which is how
## every non-directional source (core, Anchor, defender, projectile) is expressed.
static func _light(pos: Vector2, r: float, facing: float = 0.0, half: float = PI) -> Dictionary:
	return {"pos": pos, "r": r, "facing": facing, "half": half}

## Kill switch for harnesses and debugging: with fog off, everything is visible AND the
## render pipeline actually stops — the setter hides the overlay, freezes the mask
## viewport and halts the light canvas, so a harness flipping this after add_child()
## (i.e. after _ready built the layer) is not silently paying for a mask it disowned.
var fog_enabled := true:
	set(value):
		fog_enabled = value
		_apply_fog_enabled()
## Companion switch for the milestone's Routine gates — the build restriction in
## _can_build AND the guild's respawn stall in barracks.gd — for harnesses that test
## other systems and place buildings wherever is convenient. Ships true, always.
## (The tower fire stall on in_routine predates this switch and stays unconditional.)
var routine_gates_enabled := true
## Moment of Clarity: while > 0 the whole field counts as lit (and the shader eases the
## darkness out). Wave time, not wall time — a reveal spent during a frozen build phase
## would be a reveal wasted on an empty board.
var fog_reveal_left := 0.0
var _fog_reveal_vis := 0.0
var _lit_cells := {}                  # Vector2i -> true, rebuilt in _update_fog()
var _fog_rect: ColorRect = null
var _fog_mat: ShaderMaterial = null
var _light_viewport: SubViewport = null
var _light_canvas: LightMaskCanvas = null
## Established Routine sources (core + chained Anchors), cached by _update_routine_reach
## so the build gate and the fog share one per-frame computation.
var _routine_sources: Array = []

## Draws every light as one additive radial sprite into the mask viewport. One node, one
## _draw() pass per frame — hundreds of lights are hundreds of draw_texture_rect calls,
## not hundreds of nodes.
class LightMaskCanvas extends Node2D:
	var game: Game
	static var _light_tex: ImageTexture = null

	static func light_tex() -> ImageTexture:
		if _light_tex == null:
			var n := 128
			var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
			var half := (n - 1) / 2.0
			for y in range(n):
				for x in range(n):
					var d := Vector2(x - half, y - half).length() / half
					# Flat core, falling rim: full brightness out to ~62% of the radius,
					# then a smooth drop to black at the edge. A linear falloff read as a
					# lamp half the size the gameplay circle actually grants (the shader
					# clears only where the mask is bright), and the two must agree.
					var v := 1.0 - smoothstep(0.62, 1.0, d)
					img.set_pixel(x, y, Color(v, v, v, 1.0))
			_light_tex = ImageTexture.create_from_image(img)
		return _light_tex

	func _process(_dt: float) -> void:
		queue_redraw()

	## Fan covering a wedge: apex, then the rim. The falloff ALONG the radius comes from
	## the lamp texture through the UVs, so a beam dims with distance on exactly the same
	## curve a circular lamp does. The falloff ACROSS the beam is the vertex colours below.
	##
	## Two ways to soften the sides were possible and one of them is wrong: a shader would
	## have to be told the facing and arc of every light and this canvas draws them all in
	## one pass, whereas vertex colours ride along with the geometry that already exists.
	## No uniform, no second material, no per-light draw state.
	##
	## THE POINT LIST IS A FAN, AND ONLY THE INDICES SAY SO. Handing these same points to
	## draw_polygon() looks right and renders wrong: that call triangulates the outline by
	## ear clipping, which does not have to keep — and does not keep — the apex in every
	## triangle. The interior triangles it produces span rim vertex to rim vertex, and
	## every rim UV sits on the DARK edge of the lamp texture, so the middle of the beam
	## interpolates to black: a lit crescent around a hole, with a hard seam where the
	## triangulation happened to cut. Measured on the mask itself — brightness along the
	## beam axis fell to 4% at 0.4r before rising to a ring peak at 0.62r — not guessed.
	static func wedge_fan(center: Vector2, r: float, facing: float, half: float,
			steps: int) -> PackedVector2Array:
		var pts := PackedVector2Array()
		pts.push_back(center)
		for i in range(steps + 1):
			var a := facing - half + (half * 2.0) * float(i) / float(steps)
			pts.push_back(center + Vector2.RIGHT.rotated(a) * r)
		return pts

	func _draw() -> void:
		if game == null or not game.fog_enabled:
			return
		var tex := light_tex()
		# Where the penumbra starts, as a fraction of the drawn half-angle: 1/skirt is
		# exactly the firing edge, so everything the habit can hit stays at full brightness
		# and the fade lives entirely in the skirt outside it.
		var jadro := 1.0 / Game.LIGHT_SKIRT
		for l: Dictionary in game.collect_fog_lights():
			var c: Vector2 = l["pos"]
			var r: float = l["r"]
			if l["half"] >= PI:
				draw_texture_rect(tex,
					Rect2(Vector2(c.x - r, c.y - r), Vector2(r * 2.0, r * 2.0)), false)
				continue
			var half: float = l["half"]
			# Finer than the gameplay grid needs, because this is the edge the eye lands
			# on — a coarse fan shows as facets along the penumbra.
			var steps := maxi(12, int(ceil(half * 2.0 / 0.06)))
			var pts := wedge_fan(c, r, l["facing"], half, steps)
			var uvs := PackedVector2Array()
			var cols := PackedColorArray()
			# The apex sits under the habit's own lamp, so it stays full brightness — a
			# beam that dims at its own source reads as a hole where the tower stands.
			uvs.push_back(Vector2(0.5, 0.5))
			cols.push_back(Color.WHITE)
			for i in range(steps + 1):
				var p: Vector2 = pts[i + 1]
				uvs.push_back((p - c) / (r * 2.0) + Vector2(0.5, 0.5))
				# 0 at the beam's centre line, 1 at the drawn edge.
				var t: float = absf(float(i) / float(steps) * 2.0 - 1.0)
				var v: float = 1.0 - smoothstep(jadro, 1.0, t)
				cols.push_back(Color(v, v, v, 1.0))
			# Explicit fan indices, apex in every triangle. Still one canvas command per
			# wedge, so this costs what draw_polygon cost, minus the triangulator.
			var idx := PackedInt32Array()
			idx.resize(steps * 3)
			for i in range(steps):
				idx[i * 3] = 0
				idx[i * 3 + 1] = i + 1
				idx[i * 3 + 2] = i + 2
			RenderingServer.canvas_item_add_triangle_array(
				get_canvas_item(), idx, pts, cols, uvs,
				PackedInt32Array(), PackedFloat32Array(), tex.get_rid())

## Turns the built pipeline on/off in place. Safe to call before _ready (nodes are all
## null then) and idempotent — the setter calls it on every flip.
func _apply_fog_enabled() -> void:
	if _fog_rect != null:
		_fog_rect.visible = fog_enabled
	if _light_viewport != null:
		_light_viewport.render_target_update_mode = \
			SubViewport.UPDATE_ALWAYS if fog_enabled else SubViewport.UPDATE_DISABLED
	if _light_canvas != null:
		_light_canvas.set_process(fog_enabled)

func _build_fog_layer() -> void:
	if not fog_enabled:
		return
	# Half-res mask: light edges are soft by nature, and the fog shader samples linearly.
	_light_viewport = SubViewport.new()
	_light_viewport.name = "FogLightMask"
	_light_viewport.size = Vector2i(240, 135)
	_light_viewport.disable_3d = true
	_light_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_light_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	add_child(_light_viewport)

	# Explicit black floor — the viewport clears to the project's clear colour, which is
	# not black, and any non-black floor would read as "everything slightly lit".
	var floor_rect := ColorRect.new()
	floor_rect.color = Color.BLACK
	floor_rect.size = Vector2(240, 135)
	_light_viewport.add_child(floor_rect)

	_light_canvas = LightMaskCanvas.new()
	_light_canvas.game = self
	_light_canvas.scale = Vector2(0.5, 0.5)   # world px -> half-res mask px
	var add_mat := CanvasItemMaterial.new()
	add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_light_canvas.material = add_mat
	_light_viewport.add_child(_light_canvas)

	_fog_mat = ShaderMaterial.new()
	_fog_mat.shader = load("res://shaders/brain_fog.gdshader")
	_fog_mat.set_shader_parameter("light_mask", _light_viewport.get_texture())

	_fog_rect = ColorRect.new()
	_fog_rect.name = "BrainFog"
	_fog_rect.material = _fog_mat
	# Oversized by the maximum screen-shake amplitude, so a lurching frame never shows a
	# clean strip of world at the edge of the darkness.
	_fog_rect.position = Vector2(-6, -6)
	_fog_rect.size = Vector2(480 + 12, 270 + 12)
	_fog_rect.z_index = Z_FOG
	_fog_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Explicitly opted OUT of the cast-shadow Light2D system (see the block comment above
	# has_visible_distraction). This rect's shader already IS the darkness — COLOR.a comes
	# straight from lit/dark — and a canvas_item shader with no light() override still gets
	# the engine's default additive light response unless something opts out. Without this,
	# any Light2D whose range reaches this rect (all of them: same canvas layer, default
	# range_layer 0..0) would tint its RGB, visible as a faint warm ring right at the edge
	# of the lit penumbra. Mask 0 matches no light's default range_item_cull_mask (1), so
	# this rect always renders exactly what its own shader computes — verified in
	# docs/core/15_cast_shadows.md.
	_fog_rect.light_mask = 0
	add_child(_fog_rect)

## The mask's light list, assembled ONCE per frame by _update_fog (the sight sources are
## shared with the lit-cell grid — walking build_spots and the defenders group twice a
## frame was the first thing review flagged). LightMaskCanvas._draw just reads this.
var _frame_lights: Array = []

func collect_fog_lights() -> Array:
	return _frame_lights

## Shots currently in flight, kept for the fog mask — ObjectPool only counts its actives,
## it does not list them. Appended on spawn, erased by _on_projectile_finished.
var _live_projectiles: Array = []

## Lights that buildings project — shared by the mask (via collect_fog_lights) and the
## gameplay grid (via _update_fog). An Anchor's light IS its Routine radius; any other
## working habit carries the small tower lamp. Out of Routine = dark, literally.
func _building_sight_lights() -> Array:
	var out: Array = []
	for spot in build_spots.values():
		if not is_instance_valid(spot) or spot.state != BuildSpot.State.BUILT \
				or not is_instance_valid(spot.current_habit):
			continue
		var h = spot.current_habit
		if not h.in_routine:
			continue
		if h.type_key == ANCHOR_HABIT:
			# The Anchor is the exception and stays a circle on purpose: its light IS its
			# Routine radius, which is also where you may build. "Where you can build" and
			# "where you can see" being one shape is the rule the eye reads directly, and
			# a wedge would break it.
			out.append(_light(h.global_position, ANCHOR_ROUTINE_RADIUS))
			continue
		out.append(_light(h.global_position, TOWER_LAMP_RADIUS))
		# NOT every building in a spot is a Habit with a cone — Barracks sits in one too
		# and has no attack range at all. Typed check rather than duck-typing: the harness
		# caught this as five errors a frame, and a `in h` test would have hidden the next
		# building type instead of announcing it.
		if not (h is Habit):
			continue
		var reach: float = h.current_attack_range * WEDGE_LIGHT_SCALE
		if reach > TOWER_LAMP_RADIUS:
			# Half-angle in radians, from the same degrees the dial writes — read through
			# the habit rather than recomputed, so turning the dial moves the light in the
			# same frame it moves the cone. Skirted, see LIGHT_SKIRT.
			out.append(_light(h.global_position, reach, h.facing_angle,
				deg_to_rad(h.arc_angle * 0.5) * LIGHT_SKIRT))
	return out

## Rebuilds the lit-cell grid from the SIGHT sources. Runs right after
## _update_routine_reach() so in_routine is fresh — a habit cut off this frame goes
## dark this frame, not next.
func _update_fog(delta: float) -> void:
	if fog_reveal_left > 0.0 and started and not between_waves:
		fog_reveal_left = maxf(0.0, fog_reveal_left - delta)
	if _fog_mat != null:
		var target := 1.0 if fog_reveal_left > 0.0 else 0.0
		# The uniform write is guarded — at rest the value is pinned and re-sending an
		# identical parameter every frame is free-ish but not free.
		if not is_equal_approx(_fog_reveal_vis, target):
			_fog_reveal_vis = move_toward(_fog_reveal_vis, target, delta * 3.0)
			_fog_mat.set_shader_parameter("reveal", _fog_reveal_vis)
	if not fog_enabled:
		return
	# The core lives in game-LOCAL coordinates; every other source is sampled via
	# global_position, which carries the screen-shake offset this node's own position
	# applies. Shifting the core into the same shaken space keeps its light glued to
	# the world during impacts instead of jittering against its own glow.
	var core_pos := objective_pos + position
	var sight: Array = _building_sight_lights()
	for u in get_tree().get_nodes_in_group("defenders"):
		if is_instance_valid(u) and not u._dying:
			sight.append(_light(u.global_position, DEFENDER_LIGHT_RADIUS))

	_lit_cells.clear()
	_mark_lit(_light(core_pos, CORE_ROUTINE_RADIUS))
	for l: Dictionary in sight:
		_mark_lit(l)

	# The mask gets the same list plus the two cosmetic extras: the core breathes a
	# little, and projectiles glow (shine, not sight).
	var t := Time.get_ticks_msec() / 1000.0
	_frame_lights = [_light(core_pos, CORE_ROUTINE_RADIUS * (1.0 + sin(t * 2.0) * 0.025))]
	_frame_lights.append_array(sight)
	for p in _live_projectiles:
		if is_instance_valid(p) and not p.dead:
			_frame_lights.append(_light(p.global_position, PROJECTILE_LIGHT_RADIUS))

## Marks the cells one light reaches. A full circle and a wedge differ by one dot product,
## so they share a body — two loops would be two places for the shapes to drift apart.
##
## ROZLISENI JE BLOK (48 px), NE BUNKA (16 px), a to je zamer, ne uspora nazdarbuh.
##
## Tahle smycka bezi KAZDY SNIMEK pro kazdy zdroj svetla a jeji cena roste s DRUHOU
## mocninou jemnosti mrizky: po zjemneni na 16px bunku by jedno svetlo o polomeru 330 px
## proslo 1702 bunek misto 189. Zmereno 18. 8. 2026: prazdne pole se zapnutou mlhou
## stalo 21,5 ms pred zjemnenim a 29,0 ms po nem, a cely ten rozdil byl tady.
##
## Presnost se tim NEZTRACI: 48 px je presne rozliseni, ktere mlha mela pred zjemnenim,
## a is_pos_visible() je stejne priznane hruby test ("bunka pod telem sviti"). Jemnejsi
## mrizka mela zjemnit PIXEL, ne dohlednost.
func _mark_lit(l: Dictionary) -> void:
	var center: Vector2 = l["pos"]
	var r: float = l["r"]
	var half: float = l["half"]
	var wedge := half < PI
	# cos() once per light instead of acos() per cell: the cone test is
	# "angle <= half", which is exactly "cos(angle) >= cos(half)" for angles in [0, PI].
	var cos_half := cos(half)
	var dir := Vector2.RIGHT.rotated(l["facing"])
	var b: int = Data.BUILD_BLOCK
	var min_c := Data.build_block(world_to_cell(center - Vector2(r, r)))
	var max_c := Data.build_block(world_to_cell(center + Vector2(r, r)))
	var r2 := r * r
	var cy := min_c.y
	while cy <= max_c.y:
		var cx := min_c.x
		while cx <= max_c.x:
			var cell := Vector2i(cx, cy)
			if _lit_cells.has(cell):
				cx += b
				continue
			var d := cell_center(cell) - center
			var d2 := d.length_squared()
			if d2 > r2:
				cx += b
				continue
			# Right on top of the source there is no meaningful direction — the cell under
			# the tower must not flicker in and out as it turns.
			if wedge and d2 > 1.0 and dir.dot(d / sqrt(d2)) < cos_half:
				cx += b
				continue
			_lit_cells[cell] = true
			cx += b
		cy += b

## THE gameplay visibility test — O(1), because the projectile hit loop calls it
## projectiles x enemies times per frame. Cell resolution, not per-pixel: a body is
## visible when the cell under it is lit, which errs slightly generous at light edges
## (the penumbra) and never hides something standing in plain light.
func is_pos_visible(pos: Vector2) -> bool:
	if not fog_enabled or fog_reveal_left > 0.0:
		return true
	# _lit_cells je klicovane po BLOCICH (viz _mark_lit), takze se pozice musi na blok
	# srovnat -- syrova bunka by v nem nikdy nesedela a vsechno by bylo v tme.
	return _lit_cells.has(Data.build_block(world_to_cell(pos)))

## Whether anything alive can currently be seen at all — the fog half of every tower's
## board_live gate. Memoised per frame; N towers each asking would otherwise re-walk the
## horde N times.
var _vis_cache_frame := -1
var _vis_cache := false

func has_visible_distraction() -> bool:
	var f := Engine.get_process_frames()
	if f == _vis_cache_frame:
		return _vis_cache
	_vis_cache_frame = f
	_vis_cache = false
	for d in _distractions:
		if is_instance_valid(d) and not d.dead and is_pos_visible(d.global_position):
			_vis_cache = true
			break
	return _vis_cache

# ---------------------------------------------------------------- cast shadows (Light2D)
#
# Real Light2D + LightOccluder2D — a SEPARATE system from Brain Fog above, not a
# replacement for it. Fog answers "what can the player see and hit" and has to stay a
# cheap full-screen mask because it counts every projectile (up to ~500 live shots) as a
# light; that math is exactly why fog rejected Light2D in the first place (see the block
# comment above collect_fog_lights, and docs/core/14). This system answers a much
# smaller question — "which few things in the world carry a physical lamp, and how does
# its light fall across a wall" — for atmosphere, so it only has to stay cheap for a
# handful of nodes, not hundreds.
#
# The set of lights is deliberately the SAME set that already feeds _lit_cells through
# _building_sight_lights(): the Focus core, established Anchors, and any other built
# habit (Guild included) currently in_routine. Same positions, same radii
# (CORE_ROUTINE_RADIUS / ANCHOR_ROUTINE_RADIUS / TOWER_LAMP_RADIUS) reused, not
# reinvented — "what casts a shadow" and "what lights the fog" stay one idea instead of
# two systems that can quietly disagree. Explicitly NOT lights: projectiles (the fog
# doc's reason applies doubly hard once shadows are involved — up to 500 shadow-casting
# lights recomputing a shadow map every frame is a different order of cost, not just "the
# expensive way to say 1 minus a texture"), distractions/defenders, and — for this first
# pass — small decor. A habit's WEDGE reach-light (the extra light fog gives a long,
# narrow arc down its firing lane) is also skipped: shaping a Light2D's texture into a
# rotated, per-tower wedge and keeping it in sync with the arc dial is real extra work for
# an atmospheric first pass. Left for later if the flat lamp radius reads as too small
# once seen in motion — see the open items in docs/core/15_cast_shadows.md.
#
# What actually shows up on screen: Light2D's default blend mode is ADD, and nothing in
# this project uses CanvasModulate, so the base art already renders at full authored
# brightness with zero lights present — adding a Light2D does not darken anything, it
# only ADDS a warm pool of extra brightness within its texture's radius, cut off wherever
# a LightOccluder2D sits between it and the pixel being drawn. That reads as "the lamp's
# glow stops at the wall" — a shadow — without touching the game's always-fully-visible
# base art or duplicating what the fog's darkness already does.

## Warm, deliberately desaturated — a reading-lamp colour, not a stage light. Full white
## at any real energy reads as flare against flat vector art.
const SHADOW_LIGHT_COLOR := Color(1.0, 0.92, 0.78)
## Conservative on purpose: this is glow ON TOP of art that is already fully lit without
## it (see block comment above), so it only has to suggest depth, not relight the scene.
##
## Measured 2026-08-18 (docs/core/15_cast_shadows.md): the lamp texture is flat (v=1, no
## falloff at all) out to 55% of its radius, so two lamps whose flat cores overlap — an
## Anchor built near the core, or two towers a screen-width apart — ADD their full energy
## with no softening. At 0.45 that measured as real pixels clipped to pure white where
## three sources (core + Anchor + a tower) overlapped near a start-of-game cluster: a
## harsh flare, not the "reading lamp" this is supposed to read as. 0.3 keeps a 2-source
## overlap comfortably under 1.0 (0.6) and a rare 3-source overlap close to it (0.9)
## without clipping in the common case.
const SHADOW_LIGHT_ENERGY := 0.3

## Kill switch, same shape as fog_enabled: safe pre-_ready (every use below is
## null-guarded), idempotent, and the one thing a harness or a future settings screen
## needs to flip to compare with/without. Back ON (2026-08-18, round 2): the floodlight
## complaint from the first in-game look is fixed and verified (SHADOW_CURVE_WIDE, see
## docs/core/15_cast_shadows.md "Playtest round 2"). The banded-texture complaint traced
## to a real, small, PRE-EXISTING wall/floor rendering quirk unrelated to this feature
## (present with this flag off too, unchanged by two rounds of occluder/WallShadow
## fixes) — not blocking, tracked separately in 15.
var shadow_enabled := true:
	set(value):
		shadow_enabled = value
		_apply_shadow_enabled()

var _shadow_light_layer: Node2D = null
var _core_shadow_light: Light2D = null
## BuildSpot -> Light2D, one per currently-built habit/anchor/guild. Kept as a dictionary
## rather than rebuilt from scratch every frame because towers do not move once placed —
## only whether a spot is BUILT and whether its habit is in_routine changes frame to
## frame, so the steady-state cost is a couple of property writes per built spot, not
## node churn.
var _shadow_lights: Dictionary = {}
static var _shadow_tex_cache: Dictionary = {}   # "flat,dark" key -> ImageTexture

## Tower/habit lamp curve — UNCHANGED from the first pass on purpose. Playtest feedback on
## the first pass called out two problems and this was explicitly NOT one of them: "co
## funguje dobře a MÁ zůstat: osvícení od jednotlivých věží". Flat to 55% of the light's
## radius, fully dark by 88% — see _shadow_light_tex for why that shape at all.
const SHADOW_CURVE_TIGHT := Vector2(0.55, 0.88)

## Core/Anchor curve — the actual fix for the SECOND playtest problem ("stíny nedávají
## smysl" / core reads as a floodlight, not a lamp). SHADOW_CURVE_TIGHT was being reused
## at the core's and Anchor's much bigger gameplay radius (330 / 260 vs the tower's 56),
## and a flat zone that is a FIXED FRACTION of radius does not stay lamp-sized as radius
## grows: 55% of 330 is 182px of uniformly full brightness — most of the visible circle —
## followed by a near-instant cliff in the last 12%. On screen that read as a large, hard-
## edged dome, not a falloff, and was the actual shape behind the "big diagonal hard edge
## across the screen" a live playtest reported.
##
## This is the "shift the curve per-source" fix, not a radius change: the core and Anchor
## still light and gate build/visibility at their real CORE_ROUTINE_RADIUS/
## ANCHOR_ROUTINE_RADIUS — nothing about Brain Fog or the Routine build gate moves. Only
## the VISUAL falloff shape is source-size-aware now. flat_frac=0.17 targets a roughly
## CONSTANT absolute hot-core size regardless of which of the two big sources is lighting
## (0.17 * 260 ≈ 44px, 0.17 * 330 ≈ 56px — both in the tower lamp's own ballpark, ~31px,
## rather than 5x it), and dark_frac=0.90 spends most of the remaining radius on a real
## gradual taper instead of a near-instant cutoff.
const SHADOW_CURVE_WIDE := Vector2(0.17, 0.90)

## Same 128px resolution as LightMaskCanvas.light_tex() above (a size already validated
## for a radial falloff in this exact project) but a DIFFERENT curve and a different
## channel convention, because it is a different consumer:
##   - LightMaskCanvas bakes brightness into RGB and pins alpha to 1, because a custom
##     shader reads its .r channel straight off a SubViewport.
##   - A real Light2D texture follows Godot's own convention instead — a white cookie
##     shaped by ALPHA — so this writes the SAME value into every channel and lets
##     whichever one the engine actually samples carry the falloff.
## `flat_frac`/`dark_frac` are NOT one shared constant any more (see SHADOW_CURVE_TIGHT vs
## SHADOW_CURVE_WIDE above and docs/core/15_cast_shadows.md) — cached per distinct pair
## since only two are ever requested. Both are still tighter than the fog mask's own
## curve (flat to 62%, soft out to 100%): this texture is drawn straight into the visible
## scene at NEAREST filtering, not sampled by a shader, so a long soft tail is exactly the
## "blurry glow that sticks out against flat pixel art" the render-fx brief rules out.
static func _shadow_light_tex(flat_frac: float, dark_frac: float) -> ImageTexture:
	var key := "%.3f,%.3f" % [flat_frac, dark_frac]
	if _shadow_tex_cache.has(key):
		return _shadow_tex_cache[key]
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var half := (n - 1) / 2.0
	for y in range(n):
		for x in range(n):
			var d := Vector2(x - half, y - half).length() / half
			var v := 1.0 - smoothstep(flat_frac, dark_frac, d)
			img.set_pixel(x, y, Color(v, v, v, v))
	var tex := ImageTexture.create_from_image(img)
	_shadow_tex_cache[key] = tex
	return tex

## One lamp. `radius` is always one of the fog's own constants, passed in by the caller —
## see the block comment above — never invented here. `curve` defaults to the tower's
## tight curve; callers lighting the core or an Anchor pass SHADOW_CURVE_WIDE explicitly.
func _make_shadow_light(radius: float, curve: Vector2 = SHADOW_CURVE_TIGHT) -> Light2D:
	var light := PointLight2D.new()   # Light2D itself is abstract; PointLight2D is the
									   # concrete node — see docs/core/15_cast_shadows.md.
	var tex := _shadow_light_tex(curve.x, curve.y)
	light.texture = tex
	light.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST  ## pixel-art discipline, see 01
	var tex_half := tex.get_width() / 2.0
	light.texture_scale = radius / tex_half
	light.color = SHADOW_LIGHT_COLOR
	light.energy = SHADOW_LIGHT_ENERGY
	light.shadow_enabled = true
	# Hard-edged, not the softer PCF options — same "no soft blur" reasoning as the
	# texture curve above. (This is also the engine default, written out so it reads as
	# a decision rather than an oversight.)
	light.shadow_filter = Light2D.SHADOW_FILTER_NONE
	return light

## Built once in _ready (alongside the fog layer), independent of shadow_enabled's
## starting value — construction is one-time and cheap (a container plus one light node),
## unlike fog's heavier SubViewport pipeline, so there is nothing worth skipping here.
## shadow_enabled instead gates the ongoing per-frame cost, in _sync_shadow_lights below.
func _build_shadow_light_layer() -> void:
	_shadow_light_layer = Node2D.new()
	_shadow_light_layer.name = "ShadowLights"
	_shadow_light_layer.visible = shadow_enabled
	add_child(_shadow_light_layer)

	_core_shadow_light = _make_shadow_light(CORE_ROUTINE_RADIUS, SHADOW_CURVE_WIDE)
	# Local position under a zero-offset child of Game: ordinary parent-child transform
	# inheritance already carries Game's own shaken `position` into this light's global
	# position every frame, for free. _update_fog has to add `position` back in by hand
	# for the SAME reason fog needs SCREEN_UV realignment at all — its mask lives in a
	# separate screen-aligned SubViewport that does not inherit scene-tree transforms. A
	# real scene-tree Light2D never has that problem, so this is set once, not per-frame.
	_core_shadow_light.position = objective_pos
	_shadow_light_layer.add_child(_core_shadow_light)

## Mirrors _apply_fog_enabled(): safe before _ready (everything still null), idempotent,
## and actually stops paying for the feature when off instead of just hiding it — freeing
## the per-tower lights means a later flip back to true starts _sync_shadow_lights from an
## empty dictionary instead of diffing a stale one.
func _apply_shadow_enabled() -> void:
	if _shadow_light_layer != null:
		_shadow_light_layer.visible = shadow_enabled
	if _shadow_occluder_layer != null:
		_shadow_occluder_layer.visible = shadow_enabled
	if not shadow_enabled:
		for l in _shadow_lights.values():
			if is_instance_valid(l):
				l.queue_free()
		_shadow_lights.clear()

## Keeps _shadow_lights in step with build_spots — the same walk _building_sight_lights()
## already does each frame for the fog mask (see the block comment at the top of this
## section), kept as a SEPARATE loop on purpose rather than merged into that one: the two
## systems are meant to be able to change independently (one is a gameplay-critical O(1)
## visibility grid, the other is atmosphere), and build_spots is small — one entry per 3x3
## buildable BLOCK, not per fine cell (Data.BUILD_BLOCK) — so walking it twice is noise,
## not a new order of cost. Measured under load in docs/core/15_cast_shadows.md.
func _sync_shadow_lights() -> void:
	if not shadow_enabled or _shadow_light_layer == null:
		return
	var seen := {}
	for spot in build_spots.values():
		if not is_instance_valid(spot) or spot.state != BuildSpot.State.BUILT \
				or not is_instance_valid(spot.current_habit):
			continue
		var h = spot.current_habit
		seen[spot] = true
		# Anchor-ness is re-read every sync instead of cached at creation, so an upgrade
		# that changes what a spot holds can never leave a stale radius/curve behind —
		# the cost is one string compare and, only when it actually changed, one texture
		# swap or texture_scale write, never a node rebuild.
		var is_anchor: bool = h.type_key == ANCHOR_HABIT
		var target_radius: float = ANCHOR_ROUTINE_RADIUS if is_anchor else TOWER_LAMP_RADIUS
		var target_curve: Vector2 = SHADOW_CURVE_WIDE if is_anchor else SHADOW_CURVE_TIGHT
		var light: Light2D = _shadow_lights.get(spot)
		if light == null:
			light = _make_shadow_light(target_radius, target_curve)
			_shadow_light_layer.add_child(light)
			_shadow_lights[spot] = light
			light.global_position = h.global_position
		else:
			var target_tex := _shadow_light_tex(target_curve.x, target_curve.y)
			if light.texture != target_tex:
				light.texture = target_tex
			var tex_half := target_tex.get_width() / 2.0
			var target_scale: float = target_radius / tex_half
			if not is_equal_approx(light.texture_scale, target_scale):
				light.texture_scale = target_scale
		light.visible = h.in_routine
	for spot in _shadow_lights.keys():
		if not seen.has(spot):
			_shadow_lights[spot].queue_free()
			_shadow_lights.erase(spot)

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

	# Jedna brána na zónu
	if _spawn_marker_tex != null and level != null:
		for zone: Rect2i in level.spawn_zones:
			var zc := Data.cell_center(Vector2i(zone.position.x + zone.size.x / 2, zone.position.y + zone.size.y / 2))
			var msz := Vector2(_spawn_marker_tex.get_size()) * Data.pixel_scale()
			draw_texture_rect(_spawn_marker_tex, Rect2(zc - msz / 2.0, msz), false)

	# Dynamic Animated Focus Core Rendering (Sleek & Living Reactor in 2:1 ground projection)
	var t := Time.get_ticks_msec() / 1000.0
	var base_radius := tile * 0.45

	# Podstavec pod jádrem
	if _core_prop_tex == null and _goal_marker_tex != null:
		var gsz := Vector2(_goal_marker_tex.get_size()) * Data.pixel_scale()
		draw_texture_rect(_goal_marker_tex, Rect2(objective_pos + Vector2(-gsz.x * 0.5, -gsz.y * 0.75), gsz), false)
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
	
	# Multiple concentric pulse waves radiating outward in 2:1 ellipse
	for w_i in range(2):
		var phase_offset := float(w_i) * 0.5
		var wave_phase := fmod(t * (pulse_speed * 0.25) + phase_offset, 1.0)
		var wave_r := base_radius * (1.0 + wave_phase * 0.9)
		var wave_alpha := (1.0 - wave_phase) * 0.3
		PixelDraw.ellipse(self, objective_pos, wave_r, wave_r / GridProjection.GROUND_Y_SCALE, Color(core_color.r, core_color.g, core_color.b, wave_alpha), 1.0, 1.5)
	
	# Outer Slim Health Arc (Progress Ring)
	var ring_r := base_radius + 7.0
	PixelDraw.ellipse(self, objective_pos, ring_r, ring_r / GridProjection.GROUND_Y_SCALE, Color(1, 1, 1, 0.1), 1.0, 2.0)
	if focus_ratio > 0.0:
		var start_angle := -PI / 2.0
		var end_angle := start_angle + (TAU * focus_ratio)
		PixelDraw.ellipse(self, objective_pos, ring_r, ring_r / GridProjection.GROUND_Y_SCALE, core_color, 1.0, 1.2, start_angle, end_angle)

	if _core_prop_tex != null:
		# Drawn core: a gold orb cradled in bone ribs. It replaces the three stacked
		# circles, but NOT the rings above — those carry state (the arc is remaining
		# Focus, the wave rate is how hard it is being hit) and a sprite cannot.
		#
		# The health colour survives as a TINT rather than as the fill colour, so
		# "the core goes red when Focus is low" still reads while the art stays art.
		# Anchored at its feet like every other object on this board, not centred.
		var csz := Vector2(_core_prop_tex.get_size()) * Data.pixel_scale()
		var tint := Color.WHITE.lerp(core_color, 0.35)
		if _glitch_hit > 0.01:
			tint = tint.lerp(Color.WHITE, minf(1.0, _glitch_hit * 2.0))
		draw_texture_rect(_core_prop_tex,
			Rect2(objective_pos + Vector2(-csz.x * 0.5, -csz.y + tile * 0.5), csz), false, tint)
	else:
		# Main Inner Glowing Core in 2:1 projection squash
		draw_set_transform(objective_pos, 0.0, Vector2(1.0, 1.0 / GridProjection.GROUND_Y_SCALE))
		draw_circle(Vector2.ZERO, base_radius * pulse_scale * 1.2, Color(core_color.r, core_color.g, core_color.b, 0.2))
		draw_circle(Vector2.ZERO, base_radius * pulse_scale * 0.65, core_color)
		draw_circle(Vector2.ZERO, base_radius * pulse_scale * 0.3, Color.WHITE)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

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
		var tint = Color(idef.color)
		if idef.type == "freeze_field" or idef.type == "reveal_field":
			# A field ability has no target, so a disc at the cursor would promise a
			# placement decision the player does not get to make. Frame the whole board
			# instead — it says "everywhere" without pretending to be aimable.
			var field := Rect2(Data.GRID.origin_x, Data.GRID.origin_y,
				Data.GRID.cols * Data.GRID.tile, Data.GRID.rows * Data.GRID.tile)
			draw_rect(field, Color(tint.r, tint.g, tint.b, 0.07), true)
			draw_rect(field, Color(tint.r, tint.g, tint.b, 0.55), false, 3.0)
		else:
			var mouse_pos = get_global_mouse_position()
			draw_circle(mouse_pos, idef.radius, Color(tint.r, tint.g, tint.b, 0.2))
			PixelDraw.arc(self, mouse_pos, idef.radius, tint)

	# SWHAOP Aiming mode: Sniper crosshair reticle & laser sight in 2:1 ground space
	if is_aiming and aiming_habit != null and is_instance_valid(aiming_habit):
		var mouse_pos: Vector2 = get_global_mouse_position()
		var habit_pos: Vector2 = aiming_habit.global_position

		# Laser sight as a dashed pixel trail
		PixelDraw.line(self, habit_pos, mouse_pos, Color(1.0, 0.35, 0.35, 0.7), 1.0, 2.0)

		# Ground-projected reticle at cursor (2:1 ellipse)
		var r_size := 16.0
		var r_col := Color("ff4455")
		PixelDraw.ellipse(self, mouse_pos, r_size, r_size * 0.5, r_col, 1.0, 1.5)
		PixelDraw.line(self, mouse_pos + Vector2(-r_size - 4, 0), mouse_pos + Vector2(-4, 0), r_col, 1.0, 1.5)
		PixelDraw.line(self, mouse_pos + Vector2(4, 0), mouse_pos + Vector2(r_size + 4, 0), r_col, 1.0, 1.5)
		PixelDraw.line(self, mouse_pos + Vector2(0, (-r_size - 4) * 0.5), mouse_pos + Vector2(0, -2), r_col, 1.0, 1.5)
		PixelDraw.line(self, mouse_pos + Vector2(0, 2), mouse_pos + Vector2(0, (r_size + 4) * 0.5), r_col, 1.0, 1.5)

		# Dynamic cone angle tag next to reticle
		var arc_text := "%d°" % int(aiming_habit.arc_angle)
		draw_string(ThemeDB.fallback_font, mouse_pos + Vector2(18, -8), arc_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("ffd479"))

	# Rally placement preview — the same clamp set_rally_point() will apply, drawn live,
	# so the flag the player sees is the flag they get (never past the leash, never in a
	# wall). The zone circle previews around the CANDIDATE, because that is where the
	# defenders would actually fight.
	if is_setting_rally and rally_barracks != null and is_instance_valid(rally_barracks):
		var g_pos: Vector2 = rally_barracks.global_position
		var cand: Vector2 = get_global_mouse_position()
		var reach: float = rally_barracks.def.guard_radius
		if (cand - g_pos).length() > reach:
			cand = g_pos + (cand - g_pos).normalized() * reach
		var blocked_cell: bool = high_ground.has(world_to_cell(cand))
		var col := Color("ff6b6b") if blocked_cell else Color("2bd6c0")
		PixelDraw.line(self, g_pos, cand, Color(col.r, col.g, col.b, 0.5), 1.0, 2.0)
		draw_line(cand + Vector2(0, -14), cand, Color("e8e4d8"), 2.0)
		var flag := PackedVector2Array([cand + Vector2(0, -14), cand + Vector2(9, -10), cand + Vector2(0, -6)])
		draw_colored_polygon(flag, col)
		PixelDraw.arc(self, cand, reach, Color(col.r, col.g, col.b, 0.5), 1.0, 2.0)
		draw_circle(cand, reach, Color(col.r, col.g, col.b, 0.05))

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

# ---------------------------------------------------------------- kamera desky
#
# Do 21. 8. 2026 hra kameru NEMĚLA a deska se kreslila na pevný počátek. To nebyla
# nedbalost: mřížka 24x24 dává 1536x768 px, což je přesně tolik, kolik se pod HUD vejde
# do 1080p. Velikost mapy byla tedy určená velikostí obrazovky.
#
# Kamera tenhle strop odstraňuje, ale schválně se chová NEUTRÁLNĚ, dokud je potřeba:
# když se deska na obrazovku vejde, kamera stojí přesně tam, kde dřív byl pevný pohled,
# a nedá se s ní hnout. Tím se nezmění ani pixel na stávajících levelech (a screenshotové
# testy zůstanou platné). Posouvat jde teprve tehdy, když je co posouvat.
#
# Mířit a stavět se tím nerozbije: všechna místa v tomhle souboru čtou myš přes
# `get_global_mouse_position()`, což transformaci kamery zahrnuje. Ověřeno grepem, ne
# předpokladem — jediné místo se screen-space myší je cue v HUDu, a to je správně.
const CAM_PAN_SPEED := 900.0     ## px/s klávesnicí
const CAM_EDGE := 18.0           ## jak blízko u kraje začne obraz ujíždět
const CAM_EDGE_SPEED := 700.0

var _camera: Camera2D
var _cam_free := false           ## false = deska se vejde, kamera je zamčená
var _cam_drag := false
var _cam_drag_from := Vector2.ZERO
var _cam_drag_origin := Vector2.ZERO

## Obálka desky ve světových souřadnicích — rohy izometrického kosočtverce.
func board_bounds() -> Rect2:
	return GridProjection.board_bounds()

func _build_camera() -> void:
	var b := board_bounds()
	var view: Vector2 = get_viewport_rect().size

	# ŽÁDNÁ KAMERA, KDYŽ SE DESKA VEJDE — a to je záměr, ne zkratka.
	#
	# První verze kameru vytvářela vždy a v „zamčeném" režimu ji stavěla na střed
	# viewportu, což mělo dát tentýž obraz jako dřív. Nedalo: srovnání snímků před a po
	# ukázalo 6,6 % odlišných pixelů, tedy posun celé desky. Bez kamery je plátno
	# identita a shoda je zaručená, ne dopočítaná — takže se stávající levely ani
	# screenshotové testy nemají o co rozbít.
	if b.size.x <= view.x and b.size.y <= view.y:
		_cam_free = false
		return

	_camera = Camera2D.new()
	_camera.name = "BoardCamera"
	add_child(_camera)
	_camera.make_current()
	_cam_free = true
	_camera.position = b.position + b.size * 0.5
	# Meze drží POHLED uvnitř desky, ne střed kamery — Godot si okraje odečte sám.
	_camera.limit_left = int(b.position.x)
	_camera.limit_top = int(b.position.y)
	_camera.limit_right = int(b.position.x + b.size.x)
	_camera.limit_bottom = int(b.position.y + b.size.y)

func _update_camera(delta: float) -> void:
	if _camera == null or not _cam_free or _cam_drag:
		return
	var move := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		move.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		move.x += 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		move.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		move.y += 1.0
	if move != Vector2.ZERO:
		_camera.position += move.normalized() * CAM_PAN_SPEED * delta
		return

	# Okrajové posouvání jen když je okno aktivní — jinak by obraz ujížděl pokaždé,
	# co uživatel odjede myší na druhý monitor.
	if not DisplayServer.window_is_focused():
		return
	var m: Vector2 = get_viewport().get_mouse_position()
	var view: Vector2 = get_viewport_rect().size
	var edge := Vector2.ZERO
	if m.x <= CAM_EDGE: edge.x -= 1.0
	elif m.x >= view.x - CAM_EDGE: edge.x += 1.0
	if m.y <= CAM_EDGE: edge.y -= 1.0
	elif m.y >= view.y - CAM_EDGE: edge.y += 1.0
	if edge != Vector2.ZERO:
		_camera.position += edge.normalized() * CAM_EDGE_SPEED * delta

func _camera_input(event: InputEvent) -> bool:
	if _camera == null or not _cam_free:
		return false
	# Prostřední tlačítko: levé staví a zamyká mířidla, pravé ruší — obě jsou zabraná.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE:
		_cam_drag = event.pressed
		if _cam_drag:
			_cam_drag_from = get_viewport().get_mouse_position()
			_cam_drag_origin = _camera.position
		return true
	if _cam_drag and event is InputEventMouseMotion:
		_camera.position = _cam_drag_origin \
			- (get_viewport().get_mouse_position() - _cam_drag_from)
		return true
	return false

func _unhandled_input(event: InputEvent) -> void:
	if _camera_input(event):
		return
	if game_ended:
		return
	# Any input at all resets the hands-off hold. Mouse MOTION deliberately counts: the
	# finale asks the player to stop touching the game, not to stop clicking it.
	if event is InputEventMouse or event is InputEventKey:
		_note_input()

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
		# Na blok, ne na bunku: stavi a otevira se panel po blocich 3x3 (Data.build_block).
		var click_cell := Data.build_block(world_to_cell(get_global_mouse_position()))

		if is_setting_rally:
			if event.button_index == MOUSE_BUTTON_LEFT:
				if rally_barracks != null and is_instance_valid(rally_barracks):
					rally_barracks.set_rally_point(get_global_mouse_position())
					_flash("Rally set — defenders re-forming", Color("2bd6c0"))
				_end_rally_mode()
				queue_redraw()
				return
			elif event.button_index == MOUSE_BUTTON_RIGHT:
				_end_rally_mode()
				_flash("Rally unchanged", Color("9bd0ff"))
				queue_redraw()
				return

		if is_aiming:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				aiming_habit.set_arc_angle(clampf(aiming_habit.arc_angle + aim_step(), ArcProfile.ARC_MIN, ArcProfile.ARC_MAX))
				aiming_habit.queue_redraw()
				queue_redraw()
				get_viewport().set_input_as_handled()
				return
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				aiming_habit.set_arc_angle(clampf(aiming_habit.arc_angle - aim_step(), ArcProfile.ARC_MIN, ArcProfile.ARC_MAX))
				aiming_habit.queue_redraw()
				queue_redraw()
				get_viewport().set_input_as_handled()
				return
			elif event.button_index == MOUSE_BUTTON_LEFT:
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
					# Bandwidth is released in full too — it mirrors reserve, not spend.
					if aiming_habit and aiming_spot:
						var undone := Data.get_habit(aiming_habit.type_key)
						GameState.add_dopamine(undone.build_cost)
						GameState.release_bandwidth(undone.bandwidth_cost)
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

		# Wheel = cone width on whichever habit has its panel open. Checked before the
		# left/right handling below because a wheel event carries neither, and after the
		# aiming block because there the cursor DISTANCE is already the width control —
		# two live inputs for one value would fight each other on every mouse move.
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and _adjust_arc(ARC_WHEEL_STEP):
			get_viewport().set_input_as_handled()
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN and _adjust_arc(-ARC_WHEEL_STEP):
			get_viewport().set_input_as_handled()
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
		if is_setting_rally:
			_end_rally_mode()
			_flash("Rally unchanged", Color("9bd0ff"))
		elif is_aiming:
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
	if Input.is_action_just_pressed("td_auto_aim"):
		toggle_auto_aim()
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
		KEY_F5:
			_designer_nudge_tolerance(-20.0)
			return true
		KEY_F6:
			_designer_nudge_tolerance(20.0)
			return true
		KEY_F8:
			# Otevre dalsi cekajici trod hned, misto abys musel dohrat do jeho vlny.
			# Ze stejneho duvodu jako F4 "clear wave": otazka "jak se level chova, kdyz
			# se cesta zmeni" se ma dat polozit za pet vterin, ne za pet vln.
			var next_i := -1
			for i in range(level.trods.size()):
				if level.trods[i] != null and not _trods_open.has(i):
					next_i = i
					break
			if next_i < 0:
				_flash("Designer: zadny dalsi trod", Color("ffb454"))
				return true
			_trods_open[next_i] = true
			_open_trod(level.trods[next_i])
			if _static_overlay != null and is_instance_valid(_static_overlay):
				_static_overlay.queue_redraw()
			return true
		KEY_F7:
			sinking_walls = not sinking_walls
			if not sinking_walls and _sunk:
				_set_sunk(false)
			_flash("Designer: sinking walls %s" % ("ON" if sinking_walls else "off"),
				Color("ffb454"))
			return true
	return false

## Sweeps Tolerance by hand. The reason this exists: Tolerance is the input to three
## different things a person can only judge by LOOKING — the flatten shader, the Quick
## Hit escalation, and the sinking-walls spike — and on levels where Quick Hit is off
## (the iso slice) there is otherwise no way to move it at all, so none of them can be
## eyeballed without editing a .tres and relaunching.
func _designer_nudge_tolerance(delta_t: float) -> void:
	GameState.set_tolerance(GameState.tolerance + delta_t)
	_flash("Designer: Tolerance %d%%%s" % [int(GameState.tolerance),
		"  ·  structure eroded" if _sunk else ""], Color("ffb454"))

## Kills every distraction on the field via the shield-bypassing damage channel, so even
## a boss goes down. Defeat signals fire normally — the wave completes, rewards pay out —
## because the point is to skip to the NEXT wave's layout question, not to break the run.
func _designer_clear_wave() -> void:
	var alive := get_tree().get_nodes_in_group("distractions")
	for d in alive:
		if is_instance_valid(d) and d.has_method("take_direct_damage"):
			d.take_direct_damage(999999)
	_flash("Designer: cleared %d distractions" % alive.size(), Color("ffb454"))

func _begin_rally_mode(guild: Barracks) -> void:
	_close_panel()
	is_setting_rally = true
	rally_barracks = guild
	guild.show_range_indicator = true
	_flash("Click where the guild should hold — Right Click keeps the current rally")

func _end_rally_mode() -> void:
	if rally_barracks != null and is_instance_valid(rally_barracks):
		rally_barracks.show_range_indicator = false
	is_setting_rally = false
	rally_barracks = null

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
	if not _can_build(cell):
		# The spot exists and is empty, so the one remaining reason is the dark.
		_flash_error("Outside your Routine — chain Anchors out to reach this spot")
		return
	var type_key = GameState.selected_habit
	var def := Data.get_habit(type_key)
	# Both costs are GATES, not reactions: they have to be able to abort the build
	# before anything is created. This is why habit_built below is notification-only
	# and never the thing that triggers the payment. Bandwidth is CHECKED before
	# Dopamine is spent and RESERVED after, so a refusal on either leaves both intact.
	if not GameState.can_reserve_bandwidth(def.bandwidth_cost):
		_flash_error("Not enough Bandwidth (%d needed) — sell a habit, or grow the cap" \
			% def.bandwidth_cost)
		return
	if not GameState.spend_dopamine(def.build_cost):
		_flash_error("Not enough Dopamine")
		return
	GameState.reserve_bandwidth(def.bandwidth_cost)

	var default_arc: float = def.arc_angle
	var habit := bs.build_habit(type_key, 0.0, default_arc)
	SignalBus.habit_built.emit(habit, def.build_cost)
	if _hints != null:
		_hints.show_hint("first_build")

	if def.is_blocker:
		# No cone to aim — the default recipe walks out around the tower at once. The
		# habit stays selected so several can be placed in a row (see _build_on's
		# caller); the rally and the recipe are re-tuned later from the guild's panel.
		_flash("Guild founded — click it to set the recipe and rally point", Color("2bd6c0"))
		return

	if def.is_support():
		# Anchors have no cone either — placing one used to drop the player into aiming
		# mode for a tower that will never fire. Place, extend the Routine, move on.
		_flash("Anchor set — Routine reaches %dpx around it" % int(def.range), Color("7ef2e6"))
		return

	# Enter Aiming Mode for SWHAOP Directional Cone setup
	_begin_aiming(habit, bs, true)
	SignalBus.build_requested.emit(bs)
	_flash("Aim cone with mouse (distance / wheel = cone width) — Left Click: Lock, Right Click: Cancel", Color("2bd6c0"))

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

## Placement validity — the same predicate the preview tint and _build_on() share, so
## what shows green is exactly what a click will accept. Affordability (Dopamine,
## Bandwidth) deliberately stays OUT of it: an unaffordable spot is still a valid spot,
## and the two refusals need different error messages.
func _can_build(cell: Vector2i) -> bool:
	if not build_spots.has(cell) or build_spots[cell].state != BuildSpot.State.EMPTY:
		return false
	# Only inside the Routine's light. This used to be allowed ("place, extend the
	# Routine, move on") and the freedom taught nothing: a stalled tower in the dark
	# read as a bug, not a lesson. Refusing at placement puts the Anchor decision
	# BEFORE the money is spent, where a decision belongs.
	if not routine_gates_enabled:
		return true
	return is_position_in_routine(cell_center(cell), _routine_sources)

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

## Arming an ability used to check nothing at all, so a hotkey could arm one that was on
## cooldown and then eat the next left-click on the field. With a Rush price that bug
## would also read as "the ability did nothing and my Rush is gone", so the check moved
## here — refuse to arm what cannot be cast, and say why.
func _select_intervention(key) -> void:
	_close_panel()
	_cancel_aiming()
	if selected_intervention == key:
		selected_intervention = null
	else:
		if key != null:
			var idef := Data.get_intervention(String(key))
			if idef != null:
				if intervention_cooldowns.get(String(key), 0.0) > 0.0:
					_flash_error("Ability on cooldown!")
					return
				if idef.rush_cost > 0 and not GameState.can_afford_rush(idef.rush_cost):
					_flash_error("Not enough Rush (need %d)" % idef.rush_cost)
					return
				if idef.insight_cost > 0 and not GameState.can_afford_insight(idef.insight_cost):
					_flash_error("Not enough Insight (need %d ◆)" % idef.insight_cost)
					return
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
	# Charged as a GATE, before the cooldown is committed: a refused cast must leave the
	# ability ready, the way a refused build leaves the Dopamine unspent. Insight is
	# checked BEFORE Rush is spent so a double-costed ability can never take one
	# currency and then refuse on the other.
	if idef.insight_cost > 0 and not GameState.can_afford_insight(idef.insight_cost):
		_flash_error("Not enough Insight (need %d ◆)" % idef.insight_cost)
		return
	if idef.rush_cost > 0 and not GameState.spend_rush(idef.rush_cost):
		_flash_error("Not enough Rush (need %d)" % idef.rush_cost)
		return
	if idef.insight_cost > 0:
		GameState.spend_insight(idef.insight_cost)

	# A field ability ignores where the player clicked. Anchoring its whole presentation
	# on the core keeps the strike, the ring and the popup in one place instead of
	# wherever the mouse happened to be.
	if idef.type == "freeze_field" or idef.type == "reveal_field":
		target_pos = objective_pos

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

	tw.tween_callback(strike.queue_free)

	# The mechanical effect lands on a fixed TICK countdown (_tick_pending_impacts(),
	# called from _sim_tick()), NOT on the strike Tween's own completion — Q1, docs/
	# refactor/PATHFINDING.MD's create_tween() audit. A Tween measures ~0.22 "seconds"
	# through Engine.time_scale, a real, continuous clock that has nothing to do with the
	# fixed sim tick's discrete FIXED_TICK_DT steps, so the same "0.22s" would land after
	# a DIFFERENT NUMBER OF SIM TICKS relative to everything else at 1× vs 4× — breaking
	# bit-identical determinism the instant a level exercises an intervention. roundi(),
	# not int(): a partial tick short-changing the fall time is a worse rounding error
	# than the visual and the mechanic disagreeing by up to half a tick.
	_pending_impacts.append({"idef": idef, "target_pos": target_pos,
		"ticks_left": maxi(1, roundi(0.22 / FIXED_TICK_DT))})

## Interventions whose mechanical effect is chasing a still-falling visual strike — see
## _cast_intervention()'s own comment for why this is a tick countdown and not the
## strike Tween's completion callback.
var _pending_impacts: Array = []   # [{idef: InterventionData, target_pos: Vector2, ticks_left: int}]

func _tick_pending_impacts(_delta: float) -> void:
	if _pending_impacts.is_empty():
		return
	var still_pending: Array = []
	for entry: Dictionary in _pending_impacts:
		entry.ticks_left -= 1
		if entry.ticks_left <= 0:
			_trigger_intervention_impact(entry.idef, entry.target_pos)
		else:
			still_pending.append(entry)
	_pending_impacts = still_pending

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
	elif idef.type == "freeze_field":
		# No radius test: this one is the whole board, which is the entire reason it costs
		# Rush. Freeze here means apply_slow(0.0, …) — MOVEMENT only. A Group Chat still
		# disrupts your habits under Airplane Mode and the boss still cycles its shield;
		# that is deliberate and the ability description says so.
		var frozen := 0
		for d in _distractions:
			if is_instance_valid(d) and not d.dead:
				d.apply_slow(0.0, idef.freeze_duration)
				frozen += 1
		add_shake(10.0)
		_pop_text(objective_pos, "SIGNAL CUT! (%d frozen)" % frozen, col)
		_flash("%s — the whole field goes quiet for %.0fs." % [idef.name, idef.freeze_duration], col)
	elif idef.type == "reveal_field":
		# The Brain Fog lifts everywhere for the duration — is_pos_visible() short-circuits
		# on fog_reveal_left, so towers immediately fight at their full geometry. The
		# timer runs on WAVE time (see _update_fog), so casting between waves holds the
		# lifted fog until the fight actually starts.
		fog_reveal_left = idef.reveal_duration
		_pop_text(objective_pos, "CLARITY — the fog lifts!", col)
		_flash("%s — the whole field is visible for %.0fs." % [idef.name, idef.reveal_duration], col)
	elif idef.type == "summon_allies":
		# Temporary Allies — same unit as the Accountability barracks (06), but they
		# expire on ally_lifetime instead of holding a rally slot.
		var count: int = idef.ally_count
		for i: int in range(count):
			var a := DefenderUnit.new()
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
		elif idef.rush_cost > 0 and not GameState.can_afford_rush(idef.rush_cost):
			# Off cooldown but unaffordable reads differently from recharging: the button
			# names the missing resource instead of counting down to nothing.
			btn.text = "%s\n%d Rush" % [idef.short, idef.rush_cost]
			btn.disabled = true
			btn.remove_theme_stylebox_override("normal")
			btn.remove_theme_color_override("font_color")
		elif idef.insight_cost > 0 and not GameState.can_afford_insight(idef.insight_cost):
			btn.text = "%s\n%d ◆" % [idef.short, idef.insight_cost]
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
		clampf(cell_center(cell).x - 25.0, 3.0, 480.0 - 68.0),
		clampf(cell_center(cell).y - g.tile * 2.2, g.tile * 0.5, 270.0 - 80.0)
	)
	panel.custom_minimum_size = Vector2(60, 0)
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

	# Cone width — what the targeting-mode button used to be, and a far more honest
	# control: this habit has no targeting mode, it has a shape. The label is a live
	# readout rather than a button because the wheel is the input (see _adjust_arc).
	if bs.current_habit is Habit and not def.is_support() and not def.is_blocker:
		var habit_ref: Habit = bs.current_habit
		var arc_row := UI.label(_arc_line(habit_ref), UI.FS_SMALL, UI.ACCENT)
		arc_row.tooltip_text = ("Scroll the mouse wheel over this tower to open or close "
			+ "its cone.\nThe habit always fires the same energy into the sector — the "
			+ "angle only decides\nwhat shape it arrives in. Narrow: fewer, harder, "
			+ "piercing shots that shove.\nWide: a faster, softer, fatter wall that "
			+ "staggers.")
		_panel_arc_label = arc_row
		box.add_child(arc_row)

	# Nutrition Guild controls: one cycling button per defender slot, plus the rally.
	# The slot button is the recipe — pressing it never touches the live unit, it only
	# renames what the slot respawns as, and the label says so while a swap is pending.
	if bs.current_habit is Barracks:
		var guild: Barracks = bs.current_habit
		for i in range(guild.slots.size()):
			var slot_btn := UI.button("Slot %d: %s" % [i + 1, guild.slot_label(i)], UI.FS_SMALL)
			if guild.slot_pending_change(i):
				slot_btn.text += "  (next spawn)"
			slot_btn.tooltip_text = _defender_tooltip(guild.slots[i])
			var idx := i
			slot_btn.pressed.connect(func():
				guild.cycle_slot(idx)
				slot_btn.text = "Slot %d: %s" % [idx + 1, guild.slot_label(idx)]
				if guild.slot_pending_change(idx):
					slot_btn.text += "  (next spawn)"
				slot_btn.tooltip_text = _defender_tooltip(guild.slots[idx]))
			box.add_child(slot_btn)

		var rally_btn := UI.button("Set rally point", UI.FS_SMALL)
		rally_btn.tooltip_text = ("Where the three defenders form up and hold.\n"
			+ "They chase anything inside the guard circle around the rally and\n"
			+ "walk back to formation the moment it dies or slips out of reach.")
		rally_btn.pressed.connect(_begin_rally_mode.bind(guild))
		box.add_child(rally_btn)

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
		var up_bw: int = up_def.bandwidth_cost - def.bandwidth_cost
		var affordable := GameState.can_afford(up_def.build_cost) \
			and (up_bw <= 0 or GameState.can_reserve_bandwidth(up_bw))
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
	_panel_arc_label = null
	_panel_cell = Vector2i(-999, -999)

## Slot-button tooltip: the defender's role, its own description, and the numbers that
## decide the pick — HP, damage cadence, and what it can pin.
func _defender_tooltip(id: StringName) -> String:
	var d := Data.get_defender(id)
	if d == null:
		return ""
	var lines: Array[String] = ["%s — %s" % [d.role, d.display_name], d.description,
		"%d HP · %d %s every %.2fs · pins %d weight" % [d.max_health, d.damage,
			Data.TERM.damage, d.attack_cooldown, d.block_capacity]]
	if d.damage_reduction > 0:
		lines.append("Soaks %d off every counter-hit." % d.damage_reduction)
	if d.heal_amount > 0:
		lines.append("Mends nearby defenders %d HP/s (not itself)." % d.heal_amount)
	if d.burn_dps > 0.0:
		lines.append("Hits keep searing: %s %s/s for %ss." % [Data.TERM.dot,
			String.num(d.burn_dps, 1), String.num(d.burn_duration, 1)])
	return "\n".join(lines)

## The cone's live numbers as one line: the width, and what that width is currently
## buying. Percentages against the habit's own home angle, because "×1.6 damage" only
## means something relative to the tower's own .tres — see ArcProfile.
func _arc_line(h: Habit) -> String:
	var p := h.arc_profile()
	var shape := "focused" if p.ratio > 1.02 else ("spread" if p.ratio < 0.98 else "default")
	var parts: Array[String] = ["Cone %d° (%s)" % [int(h.arc_angle), shape]]
	parts.append("%d%% dmg" % roundi(p.damage_mult * 100.0))
	if h.def.aoe:
		parts.append("%d targets" % p.aoe_targets)
	else:
		parts.append("pierce %d" % p.pierce)
	parts.append("%.2fs" % h.shot_interval())
	if p.knockback > 0.0:
		parts.append("knockback")
	elif p.stagger_factor < 1.0:
		parts.append("stagger")
	return "  ·  ".join(parts)

## Mouse wheel over an open habit panel opens or closes its cone, live, mid-wave. The
## angle is the only combat decision the player can still make once a tower is placed,
## so it needs to be reachable at the speed the wave is arriving — a re-aim mode you
## have to enter, drag through and click out of is a between-waves tool.
func _adjust_arc(step: float) -> bool:
	if _active_panel == null or not build_spots.has(_panel_cell):
		return false
	var bs: BuildSpot = build_spots[_panel_cell]
	if not (bs.current_habit is Habit):
		return false
	var h: Habit = bs.current_habit
	if h.def.is_support() or h.def.is_blocker:
		return false
	var before: float = h.arc_angle
	h.set_arc_angle(h.arc_angle + step)
	if is_equal_approx(before, h.arc_angle):
		return true   # already at a limit; still consumed, so the wheel can't scroll past
	h.queue_redraw()
	if _panel_arc_label != null and is_instance_valid(_panel_arc_label):
		_panel_arc_label.text = _arc_line(h)
	return true

func _do_upgrade(cell: Vector2i, new_type_key: String, cost: int) -> void:
	var spot: BuildSpot = build_spots[cell]
	# A tier swap re-prices the Bandwidth hold: only the DELTA moves, since the old
	# tier's reservation transfers to the new node. Checked before Dopamine is spent —
	# same gate-not-reaction rule as _build_on(): pay first, or nothing happens.
	var cur_def := Data.get_habit(spot.get_current_type_key())
	var bw_delta: int = Data.get_habit(new_type_key).bandwidth_cost \
		- (cur_def.bandwidth_cost if cur_def != null else 0)
	if bw_delta > 0 and not GameState.can_reserve_bandwidth(bw_delta):
		_flash_error("Not enough Bandwidth (+%d needed)" % bw_delta)
		return
	if not GameState.spend_dopamine(cost):
		_flash_error("Not enough Dopamine")
		return
	if bw_delta > 0:
		GameState.reserve_bandwidth(bw_delta)
	elif bw_delta < 0:
		GameState.release_bandwidth(-bw_delta)
	var habit := spot.upgrade_habit(new_type_key)
	SignalBus.habit_upgraded.emit(habit, cost)
	_close_panel()
	_flash("Upgraded to %s" % Data.get_habit(new_type_key).name, Color("9bd0ff"))

## Selling a committed habit refunds 50% (computed by the caller from the panel).
## Contrast the aiming-cancel path in _unhandled_input(), which refunds 100%.
func _do_sell(cell: Vector2i, refund: int) -> void:
	var spot: BuildSpot = build_spots[cell]
	# Bandwidth comes back IN FULL where Dopamine comes back at 50% — it was held, not
	# spent, and a partial release would slowly leak the cap into nothing.
	var sold_def := Data.get_habit(spot.get_current_type_key())
	if sold_def != null:
		GameState.release_bandwidth(sold_def.bandwidth_cost)
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

## Shared pacing constants for WaveCurveEntryData.SpawnShape.CLUSTER/BURST — one
## curve for the whole roster, like ArcProfile's damage/rate/knockback exponents, not
## per-level content (S7, docs/refactor/SYSTEMS.MD).
const WAVE_CLUSTER_SIZE := 5          ## Enemies per cluster before a gap.
const WAVE_CLUSTER_INNER_MULT := 0.2  ## Within-cluster spacing, as a fraction of `spacing`.
const WAVE_CLUSTER_GAP_MULT := 2.0    ## Between-cluster gap, in multiples of a full cluster's span.
const WAVE_BURST_STAGGER := 0.02      ## Seconds between "simultaneous" BURST spawns — just enough to avoid same-frame overlap, independent of `spacing`.

## Spawn time (seconds into the wave) for the k-th (0-based) spawn of `group`, per its
## SpawnShape. STREAM reproduces the pre-S7 formula exactly, so any row that never
## sets `shape` schedules identically to before this existed.
func _spawn_time_for(group: SpawnBatchData, k: int) -> float:
	match group.shape:
		WaveCurveEntryData.SpawnShape.CLUSTER:
			var cluster_index := k / WAVE_CLUSTER_SIZE
			var pos_in_cluster := k % WAVE_CLUSTER_SIZE
			return cluster_index * (group.spacing * WAVE_CLUSTER_SIZE * WAVE_CLUSTER_GAP_MULT) \
				+ (pos_in_cluster + 1) * (group.spacing * WAVE_CLUSTER_INNER_MULT)
		WaveCurveEntryData.SpawnShape.BURST:
			return k * WAVE_BURST_STAGGER
		_:
			return (k + 1) * group.spacing

func _start_wave() -> void:
	if wave_index >= level.waves.size():
		return
	var wave: WaveData = level.waves[wave_index]
	GameState.set_wave(wave_index + 1)
	# Counted per WAVE rather than per toggle: "you turned it on twice" says nothing,
	# "six of nine waves aimed themselves" is the finding.
	if auto_aim_active():
		Mirror.mark(&"auto_aim_wave")
	GameState.begin_wave_streak_window()
	# Lean wave ("no cash"): defeats pay nothing until the wave clears. The preview
	# already warned; the flash + hint land the point the moment it becomes real.
	GameState.lean_wave_active = (wave_index + 1) in level.lean_waves
	if GameState.lean_wave_active:
		if _hints != null:
			_hints.show_hint("first_lean")
		_flash("Wave %d — LEAN: defeats pay no Dopamine" % (wave_index + 1), UI.DANGER)
	elif (wave_index + 1) in level.bait_waves:
		_announce_bait_wave()
	else:
		_flash("Wave %d" % (wave_index + 1))
	# Closes the boredom-tolerance measurement: how long the player could sit in a build
	# phase before reaching for the next wave.
	_end_prep_span()
	Mirror.mark(&"wave_start", wave_index + 1)
	# BEFORE the spawn queue is built: this wave should walk the new route, not the one
	# it replaced. Opening it afterwards would let the first wave past a trod ignore it.
	_open_due_trods(wave_index + 1)
	# Repaints the telegraph for whatever opens next. The static overlay is drawn once
	# per field build rather than per frame, so this is the only thing that moves it.
	if _static_overlay != null and is_instance_valid(_static_overlay):
		_static_overlay.queue_redraw()
	_maybe_show_ad(wave_index + 1)
	spawn_queue = []
	# P7: for a level using LevelData.spawn_points, the cell an entry spawns from is
	# resolved LAZILY in _sim_tick(), at the moment it actually pops — not here, up
	# front — because the telegraph gate (_active_spawn_point_cells()'s wave_elapsed
	# argument) depends on how far into the wave that moment turns out to be, which is
	# not yet known while the queue is still being built. Every spawn_zones-only level
	# (every real level today) keeps the OLD eager resolution, unchanged: the "spawn" key
	# is set right here exactly as before, so its RNG draw stays in the exact same place
	# in the global stream it always was — this branch changes nothing for any level that
	# does not populate spawn_points.
	var uses_spawn_points := not level.spawn_points.is_empty()
	for group: SpawnBatchData in wave.groups:
		for k in range(group.count):
			var entry := {"time": _spawn_time_for(group, k), "type": group.distraction.id}
			if not uses_spawn_points:
				entry["spawn"] = _random_spawn_cell(wave_index + 1)
			spawn_queue.append(entry)
	spawn_queue.sort_custom(func(a, b): return a.time < b.time)
	wave_time = 0.0
	wave_spawning = true
	_update_enemy_stats()
	SignalBus.wave_started.emit(wave_index + 1)

## Cosmetic-only from here down (Q1, docs/refactor/PATHFINDING.MD): everything that can
## affect a RESULT_FIELDS value (see _test_level_simulator.gd's own RESULT_FIELDS) moved
## to _sim_tick(), driven by _physics_process()'s fixed-tick accumulator instead of this
## function — so speed changes how many REAL frames a level takes and nothing about the
## outcome. This still runs every real frame, Engine.time_scale-scaled: camera, the
## aiming-preview follow, the glitch/flatten shaders, the kill-feedback popup and combo
## readout, shadow-light positions, screen shake. None of it is ever read back into
## anything the fixed tick or a RESULT_FIELDS value depends on.
func _process(delta: float) -> void:
	_update_camera(delta)
	if game_ended:
		return
	_update_aiming_process()
	_update_glitch(delta)
	_update_kill_feedback(delta)
	_sync_shadow_lights()
	# Godot runs physics before process on the same frame, so by the time this reads
	# `_distractions` every sim tick this frame (possibly several, at high speed) has
	# already run — a distraction spawned or killed this frame is already reflected,
	# same guarantee the original single-tick-per-frame version had (P5, docs/refactor/
	# PATHFINDING.MD's original horde_renderer comment), now resting on Godot's own
	# physics-before-process ordering instead of incidental per-node call order.
	horde_renderer.rebuild(_distractions)
	queue_redraw()
	_update_hover()

	# Screen Shake decay — _shake_rng, not the shared global stream; see its own comment.
	if _shake_amount > 0.05:
		_shake_amount = lerpf(_shake_amount, 0.0, 12.0 * delta)
		position = Vector2(_shake_rng.randf_range(-_shake_amount, _shake_amount),
			_shake_rng.randf_range(-_shake_amount, _shake_amount))
	else:
		_shake_amount = 0.0
		position = Vector2.ZERO

## Matches the project's default physics_ticks_per_second (60) and, not by coincidence,
## `--fixed-fps 60` — the flag every determinism harness in this project launches with
## (level_simulator.gd's own header). A constant, never scaled by speed: accumulating N
## of them is the same math regardless of how many real frames it took to fire them,
## which is the one property Engine.time_scale itself cannot offer (see this file's
## "speed & pause" section header for why).
const FIXED_TICK_DT := 1.0 / 60.0

## Fractional tick budget: gains `_current_speed()` worth of ticks per real
## _physics_process() call (0.0 while paused), fires floor(budget) whole ticks and keeps
## the remainder — 1 tick/call at 1×, up to 4 at 4×, roughly one every 4 calls at 0.25×.
var _tick_budget := 0.0

## How many fixed sim ticks this level has run, total — the authoritative "elapsed
## simulated time" clock (tick_count * FIXED_TICK_DT). Speed-independent by
## construction: reaching a given amount of simulated time always takes the same number
## of ticks, whether they arrived one per real frame or four. Sfx reads this (see
## Sfx.sync_sim_ms(), called from _sim_tick() below) so its own anti-spam throttle never
## drifts against a SEPARATE, real-frame-accumulated approximation of the same quantity.
var _sim_tick_count := 0

## Godot's own fixed-rate callback. physics_ticks_per_second stays at the project
## default — this does not add or remove physics steps, it decides how many
## FIXED_TICK_DT-sized sim ticks fire inside each one. Runs whether or not the tree is
## paused (this node is PROCESS_MODE_ALWAYS — see _ready()) specifically so `_paused` is
## what gates the simulation, not Godot's own pause machinery: a build/sell/aim/
## Quick-Hit/intervention command issued while paused must still reach its handler, and
## the accumulator gaining zero budget here is what actually keeps distraction movement,
## timers, wave spawning and damage frozen.
func _physics_process(_delta: float) -> void:
	if game_ended:
		return
	_tick_budget += 0.0 if _paused else _current_speed()
	while _tick_budget >= 1.0:
		_tick_budget -= 1.0
		var was_between_waves := between_waves
		_sim_tick(FIXED_TICK_DT)
		if between_waves != was_between_waves:
			# A wave just started or ended on THIS tick. Discard the rest of this
			# frame's budget instead of continuing to drain it — otherwise, at a speed
			# where several ticks batch into one real frame, the ticks AFTER the
			# transition would keep spending the new phase's own clock (e.g. the
			# early-call wave bonus, which starts counting down the instant build phase
			# begins) before anything watching for the phase change — a real player, or
			# LevelSimulator's frame-granular SimStrategy (see sim_strategy.gd's own
			# header: "ticked once per simulated frame") — ever gets a chance to react
			# to it. At 1x this is a no-op (never more than one tick per frame anyway);
			# at 4x it is the difference between a bit-identical result and a wave bonus
			# that quietly differs by a tick or three depending on where inside a
			# 4-tick batch the transition happened to land (Q1, docs/refactor/
			# PATHFINDING.MD — found by _test_timecontrol.gd itself failing on exactly
			# this, a couple of Dopamine off between 1x and 4x, before this fix).
			_tick_budget = 0.0
			break

## Everything that can change a RESULT_FIELDS value lives here — this is the body
## _process() used to be, unchanged in order (nothing here ever depended on Godot's own
## inter-node call order; habits/distractions/projectiles/defenders were always
## separately-scheduled Node._process() calls with no ordering guarantee relative to
## Game's own — this function now IS that ordering, made explicit and reproducible
## instead of incidental). Called 0-4 times per real frame by _physics_process()'s
## accumulator, always with the SAME constant FIXED_TICK_DT, which is what makes a 4×
## run bit-identical to a 1× run of the same seed: the same sequence of fixed-size steps
## runs either way, just bunched differently across real frames.
func _sim_tick(delta: float) -> void:
	_sim_tick_count += 1
	# Sfx's own anti-spam throttle needs to read the SAME authoritative clock this tick
	# runs on rather than its own independently-accumulated approximation — see
	# Sfx._sim_ms's own comment for the bug this closes (found by _test_timecontrol.gd
	# itself failing non-reproducibly before this fix).
	Sfx.sync_sim_ms(roundi(float(_sim_tick_count) * FIXED_TICK_DT * 1000.0))
	# Rebuilt once per TICK rather than per query — see query_distractions_near()'s
	# header. Positions in it are wherever each distraction was at the END OF THE
	# PREVIOUS tick — up to one tick stale, the same tolerance the old per-frame version
	# had (P4, docs/refactor/PATHFINDING.MD), just precisely one tick now instead of
	# ambiguously one engine-frame depending on scene-tree order.
	_rebuild_distraction_hash()
	_update_interventions(delta)
	_tick_pending_impacts(delta)

	# Snapshotted BEFORE anything below can append to either list this tick — matching
	# the semantics Godot's automatic per-frame scheduling always had here (a node
	# added to the tree mid-frame does not get its own _process() call until the frame
	# after): a distraction that spawns or a shot that fires this tick starts moving on
	# the NEXT one, not this one.
	var distraction_batch := _distractions.duplicate()
	var projectile_batch := _live_projectiles.duplicate()

	if wave_spawning:
		wave_time += delta
		var spawned_any := false
		while spawn_queue.size() > 0 and spawn_queue[0].time <= wave_time:
			var entry = spawn_queue.pop_front()
			# P7: entries built for a spawn_points level (see _start_wave()) carry no
			# "spawn" key — the cell is resolved HERE, at the tick it actually pops, with
			# the wave's REAL elapsed sim-time (wave_time, just advanced above) as the
			# telegraph gate's reference. This is the one call site that ever passes a
			# real wave_elapsed instead of the INF default, i.e. the one place a newly-
			# activating point's telegraph_lead_time actually withholds production — every
			# other caller (tests, the marker's own render pass) only READS the gate.
			var sc: Vector2i = entry.spawn if entry.has("spawn") \
				else _random_spawn_cell(wave_index + 1, wave_time)
			spawn_distraction(entry.type, sc)
			spawned_any = true
		if spawned_any:
			_update_enemy_stats()
		if spawn_queue.is_empty():
			wave_spawning = false
	_run_log.tick(delta)
	_update_attention(delta)
	_update_tolerance(delta)
	_update_wave_bonus(delta)
	_update_autoplay(delta)
	_update_effort_offer()
	_update_routine_reach()
	_update_fog(delta)

	# Live entities, driven directly rather than through Godot's automatic per-node
	# _process() — each disables its own automatic scheduling on setup (see e.g.
	# enemy.gd's set_process(false) and its header comment) — so this loop is the ONE
	# place deciding how many times each one advances, in a fixed order that never
	# varies with speed.
	for d: Distraction in distraction_batch:
		if is_instance_valid(d) and not d.dead:
			d._process(delta)
	for spot: BuildSpot in build_spots.values():
		if is_instance_valid(spot) and spot.state == BuildSpot.State.BUILT \
				and is_instance_valid(spot.current_habit):
			spot.current_habit._process(delta)
	for p: Projectile in projectile_batch:
		if is_instance_valid(p) and not p.dead:
			p._process(delta)
	for u in get_tree().get_nodes_in_group("defenders"):
		if is_instance_valid(u) and not u._dying:
			u._process(delta)

	_check_wave_progress()

func _update_aiming_process() -> void:
	if not is_aiming or aiming_habit == null or not is_instance_valid(aiming_habit):
		return
	var mouse_pos: Vector2 = get_global_mouse_position()
	var habit_pos: Vector2 = aiming_habit.global_position
	var ground_vec := GridProjection.to_ground(mouse_pos - habit_pos)
	if ground_vec.length_squared() > 1.0:
		aiming_habit.facing_angle = ground_vec.angle()
		var dist: float = ground_vec.length()
		var max_r: float = aiming_habit.current_attack_range
		# Closer cursor -> Wide cone (125.0°), Farther cursor -> Tight sniper cone (10.0°)
		var norm_dist: float = clampf((dist - 30.0) / maxf(1.0, max_r - 30.0), 0.0, 1.0)
		var calc_arc: float = lerpf(ArcProfile.ARC_MAX, ArcProfile.ARC_MIN, norm_dist)
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
	# Cached for the build gate (_can_build/_build_on) and anyone else asking between
	# frames — recomputing the chain per click would be the drift bug waiting to happen.
	_routine_sources = anchor_positions

	var any_stalled := false
	for h in habits:
		# routine_gates_enabled se musi promitnout SEM, ne az k jednotlivym spotrebitelum.
		# `in_routine` cte sest mist -- strelba (tower.gd), viditelnost svetla, mireni
		# nepratel, barracks, varovny popisek a odhalovani mlhy -- a s vypnutou branou
		# byla vsechna krome barracks spatne. Na izo levelech (routine_gates = false)
		# to znamenalo, ze vez SLO postavit mimo Routine, ale uz nikdy nevystrelila:
		# _can_build branu obesel, tower.gd _process ji ne. Vez, ktera stoji a mlci,
		# se cte jako bug, ne jako pravidlo -- a to pravidlo tam navic zadne nebylo.
		# `position`, not `global_position` — Q1, docs/refactor/PATHFINDING.MD.
		# `_routine_sources`/anchor_positions are built from `position`/objective_pos
		# (both already game-local, shake-free) below and at build_block()'s own
		# is_position_in_routine() call (line ~3028) — mixing a shake-contaminated
		# global_position into ONE of the two comparison sides let screen shake
		# (add_shake(), decaying on real per-frame delta) flip in_routine for a habit
		# sitting near CORE_ROUTINE_RADIUS/ANCHOR_ROUTINE_RADIUS's edge, which gates
		# whether it fires at all — found by _test_timecontrol.gd's cheap-even block
		# giving a real, reproducible (not flaky) kill-count difference between 1x and
		# 4x even after the projectile/targeting fixes next to this one.
		h.in_routine = (not routine_gates_enabled) \
			or is_position_in_routine(h.position, anchor_positions)
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
			# `position`, not `global_position` — see _update_routine_reach()'s own
			# comment (Q1, docs/refactor/PATHFINDING.MD).
			if is_position_in_routine(a.position, sources):
				sources.append(a.position)
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
	var c := Data.build_block(world_to_cell(get_global_mouse_position()))
	if c != _hover_cell:
		_hover_cell = c
		should_redraw = true

	if should_redraw:
		queue_redraw()
	_update_hover_tooltip()

# ---------------------------------------------------------------- hover stats (Q1)
#
# Full live stats on hover, for both habits and distractions — the click-to-open panel
# (_open_panel) already showed a habit's numbers, but only once built AND only after a
# click, and it never covered distractions at all. This is the missing "what am I
# looking at, right now" readout the task asks for: no click, no truncation.

var _hover_tooltip: PanelContainer = null
var _hover_tooltip_label: Label = null

func _build_hover_tooltip() -> void:
	_hover_tooltip = UI.panel(UI.BORDER_HI, 1)
	_hover_tooltip.visible = false
	# A tooltip that eats the click meant for the thing underneath it is worse than no
	# tooltip — see UI.panel()'s own header for why it defaults to STOP.
	_hover_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hover_tooltip.custom_minimum_size = Vector2(190, 0)
	_hover_tooltip_label = Label.new()
	_hover_tooltip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hover_tooltip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hover_tooltip_label.add_theme_font_size_override("font_size", UI.FS_SMALL)
	_hover_tooltip_label.add_theme_color_override("font_color", UI.TEXT_DIM)
	_hover_tooltip.add_child(_hover_tooltip_label)
	_hud_root.add_child(_hover_tooltip)

## Nearest live distraction whose body the cursor is actually over — a coarse spatial-
## hash prefilter (same one tower targeting uses) then an exact radius test, matching
## how every other hit-adjacent check in this file already works.
func _distraction_under_mouse(world_pos: Vector2) -> Distraction:
	var best: Distraction = null
	var best_d := INF
	for d in query_distractions_near(world_pos, 48.0):
		if not is_instance_valid(d) or d.dead:
			continue
		var dist: float = world_pos.distance_to(d.global_position)
		if dist <= d.def.radius + 6.0 and dist < best_d:
			best_d = dist
			best = d
	return best

func _update_hover_tooltip() -> void:
	if _hover_tooltip == null:
		return
	# Don't fight an open panel, an active aim/rally drag, or the draft screen for
	# screen space — those already show their own, more actionable numbers.
	if is_aiming or is_setting_rally or _active_panel != null \
			or is_instance_valid(_draft_overlay):
		_hover_tooltip.visible = false
		return

	var text := ""
	if build_spots.has(_hover_cell):
		var spot: BuildSpot = build_spots[_hover_cell]
		if spot.state == BuildSpot.State.BUILT and is_instance_valid(spot.current_habit):
			text = _habit_hover_text(spot.current_habit)
	var world_pos := get_global_mouse_position()
	if text == "":
		var d := _distraction_under_mouse(world_pos)
		if d != null:
			text = _distraction_hover_text(d)

	if text == "":
		_hover_tooltip.visible = false
		return
	_hover_tooltip_label.text = text
	_hover_tooltip.visible = true
	_hover_tooltip.reset_size()
	var mouse: Vector2 = get_viewport().get_mouse_position()
	var vp: Vector2 = get_viewport_rect().size
	var pos := mouse + Vector2(18, 18)
	pos.x = clampf(pos.x, 0.0, maxf(0.0, vp.x - _hover_tooltip.size.x))
	pos.y = clampf(pos.y, 0.0, maxf(0.0, vp.y - _hover_tooltip.size.y))
	_hover_tooltip.position = pos

## Full stats for a placed habit: base/current combat numbers (reusing the same
## _habit_stats_line the click-to-open panel already shows), plus everything that only
## changes live and the panel never surfaced — Routine state, work/rest countdown,
## disrupt countdown, fire cooldown.
func _habit_hover_text(h) -> String:
	var def := Data.get_habit(h.type_key)
	var lines: Array[String] = [def.name]
	lines.append(_habit_stats_line(def, h as Habit if h is Habit else null))
	if not h.in_routine:
		lines.append("⚠ Not in Routine — idle")
	if h is Habit:
		var hb: Habit = h
		if hb.disrupted_left > 0.0:
			lines.append("Disrupted: %.1fs left" % hb.disrupted_left)
		if hb.has_work_cycle():
			if hb.is_resting():
				lines.append("Resting: %.1fs left" % hb.break_left)
			else:
				lines.append("Work left: %.1fs" % hb.work_left)
		if not def.is_support():
			lines.append("Cooldown: %.2fs" % maxf(0.0, hb.cooldown))
	if not def.is_support() and not def.is_blocker:
		lines.append("Defeated %d · %d damage dealt" % [h.kills, h.damage_dealt])
	return "\n".join(lines)

## Full stats for a live distraction: health, effective (post-resistance) speed, both
## damage-channel resistances, and every active status — nothing here is guessable from
## the board alone (a Calm'd body and a merely slow archetype look the same at a glance).
func _distraction_hover_text(d: Distraction) -> String:
	var lines: Array[String] = [d.def.display_name]
	lines.append("HP %d / %d" % [d.current_health, d.max_health])
	lines.append("Speed %.0f (base %.0f)" \
		% [d.current_speed * d.status_manager.move_scale(), d.current_speed])
	lines.append("Resists: %d %s · %d %s" % [d.effective_compulsion(), Data.TERM.damage,
		d.effective_rationalization(), Data.TERM.mind_damage])
	var sm := d.status_manager
	var statuses: Array[String] = []
	if sm.has_slow():
		statuses.append("Calm x%.2f" % sm.slow_factor)
	if sm.has_haste():
		statuses.append("Rush x%.2f" % sm.haste_factor)
	if sm.has_reframe():
		statuses.append("Reframe −%d" % sm.reframe_amount)
	if sm.has_boredom():
		statuses.append("Boredom %s/s" % String.num(sm.boredom_dps, 1))
	if sm.has_vulnerable():
		statuses.append("Vulnerable x%.2f" % sm.vulnerable_mult)
	if d.is_overdriven():
		statuses.append("Overdrive")
	if d.is_blocked:
		statuses.append("Blocked")
	if d is Boss and (d as Boss).is_shielded():
		statuses.append("Denial Shield up")
	lines.append("Status: %s" % (", ".join(statuses) if not statuses.is_empty() else "none"))
	return "\n".join(lines)

func _check_wave_progress() -> void:
	if not started or wave_spawning or between_waves:
		return
	if _distractions.size() > 0:
		return
	GameState.note_wave_cleared()
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
	# The autoplay countdown replaces the early-call bonus rather than sitting beside it:
	# once the wave is starting anyway there is no early call left to reward, and two
	# numbers on one button is exactly the dashboard the receipt rules ban.
	if _autoplay_left >= 0.0 and between_waves:
		label += "   ▶ %0.1fs" % maxf(_autoplay_left, 0.0)
	elif between_waves and bonus > 0:
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
	# Settle the previous wave's promises before the next build phase opens: a waited-for
	# payout, and a bonus wave that was announced and paid nothing.
	_settle_delay_offer()
	_resolve_bait_wave()
	# Phase 1 of the cue only ever rides a REAL reward — that consistency is the whole
	# asset, and it is the thing level 4 gets to spend.
	if level.cue_phase == 1:
		_fire_cue(true)
	_begin_prep_span()
	if _start_wave_button:
		_start_wave_button.disabled = false
		_start_wave_button.modulate = Color("7cffb2")
	if _skip_wave_button:
		_skip_wave_button.disabled = false
		_skip_wave_button.modulate = Color.WHITE
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
	_wave_preview_panel.position = Vector2(480.0 - 72.0, float(_HUD_TOP_H) + 3.0)
	_wave_preview_panel.custom_minimum_size = Vector2(67, 0)
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
	if _skip_wave_button:
		_skip_wave_button.disabled = true
		_skip_wave_button.modulate = Color(0.6, 0.6, 0.6)
	if bonus > 0:
		GameState.add_dopamine(bonus)
		_pop_text(objective_pos, "+%d Early Call" % bonus, Color("7cffb2"))
	_start_wave()

func spawn_distraction(type_key: String, spawn_cell: Vector2i, gen: int = 0) -> Distraction:
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
	# BEFORE setup(): the splitter's health and visual scale are both read off it there.
	d.generation = gen
	d.setup(self, type_key)
	# `position` is relative to `entities`, which never itself moves — that alone
	# already places `d` correctly via normal Node2D transform propagation. Reassigning
	# `global_position` from the LOCAL value used to sit here too, and it was always
	# wrong the moment any ancestor's transform was non-identity: Game.position IS the
	# screen-shake offset (add_shake()), so any shake active at the instant a wave spawn
	# landed baked that frame's shake offset into this distraction's ACTUAL position as
	# a real, permanent error. Harmless-looking before Q1 (nothing ever compared
	# positions bit-for-bit across two runs of a combat-involving level), but a kill's
	# own add_shake(7.0) plus this bug is exactly what made a post-kill spawn land at a
	# different position depending on real per-frame shake-decay timing relative to the
	# fixed sim tick — found by _test_timecontrol.gd's cheap-even block diverging even
	# at a FIXED speed, three different kill counts across three same-seed launches,
	# before this fix (Q1, docs/refactor/PATHFINDING.MD). See spawn_split()'s matching
	# fix below for the second site.
	d.position = cell_center(spawn_cell)
	# Flyers ignore the maze and steer straight at the objective (Distraction._fly());
	# current_cell stays unused for them, but harmless to set.
	d.current_cell = spawn_cell
	d.defeated.connect(_on_distraction_defeated)
	d.reached_core.connect(_on_distraction_reached_core)
	d.expired.connect(_on_distraction_expired)
	_distractions.append(d)
	SignalBus.distraction_spawned.emit(d)
	_update_enemy_stats()
	if not _intro_seen.has(type_key):
		_intro_seen[type_key] = true
		if _hints != null:
			_hints.show_enemy_intro(d.def)
	return d

func spawn_directional_projectile(pos: Vector2, dir_angle: float, max_dist: float,
		wp: int, aw: int, color: Color, source: Object = null,
		dot: float = 0.0, dot_duration: float = 0.0, spin: float = 0.0,
		pierce: int = 2, padding: float = ArcProfile.BASE_HIT_PADDING,
		knock: float = 0.0, stagger: float = 1.0) -> void:
	var p: Projectile = projectile_pool.acquire()
	if p != null:
		# `position`, not `global_position` — `pos` arrives already expressed in the
		# same shake-free game-space every other gameplay position uses (Q1, docs/
		# refactor/PATHFINDING.MD — see tower.gd's _fire() and projectile.gd's own
		# _process() for why). Projectile is parented directly under Game, and
		# `entities` (everything else's parent) sits at Game's own local origin with
		# no rotation/scale, so this is the same numeric space Distraction/Habit
		# `position` already lives in.
		p.position = pos
		p.setup_directional(self, dir_angle, max_dist, wp, aw, color, source,
			dot, dot_duration, spin, pierce, padding, knock, stagger)
		_live_projectiles.append(p)

## Presentation half of a defeat. The economy half (tolerance-scaled reward, card
## bonuses, kill count) lives in GameState, driven by SignalBus.distraction_defeated
## which Distraction._die() emits alongside this per-instance signal.
##
## ONE SYSTEM, ONE SENSE (docs/design/dopamine_mechanics.md §3). A game feels muddy when
## two systems move the same output: the player can tell something changed and never
## what caused it, and an effect they cannot attribute teaches nothing. So the channels
## are split and never shared:
##
##   TOLERANCE → COLOUR      saturation, particle count, the washed-out death flash
##   NOVELTY   → SOUND       bright chime → dull thud as a habit's kills become predictable
##   BURNOUT   → CAMERA      the tremble (see _update_burnout)
##
## The baseline shake stays CONSTANT here on purpose. Camera belongs to Burnout, so
## nothing else is allowed to modulate it — but a kill with no kick at all reads as a
## bug, and a flat floor is not a channel.
##
## The result the player can actually name after two levels: "grey means I'm taking too
## much cheap dopamine", "silent means this stopped surprising me", "shaking means I'm
## letting things through". Three sentences, learned without being told any of them.
func _on_distraction_defeated(d: Distraction) -> void:
	_distractions.erase(d)
	_update_enemy_stats()
	# Killing a limited-time offer is the receipt's sharpest single number, because the
	# damage it would have done is knowable and it is zero. Recorded here rather than in
	# the enemy so the log stays a record of OUTCOMES the game observed.
	if d.def.lifetime_seconds > 0.0:
		Mirror.mark(&"bait_kill", d.type_key)
	_reward_pos = d.position
	_combo += 1
	_combo_timer = _COMBO_HOLD_TIME

	# Juice factor: 1.0 at clean play → 0.15 at max Tolerance. Colour channel only.
	var tol_ratio: float = GameState.tolerance / 100.0
	var juice: float = Sfx.juice_factor(tol_ratio)

	# Kill sound rides NOVELTY, not Tolerance. Read before GameState ages the counter —
	# Distraction._die() emits `defeated` (here) before the bus signal (economy), so this
	# is the surprise of the kill that just happened rather than of the next one.
	Sfx.play_defeat(GameState.surprise_of(d.killer_key))

	# Particles — fewer and slower when numb.
	_spawn_dopamine_burst(d.position, juice)

	# Constant: the camera is Burnout's channel and nothing else writes to it.
	add_shake(7.0)

	# Death burst in the enemy's own colour — shrinks with juice.
	var fx = impact_fx_pool.acquire()
	if fx != null:
		fx.global_position = d.global_position
		var burst_scale: float = lerpf(0.6, 1.8, juice)
		# Dim the colour at high tolerance — deaths look washed out.
		var col := Color(d.def.color)
		col = col.lerp(Color(0.5, 0.5, 0.5), 1.0 - juice)
		fx.play(col, burst_scale)

## What the player has actually committed to, as raw damage per channel. Read by the
## comparison archetype at spawn time.
##
## The BOARD, not the kill log: a maze the player is looking at is something they can
## reason about, and an adaptation they can anticipate is a decision rather than a dice
## roll. Upgrades count for free because current_*_damage is already the modified value.
# ---------------------------------------------------------------- effort discounting
#
# Salamone's barrier, made out of a mouse wheel.
#
# The finding almost every article about dopamine gets backwards: dopamine is not the
# pleasure chemical, it is the EFFORT chemical. Depleted animals still like the good
# food exactly as much; they just stop being willing to climb for it and take the free
# chow instead. Nothing about the reward changed. What changed is what it costs to go
# and get it, relative to what the animal has left.
#
# So the barrier here rises with Tolerance: the wheel that tunes the cone starts moving
# in smaller steps, and tuning the same angle costs two and a half times the clicks — at
# exactly the moment the player has least patience for it. Nothing got harder to WIN.
# It got more tedious to DO, which is a different axis and the correct one.
#
# And then, precisely there, the game offers the chow: press A and your habits point
# themselves. It is a real offer with a real cost (see Habit.set_auto_aim) and the
# player will take it, and the receipt will tell them what it was worth. There is no
# right answer being withheld — taking it IS the demonstration.

## Degrees per wheel notch, fresh and worn out.
const AIM_STEP_FRESH := 10.0
const AIM_STEP_TIRED := 4.0
## Where the barrier starts rising. Below this, aiming costs exactly what it always did.
const EFFORT_STRAIN := 45.0

var _effort_offered := false

func aim_step() -> float:
	var t: float = clampf(inverse_lerp(EFFORT_STRAIN, 100.0, GameState.tolerance), 0.0, 1.0)
	return lerpf(AIM_STEP_FRESH, AIM_STEP_TIRED, t)

## Every built, firing habit. Support habits (the Anchor line) never aim, so they are
## not part of the offer and set_auto_aim ignores them anyway.
func _aiming_habits() -> Array:
	var out: Array = []
	for spot in build_spots.values():
		if not is_instance_valid(spot) or spot.state != BuildSpot.State.BUILT:
			continue
		var h = spot.current_habit
		if is_instance_valid(h) and h.def != null and not h.def.is_support():
			out.append(h)
	return out

## Walks build_spots directly rather than going through _aiming_habits(): this is asked
## every frame by the offer below, and allocating an Array to answer "is anything on?"
## is per-frame money for a question whose answer is almost always no.
func auto_aim_active() -> bool:
	for spot in build_spots.values():
		if not is_instance_valid(spot) or spot.state != BuildSpot.State.BUILT:
			continue
		var h = spot.current_habit
		if is_instance_valid(h) and h.auto_aim:
			return true
	return false

## All or nothing on purpose. Per-habit micromanagement would be MORE effort than aiming
## by hand, which would invert the whole point of the offer.
func toggle_auto_aim() -> void:
	var habits: Array = _aiming_habits()
	if habits.is_empty():
		return
	var on: bool = not auto_aim_active()
	var surrendered := 0.0
	for h in habits:
		h.set_auto_aim(on)
		surrendered += h.surrendered_mult
	if on:
		# What their own aiming was worth, averaged over the board. 1.0 means they were
		# sitting at the home angle and handed over nothing.
		Mirror.mark(&"auto_aim_on", surrendered / float(habits.size()))
		_flash("Auto-aim on. Your habits will point themselves.", Color("9bd0ff"))
	else:
		Mirror.mark(&"auto_aim_off")
		_flash("Auto-aim off — you have the wheel again.", Color("7cffb2"))
	Sfx.play(&"cue")

## The offer itself, made once per level the first time the barrier is actually felt.
## Mid-wave rather than in the build phase: the point is that it arrives while the
## player is tired of doing it, not while they are calmly reading a menu.
func _update_effort_offer() -> void:
	# Cheapest gates first, and both of them latch or sit still: _effort_offered is true
	# for the rest of the level after one firing, and Tolerance is under the threshold for
	# most of a clean run. The two board walks below only ever run in the narrow window
	# where the offer is actually about to be made.
	if _effort_offered or game_ended:
		return
	if GameState.tolerance < EFFORT_STRAIN:
		return
	if auto_aim_active() or _aiming_habits().is_empty():
		return
	_effort_offered = true
	Mirror.mark(&"effort_offer")
	_flash("Aiming feels heavy. Press A and let your habits aim themselves.",
		Color("ffd479"))

func player_damage_profile() -> Dictionary:
	var wp := 0
	var aw := 0
	var top_key: StringName = &""
	var top_damage := 0
	for spot in build_spots.values():
		if not is_instance_valid(spot) or spot.state != BuildSpot.State.BUILT:
			continue
		var h = spot.current_habit
		if not is_instance_valid(h):
			continue
		wp += h.current_willpower_damage
		aw += h.current_awareness_damage
		var total: int = h.current_willpower_damage + h.current_awareness_damage
		if total > top_damage:
			top_damage = total
			top_key = h.type_key
	return {"willpower": wp, "awareness": aw, "top": top_key, "top_damage": top_damage}

## Splitter archetype (Just One More): a body leaves smaller copies where it fell.
##
## The children repath from the parent's cell rather than from the spawn zone, which is
## the entire feel of the archetype — the queue does not restart, it CONTINUES, one step
## closer than the thing you just killed. Restarting them at the entrance would turn an
## attrition mechanic into a free reset and quietly make killing the parent a good move.
##
## Hard-capped on live bodies. `split_count` and `split_generations` multiply, so a
## mis-authored .tres is an exponent, not a typo — and the failure mode of an exponent is
## a frozen frame rather than a wrong number.
const MAX_LIVE_DISTRACTIONS := 220

func spawn_split(parent: Distraction, index: int) -> void:
	if game_ended or parent == null:
		return
	if _distractions.size() >= MAX_LIVE_DISTRACTIONS:
		return
	var cell: Vector2i = world_to_cell(parent.position)
	var child := spawn_distraction(parent.type_key, cell, parent.generation + 1)
	if child == null:
		return
	# Under the flow field (P4, docs/refactor/PATHFINDING.MD) there is no route to
	# inherit — every live body, parent and child alike, reads the SAME shared field, so
	# a child spawned at the parent's own cell already continues from exactly where the
	# parent stood, with zero extra bookkeeping. The one thing that still needs a check is
	# the old soft-lock guard: the parent can be standing on a cell the field never
	# reached (a wall, or a cell the sinking-walls spike just put back) after knockback or
	# scatter, and a child idling forever there would hold the wave open with nothing
	# visible to kill. One missing copy is a rounding error in an archetype that spawns
	# fifteen; a run that never ends is the whole session.
	if not child.is_flying and (flow_field == null or not flow_field.has_cell(child.current_cell)):
		_distractions.erase(child)
		child.queue_free()
		return
	# Fan them apart so a split reads as several bodies rather than one that got smaller.
	var spread: float = Data.GRID.tile * 0.3
	var angle: float = TAU * (float(index) + 0.5) / float(maxi(1, parent.def.split_count))
	# `position` alone is already correct — see spawn_distraction()'s matching comment
	# for why reassigning `global_position` from it here was the same latent bug.
	child.position += GridProjection.ground_dir_to_screen(angle) * spread
	Mirror.mark(&"split", parent.type_key)

## Fleeting archetype (FOMO): the offer closed on its own. No Focus damage, no reward,
## no kill credit, no screen shake — the point is that nothing happens, and the silence
## is the lesson. Only the live list and the wave-progress check care.
func _on_distraction_expired(d: Distraction) -> void:
	_distractions.erase(d)
	_update_enemy_stats()
	# No _check_wave_progress() here: _process polls it every frame, and a wave whose
	# last body simply left still has to end through that one path.

# ---------------------------------------------------------------- autoplay

## Seconds left before the next wave starts itself, or -1.0 when nothing is armed.
var _autoplay_left := -1.0

## Called by a Distraction whose autoplay deadline expired. From here the build phase is
## no longer untimed: it gets `grace` seconds and then starts without being asked.
##
## Latched rather than cancellable, and armed DURING the wave it was spawned in, so the
## player finds out while they can still do something about the next one. The rule the
## game is teaching is that the pause is the thing worth defending, and it can only teach
## that by taking it away once.
func arm_autoplay(grace: float) -> void:
	if game_ended or _autoplay_left >= 0.0:
		return
	_autoplay_left = maxf(1.0, grace)
	Sfx.play(&"cue")
	_flash("▶ AUTOPLAY — next wave starts by itself", Color("ff6b6b"))

func _update_autoplay(delta: float) -> void:
	if _autoplay_left < 0.0 or game_ended:
		return
	# Only burns down in the build phase. During the wave it just sits armed: it is a
	# threat against the PAUSE, so it has nothing to take while there is no pause.
	if not between_waves:
		return
	_autoplay_left -= delta
	_refresh_start_wave_button()
	if _autoplay_left <= 0.0:
		_autoplay_left = -1.0
		Mirror.mark(&"autoplay_stole_prep")
		if between_waves and not game_ended:
			_on_start_wave_pressed()

## The paid-out amount arrives separately from GameState, because only GameState knows
## the economy rules and only the distraction knows where it died. Both write to
## independent buffers that _update_kill_feedback() flushes together, so the two
## handlers can fire in either order.
func _on_defeat_reward_granted(amount: int) -> void:
	_reward_accum += amount
	_reward_flush = _REWARD_FLUSH_TIME

## Presentation half of a core breach. Focus loss and the resulting game-over live in
## GameState, driven by SignalBus.distraction_escaped.
## NOTE: core breaches are NOT juice-scaled — losing Focus always hurts at full volume.
## The asymmetry is deliberate: rewards degrade with tolerance, but consequences don't.
func _on_distraction_reached_core(d: Distraction) -> void:
	_distractions.erase(d)
	_update_enemy_stats()
	# A fleeting distraction that made it home still costs nothing, so it gets none of
	# the breach presentation. Printing "-0 FOCUS" would read as a bug, and worse, it
	# would tell the player the thing was a threat after all.
	if d.def.focus_damage <= 0:
		return
	_glitch_hit = 0.85   # the screen lurches when your attention takes a hit
	add_shake(9.0)
	_pop_text(objective_pos, "-%d FOCUS" % d.def.focus_damage, Color("ff4455"))

# ---------------------------------------------------------------- tolerance / quick hit

## How far the Routine reaches. Named constants rather than magic numbers scattered
## across the draw and update paths, which is where they used to drift apart.
##
## HALVED AT P8b (2026-08-30), AND THE HALF IS DERIVED, NOT TASTED. These were authored
## for the pre-T5 isometric board and `26814f9` carried them across byte-identical while
## the board underneath them changed size. What actually changed is the size of ONE BUILD
## BLOCK: T5 took `GRID.tile` from 32 px to 16 px and left `BUILD_BLOCK` at 3, so a block
## went from 96 px of board to 48 px (block area 9216 -> 2304 px^2, i.e. exactly half in
## every linear measure). Every radius on this page means "reaches N build blocks", so
## every one of them halves with the block. No fitting, no per-level tuning: 330 -> 165,
## 260 -> 130, and the same 0.5 applied to the lamp/defender/projectile radii in the brain
## fog section and to every `range` in data/habits/.
##
## What it was costing: on the 480x224 board, 330 px lit 35 of the 50 build blocks from
## level_1's objective and 87% of them averaged over every possible objective position.
## Brain Fog was a mechanic that could not fail to be satisfied. At 165 it is 18 of 50
## (45% averaged), which is where the pre-T5 board sat (38%).
##
## 165 also stays OFF the 48 px build lattice on purpose. A radius that is an exact
## multiple of 48 puts a whole ring of build blocks at distance == radius, where
## is_position_in_routine()'s `<=` decides membership on a floating-point tie.
const CORE_ROUTINE_RADIUS := 165.0
## Kept at 0.79 of the core's, exactly as before the halving -- an Anchor extends the
## Routine by less than the core projects it, so chaining outward costs something.
## data/habits/anchor.tres's `range` MUST match this: it is a support habit, and
## HabitData's own header says a support habit's range ring IS its Routine radius.
const ANCHOR_ROUTINE_RADIUS := 130.0
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
		# On a fasting level the whole point is that the meter drains — slowly enough to
		# be felt for most of the level, fast enough that the colour is genuinely back by
		# the end. Without the multiplier the fast is just a level with no Quick Hit.
		if level.fasting:
			rate *= 2.5
		GameState.set_tolerance(GameState.tolerance - delta * rate)
	if _quick_hit_cd > 0.0:
		_quick_hit_cd = maxf(0.0, _quick_hit_cd - delta)
		_update_quick_hit_button()
	elif GameState.tolerance > 0.0:
		# Keep updating even when not on cooldown so the pulse/glow animates in real time.
		_update_quick_hit_button()
	_update_burnout(delta)

# ---------------------------------------------------------------- burnout
#
# Burnout is the only stat that reads back OUT of the scoreboard and into the field. Two
# thresholds, both deliberately visible before they bite:
#
#   STRAIN  the picture starts trembling — no mechanical cost, pure warning
#   FAIL    habits start losing ticks to procrastination
#
# The failure effect reuses the disruptor's disrupt() rather than the Pomodoro burnout
# flag: burned_out belongs to the work cycle and clearing it refills work_left, which
# would hand the player a free reset every time the meter bit.

const BURNOUT_STRAIN := 50.0     ## trembling starts
const BURNOUT_FAIL := 75.0       ## habits start dropping ticks
const BURNOUT_DECAY_PER_SEC := 1.5
const BURNOUT_SHAKE_INTERVAL := 0.2
const BURNOUT_ROLL_INTERVAL := 1.0
const BURNOUT_LAPSE_DURATION := 1.2
## Chance per habit per roll at burnout 100. At the FAIL threshold it is 0 and it ramps
## from there, so crossing the line is a warning rather than an instant collapse.
const BURNOUT_LAPSE_CHANCE_MAX := 0.35

var _burnout_shake_cd := 0.0
var _burnout_roll_cd := 0.0
var _burnout_was_over_fail := false

func _update_burnout(delta: float) -> void:
	var b: float = GameState.burnout
	if b > 0.0:
		GameState.set_burnout(b - delta * BURNOUT_DECAY_PER_SEC)
		b = GameState.burnout

	# Announce the threshold once per crossing, not every frame it stays crossed.
	if b >= BURNOUT_FAIL and not _burnout_was_over_fail:
		_burnout_was_over_fail = true
		_flash("Burnout — your habits are starting to slip.", UI.DANGER)
	elif b < BURNOUT_FAIL - 5.0 and _burnout_was_over_fail:
		_burnout_was_over_fail = false

	if b < BURNOUT_STRAIN:
		return

	# Re-arming on an interval instead of every frame: add_shake() takes the max and
	# _process lerps it down (game.gd:1747), so a per-frame call would pin the amplitude
	# and the tremble would lose its decay entirely.
	_burnout_shake_cd -= delta
	if _burnout_shake_cd <= 0.0:
		_burnout_shake_cd = BURNOUT_SHAKE_INTERVAL
		var strain: float = inverse_lerp(BURNOUT_STRAIN, 100.0, b)
		add_shake(1.5 + 2.5 * strain)

	if b < BURNOUT_FAIL:
		return

	_burnout_roll_cd -= delta
	if _burnout_roll_cd > 0.0:
		return
	_burnout_roll_cd = BURNOUT_ROLL_INTERVAL
	var chance: float = inverse_lerp(BURNOUT_FAIL, 100.0, b) * BURNOUT_LAPSE_CHANCE_MAX
	for spot in build_spots.values():
		if not is_instance_valid(spot) or spot.state != BuildSpot.State.BUILT:
			continue
		var h = spot.current_habit
		if not (h is Habit) or h.def.is_support() or h.disrupted_left > 0.0:
			continue
		if randf() >= chance:
			continue
		h.disrupt(BURNOUT_LAPSE_DURATION)
		# Named on the tower, because a lapse and a Group Chat ping look identical
		# otherwise and the player would blame the wrong thing.
		_pop_text(h.global_position + Vector2(-30.0, -46.0), "procrastinating", UI.DANGER)

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
	# Wanting up, liking down, from the same press. Two lines that started as one and
	# come apart over a campaign — that picture is the lesson, and this is where it gets
	# drawn (GameState: craving / satisfaction).
	GameState.add_craving(14.0)
	GameState.add_satisfaction(GameState.SATISFACTION_PER_QUICK_HIT)
	Mirror.mark(&"quick_hit", payout)
	_update_quick_hit_button()
	if level.fasting:
		# RELAPSE IS NOT A FAIL STATE. The meter jumps and continues; nothing resets and
		# nothing scolds. Shame is what actually drives the spiral, so a game that shames
		# the player here would be reproducing the exact mechanism it is warning about.
		_flash("Tolerance +%d. Continuing." % int(QUICK_HIT_SPIKE), UI.TEXT_DIM)
	else:
		_flash("+%d Cheap Dopamine… baseline Tolerance +%d" % [payout, int(QUICK_HIT_FLOOR_GAIN)],
			Color("ffcc00"))
	_pop_text(Vector2(480 - 38, 270 - 25), "+%d Cheap Dopamine" % payout, Color("ffcc00"))

## The shrinking number on the button is the lesson made visible — the player watches
## their own cheap source pay less every time they reach for it.
## TOLERANCE → QUICK HIT ESCALATION: the button gets louder as Tolerance rises.
## Size grows, colour shifts from neutral to urgent gold, and above 40% a pulsing
## glow appears. The asymmetry is the lesson: kill rewards are fading (juice) while
## the cheap source SCREAMS for attention. That is exactly how an app behaves when
## engagement is dropping — it escalates the push, not the content.
func _update_quick_hit_button() -> void:
	if _quick_hit_button == null:
		return
	if _quick_hit_cd > 0.0:
		_quick_hit_button.text = "Quick Hit (%.1fs)" % _quick_hit_cd
		_quick_hit_button.disabled = true
		_quick_hit_button.modulate = Color(0.6, 0.6, 0.6)
		_quick_hit_button.scale = Vector2.ONE
	else:
		_quick_hit_button.text = "Quick Hit +%d" % quick_hit_payout()
		_quick_hit_button.disabled = false

		# Escalation: scale, colour and pulse driven by tolerance.
		var t: float = GameState.tolerance / 100.0

		# Size: 1.0 at rest → 1.25 at max tolerance. The button literally grows.
		var s: float = lerpf(1.0, 1.25, t)
		_quick_hit_button.scale = Vector2(s, s)
		# Keep the button's anchor so it doesn't drift — pivot from centre.
		_quick_hit_button.pivot_offset = _quick_hit_button.size * 0.5

		# Colour: neutral white → urgent gold/amber at high tolerance.
		var base_col := Color(1.0, 1.0, 1.0).lerp(Color("ffaa22"), t)

		# Pulse: above 40% tolerance the button breathes. Faster at higher tolerance.
		if t > 0.4:
			var pulse_speed: float = lerpf(2.0, 5.0, (t - 0.4) / 0.6)
			var pulse: float = 0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * pulse_speed * TAU)
			# Pulse amplitude: subtle at 40%, aggressive at 100%.
			var amp: float = lerpf(0.08, 0.35, (t - 0.4) / 0.6)
			base_col = base_col.lerp(Color("ff6622"), pulse * amp)

		_quick_hit_button.modulate = base_col

# ---------------------------------------------------------------- attention lessons
#
# Everything in this section exists to be FELT during a level and understood after it.
# None of it adds a number to the HUD (docs/design/dopamine_mechanics.md §4): the
# scoreboard shows only what the player can act on within three seconds, the senses
# carry the rest, and the receipt does the explaining once the wave is over.
#
# The budget is one MOMENT per level. Every trick here — the empty bonus wave, the cue
# going hollow, an ad with a working button — is a one-shot. Fired twice it is a trick;
# fired every wave it is harassment. They cost nothing in ongoing complexity precisely
# because they almost never happen: ~95% of playing time is a plain, quiet tower
# defense, and it has to be, or none of this is worth sitting through.

## Full-screen wash that carries the TOLERANCE channel. Deliberately a flat grey mix
## rather than a luminance-preserving desaturation shader: mixing toward grey removes
## saturation AND contrast, which is closer to what "the colour went out of it" actually
## looks like, and it needs no shader to go wrong on somebody's driver.
##
## It sits BELOW the HUD layer, which is the whole trick — the map fades while the Quick
## Hit button keeps escalating in full colour on top of it. That asymmetry is the lesson
## and here it is free: the app gets louder exactly as the content stops paying.
## How far the picture flattens at Tolerance 100. Not 1.0 — the level still has to be
## playable at the bottom, and the sentence is "nothing stands out", not "you cannot see".
const FLATTEN_MAX := 0.85
var _wash: ColorRect = null
var _wash_mat: ShaderMaterial = null
var _flatten := 0.0

# --- Tolerance's visual verb --------------------------------------------------
#
# ONE SYSTEM, ONE SENSE. Tolerance owns colour and gets exactly one operation; Burnout
# owns the camera (tremble AND glitch, see _update_glitch); novelty owns the kill sound.
#
# The verb is FLATTEN, not "dim" and not "add grey", and it is drawn by
# shaders/flatten.gdshader — drain the saturation, collapse the range toward the scene's
# own mid-tone. Anhedonia is not reported as "everything looked faded", it is reported as
# "everything looked the same, nothing stood out", and collapsing the spread is that
# sentence. It also stays distinct from Brain Fog by construction, which matters because
# fog is a full-screen effect one CanvasLayer below:
#
#   Brain Fog   darkens and occludes  ->  takes INFORMATION (you cannot see what is there)
#   Tolerance   drains and collapses  ->  takes DEPTH       (you see it all, nothing stands out)
#
# MEASURED, and this is why the shader exists (build/flat*, 2026-08-20, _shot_flat.gd):
#
#   grey ColorRect   brightness ROSE 0.123 -> 0.148 as Tolerance went 0 -> 95. On a dark
#                    scene, mixing toward opaque grey lightens it. Reads as haze.
#   Light2D energy   the first fix attempt: drive the scene's lamps to zero, so "the
#                    lights go out and the depth goes with them". Turning EVERY light off
#                    moved contrast 3.1% and brightness 2.0% — nothing. The lamps are
#                    additive glow on top of art that already renders at full authored
#                    brightness (see the block comment above SHADOW_LIGHT_ENERGY); there
#                    is no darkness for them to lift out of, so there is nothing to take
#                    away by switching them off.
#
# The lighting version is still the better idea for isometric, but it needs a
# CanvasModulate base darkness under the whole field first — a real rendering decision
# with consequences for every piece of authored art, not a bolt-on. `depth_channel`
# below is the hook for it and is OFF until that lands.

## Drive Light2D energy from Tolerance as well as the flatten shader. OFF: measured at
## 3% of contrast (see above). Turn it on only once the field has a CanvasModulate base
## darkness for the lamps to lift out of, and re-measure with _shot_flat.gd before
## trusting it.
var depth_channel := false
## Light energy left at Tolerance 100, as a fraction of SHADOW_LIGHT_ENERGY.
const DEPTH_FLOOR := 0.0

## How far below its own baseline the picture drops during a bait wave's payoff. The one
## place anything is allowed to go under resting state — negative prediction error is not
## the absence of a reward, it is a dip, and rendering it as "merely nothing" would teach
## the wrong half of Schultz.
const BAIT_UNDERSHOOT := 0.30
var _bait_undershoot := 0.0
var _bait_armed := false

# --- the conditioned cue -----------------------------------------------------
#
# Pavlov, then Schultz: the dopamine response migrates backwards off the reward and onto
# whatever reliably predicts it. That is why an app ICON works on you and the content
# behind it does not have to.
#
# It can only be taught in this order and it cannot be done retroactively — level 1 must
# already be training a cue or there is nothing to hollow out in level 4. So phase 1 is
# the cheapest thing in this whole file (one rectangle and one chime) and the only one
# with a deadline.
const CUE_SIZE := Vector2(26, 26)
## Where the flash sits, as a CENTRE rather than a corner.
##
## Below the HUD bar, not inside it. It used to be pinned at (28, 28), which is on top of
## the Dopamine chip — and once conditioning started growing the square (up to 1.7x) it
## covered the number outright. A cue is supposed to pull the eye from the PERIPHERY; one
## that hides a stat is not peripheral, it is an obstruction.
##
## Centre rather than corner so growth expands both ways and the point the mouse is
## measured against (CUE_PULL_RADIUS) stays put no matter how conditioned it is.
const CUE_ORIGIN := Vector2(46, 122)
const CUE_COLOR := Color("4db4ff")
## A mouse inside this radius within CUE_WINDOW counts as having been pulled. Not a
## click: the cue is not a button and never was. Attention is the thing being measured,
## and the honest proxy available without eye tracking is "did the hand start moving".
const CUE_PULL_RADIUS := 220.0
const CUE_WINDOW := 2.0
## Share of phase-2 cues that still pay. It is NOT zero, and that is the entire point: a
## cue that is always empty gets extinguished in one level, and the player walks away
## having learned that they can train themselves out of it. They cannot. Variable ratio
## is what makes notifications un-ignorable, so the game has to be honest and keep some
## of them real.
const CUE_TRUE_RATE := 0.30

var _cue_rect: ColorRect = null
var _cue_glow := 0.0
var _cue_window_left := 0.0
var _cue_counted := false
var _cue_idle := 0.0

# --- downtime ----------------------------------------------------------------
#
# The prep phase is the only genuinely restful part of a tower defense, and boredom
# intolerance is the single best predictor of compulsive scrolling. Nobody has made that
# a mechanic, and the room for it already exists in the genre.
#
# At low Craving the build phase is a rest. At high Craving it is unbearable: the picture
# flattens, a thin tone sits on top of it, and the player starts skipping prep just to
# make the feeling stop. The receipt then reports what that cost them in seconds.
var _prep_started_at := -1.0
var _prep_tone_cd := 0.0

# --- delay discounting -------------------------------------------------------
#
# The larger payout is ALWAYS the better one, so every impatient pick is a measurement
# rather than a mistake the level punished. Across a campaign this draws the player's own
# discount curve, and the curve steepens exactly as Craving rises.
const OFFER_NOW := 20
const OFFER_LATER := 60
var _offer_panel: Control = null
var _offer_pending := false

# --- ads ---------------------------------------------------------------------
var _ads_left: Array[AdData] = []
var _ad_open: AdOverlay = null
## What one interstitial costs in Focus if the player lets the wave run while they hunt
## for the X. Small on purpose. The joke has teeth; it does not have jaws.
const AD_FOCUS_COST := 1

# --- the hands-off finale ----------------------------------------------------
#
# The Feed cannot be cleared, so the level is not won by clearing it. It is won by
# building enough that the board holds without you — and then taking your hands off and
# watching it happen.
#
# This is the ending because it is the one state where the most relaxing thing a tower
# defense can produce and the thesis of the game are the same thing. The goal was never
# to fight the feed harder.
const HANDS_OFF_SECONDS := 30.0
var _idle_seconds := 0.0
var _hands_off_active := false
var _hands_off_label: Label = null

func _setup_attention() -> void:
	# Layer 6: above the fog shader (5), below the HUD (10). Below the HUD is the whole
	# trick — the field flattens while the Quick Hit button keeps escalating in full
	# colour on top of it. The app gets louder exactly as the content stops paying.
	var wash_layer := CanvasLayer.new()
	wash_layer.layer = 6
	add_child(wash_layer)
	_wash_mat = ShaderMaterial.new()
	_wash_mat.shader = load("res://shaders/flatten.gdshader")
	_wash = ColorRect.new()
	_wash.material = _wash_mat
	_wash.color = Color.WHITE          # unused by the shader; it samples the screen
	_wash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wash.visible = false              # nothing to do at Tolerance 0; skip the pass
	wash_layer.add_child(_wash)

	if level.cue_phase > 0:
		_cue_rect = ColorRect.new()
		_cue_rect.color = Color(CUE_COLOR, 0.0)
		_cue_rect.custom_minimum_size = CUE_SIZE
		_cue_rect.size = CUE_SIZE
		_cue_rect.position = CUE_ORIGIN - CUE_SIZE * 0.5
		_cue_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_hud_root.add_child(_cue_rect)

	sinking_walls = level.sinking_walls
	_pick_sink_block()

	_ads_left = level.ads.duplicate()
	# The fast: the player arrives already downregulated and spends the level climbing
	# back out. Deliberately the least fun stretch in the campaign for its first two
	# thirds — and the reason the first clean chime afterwards lands on someone who has
	# been starved of it for six minutes. You cannot teach "it gets better" in text.
	if level.fasting:
		GameState.set_tolerance(70.0)
		GameState.set_satisfaction(15.0)

func _update_attention(delta: float) -> void:
	_update_depth_channel()
	_update_sinking(delta)
	if _wash != null:
		var target: float = (GameState.tolerance / 100.0) * FLATTEN_MAX
		_flatten = lerpf(_flatten, target, clampf(delta * 2.0, 0.0, 1.0))
		# Hidden outright at rest, same reasoning as the glitch overlay: a screen-texture
		# pass that changes nothing should not be paid for during clean play.
		_wash.visible = _flatten > 0.005 or _bait_undershoot > 0.005
		if _wash.visible:
			_wash_mat.set_shader_parameter("flatten", _flatten)
			_wash_mat.set_shader_parameter("dim", _bait_undershoot)
	if _bait_undershoot > 0.0:
		_bait_undershoot = maxf(0.0, _bait_undershoot - delta * (BAIT_UNDERSHOOT / 3.0))

	_update_cue(delta)
	_update_downtime(delta)
	_update_hands_off(delta)

# --- depth channel -----------------------------------------------------------

## Only claims Tolerance when there is actually a lit scene to unlight. On a level with
## shadows off there is nothing to flatten, so the wash keeps the job.
func _depth_channel_active() -> bool:
	return depth_channel and shadow_enabled and _shadow_light_layer != null

## Rides the SAME lights the atmosphere pass already built (_make_shadow_light) rather
## than adding a second lighting system — at Tolerance 0 the scene is lit exactly as
## authored, so this costs nothing until the player starts spending.
func _update_depth_channel() -> void:
	if not _depth_channel_active():
		return
	var flat: float = clampf(GameState.tolerance / 100.0, 0.0, 1.0)
	var e: float = SHADOW_LIGHT_ENERGY * lerpf(1.0, DEPTH_FLOOR, flat)
	if _core_shadow_light != null and is_instance_valid(_core_shadow_light):
		_core_shadow_light.energy = e
	for l in _shadow_lights.values():
		if is_instance_valid(l):
			l.energy = e

# --- cue ---------------------------------------------------------------------

func _update_cue(delta: float) -> void:
	if _cue_rect == null:
		return
	# Fades slower the more it means — a strongly conditioned cue holds the eye longer.
	_cue_glow = maxf(0.0, _cue_glow - delta * lerpf(2.0, 0.9, GameState.conditioning))
	_cue_rect.color = Color(CUE_COLOR, _cue_glow)

	if _cue_window_left > 0.0:
		_cue_window_left -= delta
		if not _cue_counted:
			# Actual size, not CUE_SIZE: a conditioned cue is bigger, so the constant
			# would put the centre off to one corner of it.
			var centre: Vector2 = _cue_rect.global_position + _cue_rect.size * 0.5
			if _hud_root.get_global_mouse_position().distance_to(centre) < CUE_PULL_RADIUS:
				_cue_counted = true
				Mirror.mark_click(&"cue")

	# Phase 2 fires on its own, unattached to anything. Phase 1 never does — it only ever
	# rides a real reward, which is what makes it worth anything later.
	if level.cue_phase >= 2 and not between_waves and not game_ended:
		_cue_idle -= delta
		if _cue_idle <= 0.0:
			_cue_idle = randf_range(7.0, 16.0)
			_fire_cue(randf() < CUE_TRUE_RATE)

## Flash + chime. `real` decides whether anything is behind it.
func _fire_cue(real: bool) -> void:
	if _cue_rect == null:
		return
	# The pairing happens BEFORE the presentation, so the flash the player sees is the
	# one this pairing produced rather than the previous one's strength.
	var reinstated: bool = GameState.condition_cue(real)
	var pull: float = GameState.conditioning
	_cue_glow = 1.0
	_cue_window_left = CUE_WINDOW
	_cue_counted = false
	# A conditioned cue is bigger and lingers longer. It is the same square of light; it
	# just takes up more of the screen the more it has come to mean. Nothing about the
	# game got harder, which is the point.
	var cue_sz: Vector2 = CUE_SIZE * (1.0 + pull * 0.7)
	_cue_rect.size = cue_sz
	_cue_rect.position = CUE_ORIGIN - cue_sz * 0.5
	Sfx.play_cue(pull)
	Mirror.mark(&"cue_flash", real)
	Mirror.mark(&"cue_pull", pull)
	if reinstated:
		# The moment worth naming: it had gone quiet, and one real payout brought it
		# most of the way back in a single step.
		Mirror.mark(&"cue_reinstated", pull)
		_flash("The flash means something again.", Color(CUE_COLOR))
	if real:
		GameState.add_run_insight(1)
		GameState.insight_dropped.emit(objective_pos, 1)

# --- downtime ----------------------------------------------------------------

func _begin_prep_span() -> void:
	_prep_started_at = Mirror.level_time()
	if level.delay_offers:
		_show_delay_offer()

func _end_prep_span() -> void:
	if _prep_started_at >= 0.0:
		Mirror.mark(&"prep_span", Mirror.level_time() - _prep_started_at)
		_prep_started_at = -1.0
	_hide_delay_offer()

func _update_downtime(delta: float) -> void:
	if not between_waves or game_ended:
		return
	var craving: float = GameState.craving / 100.0
	if craving < 0.45:
		return
	# A thin, unpleasant tone on an interval that tightens with Craving. Nothing is
	# mechanically wrong; it is just no longer restful to sit here.
	_prep_tone_cd -= delta
	if _prep_tone_cd <= 0.0:
		_prep_tone_cd = lerpf(3.2, 1.1, (craving - 0.45) / 0.55)
		Sfx.play(&"click")

# --- delay discounting -------------------------------------------------------

func _show_delay_offer() -> void:
	_hide_delay_offer()
	var panel := UI.panel(UI.DOPAMINE, 1)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	box.add_child(UI.label("Take %d Dopamine now — or %d when the wave clears."
		% [OFFER_NOW, OFFER_LATER], UI.FS_BODY, UI.TEXT))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)

	var now_btn := UI.button("Now  +%d" % OFFER_NOW)
	now_btn.pressed.connect(func():
		GameState.add_dopamine(OFFER_NOW)
		# Impatience is a real cheap hit, so it prices like one — small, but it counts.
		GameState.add_craving(5.0)
		Mirror.mark(&"offer_now")
		_hide_delay_offer())
	row.add_child(now_btn)

	var later_btn := UI.button("Wait  +%d" % OFFER_LATER)
	later_btn.pressed.connect(func():
		_offer_pending = true
		Mirror.mark(&"offer_later")
		_hide_delay_offer())
	row.add_child(later_btn)

	panel.position = Vector2(24, 190)
	_hud_root.add_child(panel)
	_offer_panel = panel

func _hide_delay_offer() -> void:
	if _offer_panel != null and is_instance_valid(_offer_panel):
		_offer_panel.queue_free()
	_offer_panel = null

func _settle_delay_offer() -> void:
	if not _offer_pending:
		return
	_offer_pending = false
	GameState.add_dopamine(OFFER_LATER)
	_pop_text(objective_pos, "+%d Dopamine (waited)" % OFFER_LATER, UI.DOPAMINE)

# --- bait wave ---------------------------------------------------------------

## Announced as a bonus, pays nothing. The announcement has to be completely sincere or
## the prediction never forms and there is nothing to violate.
func _announce_bait_wave() -> void:
	_bait_armed = true
	_flash("BONUS WAVE — DOUBLE DOPAMINE", UI.DOPAMINE)

func _resolve_bait_wave() -> void:
	if not _bait_armed:
		return
	_bait_armed = false
	# No message, no explanation, no "gotcha". Three seconds of the room being emptier
	# than its own baseline, and then it comes back. Naming it here would convert a
	# feeling into a fact, and the fact is the weaker of the two.
	_bait_undershoot = BAIT_UNDERSHOOT
	Music.duck(3.0)
	Mirror.mark(&"bait_wave")

# --- ads ---------------------------------------------------------------------

func _maybe_show_ad(for_wave: int) -> void:
	if _ad_open != null and is_instance_valid(_ad_open):
		return
	var last_wave: int = level.waves.size()
	for i in range(_ads_left.size()):
		var ad: AdData = _ads_left[i]
		if ad.between_levels:
			continue
		# An ad's wave lives on the AdData because it is part of the trust curve — which
		# ad the player is ready for depends on how many they have already seen, not on
		# which level they are standing in. That breaks down on a level SHORTER than the
		# wave an ad was authored for (the 5-wave isometric slice against ads written for
		# a 15-wave campaign), where it would simply never fire and the mechanic would
		# look unimplemented. Clamping to the finale keeps every authored ad reachable.
		var at: int = mini(ad.wave, last_wave) if last_wave > 0 else ad.wave
		if at != for_wave:
			continue
		_ads_left.remove_at(i)
		_show_ad(ad)
		return

## THE GAME KEEPS RUNNING behind this. While the player is laughing and hunting for a
## six-pixel X, the wave does not wait — which is the attention economy in a single
## interaction, and cheaper to feel than to be told.
##
## The Focus charge is one point and is named immediately afterwards. A joke that costs
## a level is not a joke, and a game that punishes you for getting caught has become the
## thing it is warning about.
func _show_ad(ad: AdData) -> void:
	var overlay := AdOverlay.create(ad)
	# Parented to the HUD layer, NOT the tree root — a scene change during an open ad
	# would otherwise leak it over the next screen.
	_hud_root.add_child(overlay)
	_ad_open = overlay
	overlay.closed.connect(func(tapped: bool, seconds: float):
		_ad_open = null
		if game_ended:
			return
		# Guarded, not just small: lose_focus() does NOT check for game over, so an
		# unguarded charge could silently strand the run at 0 Focus with no end screen.
		# It also must never be the thing that loses a level — see _show_ad's docs.
		var charged: int = 0
		if seconds > 1.5 and not level.fasting and GameState.focus > AD_FOCUS_COST:
			charged = AD_FOCUS_COST
			GameState.lose_focus(charged)
		_flash("Ad on screen: %.1fs. Focus lost: %d. Funny though." % [seconds, charged],
			UI.TEXT_DIM)
		if tapped:
			# Named plainly and once. No lecture: the receipt will show the count at the
			# end and the player can do their own arithmetic about what they knew.
			_flash("You knew what that was.", UI.TOLERANCE))

# --- hands-off finale --------------------------------------------------------

func _update_hands_off(delta: float) -> void:
	if not level.hands_off_finale or game_ended:
		return
	if wave_index + 1 < level.waves.size():
		return
	if not _hands_off_active:
		_hands_off_active = true
		_hands_off_label = UI.label("", UI.FS_TITLE, UI.FOCUS, HORIZONTAL_ALIGNMENT_CENTER)
		_hands_off_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
		_hands_off_label.position = Vector2(660, 150)
		_hands_off_label.custom_minimum_size = Vector2(600, 0)
		_hud_root.add_child(_hands_off_label)

	_idle_seconds += delta
	var left: float = HANDS_OFF_SECONDS - _idle_seconds
	if _hands_off_label != null and is_instance_valid(_hands_off_label):
		if _idle_seconds < 1.0:
			_hands_off_label.text = "Take your hands off the mouse.\nYour habits will hold."
		else:
			_hands_off_label.text = "Take your hands off the mouse.\nYour habits will hold.\n\n%0.0f" % maxf(left, 0.0)
	if left <= 0.0:
		Mirror.mark(&"hands_off_cleared")
		_level_complete()

## Any input at all resets the hold. Called from _unhandled_input.
func _note_input() -> void:
	_idle_seconds = 0.0

# ---------------------------------------------------------------- living map: trods
#
# The level's own move against the player: partway through, a new route to the core
# opens. See scripts/resources/trod_data.gd for the thesis behind it and for the
# convergence rule that keeps it fair.
#
# WHY IT CHANGES NO TERRAIN. A trod only re-weights ground the horde could already
# cross, so nothing can appear or vanish under something the player built and no level
# can be made unsolvable. That is the whole difference between this and the sinking-walls
# spike directly below, which really does erode a wall and needs all that extra care.

## index into level.trods -> true, for the ones already open. Reset in _build_field, so
## a retry of the same level starts closed again.
var _trods_open := {}

## The trod that opens at the START of the next wave, or null. This is the telegraph:
## drawn faint for one whole wave before it goes live. Without it a new route is a coin
## flip; with it the player watches it coming and cannot quite finish in time, which is
## the best tension a tower defense has.
func pending_trod() -> TrodData:
	if level == null:
		return null
	for i in range(level.trods.size()):
		var t: TrodData = level.trods[i]
		if t != null and not _trods_open.has(i) and t.open_at_wave == wave_index + 2:
			return t
	return null

## Opens everything due at `wave` (1-based). Called from _start_wave.
func _open_due_trods(wave: int) -> void:
	if level == null:
		return
	for i in range(level.trods.size()):
		var t: TrodData = level.trods[i]
		if t == null or _trods_open.has(i) or t.open_at_wave > wave:
			continue
		_trods_open[i] = true
		_open_trod(t)

func _open_trod(t: TrodData) -> void:
	var added := 0
	for c: Vector2i in t.cells:
		if not lane_cells.has(c) and _in_bounds(c) and not high_ground.has(c):
			lane_cells[c] = true
			added += 1
	if added == 0:
		return
	# A trod reclassifies already-open floor as lane (see the guard above: it never
	# touches `high_ground`), which only matters to the WEIGHTED preview astar and the
	# path art. It does not change what is reachable, so the shared flow_field every live
	# distraction actually walks on is untouched — no per-unit refresh needed here (P4,
	# docs/refactor/PATHFINDING.MD). BEHAVIOUR CHANGE from before P4: live movement now
	# reads the unweighted field and always takes the raw-shortest route, so opening a
	# trod no longer pulls a wave already on the board onto it — only the weighted
	# preview line (still astar, still honors path_off_lane_cost) shows the lane as
	# preferred. _test_trod.gd only asserts on that preview line, not on any live unit,
	# so it does not see this change; see PROGRESS.md's P4 entry for the reasoning.
	_apply_path_weights()
	_build_path_layer()
	_compute_path_previews()
	if _static_overlay != null and is_instance_valid(_static_overlay):
		_static_overlay.queue_redraw()
	queue_redraw()
	_flash(t.announce, UI.TOLERANCE)

# ---------------------------------------------------------------- sinking walls (SPIKE)
#
# SPIKE, not a shipped mechanic. One block, one threshold, disrupt() instead of
# destruction. The question it exists to answer is narrow: does erosion READ, and does
# A* cope with the maze changing under live distractions?
#
# THE IDEA. Tolerance has a look (shaders/flatten.gdshader) and now it gets a COST.
# docs/core/00_overview.md maps the maze onto "Structure & boundaries", so the honest
# consequence of spending too much cheap dopamine is that the structure erodes and the
# distractions reach the habits themselves. That is not a metaphor bolted onto a
# mechanic, it is the mechanic.
#
# It is also isometric-native: height IS the projection, so a block dropping to path
# level is legible in iso and literally invisible top-down. This is the first mechanic
# the flat version of the game cannot have.
#
# WHY IT IS DELIBERATELY SMALL. The obvious version — erode continuously with the
# Tolerance number — is a death spiral: maze dissolves, more leaks, more Burnout, worse.
# That is exactly the one-way descent docs/design/dopamine_mechanics.md §2 rejects. Three
# things keep it a rhythm instead:
#
#   1. ONE block, the furthest from the core. The maze frays at its edge, not everywhere.
#   2. A THRESHOLD with hysteresis, not a gradient. The line is visible and avoidable,
#      and dropping back under it RAISES THE WALL AGAIN — recovery you can watch.
#   3. An exposed habit is DISRUPTED, never destroyed. "When your boundaries erode your
#      habits are not destroyed, they are interrupted" is both truer and unspiral-able,
#      and it reuses the disruptor machinery that already exists (Tower.disrupt).
#
# KNOWN SPIKE LIMITATION: the block vanishes rather than animating downward, and a
# distraction standing on the cells when the wall returns is simply repathed out. The
# lowering animation is the next step, not this one.

## Set per level. Off everywhere by default — this is not a shipped mechanic yet.
var sinking_walls := false
const SINK_AT := 60.0
## Hysteresis, and it is wide on purpose: a block flickering up and down around a single
## number would repath the whole field every few frames and read as a bug.
const SINK_OFF := 45.0
const EXPOSED_DISRUPT_RADIUS := 110.0
const EXPOSED_DISRUPT_INTERVAL := 2.5
const EXPOSED_DISRUPT_DURATION := 1.6

var _sink_block := Vector2i(-9999, -9999)
var _sink_cells: Array[Vector2i] = []
var _sunk := false
var _exposed_cd := 0.0

## Picks which block erodes. Two rules, in order:
##
##  1. PREFER A BLOCK WITH A HABIT ON IT. The cost of eroded structure is supposed to be
##     "the distractions reach your habits", so a block with nothing on it costs nothing
##     and teaches nothing.
##  2. Among those, the one FURTHEST from the core. Furthest because that is where the
##     maze can afford to lose a piece, and because the habit you maintain least closely
##     is the honest one to lose first. Eroding the block next to the objective would be
##     a coin-flip on the whole level rather than a cost the player can play around.
##
## Re-picked at the moment it sinks, not once at level start: nothing is built when the
## level opens, so a start-of-level choice would always fall through to rule 2.
func _pick_sink_block() -> void:
	_sink_cells.clear()
	_sink_block = Vector2i(-9999, -9999)
	var best_d := -1.0
	var best_built_d := -1.0
	var best_built := Vector2i(-9999, -9999)
	for cell: Vector2i in build_spots:
		var d: float = cell_center(cell).distance_to(objective_pos)
		var spot = build_spots[cell]
		if is_instance_valid(spot) and spot.state == BuildSpot.State.BUILT 				and spot.current_habit is Habit and d > best_built_d:
			best_built_d = d
			best_built = cell
		if d > best_d:
			best_d = d
			_sink_block = cell
	if best_built.x > -9998:
		_sink_block = best_built
	if _sink_block.x < -9998:
		return
	var b: int = Data.BUILD_BLOCK
	for dy in range(-(b / 2), b / 2 + 1):
		for dx in range(-(b / 2), b / 2 + 1):
			var c: Vector2i = _sink_block + Vector2i(dx, dy)
			if high_ground.has(c):
				_sink_cells.append(c)

func _update_sinking(delta: float) -> void:
	if not sinking_walls or _sink_cells.is_empty() or game_ended:
		return
	if not _sunk and GameState.tolerance >= SINK_AT:
		# Re-pick now that the board has something on it (see _pick_sink_block).
		_pick_sink_block()
		if _sink_cells.is_empty():
			return
		_set_sunk(true)
	elif _sunk and GameState.tolerance <= SINK_OFF:
		_set_sunk(false)
	if _sunk:
		_tick_exposed(delta)

func _set_sunk(sunk: bool) -> void:
	_sunk = sunk
	for c: Vector2i in _sink_cells:
		if sunk:
			high_ground.erase(c)
			level.high_ground.erase(c)
		else:
			high_ground[c] = true
			if not level.high_ground.has(c):
				level.high_ground.append(c)
		if astar.is_in_bounds(c.x, c.y):
			astar.set_point_solid(c, not sunk)

	# Everything downstream of "which cells are walls" has to be rebuilt, in this order:
	# platforms (flood fill over high_ground), the terrain art (painted from
	# level.high_ground), then the paths.
	_build_platforms()
	_rebuild_walls()
	_compute_path_previews()
	# `high_ground` just changed — the ONE thing that invalidates the shared flow_field
	# (see its own header). Rebuilding it here is enough: every live distraction reads it
	# fresh every frame (Distraction._process()), so there is no per-unit list to walk any
	# more. A distraction standing exactly on a cell that just re-solidified goes idle on
	# its own (flow_field.has_cell() false for a blocked cell) rather than tunnelling
	# through on a stale route — see docs/refactor/PATHFINDING.MD P4.
	_rebuild_flow_field()
	queue_redraw()
	_flash("Structure eroded — a habit is exposed" if sunk else "Structure restored",
		UI.TOLERANCE if sunk else UI.FOCUS)

## Repaints the walls after the maze changed shape.
##
## Calls _build_wall_segments(), the same builder _build_field() uses during _ready.
## An earlier square corner-tile builder existed here and was never wired into either
## path (removed in the C1 dead-code cleanup, docs/CLEANUP_AUDIT.md) — mixing it with
## the iso field used to produce a shower of "Cannot create tile" errors from the
## wrong geometry, which is why this comment used to warn against calling it here.
func _rebuild_walls() -> void:
	_build_wall_segments()

## The habit standing on the sunk block, or null.
func exposed_habit() -> Habit:
	if not _sunk or not build_spots.has(_sink_block):
		return null
	var spot = build_spots[_sink_block]
	if not is_instance_valid(spot) or spot.state != BuildSpot.State.BUILT:
		return null
	var h = spot.current_habit
	return h if h is Habit else null

## Any distraction that gets close to an exposed habit interrupts it — not only the
## dedicated disruptor types. Reaching the habit at all is the escalation; what it does
## when it gets there is the same disrupt() the Group Chat already uses, so nothing new
## has to be balanced and nothing can be lost permanently.
func _tick_exposed(delta: float) -> void:
	_exposed_cd -= delta
	if _exposed_cd > 0.0:
		return
	var h = exposed_habit()
	if h == null or h.disrupted_left > 0.0:
		return
	for d in _distractions:
		if not is_instance_valid(d) or d.dead:
			continue
		if d.global_position.distance_to(h.global_position) > EXPOSED_DISRUPT_RADIUS:
			continue
		_exposed_cd = EXPOSED_DISRUPT_INTERVAL
		h.disrupt(EXPOSED_DISRUPT_DURATION)
		_pop_text(h.global_position + Vector2(-30.0, -46.0), "exposed", UI.DANGER)
		return

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
	_draft_options = options

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

# ---------------------------------------------------------------- distraction spatial hash
#
# Tower targeting used to scan EVERY live distraction per habit per call — has_enemy_in_cone,
# _tick_auto_aim and _aoe_targets in tower.gd each ran a full O(distractions) loop, so a
# board with several habits cost O(habits x distractions) every relevant tick (docs/refactor/
# PATHFINDING.MD P4). This buckets live distractions by grid cell, rebuilt once per Game
# frame (_process(), below) rather than per query — several habits querying the same frame
# share one build.
#
# Bucketed at single-cell granularity, not a coarser NxN block: this project's habits mostly
# carry ranges of 260-560px against a 480x224px playfield (docs/PERF.md's P4 entry has the
# numbers), so for most towers a query already has to touch most of the board and cell size
# buys nothing there. Where it DOES pay off is a horde marching single-file down a narrow
# lane: query_distractions_near() only visits OCCUPIED cells, so a query over a mostly-empty
# radius costs close to the number of cells the horde actually stands on, not the live
# distraction count — cheap to build (one dictionary insert per live body) and the simplest
# structure that clears its budget, matching P1/P2's own precedent over a fancier scheme this
# map size does not need.
var _distraction_hash: Dictionary = {}   # Vector2i (grid cell) -> Array[Distraction]

func _rebuild_distraction_hash() -> void:
	_distraction_hash.clear()
	for d in _distractions:
		if not is_instance_valid(d) or d.dead:
			continue
		var cell := world_to_cell(d.position)
		if _distraction_hash.has(cell):
			_distraction_hash[cell].append(d)
		else:
			_distraction_hash[cell] = [d]

## Every live, non-dead distraction whose CELL lies within `radius` of `center` — a cheap
## coarse pre-filter, not the final answer. Callers still run their own exact test (cone
## angle, wall raycast, whatever) on what comes back, exactly as they did when the source
## was get_live_distractions(); only the candidate list got cheaper to build. Cell-radius,
## not a tight pixel-radius, so nothing at the edge of a tower's own cell gets clipped out
## by rounding — same tolerance the old full scan implicitly had.
func query_distractions_near(center: Vector2, radius: float) -> Array:
	var result: Array = []
	if radius <= 0.0:
		return result
	var tile: float = Data.GRID.tile
	var center_cell := world_to_cell(center)
	var reach: int = ceili(radius / tile) + 1
	for dy in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			var cell := center_cell + Vector2i(dx, dy)
			if _distraction_hash.has(cell):
				for d in _distraction_hash[cell]:
					result.append(d)
	return result

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
		"steady_payout":
			return "Every defeat pays exactly +%d%% — no more streaks, no more jackpots" 				% int(round((GameState.STEADY_MULT - 1.0) * 100.0))
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
		"steady_payout":
			# Strictly better than the gamble it replaces (+20% expected), and perfectly
			# predictable. Whether the player takes it is the experiment; both answers are
			# the same finding seen from opposite sides.
			GameState.steady_payout = true
			_pop_text(objective_pos, "Steady payout", UI.DOPAMINE)
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
		var a := DefenderUnit.new()
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
	_draft_options = []

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
	# Freezes this level's row into Mirror.history so the receipt can pair it against
	# level 1. A lone number means nothing; the pair is the whole finding.
	Mirror.end_level()
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
	Mirror.end_level()
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
			# Each burst gets its own material copy so juice-scaled velocity
			# changes don't bleed between concurrent active bursts.
			p.process_material = _get_burst_material().duplicate()
			p.amount = 10
			p.lifetime = _BURST_LIFETIME
			p.one_shot = true
			p.explosiveness = 0.9
			p.emitting = false
			p.finished.connect(_on_burst_finished.bind(p))
			return p,
		_BURST_POOL_SIZE, self, 100)

func _on_projectile_finished(p: Projectile) -> void:
	_live_projectiles.erase(p)
	projectile_pool.release(p)

func _on_impact_fx_finished(fx: ImpactFX) -> void:
	impact_fx_pool.release(fx)

func _on_burst_finished(p: GPUParticles2D) -> void:
	burst_pool.release(p)

## Juice-scaled particle burst. At full juice: 10 particles, fast, vivid green.
## At zero juice: 3 particles, slow, washed-out grey-green. The visual reward
## literally thins out with Tolerance — the player's eye registers it even if
## their conscious mind doesn't.
func _spawn_dopamine_burst(pos: Vector2, juice: float = 1.0) -> void:
	var p: GPUParticles2D = burst_pool.acquire()
	if p == null:
		return
	p.position = pos
	# Scale particle count: 10 at full juice → 3 at zero juice.
	p.amount = maxi(3, int(round(lerpf(3.0, 10.0, juice))))
	# Scale initial velocity: fast and explosive at full juice, sluggish at zero.
	var mat: ParticleProcessMaterial = p.process_material
	if mat:
		mat.initial_velocity_min = lerpf(15.0, 45.0, juice)
		mat.initial_velocity_max = lerpf(35.0, 95.0, juice)
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

## BURNOUT is the sustained term, a core hit is a short spike. Hidden outright at rest so
## the screen-texture pass costs nothing during clean play.
##
## This used to ride TOLERANCE, and moving it is a deliberate design fix rather than a
## tidy-up. Tolerance had quietly accumulated three visual verbs at once — this glitch,
## the grey wash, and (in isometric) the lights — and three distorters on one number is
## exactly the muddiness the channel rule exists to prevent. Rendered side by side at
## Tolerance 95 the picture read as BROKEN rather than as flat, which is the wrong
## sentence: downregulation is not a malfunction, it is a dimming.
##
## Burnout is where it belonged anyway. Burnout already owns the camera (the tremble in
## _update_burnout), and shake and glitch are the same statement — "the picture is
## unstable" — where wash and unlit are the same statement as each other. It also starts
## at the SAME threshold as the tremble, so the two halves of Burnout's channel arrive
## together instead of one sneaking in early.
func _update_glitch(delta: float) -> void:
	if _glitch_rect == null:
		return
	_glitch_hit = maxf(0.0, _glitch_hit - delta * 1.5)
	var strain: float = clampf(
		inverse_lerp(BURNOUT_STRAIN, 100.0, GameState.burnout), 0.0, 1.0)
	var amount: float = clampf(strain * 0.75 + _glitch_hit, 0.0, 1.0)
	_glitch_rect.visible = amount > 0.01
	if _glitch_rect.visible:
		_glitch_mat.set_shader_parameter("intensity", amount)

# ---------------------------------------------------------------- HUD (built in code)

const _HUD_TOP_H := 17
const _HUD_BOTTOM_H := 24

# ---------------------------------------------------------------- speed & pause
#
# A 12-wave level runs ~13 minutes at 1x, and the tail of every late wave is 20-30s of
# one slow Doomscroll crawling while the player has nothing to do. Fast-forward is table
# stakes for the genre; it is also what makes repeated playtesting affordable.
#
# Q1 (docs/refactor/PATHFINDING.MD): the ladder runs 0.25×-4× now, and speed no longer
# scales Engine.time_scale for anything outcome-affecting — see FIXED_TICK_DT and
# _physics_process() below. level_simulator.gd's own header already documented why:
# Engine.time_scale scales a still-really-measured delta rather than replacing it with
# an exact synthetic constant, so two runs at different speeds are not generally
# bit-identical even for the SAME simulated duration (floating-point accumulation over a
# differently-sized delta, across a different step count, plus every RNG draw or timer
# that crosses a threshold mid-frame). Engine.time_scale is kept ONLY for the layer that
# stays on Godot's own automatic per-frame call and never touches a RESULT_FIELDS value —
# DistractionAnimator's walk cycle, particle bursts, screen shake, the glitch/flatten
# shaders — so what the player SEES still speeds up and slows down with the button, at
# zero cost to determinism.

const SPEED_STEPS: Array[float] = [0.25, 1.0, 2.0, 4.0]
## Designer-mode F3 override — above the normal ladder on purpose: a designer skimming
## dead time between layout decisions wants more than any player-facing step offers.
const DESIGNER_TURBO_SPEED := 5.0
## Index into SPEED_STEPS a fresh level starts at — 1.0×, same default every level had
## before this ladder grew a slower step below it.
const DEFAULT_SPEED_INDEX := 1

var _speed_index := DEFAULT_SPEED_INDEX
var _designer_turbo := false
var _paused := false
var _speed_button: Button = null
var _pause_button: Button = null
var _skip_wave_button: Button = null
var _pause_menu: PauseMenu = null

## THE SPEED BUTTON IS THE IMPATIENCE METER. Every tower defense already has one, and
## it already means "more waves per real minute, in exchange for worse decisions" — the
## same trade as watching everything at 1.5x and skipping the intros. Nothing had to be
## invented; it only had to be measured, which is why this is the cheapest lesson in the
## game and one of the sharpest on the receipt.
func _cycle_speed() -> void:
	_designer_turbo = false   # touching the normal ladder always leaves turbo
	_speed_index = (_speed_index + 1) % SPEED_STEPS.size()
	_apply_time_scale()
	Mirror.mark(&"speed_changed", SPEED_STEPS[_speed_index])

func set_speed_index(i: int) -> void:
	_designer_turbo = false
	_speed_index = clampi(i, 0, SPEED_STEPS.size() - 1)
	_apply_time_scale()
	Mirror.mark(&"speed_changed", SPEED_STEPS[_speed_index])

## What the fixed-tick accumulator actually reads (_physics_process() below) — 0.0 while
## paused, so the accumulator gains no budget and the sim tick count stays frozen no
## matter what Engine.time_scale is doing for the cosmetic layer.
func _current_speed() -> float:
	return DESIGNER_TURBO_SPEED if _designer_turbo else SPEED_STEPS[_speed_index]

## Pausing IS opening the menu — a bare freeze with nothing on screen read as a hang,
## and there was no way to abandon a run from inside it. This game node is ALWAYS now
## (see _ready()'s process_mode line) specifically so build/sell/aim/Quick-Hit/
## intervention commands keep reaching their handlers while paused (Q1, docs/refactor/
## PATHFINDING.MD) — the actual SIMULATION stays frozen because _physics_process()'s
## accumulator reads `_paused` and gains zero ticks, not because this node stops running.
## `entities` (this node's world-object container) is pinned back to PAUSABLE in
## _ready() specifically so the purely cosmetic automatic processing under it (walk-cycle
## animators, in-flight cosmetic tweens, particles) still freezes like before — only the
## command path had to change.
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
## 1.0 on the way out — otherwise the menus inherit 4x and every tween there runs wrong.
func _apply_time_scale() -> void:
	var speed := _current_speed()
	Engine.time_scale = 1.0 if _paused else speed
	if _speed_button:
		_speed_button.text = _speed_label(speed)
	if _pause_button:
		_pause_button.text = "▶" if _paused else "❚❚"

## "%.0f×" alone would print 0.25× as "0×" — everything from 1.0 up still reads as a
## bare integer (2×, not 2.00×).
static func _speed_label(speed: float) -> String:
	if speed < 1.0:
		return "%s×" % String.num(speed, 2)
	return "%.0f×" % speed

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
	_build_hover_tooltip()

	# A designer run must LOOK different from a real one, or an F1-funded balance
	# impression sneaks into memory as a real result. The badge doubles as the cheat
	# sheet, so the hotkeys need no documentation trip.
	if GameState.designer_mode:
		var badge := UI.label(
			"DESIGNER MODE — F1 +500 Dopamine · F2 +10 Insight · F3 turbo 5× · F4 clear wave · F5/F6 Tolerance -/+ · F7 sinking walls · telemetry off",
			UI.FS_SMALL, Color("ffb454"))
		badge.position = Vector2(6, _HUD_TOP_H + 1)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_hud_root.add_child(badge)

	# Smaller than it was: a full-width 46px banner across the middle of the field covered
	# the very thing the message is telling you to look at.
	_message_label = UI.label("", UI.FS_TITLE, UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	_message_label.position = Vector2(0, 38)
	_message_label.size = Vector2(480, 20)
	_message_label.modulate.a = 0.0
	_hud_root.add_child(_message_label)

	# "Dopamine", never "Willpower". The currency and the damage channel are different
	# things, and labelling the currency Willpower quietly taught the ego-depletion model
	# (willpower as a finite tank you spend) — a theory whose large multi-lab replication
	# failed, and the opposite of this game's actual thesis: dopamine is EARNED and SPENT.
	GameState.dopamine_changed.connect(_on_dopamine_changed)
	GameState.streak_changed.connect(_on_streak_changed)
	GameState.focus_changed.connect(_on_focus_changed)
	GameState.wave_changed.connect(_on_wave_changed)
	GameState.tolerance_changed.connect(_on_tolerance_changed)
	GameState.burnout_changed.connect(_on_burnout_changed)
	GameState.selected_habit_changed.connect(_on_selected_habit_changed)
	GameState.run_insight_changed.connect(_on_run_insight_changed)
	GameState.rush_changed.connect(_on_rush_changed)
	GameState.insight_dropped.connect(_on_insight_dropped)
	GameState.bandwidth_changed.connect(_on_bandwidth_changed)

	_on_dopamine_changed(GameState.dopamine)
	_on_run_insight_changed(GameState.run_insight)
	_on_rush_changed(GameState.rush)
	_on_bandwidth_changed(GameState.bandwidth_used, GameState.bandwidth_max)
	_on_focus_changed(GameState.focus, GameState.max_focus)
	_on_wave_changed(GameState.wave, GameState.max_wave)
	_on_tolerance_changed(int(GameState.tolerance))
	_on_burnout_changed(GameState.burnout)
	_update_enemy_stats()

func _build_top_bar() -> void:
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel",
		UI.flat(Color(UI.SURFACE.r, UI.SURFACE.g, UI.SURFACE.b, 0.96), UI.BORDER, 0, 0))
	bar.position = Vector2.ZERO
	bar.size = Vector2(480, _HUD_TOP_H)
	# STOP, not IGNORE: world_to_cell() clamps out-of-grid coordinates back into the grid,
	# so a click that fell through the bar resolved to row 0 and acted on the field.
	bar.mouse_filter = Control.MOUSE_FILTER_STOP
	_hud_root.add_child(bar)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 6)
	margin.add_theme_constant_override("margin_right", 6)
	margin.add_theme_constant_override("margin_top", 2)
	margin.add_theme_constant_override("margin_bottom", 2)
	bar.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.alignment = BoxContainer.ALIGNMENT_BEGIN
	margin.add_child(row)

	# --- the two currencies, left, where the eye starts
	var dop_out: Array = []
	row.add_child(UI.stat_chip("Dopamine", UI.DOPAMINE, dop_out))
	_dopamine_label = dop_out[0]

	var ins_out: Array = []
	row.add_child(UI.stat_chip("Insight", UI.INSIGHT, ins_out))
	_insight_label = ins_out[0]

	# Rush sits with the currencies rather than with Focus, even though it is earned by
	# nearly losing: it is something you spend, and the player looks for spendables here.
	var rush_out: Array = []
	row.add_child(UI.stat_chip("Rush", UI.DANGER, rush_out))
	_rush_label = rush_out[0]

	# Bandwidth reads "held / cap", not a spendable number — it sits with the currencies
	# because building is where the player will look when a build gets refused.
	var bw_out: Array = []
	var bw_chip := UI.stat_chip("Bandwidth", UI.ACCENT, bw_out)
	bw_chip.tooltip_text = ("Attention Bandwidth — how much you can hold at once.\n"
		+ "Every standing habit occupies part of it and gives it back when sold.\n"
		+ "It never drains on its own: it counts commitments, not fuel.")
	row.add_child(bw_chip)
	_bandwidth_label = bw_out[0]

	# --- the streak, sitting with the currencies because that is what it is: a
	# multiplier on income. It has to be READABLE AT A GLANCE and it has to drop to zero
	# in front of the player — a loss they have to go looking for is not a loss.
	if level.streak:
		var st_out: Array = []
		var st_chip := UI.stat_chip("Streak", UI.DOPAMINE, st_out)
		st_chip.tooltip_text = ("Waves in a row with nothing reaching your core.
"
			+ "Every one raises what defeats pay, up to x%.2f.
"
			+ "One leak sets it back to zero.") % GameState.STREAK_MAX_MULT
		row.add_child(st_chip)
		_streak_label = st_out[0]

	row.add_child(UI.spacer(Vector2(8, 0)))

	# --- Focus, the thing you actually lose. A bar, and the widest element in the bar.
	_focus_meter = UIMeter.new()
	_focus_meter.caption = "Focus"
	_focus_meter.fill_color = UI.FOCUS
	_focus_meter.danger_below = 0.34
	_focus_meter.custom_minimum_size = Vector2(300, 40)
	row.add_child(_focus_meter)

	# --- Burnout, right next to Focus, because it is the consequence of the same event.
	# Narrower on purpose: Focus stays the widest thing in the bar, since Focus is what
	# ends the run. Hidden at zero so a clean run never carries a scary empty gauge.
	_burnout_meter = UIMeter.new()
	_burnout_meter.caption = "Burnout"
	_burnout_meter.fill_color = UI.DANGER
	_burnout_meter.custom_minimum_size = Vector2(180, 40)
	_burnout_meter.visible = false
	row.add_child(_burnout_meter)

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
	bar.position = Vector2(0, 270 - _HUD_BOTTOM_H)
	bar.size = Vector2(480, _HUD_BOTTOM_H)
	# Same reason as the top bar: the gaps between buttons used to build towers on row 18.
	bar.mouse_filter = Control.MOUSE_FILTER_STOP
	_hud_root.add_child(bar)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 6)
	margin.add_theme_constant_override("margin_right", 6)
	margin.add_theme_constant_override("margin_top", 3)
	margin.add_theme_constant_override("margin_bottom", 3)
	bar.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	margin.add_child(row)

	for i in range(Data.HABIT_ORDER.size()):
		var key := String(Data.HABIT_ORDER[i])
		var d := Data.get_habit(key)
		var b := UI.button("%s\n%d ◆" % [d.short, d.build_cost], UI.FS_BODY, Vector2(132, 0))
		# Numbers, not just prose: a tooltip the player can compare against the enemy's
		# stats is a decision aid; flavor text alone is decoration.
		b.tooltip_text = "%s — %d Dopamine · holds %d Bandwidth\n%s\n%s\nHotkey: %d" \
			% [d.name, d.build_cost, d.bandwidth_cost, _habit_stats_line(d),
				d.description, i + 1]
		b.autowrap_mode = TextServer.AUTOWRAP_OFF
		row.add_child(b)
		b.pressed.connect(_select_habit.bind(key))
		_habit_buttons[key] = b
		b.add_child(_hotkey_badge(str(i + 1)))

	row.add_child(UI.spacer(Vector2(18, 0)))
	var sep := VSeparator.new()
	row.add_child(sep)
	row.add_child(UI.spacer(Vector2(18, 0)))

	var intervention_keys: Array[String] = ["Q", "W", "E", "R", "T"]
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

	_speed_button = UI.button(_speed_label(_current_speed()), UI.FS_HEAD, Vector2(72, 0))
	_speed_button.tooltip_text = "Game speed — click to cycle 0.25× / 1× / 2× / 4× (+ and −)"
	_speed_button.pressed.connect(_cycle_speed)
	row.add_child(_speed_button)

	# Skip to next wave — the same "end the build phase now" action Start Wave already
	# is (both call _on_start_wave_pressed()), surfaced a second time next to Pause/Speed
	# so it reads as part of the SAME time-control cluster rather than being the only
	# time control buried in the wave-management area on the far right (Q1, docs/
	# refactor/PATHFINDING.MD).
	_skip_wave_button = UI.button("Skip ▶▶", UI.FS_BODY, Vector2(84, 0))
	_skip_wave_button.tooltip_text = "Skip the build phase and jump straight into the " \
		+ "next wave (same as Start Wave)."
	_skip_wave_button.pressed.connect(_on_start_wave_pressed)
	row.add_child(_skip_wave_button)

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
		# The guild's stats are its roster: three slots whose types the player picks.
		return "3 defender slots · respawn %.0fs · guards %dpx around the rally" \
			% [def.ally_spawn_cooldown, int(def.guard_radius)]
	if def.is_support():
		return "Extends your Routine %dpx — habits inside it keep working" % int(def.range)
	# Everything a placed habit shows is post-cone: the player is looking at the tower
	# they actually have, at the width they actually set it to. The pre-purchase preview
	# (habit == null) shows the .tres numbers, which are by definition the home angle.
	var wp: int = habit.current_willpower_damage if habit != null else def.willpower_damage
	var aw: int = habit.current_awareness_damage if habit != null else def.awareness_damage
	var rng: float = habit.current_attack_range if habit != null else def.range
	var cd: float = habit.current_fire_cooldown if habit != null else def.fire_cooldown
	if habit != null:
		var prof := habit.arc_profile()
		wp = prof.scale_damage(wp)
		aw = prof.scale_damage(aw)
		cd = habit.shot_interval()
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
	if def.stun_duration > 0.0:
		parts.append("%ss %s" % [String.num(def.stun_duration, 1), Data.TERM.stun])
	if def.dispel_haste:
		parts.append(Data.TERM.dispel)
	if def.vulnerable_mult > 1.0:
		parts.append("+%d%% %s for %ss" % [roundi((def.vulnerable_mult - 1.0) * 100.0),
			Data.TERM.vulnerable, String.num(def.vulnerable_duration, 1)])
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
		if not is_equal_approx(up_def.defender_hp_mult, cur_def.defender_hp_mult):
			parts.append("defender HP ×%.2f → ×%.2f"
				% [cur_def.defender_hp_mult, up_def.defender_hp_mult])
		if not is_equal_approx(up_def.defender_damage_mult, cur_def.defender_damage_mult):
			parts.append("defender %s ×%.2f → ×%.2f" % [Data.TERM.damage,
				cur_def.defender_damage_mult, up_def.defender_damage_mult])
		if absf(up_def.ally_spawn_cooldown - cur_def.ally_spawn_cooldown) >= 0.05:
			parts.append("respawn %.1fs → %.1fs"
				% [cur_def.ally_spawn_cooldown, up_def.ally_spawn_cooldown])
		if int(up_def.guard_radius) != int(cur_def.guard_radius):
			parts.append("guards %d → %d" % [int(cur_def.guard_radius), int(up_def.guard_radius)])
		if up_def.bandwidth_cost != cur_def.bandwidth_cost:
			parts.append("Bandwidth %d → %d" % [cur_def.bandwidth_cost, up_def.bandwidth_cost])
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
	if up_def.bandwidth_cost != cur_def.bandwidth_cost:
		parts.append("Bandwidth %d → %d" % [cur_def.bandwidth_cost, up_def.bandwidth_cost])
	return " · ".join(parts)

# ---------------------------------------------------------------- HUD readouts

func _on_dopamine_changed(v: int) -> void:
	if _dopamine_label:
		_dopamine_label.text = str(v)
	# Affordability is state the player would otherwise have to work out by reading a
	# cost and comparing it to a number at the far end of the screen.
	_refresh_habit_affordability()

## The streak readout, and the moment it breaks.
##
## The break gets floating text at the core rather than a sound: sound belongs to
## Novelty and the camera to Burnout, so the one channel a streak is allowed to use is
## the NUMBER — which is also the honest one, because a number is exactly what was lost.
func _on_streak_changed(value: int, multiplier: float) -> void:
	if _streak_label == null:
		return
	if value <= 0:
		_streak_label.text = "—"
		_streak_label.add_theme_color_override("font_color", UI.TEXT_FAINT)
	else:
		_streak_label.text = "%d   x%.2f" % [value, multiplier]
		_streak_label.add_theme_color_override("font_color", UI.DOPAMINE)
	if value == 0 and _streak_was > 0 and not game_ended:
		# Lifted clear of the core: a leak already prints "-N FOCUS" at objective_pos on
		# the same event, and centred text there also sits half-behind the core sprite.
		_pop_text(objective_pos + Vector2(0, -52), "STREAK %d LOST" % _streak_was,
			UI.DANGER)
	_streak_was = value

## Last streak value seen, so the handler can tell "reset to 0 after a run" from
## "still 0" — only the first of those is a loss worth showing.
var _streak_was := 0

func _on_run_insight_changed(v: int) -> void:
	if _insight_label:
		_insight_label.text = "%d ◆" % v
	# Moment of Clarity is Insight-priced; its button must notice the balance moving.
	_update_intervention_buttons()

func _on_rush_changed(v: int) -> void:
	if _rush_label:
		_rush_label.text = str(v)
	# Same reason the Dopamine handler refreshes habit affordability: an ability the
	# player can suddenly afford should say so without them doing the arithmetic.
	_update_intervention_buttons()

func _on_bandwidth_changed(used: int, max_value: int) -> void:
	if _bandwidth_label:
		_bandwidth_label.text = "%d / %d" % [used, max_value]
		# The chip turns hot when the next cheapest habit no longer fits — the moment
		# the cap becomes the thing the player is actually playing against.
		_bandwidth_label.modulate = UI.DANGER if max_value - used < 8 else Color(1, 1, 1)
	_refresh_habit_affordability()

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
		var affordable: bool = GameState.dopamine >= d.build_cost \
			and GameState.can_reserve_bandwidth(d.bandwidth_cost)
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

## The readout names the STATE, not the number, because the number alone does not tell
## the player that their habits are about to start missing ticks.
func _on_burnout_changed(v: float) -> void:
	if _burnout_meter == null:
		return
	_burnout_meter.visible = v > 0.0
	if not _burnout_meter.visible:
		return
	var label := "%d%%" % int(v)
	if v >= BURNOUT_FAIL:
		label += "  ·  lapsing"
	elif v >= BURNOUT_STRAIN:
		label += "  ·  strained"
	_burnout_meter.update_meter(v, 100.0, label)

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
			_refresh_split_line()
	# The Quick Hit payout is tolerance-scaled, so its label moves whenever this does.
	_update_quick_hit_button()

## The wanting/liking split, drawn inside the Tolerance bar (UIMeter.split_value).
##
## Shown as `100 - satisfaction`, so both lines start at zero on the same left edge and
## the meter genuinely reads as ONE bar for the first few levels. What separates them is
## that Tolerance decays and lost Satisfaction does not — so the gap opens on its own,
## from the player's own choices, without a single word of explanation.
func _refresh_split_line() -> void:
	if _tolerance_meter == null:
		return
	_tolerance_meter.split_value = (100.0 - GameState.satisfaction) if level.split_meter else -1.0

func _on_satisfaction_changed(_v: float) -> void:
	_refresh_split_line()

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
