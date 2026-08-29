extends Node
## Harness for the Burnout / Overdrive / damage-shape / Rush work.
##
## Same shape as _test_phase2.gd: instantiate the real Game, pin Focus so a leak can't
## trip _game_over() (which would change scene and free this node together with its
## watchdog), then drive the systems imperatively.
##
## Everything here is a rule that is invisible on screen until it is wrong: a multiplier
## that silently reads 1.0, an immunity that quietly also blocks freezes, a currency that
## resets without emitting. Those are exactly the failures playtesting does not catch.

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

func _run() -> void:
	var game: Game = load("res://scenes/Game.tscn").instantiate()
	add_child(game)
	# Milestone isolation: this harness predates the Brain Fog and the Routine build
	# gate and exercises OTHER systems — both new gates are switched off wholesale.
	# Their own coverage lives in _test_fog_bandwidth.gd.
	game.fog_enabled = false
	game.routine_gates_enabled = false
	await get_tree().process_frame
	GameState.max_focus = 999999
	GameState.focus = 999999
	game.started = true
	game.between_waves = false

	_test_burnout(game)
	await _test_overdrive(game)
	_test_damage_shape(game)
	_test_rush(game)
	await _test_airplane_mode(game)

	completed = true
	print("")
	if fails == 0:
		print("ALL PASS")
		get_tree().quit(0)
	else:
		print("%d FAILED" % fails)
		get_tree().quit(1)

# ---------------------------------------------------------------- burnout

func _test_burnout(game: Game) -> void:
	print("=== burnout rises with the size of the leak, not the count")
	GameState.set_burnout(0.0)
	var emitted := []
	GameState.burnout_changed.connect(func(v: float): emitted.append(v))

	SignalBus.distraction_escaped.emit(1)
	var after_small: float = GameState.burnout
	SignalBus.distraction_escaped.emit(5)
	var after_big: float = GameState.burnout
	_check("a leak raises Burnout", after_small > 0.0, "(%.1f)" % after_small)
	_check("a 5-Focus leak costs 5x a 1-Focus leak",
		is_equal_approx(after_big - after_small, 5.0 * after_small),
		"(%.1f then %.1f)" % [after_small, after_big - after_small])
	_check("the meter is told", emitted.size() == 2)

	print("=== burnout decays, so one bad wave is survivable")
	GameState.set_burnout(40.0)
	game._update_burnout(2.0)
	_check("decays during play", GameState.burnout < 40.0, "(%.1f)" % GameState.burnout)

	print("=== above the failure threshold, habits start dropping ticks")
	var spot := _first_empty_spot(game)
	_check("a build spot exists to test with", spot != null)
	if spot != null:
		GameState.dopamine = 9999
		GameState.select_habit("focus_timer")
		game._build_on(spot.grid_cell)
		var h = spot.current_habit
		_check("habit built", h is Habit)
		if h is Habit:
			h.disrupted_left = 0.0
			GameState.set_burnout(100.0)
			# 100 % burnout is a 35 % chance per habit per roll; 60 rolls makes a miss
			# a 1-in-10^11 event, so a failure here is a broken rule, not bad luck.
			var lapsed := false
			for i in range(60):
				game._burnout_roll_cd = 0.0
				game._update_burnout(0.0)
				if h.disrupted_left > 0.0:
					lapsed = true
					break
			_check("a habit lapses at full Burnout", lapsed)
			h.disrupted_left = 0.0

			GameState.set_burnout(0.0)
			var lapsed_clean := false
			for i in range(60):
				game._burnout_roll_cd = 0.0
				game._update_burnout(0.0)
				if h.disrupted_left > 0.0:
					lapsed_clean = true
					break
			_check("no habit lapses at zero Burnout", not lapsed_clean)

	print("=== a new level starts clean")
	var emitted_reset := []
	GameState.burnout_changed.connect(func(v: float): emitted_reset.append(v))
	GameState.set_burnout(80.0)
	emitted_reset.clear()
	GameState.reset_for_level(Data.get_level(0))
	_check("reset zeroes Burnout", is_zero_approx(GameState.burnout))
	_check("reset also EMITS it (a stale HUD is the classic miss)",
		not emitted_reset.is_empty())
	GameState.max_focus = 999999
	GameState.focus = 999999

# ---------------------------------------------------------------- overdrive

func _test_overdrive(game: Game) -> void:
	print("=== overdrive is armed by wounding, and only once")
	var e := game.spawn_distraction(&"energy_drink", game._random_spawn_cell())
	_check("energy drink spawned", e != null)
	if e == null:
		return
	await get_tree().process_frame
	var base: float = e.status_manager.move_scale()
	_check("starts at normal pace", is_equal_approx(base, 1.0), "(%.2f)" % base)

	e.take_direct_damage(int(e.max_health * 0.6))
	var hot: float = e.status_manager.move_scale()
	_check("crossing 50%% HP speeds it up 1.8x",
		is_equal_approx(hot, base * e.def.overdrive_speed_mult), "(%.2f)" % hot)

	e.take_direct_damage(1)
	_check("it does not re-arm on the next hit",
		is_equal_approx(e.status_manager.move_scale(), hot),
		"(%.2f)" % e.status_manager.move_scale())

	print("=== overdrive ignores Calm but NOT a full freeze")
	e.apply_slow(0.5, 5.0)
	_check("a slow does nothing", is_equal_approx(e.status_manager.move_scale(), hot),
		"(%.2f)" % e.status_manager.move_scale())
	e.apply_slow(0.0, 5.0)
	_check("a freeze still stops it", is_zero_approx(e.status_manager.move_scale()),
		"(%.2f)" % e.status_manager.move_scale())
	e.status_manager.clear_slow()

	print("=== the haste aura and overdrive compound instead of overwriting")
	e.status_manager.apply_haste(e.def.haste_factor, 5.0)
	var both: float = e.status_manager.move_scale()
	_check("1.8 x 1.35 = 2.43",
		is_equal_approx(both, e.def.overdrive_speed_mult * e.def.haste_factor),
		"(%.2f)" % both)
	e.queue_free()

# ---------------------------------------------------------------- damage shape

func _test_damage_shape(game: Game) -> void:
	print("=== the golem is hurt by the tool, not by the number")
	var golem := game.spawn_distraction(&"clickbait", game._random_spawn_cell())
	var plain := game.spawn_distraction(&"doomscroll", game._random_spawn_cell())
	_check("both spawned", golem != null and plain != null)
	if golem == null or plain == null:
		return

	var fast := Data.get_habit(&"focus_timer")
	var aoe := Data.get_habit(&"mindfulness")
	_check("focus_timer counts as rapid fire",
		fast.fire_cooldown <= golem.def.fast_shot_threshold,
		"(%.2fs vs threshold %.2f)" % [fast.fire_cooldown, golem.def.fast_shot_threshold])
	_check("mindfulness is the AoE side", aoe.aoe)

	# _shape_damage keys off the habit's DATA, so a stub carrying the same def is enough
	# and no build spot has to be spent.
	var fast_src := Habit.new()
	fast_src.def = fast
	var aoe_src := Habit.new()
	aoe_src.def = aoe

	var raw := 40
	_check("rapid fire is halved",
		golem._shape_damage(raw, fast_src) == int(round(raw * golem.def.fast_shot_damage_mult)),
		"(%d of %d)" % [golem._shape_damage(raw, fast_src), raw])
	_check("AoE hits harder",
		golem._shape_damage(raw, aoe_src) == int(round(raw * golem.def.aoe_damage_mult)),
		"(%d of %d)" % [golem._shape_damage(raw, aoe_src), raw])
	_check("an unshaped distraction takes both at face value",
		plain._shape_damage(raw, fast_src) == raw and plain._shape_damage(raw, aoe_src) == raw)
	_check("a sourceless hit (intervention, burst, ally) is never shaped",
		golem._shape_damage(raw, null) == raw)

	var hp_before: int = golem.current_health
	golem._on_boredom_damage(10, null)
	var dot_dealt: int = hp_before - golem.current_health
	_check("boredom is amplified too",
		dot_dealt == int(round(10.0 * golem.def.dot_damage_mult)), "(%d)" % dot_dealt)

	fast_src.free()
	aoe_src.free()
	golem.queue_free()
	plain.queue_free()

# ---------------------------------------------------------------- rush

func _test_rush(game: Game) -> void:
	print("=== rush is paid for risk, not for kills")
	GameState.rush = 0
	var near := game.spawn_distraction(&"notification", game.world_to_cell(game.objective_pos))
	if near != null:
		near.position = game.objective_pos
		SignalBus.distraction_defeated.emit(near, 1)
	_check("a kill at the core pays", GameState.rush == GameState.RUSH_PER_CLOSE_KILL,
		"(%d)" % GameState.rush)

	GameState.rush = 0
	var far := game.spawn_distraction(&"notification", game._random_spawn_cell())
	if far != null:
		far.position = game.objective_pos + Vector2(GameState.RUSH_CLOSE_RADIUS + 200.0, 0.0)
		SignalBus.distraction_defeated.emit(far, 1)
	_check("a safe kill pays nothing", GameState.rush == 0, "(%d)" % GameState.rush)

	print("=== a lean wave withholds Dopamine but still pays for the risk")
	GameState.rush = 0
	GameState.lean_wave_active = true
	if near != null:
		SignalBus.distraction_defeated.emit(near, 1)
	GameState.lean_wave_active = false
	_check("lean wave still pays Rush", GameState.rush > 0, "(%d)" % GameState.rush)

	GameState.rush = 2
	_check("spending more than you hold fails", not GameState.spend_rush(3))
	_check("and changes nothing", GameState.rush == 2, "(%d)" % GameState.rush)
	_check("spending what you hold works", GameState.spend_rush(2))

	if near != null:
		near.queue_free()
	if far != null:
		far.queue_free()

# ---------------------------------------------------------------- airplane mode

func _test_airplane_mode(game: Game) -> void:
	print("=== airplane mode: field-wide, and refused casts stay ready")
	var idef := Data.get_intervention("airplane_mode")
	_check("the ability is registered", idef != null)
	if idef == null:
		return
	_check("it is in the HUD order", Data.INTERVENTION_ORDER.has(&"airplane_mode"))
	_check("it costs Rush", idef.rush_cost > 0, "(%d)" % idef.rush_cost)

	GameState.rush = 0
	game.intervention_cooldowns["airplane_mode"] = 0.0
	game._cast_intervention("airplane_mode", game.objective_pos)
	_check("a cast with no Rush does not fire",
		is_zero_approx(game.intervention_cooldowns["airplane_mode"]))

	# Both are placed away from the core. One spawned ON the objective reaches it on its
	# first frame, frees itself, and every later check on it is silently skipped — the
	# reference is not null, it is dangling, so `!= null` is no guard at all.
	var far_cell := Vector2i(2, 2)
	var near_cell: Vector2i = game.world_to_cell(game.objective_pos) - Vector2i(4, 0)
	var a := game.spawn_distraction(&"notification", far_cell)
	var b := game.spawn_distraction(&"notification", near_cell)
	_check("two test distractions on the field",
		is_instance_valid(a) and is_instance_valid(b))
	await get_tree().process_frame
	if is_instance_valid(a):
		a.position = game.cell_center(far_cell)
	GameState.rush = idef.rush_cost
	game._cast_intervention("airplane_mode", game.objective_pos)
	_check("it spends the Rush", GameState.rush == 0, "(%d)" % GameState.rush)
	_check("it goes on cooldown", game.intervention_cooldowns["airplane_mode"] > 0.0)

	# The mechanical effect is fired from the sky-strike tween's callback, 0.22 s after the
	# cast — checking on the next frame reads the field before anything has happened.
	var t0: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 900:
		await get_tree().process_frame
		if is_instance_valid(a) and is_zero_approx(a.status_manager.move_scale()):
			break
	_check("both test distractions survived to be measured",
		is_instance_valid(a) and is_instance_valid(b))
	if is_instance_valid(a) and is_instance_valid(b):
		var d: float = a.global_position.distance_to(game.objective_pos)
		# 200.0, not the original 400.0: T5's topdown switch halved Data.GRID.tile
		# (32 -> 16), so a threshold tied to screen distance halves with it. User-approved
		# 2026-08-29. Habit/tower attack ranges themselves are NOT rescaled by this — a
		# separate, larger, not-yet-done part of the T5 migration (see BLOCKED.md).
		_check("the far one is well outside any targeted radius", d > 200.0, "(%.0f px)" % d)
		_check("both are frozen, wherever they stand",
			is_zero_approx(a.status_manager.move_scale())
			and is_zero_approx(b.status_manager.move_scale()),
			"(far %.2f, near %.2f)" % [a.status_manager.move_scale(),
				b.status_manager.move_scale()])
		a.queue_free()
		b.queue_free()

# ---------------------------------------------------------------- helpers

func _first_empty_spot(game: Game) -> BuildSpot:
	for spot in game.build_spots.values():
		if is_instance_valid(spot) and spot.state == BuildSpot.State.EMPTY:
			return spot
	return null
