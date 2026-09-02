extends Node
## Headless harness for P11 (PATHFINDING.MD): Quick Hit and Tolerance wired to the fog.
##
## The two links, and why they are the point of the whole mechanic:
##   Quick Hit  -> a short burst of full clarity (a surge of attention)
##   Tolerance  -> a permanently smaller sight radius (narrowed attention)
##
## M4 measured what Tolerance was worth before this existed: its only mechanical effect was
## a payout multiplier, and on a board with two build spots that priced a currency the
## player had no way to spend — so spamming Quick Hit came out PURELY beneficial (more
## Focus, more kills, +120 Dopamine on every seed). Sight is a different kind of price: a
## habit refuses a target it cannot see (tower.gd is_point_in_cone), so narrowing it takes
## away shots. These checks are what stop that price from quietly going missing again.
##
## Run:
##   godot --headless --path <proj> --main-scene res://scenes/_test_fog_modifiers.tscn

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


## Lit blocks at a given Tolerance, with the fog recomputed for it.
func _lit_at(game: Game, tolerance: float) -> int:
	GameState.set_tolerance(tolerance)
	game._update_fog(0.0)
	return game._lit_cells.size()


func _run() -> void:
	var game: Game = load("res://scenes/Game.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	GameState.max_focus = 999999
	GameState.focus = 999999
	# The fixture owns its subject — a content file must not be able to switch off the
	# thing under test (the lesson P8b paid for).
	game.fog_enabled = true
	game.routine_gates_enabled = true
	ModifierManager.active_cards.clear()
	GameState.clear_tolerance()
	await get_tree().process_frame

	print("=== Tolerance narrows sight — the two ends of the meter")
	var mult_0: float = game.sight_radius_mult()
	GameState.set_tolerance(100.0)
	var mult_100: float = game.sight_radius_mult()
	GameState.clear_tolerance()
	_check("at Tolerance 0 the board keeps its full sight",
		is_equal_approx(mult_0, 1.0), "(mult %.3f)" % mult_0)
	_check("at Tolerance 100 sight is narrowed",
		mult_100 < mult_0, "(%.3f -> %.3f)" % [mult_0, mult_100])
	_check("at Tolerance 100 sight is narrowed by exactly SIGHT_TOLERANCE_PENALTY",
		is_equal_approx(mult_100, 1.0 - Game.SIGHT_TOLERANCE_PENALTY),
		"(%.3f vs %.3f)" % [mult_100, 1.0 - Game.SIGHT_TOLERANCE_PENALTY])

	print("=== and the narrowing reaches the actual lit grid, not just the number")
	var lit_0 := _lit_at(game, 0.0)
	var lit_100 := _lit_at(game, 100.0)
	_check("Tolerance 100 lights strictly less board than Tolerance 0",
		lit_100 < lit_0, "(%d -> %d blocks)" % [lit_0, lit_100])

	print("=== monotone across the meter, not just at its ends")
	var last := 999999
	var rises := 0
	var trace: Array[String] = []
	for step in [0.0, 25.0, 50.0, 75.0, 100.0]:
		var n := _lit_at(game, step)
		trace.append("%d:%d" % [int(step), n])
		if n > last:
			rises += 1
		last = n
	_check("more Tolerance never lights MORE board", rises == 0,
		"(" + " ".join(trace) + ")")
	GameState.clear_tolerance()
	game._update_fog(0.0)

	print("=== Quick Hit buys a burst of clarity")
	var g = Data.GRID
	var far_corner: Vector2 = Data.cell_center(Vector2i(0, int(g.rows) - 1))
	game.fog_reveal_left = 0.0
	game._update_fog(0.0)
	_check("the far corner starts dark", not game.is_pos_visible(far_corner))

	GameState.quick_hit_enabled = true
	game._quick_hit_cd = 0.0
	var mult_before_press: float = game.sight_radius_mult()
	game.do_quick_hit()
	_check("the press lifted the fog", game.fog_reveal_left >= Game.QUICK_HIT_CLARITY,
		"(%.2f s)" % game.fog_reveal_left)
	_check("the far corner is visible during the surge", game.is_pos_visible(far_corner))

	print("=== and the same press pays for it, permanently")
	# The spike decays; the FLOOR does not. That asymmetry is the mechanic: sight comes
	# back a little, but never all the way back to where it was before the press.
	_check("the press raised the Tolerance floor",
		GameState.tolerance_floor >= Game.QUICK_HIT_FLOOR_GAIN,
		"(floor %.1f)" % GameState.tolerance_floor)
	var mult_after_press: float = game.sight_radius_mult()
	_check("sight is narrower right after the press than before it",
		mult_after_press < mult_before_press,
		"(%.3f -> %.3f)" % [mult_before_press, mult_after_press])

	# Drain the spike the way _update_tolerance would, and confirm the floor holds sight
	# below its pre-press value even once the visible spike is gone.
	GameState.set_tolerance(0.0)
	var mult_settled: float = game.sight_radius_mult()
	_check("once the spike decays, the floor still holds sight below its old value",
		mult_settled < mult_before_press,
		"(%.3f < %.3f, floor %.1f)" % [mult_settled, mult_before_press, GameState.tolerance_floor])

	print("=== the link goes through ModifierManager, so cards can steer it")
	GameState.clear_tolerance()
	var clean: float = game.sight_radius_mult()
	var eff := CardEffectData.new()
	eff.stat_type = ModifierManager.STAT_SIGHT_RADIUS
	eff.target = "ALL"
	eff.value = -0.5
	eff.is_percentage = true
	var card := CardData.new()
	card.id = &"_test_sight_card"
	card.effects = [eff]
	ModifierManager.active_cards.append(card)
	var carded: float = game.sight_radius_mult()
	_check("a card carrying STAT_SIGHT_RADIUS changes the multiplier",
		carded < clean, "(%.3f -> %.3f)" % [clean, carded])
	var lit_carded := _lit_at(game, 0.0)
	_check("and that reaches the lit grid too", lit_carded < lit_0,
		"(%d -> %d blocks)" % [lit_0, lit_carded])
	ModifierManager.active_cards.clear()

	print("=== the floor never lets sight collapse to nothing")
	GameState.set_tolerance(100.0)
	ModifierManager.active_cards.clear()
	_check("even maxed out, some sight remains", game.sight_radius_mult() >= 0.2,
		"(mult %.3f)" % game.sight_radius_mult())
	GameState.clear_tolerance()

	completed = true
	print("\n%d FAIL(S)" % fails if fails > 0 else "\nALL PASS")
	get_tree().quit(1 if fails > 0 else 0)
