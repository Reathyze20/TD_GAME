extends Node
## Harness for the Zen Pulsar: hard stun, momentum dispel, vulnerability, and the
## charge telegraph.
##
## Same shape as _test_phase7.gd — instantiate the real Game, pin Focus so a leak cannot
## trip _game_over() (which changes scene and frees this node together with its watchdog),
## then drive the systems imperatively.
##
## Every check here is a rule that looks fine on screen until it is wrong: an ordering
## that lets a debuff pay its own caster, a dispel that quietly also strips a latched
## phase change, a telegraph that wraps instead of holding. None of that is visible in
## a playtest — you would just feel the tower being slightly too good.

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
	_test_art_fallback()
	await _test_stun(game)
	await _test_dispel(game)
	await _test_vulnerable(game)
	await _test_pulse_order(game)
	_test_charge_telegraph()

	completed = true
	print("")
	if fails == 0:
		print("ALL PASS")
		get_tree().quit(0)
	else:
		print("%d FAILED" % fails)
		get_tree().quit(1)

# ---------------------------------------------------------------- data wiring

func _test_data() -> void:
	print("=== the line loads and both branches hang off it")
	var base := Data.get_habit(&"zen_pulsar")
	var a := Data.get_habit(&"zen_pulsar_2a")
	var b := Data.get_habit(&"zen_pulsar_2b")
	_check("all three habits load", base != null and a != null and b != null)
	if base == null or a == null or b == null:
		return
	_check("base offers BOTH upgrades, not one",
		base.upgrades.size() == 2 and base.upgrades.has(&"zen_pulsar_2a")
			and base.upgrades.has(&"zen_pulsar_2b"),
		"(%s)" % str(base.upgrades))
	# habit_family is what card targeting and the art fallback both key off; a branching
	# line is the first thing in the game that could break it.
	_check("both branches resolve to the tier-1 root",
		Data.habit_family(&"zen_pulsar_2a") == &"zen_pulsar"
			and Data.habit_family(&"zen_pulsar_2b") == &"zen_pulsar")
	_check("it is in the build panel", Data.HABIT_ORDER.has(&"zen_pulsar"))

	# HABIT_ORDER and the input map have to grow together — is_action_just_pressed on a
	# missing action errors every frame, which is noisy but easy to miss in a log.
	var missing: Array[String] = []
	for i in range(Data.HABIT_ORDER.size()):
		if not InputMap.has_action("td_habit_%d" % (i + 1)):
			missing.append("td_habit_%d" % (i + 1))
	_check("every panel slot has a hotkey action", missing.is_empty(), str(missing))

	print("=== the two branches actually differ")
	_check("A widens the reach", a.range > base.range,
		"(%d vs %d)" % [int(a.range), int(base.range)])
	_check("A is the only one that opens targets up",
		a.vulnerable_mult > 1.0 and base.vulnerable_mult == 1.0 and b.vulnerable_mult == 1.0)
	_check("B beats faster but holds shorter",
		b.fire_cooldown < base.fire_cooldown and b.stun_duration < base.stun_duration,
		"(%.1fs / %.1fs vs %.1fs / %.1fs)"
			% [b.fire_cooldown, b.stun_duration, base.fire_cooldown, base.stun_duration])

# ---------------------------------------------------------------- art fallback

func _test_art_fallback() -> void:
	print("=== upgraded tiers inherit the sprite instead of vanishing")
	_check("the base has head art",
		FileAccess.file_exists("res://assets/towers/head_zen_pulsar_frame_1.png"))
	# The old fallback was trim_suffix("_2"), which leaves "zen_pulsar_2a" untouched and
	# would have loaded nothing at all for a branching line.
	for key in [&"zen_pulsar_2a", &"zen_pulsar_2b"]:
		var h := Habit.new()
		h.type_key = String(key)
		h.def = Data.get_habit(key)
		_check("%s falls back to the base sprite" % key,
			h._head_art_key() == "zen_pulsar", "(got %s)" % h._head_art_key())
		h.free()

# ---------------------------------------------------------------- hard stun

func _test_stun(game: Game) -> void:
	print("=== the freeze stops things a slow cannot")
	var e = game.spawn_distraction(&"energy_drink", game._random_spawn_cell())
	_check("energy drink spawned", e != null)
	if e == null:
		return
	await get_tree().process_frame

	e.apply_stun(1.2)
	_check("a stunned distraction does not move",
		is_equal_approx(e.status_manager.move_scale(), 0.0),
		"(%.2f)" % e.status_manager.move_scale())

	# Overdrive grants slow_immune. The freeze has to land anyway — StatusManager's own
	# rule is that "ignores slows" and "cannot be stopped" are different promises, and a
	# control tower that reads as broken against the one enemy you most want stopped
	# would be worse than not shipping it.
	e.status_manager.reset()
	e.take_direct_damage(int(e.max_health * 0.6))
	_check("it is overdriven and slow-immune", e.is_overdriven() and e.status_manager.slow_immune)
	var hot: float = e.status_manager.move_scale()
	e.apply_slow(0.5, 5.0)
	_check("a partial slow bounces off",
		is_equal_approx(e.status_manager.move_scale(), hot), "(%.2f)" % e.status_manager.move_scale())
	e.apply_stun(1.2)
	_check("the freeze still lands",
		is_equal_approx(e.status_manager.move_scale(), 0.0),
		"(%.2f)" % e.status_manager.move_scale())

	# And it must let go on its own — a stun that never expires is a soft lock.
	e.status_manager.tick(1.3)
	_check("it wears off", e.status_manager.move_scale() > 0.0,
		"(%.2f)" % e.status_manager.move_scale())
	e.queue_free()

# ---------------------------------------------------------------- momentum dispel

func _test_dispel(game: Game) -> void:
	print("=== the dispel takes the aura, not the phase change")
	var e = game.spawn_distraction(&"energy_drink", game._random_spawn_cell())
	if e == null:
		_check("energy drink spawned", false)
		return
	await get_tree().process_frame

	e.status_manager.apply_haste(1.35, 3.0)
	_check("the rush aura is up", e.status_manager.has_haste(),
		"(%.2f)" % e.status_manager.haste_factor)
	e.dispel_haste()
	_check("dispel clears it outright", not e.status_manager.has_haste(),
		"(%.2f)" % e.status_manager.haste_factor)

	# Overdrive rides extra_factor precisely so a strongest-wins haste cannot swallow it.
	# The dispel must respect that same separation, or one habit undoes a wounded Energy
	# Drink's entire second act.
	e.take_direct_damage(int(e.max_health * 0.6))
	var over: float = e.status_manager.extra_factor
	_check("overdrive raised extra_factor", over > 1.0, "(%.2f)" % over)
	e.status_manager.apply_haste(1.35, 3.0)
	e.dispel_haste()
	_check("dispel leaves overdrive alone",
		is_equal_approx(e.status_manager.extra_factor, over)
			and is_equal_approx(e.status_manager.move_scale(), over),
		"(extra %.2f, scale %.2f)" % [e.status_manager.extra_factor, e.status_manager.move_scale()])
	e.queue_free()

# ---------------------------------------------------------------- vulnerability

func _test_vulnerable(game: Game) -> void:
	print("=== vulnerability amplifies what other habits do")
	var d = game.spawn_distraction(&"doomscroll", game._random_spawn_cell())
	if d == null:
		_check("doomscroll spawned", false)
		return
	await get_tree().process_frame

	# doomscroll is the unshaped control in _test_phase7 — no aoe/fast-shot multipliers —
	# so anything the number does here is the vulnerability and nothing else.
	var src := Habit.new()
	src.def = Data.get_habit(&"exercise")
	var raw := 40
	_check("baseline is unshaped", d._shape_damage(raw, src) == raw,
		"(%d)" % d._shape_damage(raw, src))

	d.apply_vulnerable(1.25, 3.0)
	_check("it takes 25%% more", d._shape_damage(raw, src) == int(round(raw * 1.25)),
		"(%d of %d)" % [d._shape_damage(raw, src), raw])

	# Same strongest-wins/never-truncated rule as Calm, Rush and Reframe.
	d.apply_vulnerable(1.10, 9.0)
	_check("a weaker application cannot dilute it",
		is_equal_approx(d.status_manager.vulnerable_mult, 1.25),
		"(%.2f)" % d.status_manager.vulnerable_mult)

	d.status_manager.tick(3.1)
	_check("it expires", d._shape_damage(raw, src) == raw, "(%d)" % d._shape_damage(raw, src))

	# Sourceless damage (interventions, burst cards) is never shaped, so it must stay
	# unamplified even while the target is open.
	d.apply_vulnerable(1.25, 3.0)
	_check("a sourceless hit is not amplified", d._shape_damage(raw, null) == raw,
		"(%d)" % d._shape_damage(raw, null))

	src.free()
	d.queue_free()

# ------------------------------------------------- pulse ordering (the real prize)

func _test_pulse_order(game: Game) -> void:
	print("=== Resonance Wave does not cash in on its own debuff")
	var d = game.spawn_distraction(&"doomscroll", game._random_spawn_cell())
	if d == null:
		_check("doomscroll spawned", false)
		return
	await get_tree().process_frame
	d.current_health = 99999

	var wave := Habit.new()
	wave.def = Data.get_habit(&"zen_pulsar_2a")
	wave.current_willpower_damage = wave.def.willpower_damage
	wave.current_awareness_damage = wave.def.awareness_damage

	var before: int = d.current_health
	wave.apply_pulse_to(d)
	var first_hit: int = before - d.current_health
	_check("the target is left open", d.status_manager.has_vulnerable(),
		"(x%.2f)" % d.status_manager.vulnerable_mult)

	# The second pulse lands on an already-open target, so it SHOULD be bigger. If the
	# first one had amplified itself the two would match and the tower would be quietly
	# 25% stronger than its own tooltip claims.
	before = d.current_health
	wave.apply_pulse_to(d)
	var second_hit: int = before - d.current_health
	_check("its own first hit was unamplified", second_hit > first_hit,
		"(%d then %d)" % [first_hit, second_hit])
	_check("the second hit is the 25%% one",
		second_hit == int(round(float(first_hit) * 1.25)),
		"(%d vs expected %d)" % [second_hit, int(round(float(first_hit) * 1.25))])

	print("=== the base pulse freezes and dispels in one go")
	var e = game.spawn_distraction(&"energy_drink", game._random_spawn_cell())
	if e != null:
		await get_tree().process_frame
		e.current_health = 99999
		e.status_manager.apply_haste(1.35, 5.0)
		var pulsar := Habit.new()
		pulsar.def = Data.get_habit(&"zen_pulsar")
		pulsar.current_willpower_damage = pulsar.def.willpower_damage
		pulsar.current_awareness_damage = pulsar.def.awareness_damage
		pulsar.apply_pulse_to(e)
		_check("it is frozen", is_equal_approx(e.status_manager.move_scale(), 0.0),
			"(%.2f)" % e.status_manager.move_scale())
		_check("and its speed boost is gone", not e.status_manager.has_haste())
		_check("the base line opens nothing", not e.status_manager.has_vulnerable())
		pulsar.free()
		e.queue_free()

	wave.free()
	d.queue_free()

# ---------------------------------------------------------------- charge telegraph

func _test_charge_telegraph() -> void:
	print("=== the sprite is the countdown")
	var h := Habit.new()
	h.def = Data.get_habit(&"zen_pulsar")
	h.current_fire_cooldown = h.def.fire_cooldown
	var n := 8
	for i in range(n):
		h._head_frames.append(PlaceholderTexture2D.new())

	h.cooldown = h.current_fire_cooldown       # just fired
	h._advance_charge_anim()
	_check("frame 1 the instant it fires", h._frame_index() == 0, "(%d)" % h._frame_index())

	h.cooldown = h.current_fire_cooldown * 0.5
	h._advance_charge_anim()
	var mid := h._frame_index()
	_check("mid-reload sits mid-animation", mid > 0 and mid < n - 1, "(%d of %d)" % [mid, n])

	h.cooldown = 0.0
	h._advance_charge_anim()
	_check("fully charged on the last frame", h._frame_index() == n - 1, "(%d)" % h._frame_index())

	# A charged habit waiting for a target runs `cooldown` NEGATIVE (it is only reset on
	# an actual shot). Unclamped that wraps the index back to the discharge frame and the
	# tower would look like it keeps firing at nothing.
	h.cooldown = -12.0
	h._advance_charge_anim()
	_check("it HOLDS the charged frame while waiting for a target",
		h._frame_index() == n - 1, "(%d)" % h._frame_index())
	h.free()
