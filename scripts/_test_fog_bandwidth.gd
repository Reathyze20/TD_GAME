extends Node
## Headless harness for the Brain Fog + Attention Bandwidth milestone (docs/core/14).
##
## Covers the three new rule families with the gates ON (every other harness switches
## them off — this is the one place they are the subject):
##   1. Routine build gate — _can_build/_build_on refuse spots outside the light.
##   2. Bandwidth accounting — reserve on build, delta on upgrade, full release on
##      sell AND on an aiming-cancel rollback; the cap is a gate that aborts.
##   3. Fog visibility — lit cells around the core, darkness elsewhere, the projectile
##      hit loop and is_point_in_cone honouring it, and Moment of Clarity lifting it.
##   4. The guild respawn stall out of Routine (barracks.gd).

var completed := false
var fails := 0

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

func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("  ok   %s %s" % [label, detail])
	else:
		fails += 1
		print("  FAIL %s %s" % [label, detail])

## First EMPTY spot inside/outside the current Routine, or (-999,-999) when none.
func _find_spot(game: Game, inside: bool) -> Vector2i:
	for cell: Vector2i in game.build_spots:
		var bs: BuildSpot = game.build_spots[cell]
		if bs.state != BuildSpot.State.EMPTY:
			continue
		var in_r: bool = game.is_position_in_routine(game.cell_center(cell), game._routine_sources)
		if in_r == inside:
			return cell
	return Vector2i(-999, -999)

func _run() -> void:
	var game: Game = load("res://scenes/Game.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	# See reference-godot-binary memory: without defenses the core drains and
	# _game_over()'s scene change frees this harness mid-test.
	GameState.max_focus = 999999
	GameState.focus = 999999
	await get_tree().process_frame   # one full _process so routine + fog are computed

	print("=== routine build gate")
	var in_cell := _find_spot(game, true)
	var out_cell := _find_spot(game, false)
	_check("level has an empty spot inside the Routine", in_cell.x > -999)
	_check("level has an empty spot outside the Routine", out_cell.x > -999)

	var def := Data.get_habit(&"focus_timer")
	GameState.dopamine = 10000

	if out_cell.x > -999:
		var dop_before: int = GameState.dopamine
		var bw_before: int = GameState.bandwidth_used
		GameState.select_habit("focus_timer")
		game._build_on(out_cell)
		_check("build outside the Routine is refused",
			game.build_spots[out_cell].state == BuildSpot.State.EMPTY)
		_check("...and spends no Dopamine", GameState.dopamine == dop_before)
		_check("...and reserves no Bandwidth", GameState.bandwidth_used == bw_before)

	print("=== bandwidth accounting")
	GameState.select_habit("focus_timer")
	game._build_on(in_cell)
	game._end_aiming()
	_check("build inside the Routine succeeds",
		game.build_spots[in_cell].state == BuildSpot.State.BUILT)
	_check("build reserves the habit's bandwidth_cost",
		GameState.bandwidth_used == def.bandwidth_cost,
		"(got %d, expected %d)" % [GameState.bandwidth_used, def.bandwidth_cost])

	var up_def := Data.get_habit(&"focus_timer_2")
	game._do_upgrade(in_cell, "focus_timer_2", up_def.build_cost)
	_check("upgrade charges only the bandwidth delta",
		GameState.bandwidth_used == up_def.bandwidth_cost,
		"(got %d, expected %d)" % [GameState.bandwidth_used, up_def.bandwidth_cost])

	game._do_sell(in_cell, 1)
	_check("sell releases the full hold", GameState.bandwidth_used == 0,
		"(got %d)" % GameState.bandwidth_used)

	# The cap is a GATE: when the next habit does not fit, nothing moves.
	var used_backup: int = GameState.bandwidth_used
	GameState.bandwidth_used = GameState.bandwidth_max - def.bandwidth_cost + 1
	var dop_gate: int = GameState.dopamine
	GameState.select_habit("focus_timer")
	game._build_on(in_cell)
	_check("over-cap build is aborted",
		game.build_spots[in_cell].state == BuildSpot.State.EMPTY)
	_check("...and spends no Dopamine", GameState.dopamine == dop_gate)
	GameState.bandwidth_used = used_backup

	# Aiming-cancel rollback: right-click during the fresh-build aim returns BOTH
	# currencies in full — bandwidth mirrors reserve, not spend.
	GameState.select_habit("focus_timer")
	game._build_on(in_cell)
	_check("aiming after fresh build", game.is_aiming)
	var dop_mid: int = GameState.dopamine
	var rmb := InputEventMouseButton.new()
	rmb.button_index = MOUSE_BUTTON_RIGHT
	rmb.pressed = true
	game._unhandled_input(rmb)
	_check("cancel rolls the spot back",
		game.build_spots[in_cell].state == BuildSpot.State.EMPTY)
	_check("cancel refunds the Dopamine in full",
		GameState.dopamine == dop_mid + def.build_cost,
		"(got %d)" % GameState.dopamine)
	_check("cancel releases the Bandwidth in full", GameState.bandwidth_used == 0,
		"(got %d)" % GameState.bandwidth_used)
	GameState.select_habit(null)

	print("=== fog visibility")
	await get_tree().process_frame
	_check("the core's cell is lit", game.is_pos_visible(game.objective_pos))
	# The far corner of level 1 sits well outside every light.
	var dark_cell := Vector2i(-999, -999)
	for y in range(Data.GRID.rows):
		for x in range(Data.GRID.cols):
			var c := Vector2i(x, y)
			if game.high_ground.has(c) or game._lit_cells.has(c):
				continue
			dark_cell = c
			break
		if dark_cell.x > -999:
			break
	_check("some walkable cell is dark", dark_cell.x > -999)
	var dark_pos: Vector2 = game.cell_center(dark_cell)
	_check("darkness is not visible", not game.is_pos_visible(dark_pos))
	game.fog_reveal_left = 1.0
	_check("reveal makes it visible", game.is_pos_visible(dark_pos))
	game.fog_reveal_left = 0.0

	# A distraction standing in the dark: no tower fires at it (board_live) and a shot
	# passing straight through it leaves it untouched.
	var d: Distraction = game.spawn_distraction("doomscroll", dark_cell)
	d.apply_slow(0.0, 999.0)   # freeze in place so the geometry below holds
	await get_tree().process_frame
	_check("a fog-hidden distraction does not light the board",
		not game.has_visible_distraction())
	var hp_before: int = d.current_health
	game.spawn_directional_projectile(dark_pos - Vector2(90, 0), 0.0, 240.0, 5, 0,
		Color.WHITE)
	for i in range(30):
		await get_tree().process_frame
	_check("a shot passes through a fog-hidden body", d.current_health == hp_before,
		"(hp %d -> %d)" % [hp_before, d.current_health])
	game.fog_reveal_left = 5.0
	game.spawn_directional_projectile(dark_pos - Vector2(90, 0), 0.0, 240.0, 5, 0,
		Color.WHITE)
	for i in range(30):
		await get_tree().process_frame
	_check("the same shot lands once the fog lifts", d.current_health < hp_before,
		"(hp %d -> %d)" % [hp_before, d.current_health])
	game.fog_reveal_left = 0.0
	d.take_direct_damage(999999)   # clean the board for the checks below
	await get_tree().process_frame

	print("=== moment of clarity")
	GameState.run_insight = 10
	game._cast_intervention("moment_of_clarity", Vector2.ZERO)
	await get_tree().create_timer(0.6).timeout   # sky-strike tween lands after 0.22s
	_check("cast spends the Insight", GameState.run_insight == 4,
		"(got %d)" % GameState.run_insight)
	_check("cast lifts the fog", game.fog_reveal_left > 0.0,
		"(left %.1f)" % game.fog_reveal_left)
	_check("cast commits the cooldown",
		game.intervention_cooldowns.get("moment_of_clarity", 0.0) > 0.0)
	var insight_short: int = GameState.run_insight
	GameState.run_insight = 0
	game.intervention_cooldowns["moment_of_clarity"] = 0.0
	game._cast_intervention("moment_of_clarity", Vector2.ZERO)
	_check("an unaffordable cast is refused before the cooldown",
		game.intervention_cooldowns.get("moment_of_clarity", 0.0) == 0.0)
	GameState.run_insight = insight_short
	game.fog_reveal_left = 0.0

	print("=== guild respawn stalls out of Routine")
	var guild_cell := _find_spot(game, true)
	GameState.select_habit("accountability")
	game._build_on(guild_cell)
	GameState.select_habit(null)
	var guild: Barracks = game.build_spots[guild_cell].current_habit
	await get_tree().process_frame
	var victim = guild._slot_units[0]
	victim.take_damage(999999)
	await get_tree().process_frame
	_check("slot opens on death", guild._slot_units[0] == null)
	var timer_at_death: float = guild._slot_timers[0]
	_check("slot timer armed", timer_at_death > 0.0)
	# Yank the Routine out from under it: the core is the only source, so moving the
	# cached objective_pos far away cuts every habit off on the next frame.
	var real_objective: Vector2 = game.objective_pos
	game.objective_pos = Vector2(-99999, -99999)
	await get_tree().create_timer(1.0).timeout
	_check("guild is out of Routine", not guild.in_routine)
	_check("respawn timer is frozen while dark",
		is_equal_approx(guild._slot_timers[0], timer_at_death),
		"(%.2f vs %.2f)" % [guild._slot_timers[0], timer_at_death])
	game.objective_pos = real_objective
	await get_tree().create_timer(guild.def.ally_spawn_cooldown + 1.0).timeout
	_check("slot respawns once the Routine returns", guild._slot_units[0] != null)

	print("=== level reset clears the hold")
	GameState.reset_for_level(game.level)
	_check("reset zeroes bandwidth_used", GameState.bandwidth_used == 0)
	_check("reset restores the cap at least to base",
		GameState.bandwidth_max >= GameState.BASE_BANDWIDTH,
		"(cap %d)" % GameState.bandwidth_max)

	completed = true
	if fails == 0:
		print("ALL PASS")
		get_tree().quit(0)
	else:
		print("SOME CHECKS FAILED (%d)" % fails)
		get_tree().quit(1)
