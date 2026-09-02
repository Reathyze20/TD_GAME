extends Node
## Headless harness for the `explored` half of the Brain Fog rule (P10, PATHFINDING.MD).
##
## SCOPE, and why it is this narrow. P10 asks for two things: towers may only target what
## is visible, and `explored` only ever grows. The FIRST is already shipped and already
## covered — `tower.gd:is_point_in_cone()` refuses a target whose position fails
## `is_pos_visible()`, `projectile.gd` lets a shot pass through a fog-hidden body, and
## `_test_fog_bandwidth` asserts all three of those directly ("a fog-hidden distraction
## does not light the board", "a shot passes through a fog-hidden body", "the same shot
## lands once the fog lifts"). Repeating them here would be coverage theatre. What had no
## test at all, because it had no implementation, is `explored`.
##
## Run:
##   godot --headless --path <proj> --main-scene res://scenes/_test_fog.tscn

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


## First EMPTY spot inside the current Routine, or (-999,-999).
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
	# Without defenses the core drains and _game_over()'s scene change frees this harness
	# mid-test — see the reference-godot-binary note.
	GameState.max_focus = 999999
	GameState.focus = 999999
	# The fixture owns its own subject: `fog` is a per-level bool and a content file must
	# not be able to switch off the thing under test. _test_fog_bandwidth learned this the
	# expensive way — it inherited the flag from level 1 and went from 2 failures to 14 in
	# silence when M3 turned it off there.
	game.fog_enabled = true
	game.routine_gates_enabled = true
	await get_tree().process_frame

	print("=== explored starts empty and follows the light")
	game._update_fog(0.0)
	_check("the core's own block is explored", game.is_explored(game.objective_pos))

	# A corner as far from the core as the board allows: outside every light at wave 0.
	var g = Data.GRID
	var far_corner: Vector2 = Data.cell_center(Vector2i(0, int(g.rows) - 1))
	_check("a far corner is not visible", not game.is_pos_visible(far_corner),
		str(far_corner))
	_check("a far corner is not explored either", not game.is_explored(far_corner))

	print("=== everything visible is explored")
	var visible_not_explored := 0
	for c: Vector2i in game._lit_cells:
		if not game._explored_cells.has(c):
			visible_not_explored += 1
	_check("no lit block is unexplored", visible_not_explored == 0,
		"(%d of %d lit blocks missing)" % [visible_not_explored, game._lit_cells.size()])

	print("=== a habit's cone explores new ground")
	var spot := _spot_in_routine(game)
	_check("level has an empty spot inside the Routine", spot.x > -999, str(spot))
	if spot.x <= -999:
		_finish()
		return

	var before_build: int = game._explored_cells.size()
	GameState.dopamine = 10000
	GameState.select_habit("focus_timer")
	game._build_on(spot)
	game._end_aiming()
	var hab: Habit = game.build_spots[spot].current_habit
	_check("a habit was built", hab != null)
	if hab == null:
		_finish()
		return

	# Aimed AWAY from the core, for the reason P8b measured: a legal build spot sits inside
	# the core's own Routine disk, so a cone pointed at the core lights nothing new and the
	# measurement would be aimed into ground that is lit whatever the habit does.
	hab.facing_angle = (hab.global_position - game.objective_pos).angle()
	hab.set_arc_angle(60.0)
	game._update_fog(0.0)
	var after_build: int = game._explored_cells.size()
	_check("the habit's cone explored blocks the core alone did not",
		after_build > before_build, "(%d -> %d blocks)" % [before_build, after_build])

	print("=== explored never shrinks — the whole point of the grid")
	# Snapshot every block explored so far, then take the habit away. `_lit_cells` is
	# rebuilt from scratch each update and MUST lose ground; `_explored_cells` must not.
	var snapshot: Dictionary = game._explored_cells.duplicate()
	var lit_before: int = game._lit_cells.size()
	game._do_sell(spot, 1)
	game._update_fog(0.0)
	var lit_after: int = game._lit_cells.size()

	_check("selling the habit really did unlight ground", lit_after < lit_before,
		"(%d -> %d lit blocks)" % [lit_before, lit_after])

	var forgotten := 0
	for c: Vector2i in snapshot:
		if not game._explored_cells.has(c):
			forgotten += 1
	_check("no explored block was forgotten", forgotten == 0,
		"(%d of %d dropped)" % [forgotten, snapshot.size()])
	_check("explored is still at least as large as before the sell",
		game._explored_cells.size() >= snapshot.size(),
		"(%d >= %d)" % [game._explored_cells.size(), snapshot.size()])

	print("=== monotone across many updates, not just one")
	var last: int = game._explored_cells.size()
	var dropped := 0
	for i in range(30):
		game._update_fog(1.0 / 60.0)
		var now: int = game._explored_cells.size()
		if now < last:
			dropped += 1
		last = now
	_check("explored never decreased over 30 fog updates", dropped == 0,
		"(%d decreases, final %d blocks)" % [dropped, last])

	print("=== a Moment of Clarity reveals without exploring")
	# Deliberate: is_pos_visible() short-circuits true during a reveal, but `_lit_cells` is
	# untouched, so nothing accumulates. See Game._explored_cells' own comment for why a
	# peek is not a survey — and for how to flip it if that reads wrong in play.
	var explored_before_reveal: int = game._explored_cells.size()
	game.fog_reveal_left = 5.0
	_check("reveal makes the far corner visible", game.is_pos_visible(far_corner))
	game._update_fog(0.0)
	_check("reveal did not explore the far corner", not game.is_explored(far_corner))
	_check("reveal added no explored blocks",
		game._explored_cells.size() == explored_before_reveal,
		"(%d -> %d)" % [explored_before_reveal, game._explored_cells.size()])
	game.fog_reveal_left = 0.0

	print("=== with fog off, everything counts as explored")
	# Mirrors is_pos_visible()'s own short-circuit. A minimap built on is_explored() must
	# show the whole board on a level that ships `fog = false`, not an empty one.
	game.fog_enabled = false
	_check("fog off: the far corner is visible", game.is_pos_visible(far_corner))
	_check("fog off: the far corner is explored", game.is_explored(far_corner))

	_finish()


func _finish() -> void:
	completed = true
	print("\n%d FAIL(S)" % fails if fails > 0 else "\nALL PASS")
	get_tree().quit(1 if fails > 0 else 0)
