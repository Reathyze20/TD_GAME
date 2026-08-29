extends Node
# Phase 4 verification: BaseHabit/Habit/Barracks split.
# Verifies inheritance, cone math, wave-active gating, upgrade state preservation,
# sell cleanup, economy parity, and barracks spawning.

var completed := false
var _game_over_events: Array = []

func _ready() -> void:
	var watchdog := Timer.new()
	watchdog.wait_time = 25.0
	watchdog.one_shot = true
	watchdog.timeout.connect(_on_timeout)
	add_child(watchdog)
	watchdog.start()
	call_deferred("_run")

func _on_timeout() -> void:
	if not completed:
		print("FAILED (watchdog timeout)")
		get_tree().quit(1)

func _check(cond: bool, msg: String) -> bool:
	print(("PASS " if cond else "FAIL ") + msg)
	return cond

## First build spot with several clear cells to its west, so a wedge pointed that way
## isn't shaded by terrain. Falls back to the first spot rather than failing outright —
## a level with no such spot is a level-design problem, and it should show up as the
## cone assertions failing with an explanation, not as a crash in the setup.
func _spot_with_clear_west(game: Node, spots: Array) -> BuildSpot:
	for s in spots:
		var clear := true
		for i in range(1, 5):
			if game.high_ground.has(s.grid_cell + Vector2i(-i, 0)):
				clear = false
				break
		if clear:
			return s
	print("NOTE: no build spot has open ground to its west; cone checks may misreport")
	return spots[0]

func _run() -> void:
	var ok := true

	GameState.current_level_index = 0
	var game: Node = load("res://scenes/Game.tscn").instantiate()
	add_child(game)
	# Milestone isolation: this harness predates the Brain Fog and the Routine build
	# gate and exercises OTHER systems — both new gates are switched off wholesale.
	# Their own coverage lives in _test_fog_bandwidth.gd.
	game.fog_enabled = false
	game.routine_gates_enabled = false
	await get_tree().process_frame
	await get_tree().process_frame

	SignalBus.game_over.disconnect(game._on_bus_game_over)
	SignalBus.game_over.connect(func(victory: bool): 
		_game_over_events.append(victory)
		game.game_ended = true
	)

	GameState.max_focus = 999999
	GameState.focus = 999999
	game.started = false
	game.between_waves = true
	
	var spots: Array = game.build_spots.values()
	# The cone-math section below fires WEST and checks that points to the west are in
	# cone, so the spot it uses has to have open ground to its west — is_point_in_cone
	# also casts for line of sight, and a wall shades the wedge exactly like a range
	# limit. Taking spots[0] blindly used to work and then quietly stopped when level_1
	# was re-laid out: the first build spot became (26,7) with four solid cells to its
	# left, and the cone math looked broken while it was doing precisely its job.
	var spot0: BuildSpot = _spot_with_clear_west(game, spots)
	var spot1: BuildSpot = spots[0] if spots[0] != spot0 else spots[1]

	# 1. Build ranged habit subclass
	GameState.dopamine = 9999
	GameState.selected_habit = "focus_timer"
	game._build_on(spot0.grid_cell)
	# Force aim lock since it waits for player click
	game.aiming_habit.facing_angle = PI
	game.aiming_habit.set_arc_angle(90.0)
	game.is_aiming = false
	game.aiming_habit.show_range_indicator = false
	game.aiming_habit = null
	game.aiming_spot = null
	var h1 := spot0.current_habit
	ok = _check(h1 is Habit, "ranged habit is class Habit") and ok
	ok = _check(h1.facing_angle == PI, "ranged habit sets facing") and ok
	ok = _check(h1.arc_angle == 90.0, "ranged habit sets arc") and ok

	# 2. Build barracks subclass
	GameState.selected_habit = "accountability"
	game._build_on(spot1.grid_cell)
	var h2 := spot1.current_habit
	ok = _check(h2 is Barracks, "barracks is class Barracks") and ok
	# The Nutrition Guild fields its whole three-slot recipe at once — a fresh guild
	# is never a lone unit slowly training up to strength.
	ok = _check(h2.owned_allies.size() == 3, "guild fields full recipe on build (got %d)" % h2.owned_allies.size()) and ok
	
	# 3. Cone math verification
	# h1 is at game.spots[0]. h1 is facing PI (left), 90 degree cone (45 each way)
	var h1_pos: Vector2 = h1.global_position
	var range_dist: float = h1.current_attack_range
	ok = _check(h1.is_point_in_cone(h1_pos + (Vector2.LEFT * range_dist * 0.5)), "cone math: center inside") and ok
	ok = _check(not h1.is_point_in_cone(h1_pos + (Vector2.LEFT * range_dist * 1.5)), "cone math: center outside range") and ok
	ok = _check(h1.is_point_in_cone(h1_pos + (Vector2.LEFT.rotated(deg_to_rad(40.0)) * range_dist * 0.5)), "cone math: edge inside") and ok
	ok = _check(not h1.is_point_in_cone(h1_pos + (Vector2.LEFT.rotated(deg_to_rad(50.0)) * range_dist * 0.5)), "cone math: edge outside") and ok

	# 4. Wave-active gating
	h1.cooldown = 0.0
	h1._process(0.1)
	var active_proj = game.projectile_pool._active
	# Because game.started = false, no projectiles should spawn
	ok = _check(game.projectile_pool._active == active_proj, "wave-active gate: no fire when inactive") and ok
	
	game.started = true
	game.between_waves = false
	var d = game.spawn_distraction(&"notification", spot0.grid_cell + Vector2i.LEFT)
	d.global_position = h1_pos + Vector2.LEFT * 50.0
	# Routine chaining (pilot Phase 2b) would idle a habit outside it, and that gate is
	# out of scope here — satisfied up front so the check stays about WAVE gating alone.
	# The barrel no longer gates anything: a habit fires into its sector whether or not
	# anything is standing in it, so long as the board has something live on it at all.
	h1.in_routine = true
	h1.cooldown = 0.0
	h1._process(0.1)
	ok = _check(game.projectile_pool._active > active_proj, "wave-active gate: fires when active") and ok

	# 5. Upgrade preserves facing
	game._do_upgrade(spot0.grid_cell, "focus_timer_2", 0)
	var h1_up := spot0.current_habit
	ok = _check(h1_up is Habit, "upgrade preserves Habit class") and ok
	ok = _check(h1_up.facing_angle == PI, "upgrade preserves facing angle") and ok
	ok = _check(h1_up.arc_angle == 90.0, "upgrade preserves arc angle") and ok
	
	# 6. Sell cleans up allies
	var ally_ref = h2.owned_allies[0]
	ok = _check(is_instance_valid(ally_ref), "ally exists before sell") and ok
	game._do_sell(spot1.grid_cell, 0)
	# Wait for queue_free
	await get_tree().process_frame
	ok = _check(not is_instance_valid(ally_ref), "sell barracks frees its allies") and ok

	# 7. Economy parity
	GameState.dopamine = 100
	GameState.selected_habit = "focus_timer"
	# Ensure the spot is empty first
	if spot1.state != BuildSpot.State.EMPTY:
		game._do_sell(spot1.grid_cell, 0)
	game._build_on(spot1.grid_cell)
	game.is_aiming = false
	game.aiming_habit.show_range_indicator = false
	game.aiming_habit = null
	game.aiming_spot = null
	ok = _check(GameState.dopamine == 100 - 30, "economy: build costs 30 (got %d)" % (100 - GameState.dopamine)) and ok
	game._do_sell(spot1.grid_cell, 15)
	ok = _check(GameState.dopamine == 100 - 30 + 15, "economy: sell refunds 15 (got %d)" % (GameState.dopamine - (100 - 30))) and ok

	# 8. A fallen slot respawns on its timer — as whatever the slot names by then.
	GameState.selected_habit = "accountability"
	game._build_on(spot1.grid_cell)
	var h3 := spot1.current_habit
	ok = _check(h3.owned_allies.size() == 3, "guild starts full (got %d)" % h3.owned_allies.size()) and ok
	var fallen = h3._slot_units[0]
	fallen.take_damage(999999)
	await get_tree().process_frame
	ok = _check(h3.owned_allies.size() == 2, "death empties the slot (got %d)" % h3.owned_allies.size()) and ok
	ok = _check(h3._slot_timers[0] > 0.0, "and starts its respawn clock") and ok
	for i in range(45):
		h3._process(0.1)   # 4.5s of wall time > 4.0s respawn
	ok = _check(h3.owned_allies.size() == 3, "slot respawns after the cooldown (got %d)" % h3.owned_allies.size()) and ok
	
	game.queue_free()
	completed = ok
	print("ALL PASS" if ok else "SOME CHECKS FAILED")
	get_tree().quit(0 if ok else 1)
