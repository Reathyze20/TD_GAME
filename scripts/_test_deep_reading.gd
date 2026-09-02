extends Node
## Harness for Deep Reading's switch from AoE cone pulse to directional page fire.
##
## The whole reason this file exists: boredom used to be applied ONLY inside tower.gd's
## `if def.aoe:` branch, so "has a DoT" and "is a cone pulse" were the same fact. Flipping
## `aoe = false` therefore had a silent failure mode — the tower keeps firing, keeps
## dealing its 2 mind damage, and simply stops applying the damage-over-time that is its
## entire identity. Nothing errors. You would only notice by watching health bars.
##
## Same shape as _test_phase7.gd: real Game, Focus pinned so a leak cannot trip
## _game_over() and free this node together with its watchdog.

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

	_test_data()
	await _test_projectile_carries_dot(game)
	await _drain_projectiles(game)
	await _test_dot_source_semantics(game)
	await _drain_projectiles(game)
	await _test_other_habits_unchanged(game)

	completed = true
	print("")
	if fails == 0:
		print("ALL PASS")
		get_tree().quit(0)
	else:
		print("%d FAILED" % fails)
		get_tree().quit(1)

# ---------------------------------------------------------------- data

func _test_data() -> void:
	print("=== the line is a long-range rapid-fire DoT, not a pulse")
	var t1 := Data.get_habit(&"real_hobby")
	var t2 := Data.get_habit(&"real_hobby_2")
	_check("both tiers load", t1 != null and t2 != null)
	if t1 == null or t2 == null:
		return
	_check("neither pulses any more", not t1.aoe and not t2.aoe)
	_check("both still carry the DoT", t1.boredom > 0.0 and t2.boredom > 0.0,
		"(%.1f/s, %.1f/s)" % [t1.boredom, t2.boredom])
	_check("both fire fast enough to read as automatic",
		t1.fire_cooldown <= 0.2 and t2.fire_cooldown <= 0.2,
		"(%.2fs, %.2fs)" % [t1.fire_cooldown, t2.fire_cooldown])
	# THRESHOLD WAS A HARDCODED `>= 500.0` AND IS NOW DERIVED (M9, 2026-09-02). 500 px is
	# longer than the whole board: the field is 480x224 since the T5 square migration, and
	# P8b (`612a043`) rescaled every fire radius down to match — real_hobby went to 260.
	# So the check has been failing since 2026-08-30 for a reason that has nothing to do
	# with Deep Reading, and docs/KNOWN_BROKEN.md never recorded it because that entry was
	# written before the rescale landed. Exactly the artifact class BLOCKED.md already
	# closed for _test_phase7 ("hardcoded 400px ... was a pre-migration scale artifact").
	#
	# Comparing against the roster's OWN maximum is what the label says anyway, and it
	# cannot rot when the board is rescaled again.
	var longest_other := 0.0
	for other_key: StringName in Data.HABIT_ORDER:
		if other_key == &"real_hobby":
			continue
		var od: HabitData = Data.get_habit(other_key)
		if od != null:
			longest_other = maxf(longest_other, od.range)
	_check("both still outrange everything else",
		t1.range > longest_other and t2.range >= t1.range,
		"(%d, %d)" % [int(t1.range), int(t2.range)])
	# A book GPU-rotated through 360 degrees spins like a plate. The pages aim; the book does not.
	_check("the book does not swivel", not t1.head_aims and not t2.head_aims)
	_check("its shots tumble like paper", t1.projectile_spin > 0.0 and t2.projectile_spin > 0.0,
		"(%.1f, %.1f rad/s)" % [t1.projectile_spin, t2.projectile_spin])
	_check("tier 2 is the harder-hitting one",
		t2.boredom > t1.boredom and t2.awareness_damage >= t1.awareness_damage
			and t2.fire_cooldown <= t1.fire_cooldown)

# ------------------------------------------------- the regression this file exists for

## Fires a real projectile through the real spawn path into a real distraction.
func _shoot(game: Game, target, dot: float, dot_dur: float, src: Object,
		spin: float = 11.0) -> void:
	var from: Vector2 = target.global_position - Vector2(30.0, 0.0)
	game.spawn_directional_projectile(from, 0.0, 400.0, 0, 2,
		Color("ffe6b8"), src, dot, dot_dur, spin)
	for _i in range(6):        # 560 px/s ~= 9.3 px per frame; 30px needs a few
		await get_tree().process_frame

## Waits until nothing is in flight. A shot outlives the 6-frame wait above by ~40
## frames (400px at 560px/s), and spawn cells are random — so a DoT page from one
## sub-test could cross a later sub-test's fresh target and poison its "clean before
## the shot" premise. Flaky by construction; this drain is what makes each sub-test
## actually start from the empty air it assumes.
func _drain_projectiles(game: Game) -> void:
	for _i in range(120):
		if game.projectile_pool._active == 0:
			return
		await get_tree().process_frame

func _test_projectile_carries_dot(game: Game) -> void:
	print("=== a page sticks: the DoT survived the move off the cone")
	var d := game.spawn_distraction(&"doomscroll", game._random_spawn_cell())
	if d == null:
		_check("doomscroll spawned", false)
		return
	await get_tree().process_frame
	d.current_health = 99999

	var src := Habit.new()
	src.def = Data.get_habit(&"real_hobby")

	_check("clean before the shot", not d.status_manager.has_boredom())
	await _shoot(game, d, src.def.boredom, src.def.boredom_duration, src)
	_check("the shot landed its damage", d.current_health < 99999,
		"(%d)" % (99999 - d.current_health))
	_check("and left the DoT behind",
		is_equal_approx(d.status_manager.boredom_dps, src.def.boredom),
		"(%.1f/s, expected %.1f/s)" % [d.status_manager.boredom_dps, src.def.boredom])

	# It has to actually tick health down, not merely be present on the status manager.
	var hp: int = d.current_health
	d.status_manager.tick(1.05)
	_check("the DoT burns", d.current_health < hp, "(-%d hp)" % (hp - d.current_health))

	# And it has to let go: a dot refreshed by every shot must still expire once the
	# stream stops, or one burst disables an enemy permanently.
	d.status_manager.tick(src.def.boredom_duration + 0.5)
	_check("and expires when the stream stops", not d.status_manager.has_boredom(),
		"(%.1f/s)" % d.status_manager.boredom_dps)

	src.free()
	d.queue_free()

func _test_dot_source_semantics(game: Game) -> void:
	print("=== per-source stacking survived the move too")
	var d := game.spawn_distraction(&"doomscroll", game._random_spawn_cell())
	if d == null:
		_check("doomscroll spawned", false)
		return
	await get_tree().process_frame
	d.current_health = 99999

	var a := Habit.new()
	a.def = Data.get_habit(&"real_hobby")
	var b := Habit.new()
	b.def = Data.get_habit(&"real_hobby")

	await _shoot(game, d, a.def.boredom, a.def.boredom_duration, a)
	var one: float = d.status_manager.boredom_dps
	# A second shot from the SAME habit must not stack — otherwise an automatic weapon
	# ramps its own DoT to infinity, which is exactly what per-source semantics prevent.
	await _shoot(game, d, a.def.boredom, a.def.boredom_duration, a)
	_check("one habit's own stream does not stack with itself",
		is_equal_approx(d.status_manager.boredom_dps, one), "(%.1f/s)" % d.status_manager.boredom_dps)
	# A second TOWER must stack, or building another one adds nothing.
	await _shoot(game, d, b.def.boredom, b.def.boredom_duration, b)
	_check("a second habit does stack",
		d.status_manager.boredom_dps > one + 0.01,
		"(%.1f/s vs %.1f/s)" % [d.status_manager.boredom_dps, one])

	a.free()
	b.free()
	d.queue_free()

func _test_other_habits_unchanged(game: Game) -> void:
	print("=== the shared projectile is pooled — no leaking into other habits")
	# `head_aims` USED TO BE IN THIS CONJUNCTION AND WAS REMOVED (M9, 2026-09-02), with the
	# user's say-so, because it was wrong on both counts.
	#
	# It could never have caught a leak. This check guards against Deep Reading's traits
	# bleeding into other habits through the POOLED projectile, and a trait can only leak
	# from a habit that has it — `real_hobby`/`real_hobby_2` carry `head_aims = false` like
	# everyone else, so there was nothing to leak from. `projectile_spin` and `boredom` are
	# the two that Deep Reading actually sets, and they are the two that stay.
	#
	# And it asserted the opposite of a deliberate, documented decision: `head_aims` is
	# false on ALL FIFTEEN habits in data/, and tower.gd's own comment (~line 610) says why
	# in as many words — "presne to je duvod, proc `head_aims` zustava u cele rodiny false:
	# rotace bitmapy je spatna operace". The eight-direction head art replaced rotation, so
	# nothing aims a head any more. The fixture was pinning a default that the roster left
	# behind, and docs/KNOWN_BROKEN.md had it filed as "a deliberate data change nobody
	# reflected in the test that pins it" — which was exactly right.
	for key in [&"focus_timer", &"focus_timer_2", &"exercise", &"exercise_2"]:
		var h := Data.get_habit(key)
		_check("%s fires plain bolts — no borrowed spin or Boredom" % key,
			is_equal_approx(h.projectile_spin, 0.0) and is_equal_approx(h.boredom, 0.0))

	# A pooled projectile is reused: if a page's DoT/spin were not reset on setup, the
	# next habit to borrow that instance would inherit them.
	var d := game.spawn_distraction(&"doomscroll", game._random_spawn_cell())
	if d == null:
		_check("doomscroll spawned", false)
		return
	await get_tree().process_frame
	d.current_health = 99999

	var timer := Habit.new()
	timer.def = Data.get_habit(&"focus_timer")
	await _shoot(game, d, 0.0, 0.0, timer, 0.0)     # dot 0, spin 0: a plain bolt
	_check("a plain bolt leaves no DoT", not d.status_manager.has_boredom(),
		"(%.1f/s)" % d.status_manager.boredom_dps)

	timer.free()
	d.queue_free()
