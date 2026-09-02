extends Node
## Headless harness for the minimap's one hard rule (P12, PATHFINDING.MD): it may never
## show more than the player has already been able to see.
##
## The rule is asserted against `Minimap.terrain_cells()` / `live_blips()` rather than
## against pixels, because those two functions ARE what `_draw()` is allowed to paint —
## see the Minimap header for why the content is a function. A pixel test would need a
## real renderer and would still only prove something about colours.
##
## Run:
##   godot --headless --path <proj> --main-scene res://scenes/_test_minimap.tscn

var completed := false
var fails := 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("  ok   %s %s" % [label, detail])
	else:
		fails += 1
		print("  FAIL %s %s" % [label, detail])


func _ready() -> void:
	var wd := Timer.new()
	wd.wait_time = 90.0
	wd.one_shot = true
	add_child(wd)
	wd.timeout.connect(func():
		if not completed:
			print("FAILED: watchdog fired")
			get_tree().quit(1))
	wd.start()
	call_deferred("_run")


func _spot_in_routine(game: Game) -> Vector2i:
	for cell: Vector2i in game.build_spots:
		var bs: BuildSpot = game.build_spots[cell]
		if bs.state != BuildSpot.State.EMPTY:
			continue
		if game.is_position_in_routine(game.cell_center(cell), game._routine_sources):
			return cell
	return Vector2i(-999, -999)


func _run() -> void:
	var game: Game = load("res://scenes/Game.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	GameState.max_focus = 999999
	GameState.focus = 999999
	# The fixture owns its subject — a content file must not be able to switch off the fog
	# this whole rule is about (the lesson P8b paid for).
	game.fog_enabled = true
	game.routine_gates_enabled = true
	await get_tree().process_frame
	game._update_fog(0.0)

	# Found by walking the tree rather than by a stored reference: the point is to check the
	# widget the GAME actually built and wired, not one this fixture made for itself.
	var map: Minimap = null
	for n in game.find_children("Minimap", "", true, false):
		map = n
		break
	_check("the game built a minimap", map != null)
	if map == null:
		_finish()
		return

	print("=== the rule: never more than explored")
	var cells := map.terrain_cells()
	_check("the map draws something at all", cells.size() > 0, "(%d cells)" % cells.size())
	var leaked := 0
	for c: Vector2i in cells:
		if not game.is_explored(Data.cell_center(c)):
			leaked += 1
	_check("no drawn cell is unexplored", leaked == 0,
		"(%d of %d leaked)" % [leaked, cells.size()])

	print("=== and it really is withholding something")
	# A rule that never bites is not a rule. The board is 30x14 = 420 cells; with fog on
	# and one Routine disk lit, the map must be showing well under all of them.
	var g = Data.GRID
	var total: int = int(g.cols) * int(g.rows)
	_check("the map is hiding most of the board", cells.size() < total,
		"(%d of %d cells shown)" % [cells.size(), total])
	var far_corner := Vector2i(0, int(g.rows) - 1)
	_check("a far unexplored corner is not drawn", not cells.has(far_corner))

	print("=== exploring more shows more, and never less")
	var before: int = cells.size()
	var spot := _spot_in_routine(game)
	_check("level has an empty spot inside the Routine", spot.x > -999, str(spot))
	if spot.x > -999:
		GameState.dopamine = 10000
		GameState.select_habit("focus_timer")
		game._build_on(spot)
		game._end_aiming()
		var hab: Habit = game.build_spots[spot].current_habit
		if hab != null:
			hab.facing_angle = (hab.global_position - game.objective_pos).angle()
			hab.set_arc_angle(60.0)
		game._update_fog(0.0)
		var after: int = map.terrain_cells().size()
		_check("a habit's cone put new ground on the map", after > before,
			"(%d -> %d cells)" % [before, after])

		# And selling it must not take the map away again — that is the explored grid's
		# whole job, seen from the UI side.
		game._do_sell(spot, 1)
		game._update_fog(0.0)
		var after_sell: int = map.terrain_cells().size()
		_check("selling the habit did not un-draw the map", after_sell >= after,
			"(%d -> %d cells)" % [after, after_sell])

	print("=== live bodies are NOT remembered, unlike terrain")
	var dark_cell := far_corner
	var d: Distraction = game.spawn_distraction(&"doomscroll", dark_cell)
	d.apply_slow(0.0, 999.0)   # hold it still so the geometry below stays true
	await get_tree().process_frame
	game._update_fog(0.0)
	_check("a distraction standing in the dark is not on the map",
		map.live_blips().is_empty(), "(%d blips)" % map.live_blips().size())

	game.fog_reveal_left = 5.0
	_check("it appears while a Moment of Clarity is lifting the fog",
		map.live_blips().size() > 0, "(%d blips)" % map.live_blips().size())
	game.fog_reveal_left = 0.0
	game._update_fog(0.0)
	_check("and it is gone again once the fog closes", map.live_blips().is_empty(),
		"(%d blips)" % map.live_blips().size())

	print("=== with fog off the whole board is shown, not none of it")
	game.fog_enabled = false
	_check("fog off: every cell is drawable", map.terrain_cells().size() == total,
		"(%d of %d)" % [map.terrain_cells().size(), total])

	_finish()


func _finish() -> void:
	completed = true
	print("\n%d FAIL(S)" % fails if fails > 0 else "\nALL PASS")
	get_tree().quit(1 if fails > 0 else 0)
