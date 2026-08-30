extends Node
# Phase 3 verification: StatusManager extraction must not change any observable behavior.
# Tests slow strongest-wins, reframe resistance stripping, boredom accumulator and
# mid-tick kill, status ticking while blocked, and economy parity (Phase 2 regression).
# Delete after use.

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

func _run() -> void:
	var ok := true

	# ---- Standalone StatusManager tests (no game scene needed) ----------------

	# 1. Slow strongest-wins: stronger (lower factor) wins, weaker rejected entirely
	var sm := StatusManager.new()
	sm.name = "TestSM1"
	add_child(sm)
	sm.apply_slow(0.5, 2.0)
	sm.apply_slow(0.8, 3.0)  # weaker factor (higher value) — fully rejected
	ok = _check(sm.slow_factor == 0.5, "slow strongest-wins: factor stays 0.5 (got %s)" % sm.slow_factor) and ok
	ok = _check(sm._slow_left == 2.0, "slow weaker rejected: duration stays 2.0 (got %s)" % sm._slow_left) and ok
	# Applying same-or-stronger slow DOES extend duration
	sm.apply_slow(0.5, 4.0)  # same factor, longer
	ok = _check(sm._slow_left == 4.0, "slow same-strength extends: duration extends to 4.0 (got %s)" % sm._slow_left) and ok
	sm.queue_free()

	# 2. Slow weaker rejected entirely
	var sm2 := StatusManager.new()
	sm2.name = "TestSM2"
	add_child(sm2)
	sm2.apply_slow(0.3, 2.0)
	sm2.apply_slow(0.6, 1.0)  # weaker factor (higher), shorter — rejected
	ok = _check(sm2.slow_factor == 0.3, "slow weaker rejected: factor stays 0.3 (got %s)" % sm2.slow_factor) and ok
	ok = _check(sm2._slow_left == 2.0, "slow weaker rejected: duration stays 2.0 (got %s)" % sm2._slow_left) and ok
	sm2.queue_free()

	# 3. Reframe strongest-wins: higher amount wins, duration extends
	var sm3 := StatusManager.new()
	sm3.name = "TestSM3"
	add_child(sm3)
	sm3.apply_reframe(5, 2.0)
	sm3.apply_reframe(3, 3.0)  # weaker amount — rejected, but duration would extend if same
	ok = _check(sm3.reframe_amount == 5, "reframe strongest-wins: amount stays 5 (got %d)" % sm3.reframe_amount) and ok
	# The weaker application is rejected entirely (amount < current), so duration stays
	ok = _check(sm3._reframe_left == 2.0, "reframe weaker rejected: duration stays 2.0 (got %s)" % sm3._reframe_left) and ok
	sm3.queue_free()

	# 4. Reframe equal-or-stronger extends duration
	var sm3b := StatusManager.new()
	sm3b.name = "TestSM3b"
	add_child(sm3b)
	sm3b.apply_reframe(5, 2.0)
	sm3b.apply_reframe(5, 4.0)  # same amount, longer duration
	ok = _check(sm3b.reframe_amount == 5, "reframe equal extends: amount stays 5") and ok
	ok = _check(sm3b._reframe_left == 4.0, "reframe equal extends: duration extends to 4.0 (got %s)" % sm3b._reframe_left) and ok
	sm3b.queue_free()

	# 5. Slow expiry clears factor
	var sm4 := StatusManager.new()
	sm4.name = "TestSM4"
	add_child(sm4)
	sm4.apply_slow(0.5, 0.1)
	sm4.tick(0.15)  # past expiry
	ok = _check(sm4.slow_factor == 1.0, "slow expired: factor resets to 1.0 (got %s)" % sm4.slow_factor) and ok
	sm4.queue_free()

	# 6. Reframe expiry clears amount
	var sm5 := StatusManager.new()
	sm5.name = "TestSM5"
	add_child(sm5)
	sm5.apply_reframe(5, 0.1)
	sm5.tick(0.15)
	ok = _check(sm5.reframe_amount == 0, "reframe expired: amount resets to 0 (got %d)" % sm5.reframe_amount) and ok
	sm5.queue_free()

	# 7. Boredom fractional accumulator
	# NOTE: GDScript closures capture primitives by value, so we use an Array to
	# make the accumulator mutable from inside the lambda.
	var sm6 := StatusManager.new()
	sm6.name = "TestSM6"
	add_child(sm6)
	var boredom_buf := [0]  # mutable capture via Array
	# boredom_damage gained a `source` arg when Boredom became per-source (so towers can
	# be credited for their dot damage); totals this test asserts are unchanged.
	sm6.boredom_damage.connect(func(amount: int, _source: Object): boredom_buf[0] += amount)
	sm6.apply_boredom(0.5, 10.0)  # 0.5 DPS
	# 3 ticks at 1/60 = 0.05s total -> 0.5 * 0.05 = 0.025 accumulated, no whole number yet
	sm6.tick(1.0 / 60.0)
	sm6.tick(1.0 / 60.0)
	sm6.tick(1.0 / 60.0)
	ok = _check(boredom_buf[0] == 0, "boredom fractional: no damage after 0.05s at 0.5 DPS (got %d)" % boredom_buf[0]) and ok
	# Tick 2 seconds: 0.5 * 2.0 = 1.0 more accumulated (plus leftover) -> should emit 1
	sm6.tick(2.0)
	ok = _check(boredom_buf[0] == 1, "boredom fractional: 1 damage after 2.05s at 0.5 DPS (got %d)" % boredom_buf[0]) and ok
	sm6.queue_free()

	# 8. Boredom expiry clears state
	var sm7 := StatusManager.new()
	sm7.name = "TestSM7"
	add_child(sm7)
	sm7.apply_boredom(5.0, 0.1)
	sm7.tick(0.15)  # past expiry
	ok = _check(sm7.boredom_dps == 0.0, "boredom expired: dps resets to 0 (got %s)" % sm7.boredom_dps) and ok
	# The shared accumulator moved into per-source entries; expiry now means no sources.
	ok = _check(sm7._boredom_sources.is_empty(), "boredom expired: sources cleared") and ok
	sm7.queue_free()

	# ---- Integration tests with Game scene -----------------------------------

	GameState.current_level_index = 0
	var game: Node = load("res://scenes/Game.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame

	SignalBus.game_over.disconnect(game._on_bus_game_over)
	SignalBus.game_over.connect(func(victory: bool): _game_over_events.append(victory))

	GameState.max_focus = 999999
	GameState.focus = 999999

	# 9. Reframe strips both resistances on a live Distraction
	game.spawn_distraction("doomscroll", game._random_spawn_cell())
	var d: Distraction = game._distractions[game._distractions.size() - 1]
	var comp_before: int = d.current_compulsion
	var rat_before: int = d.current_rationalization
	d.apply_reframe(3, 5.0)
	var eff_comp: int = d.effective_compulsion()
	var eff_rat: int = d.effective_rationalization()
	ok = _check(eff_comp == maxi(0, comp_before - 3), "reframe strips compulsion: %d -> %d (got %d)" % [comp_before, maxi(0, comp_before - 3), eff_comp]) and ok
	ok = _check(eff_rat == maxi(0, rat_before - 3), "reframe strips rationalization: %d -> %d (got %d)" % [rat_before, maxi(0, rat_before - 3), eff_rat]) and ok
	d.take_direct_damage(9999)
	await get_tree().process_frame

	# 10. Boredom mid-tick kill: health=1 + high DPS -> dies during tick
	game.spawn_distraction("notification", game._random_spawn_cell())
	var d2: Distraction = game._distractions[game._distractions.size() - 1]
	d2.current_health = 1
	d2.apply_boredom(100.0, 10.0)  # massive DPS — will kill on first tick
	# Manually call tick to verify synchronous death, before the frame processes
	d2.status_manager.tick(0.016)
	ok = _check(d2.dead, "boredom mid-tick kill: dead after manual tick (health was 1)") and ok
	await get_tree().process_frame
	await get_tree().process_frame

	# 11. Status ticks while blocked: slow expires even when movement is halted
	game.spawn_distraction("notification", game._random_spawn_cell())
	var d3: Distraction = game._distractions[game._distractions.size() - 1]
	d3.is_blocked = true
	d3.apply_slow(0.5, 0.05)
	ok = _check(d3.status_manager.slow_factor == 0.5, "slow applied while blocked: factor 0.5") and ok
	# Wait on REAL ELAPSED TIME, not a fixed frame count (docs/KNOWN_BROKEN.md, P0e/P0f).
	# The duration above is 0.05 SECONDS; 10 process_frame()s is not guaranteed to cover
	# that -- a slow machine or a loaded CI runner can take longer than 0.005s/frame, and
	# then the slow has not actually expired yet when this checks it. create_timer() waits
	# for its argument in actual seconds regardless of frame rate, which is what "past the
	# duration" means; 0.15s is a 3x margin over the 0.05s being waited out.
	await get_tree().create_timer(0.15).timeout
	ok = _check(d3.status_manager.slow_factor == 1.0, "slow expired while blocked: factor reset to 1.0 (got %s)" % d3.status_manager.slow_factor) and ok
	d3.take_direct_damage(9999)
	await get_tree().process_frame

	# 12. Economy parity regression — defeat reward at tolerance 0
	ModifierManager.reset()
	GameState.set_tolerance(0.0)
	var dop_before: int = GameState.dopamine
	var kills_before: int = GameState.kills
	game.spawn_distraction("notification", game._random_spawn_cell())
	var d4: Distraction = game._distractions[game._distractions.size() - 1]
	d4.take_direct_damage(9999)
	await get_tree().process_frame
	ok = _check(GameState.dopamine == dop_before + 1, "economy parity: notification grants 1 Dopamine (got %d)" % (GameState.dopamine - dop_before)) and ok
	ok = _check(GameState.kills == kills_before + 1, "economy parity: kills incremented") and ok

	# 13. Economy parity — defeat reward at tolerance 50
	GameState.set_tolerance(50.0)
	dop_before = GameState.dopamine
	game.spawn_distraction("doomscroll", game._random_spawn_cell())
	var d5: Distraction = game._distractions[game._distractions.size() - 1]
	d5.take_direct_damage(9999)
	await get_tree().process_frame
	var granted: int = GameState.dopamine - dop_before
	ok = _check(granted == 4, "economy parity: tolerance 50 scales reward 5 -> 4 (got %d)" % granted) and ok
	GameState.set_tolerance(0.0)

	game.queue_free()
	completed = ok
	print("ALL PASS" if ok else "SOME CHECKS FAILED")
	get_tree().quit(0 if ok else 1)
