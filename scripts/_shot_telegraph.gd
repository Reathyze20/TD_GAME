extends Node
## P7 (docs/refactor/PATHFINDING.MD): screenshots the spawn telegraph mid-countdown — a
## record for PROGRESS.md, not a pass/fail check (CLAUDE.md's _shot_*.tscn vs
## _test_*.tscn distinction — nobody is judging this screenshot's aesthetics).
##
## Builds the same shape of fixture _test_telegraph.gd's real assertions run against
## (level id 1's real geometry + one SpawnPointData whose activation wave has just
## started), starts wave 1, lets a handful of REAL frames tick — Game.TelegraphOverlay's
## own _process()/queue_redraw() is what makes the marker's pulse animate in real time,
## same as PlacementOverlay (see game.gd's own header comment on that class) — so
## wave_time lands partway through telegraph_lead_time, then captures the live viewport.
##
## Spusteni (NE --headless, kresleni potrebuje skutecny renderer):
##   godot --path <proj> --main-scene res://scenes/_shot_telegraph.tscn -- \
##     --out .dev/screenshots/p7_telegraph.png

var _done := false


func _ready() -> void:
	call_deferred("_run")


func _arg(name: String, fallback: String) -> String:
	var args := OS.get_cmdline_user_args()
	for i in range(args.size()):
		if args[i] == name and i + 1 < args.size():
			return args[i + 1]
	return fallback


const TEST_LEVEL_ID := 762037
const LEAD_TIME := 5.0


## Nearest open floor cell to the grid's center, so the marker (ring + arrow + text)
## lands away from the screen edge in the shot instead of clipping against it — purely
## for legibility of the RECORD image; _test_telegraph.gd's own fixture does not need
## this (nothing in that test reads pixels) and keeps its edge cell.
func _find_center_open_cell(hg: Array[Vector2i], objective: Vector2i) -> Vector2i:
	var g = Data.GRID
	var blocked := {}
	for c: Vector2i in hg:
		blocked[c] = true
	var center := Vector2i(int(g.cols) / 2, int(g.rows) / 2)
	for radius in range(int(max(g.cols, g.rows))):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if max(abs(dx), abs(dy)) != radius:
					continue
				var c := center + Vector2i(dx, dy)
				if Data.in_bounds(c) and not blocked.has(c) and c != objective:
					return c
	return Vector2i.ZERO


func _build_fixture_level() -> LevelData:
	var base: LevelData = null
	for i in range(Data.get_level_count()):
		if Data.get_level(i).id == 1:
			base = Data.get_level(i)
			break
	if base == null or base.wave_curve.is_empty():
		return null

	var sp := SpawnPointData.new()
	sp.cell = _find_center_open_cell(base.high_ground, base.objective)
	sp.active_from_wave = 1
	sp.telegraph_lead_time = LEAD_TIME
	sp.direction_id = &"N"

	var curve_row := WaveCurveEntryData.new()
	curve_row.distraction = base.wave_curve[0].distraction
	curve_row.from_wave = 1
	curve_row.base_count = 3
	curve_row.growth_per_wave = 0.0
	curve_row.spacing = LEAD_TIME * 2.0   # first real entry lands well after the shot
	curve_row.shape = WaveCurveEntryData.SpawnShape.STREAM

	var lv := LevelData.new()
	lv.id = TEST_LEVEL_ID
	lv.display_name = "P7 telegraph screenshot fixture (never a real campaign level)"
	lv.start_dopamine = base.start_dopamine
	lv.focus = 999999
	lv.objective = base.objective
	lv.high_ground = base.high_ground.duplicate()
	lv.path_cells = base.path_cells.duplicate()
	lv.path_off_lane_cost = base.path_off_lane_cost
	lv.wave_count = 1
	lv.wave_curve = [curve_row]
	lv.spawn_zones = []
	lv.spawn_points = [sp]
	return lv


func _run() -> void:
	var out := _arg("--out", ".dev/screenshots/p7_telegraph.png")

	var lv := _build_fixture_level()
	if lv == null:
		print("shot_telegraph: could not build fixture (level id 1 missing?)")
		get_tree().quit(1)
		return
	Data._levels.append(lv)
	Data._levels.sort_custom(func(a: LevelData, b: LevelData): return a.id < b.id)
	var lv_index := -1
	for i in range(Data.get_level_count()):
		if Data.get_level(i).id == TEST_LEVEL_ID:
			lv_index = i
			break

	GameState.current_level_index = lv_index
	var game: Game = load("res://scenes/Game.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	# Bez obrany jadro vyhori a _game_over() prehodi scenu jeste pred fotkou -- viz
	# _shot_crowd.gd's own comment for the same defensive pattern.
	GameState.max_focus = 999999
	GameState.focus = 999999
	game.fog_enabled = false
	await get_tree().process_frame

	game._on_start_wave_pressed()

	# Real frames, not manual _sim_tick() calls -- this shot is specifically about the
	# COSMETIC free-running pulse (game.gd's own TelegraphOverlay._process() comment), so
	# it needs Godot's own per-frame scheduling actually running. ~1 real second at
	# default 1x speed lands wave_time comfortably inside the 5s telegraph window.
	for _i in range(60):
		await get_tree().process_frame

	var img := get_viewport().get_texture().get_image()
	img.save_png(out)
	var pending := game._pending_spawn_points(1, game.wave_time)
	print("shot_telegraph: %s  %dx%d  |  wave_time=%.2f  pending=%d" % [out, img.get_width(),
		img.get_height(), game.wave_time, pending.size()])
	_done = true
	get_tree().quit(0)
