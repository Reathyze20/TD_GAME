extends Node
## Harness for the suppression-stream rewrite: the cone angle as the combat dial, and
## the emitter that no longer picks targets.
##
## Same shape as _test_zen_pulsar.gd — instantiate the real Game, pin Focus so a leak
## cannot trip _game_over() (which changes scene and frees this node together with its
## watchdog), then drive the systems imperatively.
##
## Every check here is a rule that is invisible in a playtest. A tower that quietly kept
## firing at an empty board just looks busy; a damage curve that went super-linear just
## feels like the narrow setting is "good"; a knockback with no budget looks like the
## enemy is being juggled on purpose. The numbers are the design, so the numbers get a test.

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
	_test_profile_at_home()
	_test_profile_narrow()
	_test_profile_wide()
	_test_ratio_clamp()
	_test_lanes()
	_test_scale_damage()

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

	await _test_fires_without_a_target(game)
	await _test_knockback(game)

	completed = true
	print("")
	if fails == 0:
		print("ALL PASS")
		get_tree().quit(0)
	else:
		print("%d FAILED" % fails)
		get_tree().quit(1)

# ---------------------------------------------------------------- the curve

func _test_profile_at_home() -> void:
	print("=== at its own authored angle a habit is exactly its .tres")
	var def := Data.get_habit(&"focus_timer")
	var p := ArcProfile.new()
	p.recompute(def, def.arc_angle)
	_check("damage untouched", is_equal_approx(p.damage_mult, 1.0), "(%f)" % p.damage_mult)
	_check("rate untouched", is_equal_approx(p.rate_mult, 1.0), "(%f)" % p.rate_mult)
	_check("pierce is the authored base", p.pierce == def.base_pierce,
		"(%d vs %d)" % [p.pierce, def.base_pierce])
	_check("no impulse either way",
		p.knockback == 0.0 and is_equal_approx(p.stagger_factor, 1.0))
	_check("cooldown passes through",
		is_equal_approx(p.shot_interval(def.fire_cooldown), def.fire_cooldown))

func _test_profile_narrow() -> void:
	print("=== narrowing concentrates: harder, deeper, slower, and it shoves")
	var def := Data.get_habit(&"exercise")   # impulse 2.0, the knockback weapon
	var p := ArcProfile.new()
	p.recompute(def, ArcProfile.ARC_MIN)
	_check("damage rises", p.damage_mult > 1.0, "(x%.2f)" % p.damage_mult)
	# The whole point of the sub-linear exponent: a third of the cone must not buy three
	# times the damage, or narrow stops being a trade and becomes the answer.
	_check("but sub-linearly", p.damage_mult < p.ratio,
		"(x%.2f damage for x%.2f concentration)" % [p.damage_mult, p.ratio])
	_check("pierce rises", p.pierce > def.base_pierce, "(%d)" % p.pierce)
	_check("pierce stays bounded", p.pierce <= ArcProfile.MAX_PIERCE, "(%d)" % p.pierce)
	_check("fires slower, not faster", p.rate_mult < 1.0, "(x%.2f)" % p.rate_mult)
	_check("hit window tightens", p.hit_padding < ArcProfile.BASE_HIT_PADDING,
		"(%.1f)" % p.hit_padding)
	_check("knockback on, stagger off",
		p.knockback > 0.0 and is_equal_approx(p.stagger_factor, 1.0),
		"(%.1fpx)" % p.knockback)

func _test_profile_wide() -> void:
	print("=== widening spreads: softer, single-hit, faster, and it staggers")
	var def := Data.get_habit(&"exercise")
	var p := ArcProfile.new()
	p.recompute(def, ArcProfile.ARC_MAX)
	_check("damage falls", p.damage_mult < 1.0, "(x%.2f)" % p.damage_mult)
	_check("shots die on first contact", p.pierce == 1, "(%d)" % p.pierce)
	_check("fires faster", p.rate_mult > 1.0, "(x%.2f)" % p.rate_mult)
	_check("hit window widens to compensate",
		p.hit_padding > ArcProfile.BASE_HIT_PADDING, "(%.1f)" % p.hit_padding)
	_check("stagger on, knockback off",
		p.stagger_factor < 1.0 and p.knockback == 0.0, "(x%.2f speed)" % p.stagger_factor)
	# Stagger must never out-compete an authored Calm: apply_slow is strongest-wins, and a
	# free 0.5 riding on every wide tower would make Mindfulness's actual slow redundant.
	_check("stagger stays shallower than any real slow",
		p.stagger_factor >= ArcProfile.STAGGER_FLOOR, "(x%.2f)" % p.stagger_factor)

func _test_ratio_clamp() -> void:
	print("=== one curve, same behaviour on a 45° habit and a 120° one")
	# Unclamped, a 120°-home habit narrowed to 15° would reach ratio 8 and turn into a
	# railgun, while a 45°-home habit could only ever reach 3. The clamp is what keeps
	# "narrow it down" worth the same thing across the roster.
	var narrow_home := Data.get_habit(&"exercise")      # 45
	var wide_home := Data.get_habit(&"zen_pulsar")      # 120
	var a := ArcProfile.new()
	var b := ArcProfile.new()
	a.recompute(narrow_home, ArcProfile.ARC_MIN)
	b.recompute(wide_home, ArcProfile.ARC_MIN)
	_check("both cap at the same concentration",
		is_equal_approx(a.ratio, ArcProfile.RATIO_MAX)
			and is_equal_approx(b.ratio, ArcProfile.RATIO_MAX),
		"(%.2f / %.2f)" % [a.ratio, b.ratio])
	a.recompute(narrow_home, ArcProfile.ARC_MAX)
	_check("and at the same spread the other way",
		is_equal_approx(a.ratio, ArcProfile.RATIO_MIN), "(%.2f)" % a.ratio)
	_check("spread is the exact reciprocal", is_equal_approx(a.spread, 1.0 / a.ratio))

func _test_lanes() -> void:
	print("=== the fan fills the wedge and never leaks out of it")
	var def := Data.get_habit(&"focus_timer")
	var p := ArcProfile.new()
	var arc := 120.0
	p.recompute(def, arc)
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var half := deg_to_rad(arc / 2.0)
	var worst := 0.0
	var seen := {}
	for i in range(240):
		var a: float = p.lane_angle(i, 0.0, arc, rng)
		worst = maxf(worst, absf(a))
		seen[roundi(rad_to_deg(a) / 5.0)] = true
	_check("every shot stays inside the drawn wedge", worst <= half,
		"(worst %.1f° vs %.1f° half-width)" % [rad_to_deg(worst), rad_to_deg(half)])
	# A random angle inside the wedge clumps: you get holes in the wall and three shots
	# stacked on one line. Lanes are what make a wide cone read as a barrier.
	_check("and the fan actually spreads out", seen.size() >= 15,
		"(%d distinct 5° bands)" % seen.size())

	p.recompute(def, ArcProfile.ARC_MIN)
	var spread_narrow := 0.0
	for i in range(60):
		spread_narrow = maxf(spread_narrow, absf(p.lane_angle(i, 0.0, ArcProfile.ARC_MIN, rng)))
	_check("a narrow cone stays a line", spread_narrow <= deg_to_rad(ArcProfile.ARC_MIN / 2.0),
		"(±%.1f°)" % rad_to_deg(spread_narrow))

func _test_scale_damage() -> void:
	print("=== a damage channel can be weakened, never silently switched off")
	var def := Data.get_habit(&"mindfulness")   # 0 willpower, 5 awareness by design
	var p := ArcProfile.new()
	p.recompute(def, ArcProfile.ARC_MAX)
	_check("an authored zero stays zero", p.scale_damage(0) == 0)
	_check("a live channel floors at 1, not 0", p.scale_damage(1) >= 1,
		"(%d)" % p.scale_damage(1))

# ---------------------------------------------------------------- the emitter

func _first_build_spot(game: Game) -> BuildSpot:
	for cell in game.build_spots:
		var bs: BuildSpot = game.build_spots[cell]
		if bs.state == BuildSpot.State.EMPTY:
			return bs
	return null

func _test_fires_without_a_target(game: Game) -> void:
	print("=== it fires into the sector, not at anything")
	var bs := _first_build_spot(game)
	if bs == null:
		_check("a build spot exists", false)
		return
	var h: Habit = bs.build_habit("focus_timer", 0.0, 60.0)

	# in_routine is re-derived by game._update_routine_reach() on EVERY frame, so it has
	# to be forced immediately before each _process call — setting it once and then
	# awaiting a frame silently hands the check back a habit that is idle for an
	# unrelated reason, and every assertion below would pass without meaning anything.
	h.in_routine = true

	# Empty board: a tower spraying at nobody costs pool slots and collision passes every
	# frame and tells the player something false about what it is doing.
	var before: int = game.projectile_pool._active
	h.cooldown = 0.0
	h._process(0.1)
	_check("empty board: holds fire", game.projectile_pool._active == before,
		"(%d active)" % game.projectile_pool._active)

	# One distraction, deliberately placed BEHIND the tower — outside the cone entirely.
	# The old build would have found no target and never fired; this one has no opinion
	# about where the enemy is.
	var d := game.spawn_distraction(&"notification", bs.grid_cell + Vector2i.LEFT)
	d.global_position = h.global_position + Vector2.LEFT * 120.0
	await get_tree().process_frame
	_check("nothing is standing in the cone", not h.has_enemy_in_cone())
	before = game.projectile_pool._active
	h.in_routine = true
	h.cooldown = 0.0
	h._process(0.1)
	_check("live board, nothing in the cone: still fires",
		game.projectile_pool._active > before,
		"(%d active)" % game.projectile_pool._active)

	# And the Pomodoro is not paying for that: a habit shooting into an empty sector is
	# warming up, not working.
	var timer_bs := _first_build_spot(game)
	var ft: Habit = timer_bs.build_habit("focus_timer", 0.0, 60.0)
	ft.in_routine = true
	var work_before: float = ft.work_left
	ft._process(0.5)
	_check("work interval only drains on something in the cone",
		is_equal_approx(ft.work_left, work_before), "(%.2f)" % ft.work_left)

	d.take_direct_damage(999999)

func _test_knockback(game: Game) -> void:
	print("=== knockback shoves, then runs out")
	var bs := _first_build_spot(game)
	var h: Habit = bs.build_habit("exercise", 0.0, ArcProfile.ARC_MIN)
	h.in_routine = true
	var p := h.arc_profile()
	_check("a narrowed Exercise has push to give", p.knockback > 0.0,
		"(%.1fpx)" % p.knockback)

	var d := game.spawn_distraction(&"notification", bs.grid_cell + Vector2i.RIGHT)
	# Somewhere open, so the wall check is not what is being measured here.
	d.position = game.cell_center(game.objective_cell) + Vector2(0, -40)
	await get_tree().process_frame
	var start: Vector2 = d.position
	d.apply_knockback(Vector2.RIGHT, p.knockback)
	_check("one hit moves it", d.position.x > start.x,
		"(+%.1fpx)" % (d.position.x - start.x))

	# The budget is the whole reason this is not a stunlock: a weapon landing ten hits a
	# second would otherwise out-push any walking speed in the game and pin its target.
	var mid: Vector2 = d.position
	for i in range(40):
		d.apply_knockback(Vector2.RIGHT, p.knockback)
	var total: float = d.position.x - mid.x
	_check("forty more hits cannot keep pushing", total <= Distraction.KNOCK_BUDGET + 0.01,
		"(+%.1fpx against a %.0fpx budget)" % [total, Distraction.KNOCK_BUDGET])

	# A push must never park a body inside terrain, where it is unreachable and unkillable.
	var wall_cell: Vector2i = Vector2i(-999, -999)
	for c in game.high_ground:
		wall_cell = c
		break
	if wall_cell != Vector2i(-999, -999):
		d._knock_left = Distraction.KNOCK_BUDGET
		d.position = game.cell_center(wall_cell) + Vector2(float(Data.GRID.tile), 0.0)
		var at_wall: Vector2 = d.position
		d.apply_knockback(Vector2.LEFT, 40.0)
		_check("and never into a wall", d.position == at_wall,
			"(%s)" % str(d.position - at_wall))

	d.take_direct_damage(999999)
