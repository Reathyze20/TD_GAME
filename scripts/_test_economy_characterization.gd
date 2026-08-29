extends Node
## Characterization harness for Tolerance, Quick Hit and the Dopamine defeat-reward
## economy (docs/refactor/MIGRATION.MD T2 / docs/refactor/SYSTEMS.MD S1).
##
## These fixate CURRENT behaviour, including the 0/100 boundaries, so a later change
## (the top-down migration, an economy rebalance) is caught rather than silently
## drifting. Deliberately does NOT judge whether the numbers are good — only that they
## stay what they are today.
##
## Three things this harness controls for, because all would otherwise make the exact
## numbers below depend on whoever's machine runs it (or corrupt real player data)
## rather than testing the code:
##  * MetaProgression.current_save is swapped for a blank SaveGame for the duration of
##    the run — a real save with Growth Tree ranks would add perks (extra bandwidth,
##    tolerance-decay rate, dopamine bonus cards) on top of the formulas under test.
##  * That swap alone is NOT enough to keep the real save file untouched on disk: this
##    harness calls game.do_quick_hit() and spawns/kills distractions, and both paths
##    can trigger a FIRST-TIME hint (Hints.show_hint -> MetaProgression.mark_hint_seen),
##    which writes the CURRENT (blank, swapped-in) current_save straight to
##    user://savegame.tres via SaveGame.write_savegame() — restoring the in-memory
##    reference afterward does nothing for what already hit disk. Found the hard way:
##    this silently overwrote the real save with a near-empty one every time this
##    harness ran. Fixed by backing up the real file's raw bytes before the swap and
##    restoring them unconditionally afterward, including on watchdog timeout — the
##    same lesson _test_save_round_trip.gd (S8) documents at more length.
##  * Most reward-formula checks fire SignalBus.distraction_defeated directly with a
##    chosen base_reward, instead of spawning a real DistractionData. That tests the
##    ECONOMY FORMULA, not any one distraction's tuned balance number — a content
##    rebalance should not have to touch this file. One real spawn+kill at the end
##    confirms the wiring itself still connects a kill to a payout.

const SAVE_PATH := "user://savegame.tres"

var completed := false
var fails := 0
var _save_backup: PackedByteArray
var _had_save_file := false

func _restore_disk_save() -> void:
	if _had_save_file:
		var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
		f.store_buffer(_save_backup)
		f.close()
	elif FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)

func _ready() -> void:
	_had_save_file = FileAccess.file_exists(SAVE_PATH)
	if _had_save_file:
		var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
		_save_backup = f.get_buffer(f.get_length())
		f.close()

	var wd := Timer.new()
	wd.wait_time = 60.0
	wd.one_shot = true
	add_child(wd)
	wd.timeout.connect(func():
		if not completed:
			print("FAILED: watchdog fired")
			_restore_disk_save()
			get_tree().quit(1))
	wd.start()
	call_deferred("_run")

func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("  ok   %s %s" % [label, detail])
	else:
		fails += 1
		print("  FAIL %s %s" % [label, detail])

## Fires the bus signal a real defeat would, and returns the Dopamine delta it paid.
func _defeat(base_reward: int) -> int:
	var dummy := Node2D.new()
	var before: int = GameState.dopamine
	SignalBus.distraction_defeated.emit(dummy, base_reward)
	dummy.queue_free()
	return GameState.dopamine - before

func _run() -> void:
	# Blank save for the whole run — see file header. Restored at the very end.
	var real_save: SaveGame = MetaProgression.current_save
	MetaProgression.current_save = SaveGame.new()

	for i in range(Data.get_level_count()):
		if Data.get_level(i).id == 99:
			GameState.current_level_index = i
			break

	var game = load("res://scenes/Game.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	GameState.max_focus = 999999
	GameState.focus = 999999
	GameState.designer_mode = false
	game.level.fasting = false
	game.game_ended = false
	ModifierManager.reset()
	await get_tree().process_frame

	print("\n== Tolerance: boundaries and the floor ==")
	GameState.clear_tolerance()
	_check("reset starts tolerance at 0", GameState.tolerance == 0.0, str(GameState.tolerance))
	_check("reset starts the floor at 0", GameState.tolerance_floor == 0.0,
		str(GameState.tolerance_floor))

	GameState.set_tolerance(500.0)
	_check("set_tolerance clamps at the 100 ceiling", GameState.tolerance == 100.0,
		str(GameState.tolerance))

	GameState.set_tolerance(-500.0)
	_check("set_tolerance clamps at the floor (0) as its lower bound",
		GameState.tolerance == 0.0, str(GameState.tolerance))

	GameState.raise_tolerance_floor(10.0)
	_check("raise_tolerance_floor pulls tolerance up when it was below the new floor",
		GameState.tolerance == 10.0 and GameState.tolerance_floor == 10.0,
		"tol=%.1f floor=%.1f" % [GameState.tolerance, GameState.tolerance_floor])

	GameState.set_tolerance(50.0)
	GameState.raise_tolerance_floor(5.0)
	_check("raise_tolerance_floor does NOT pull tolerance down when already above it",
		GameState.tolerance == 50.0 and GameState.tolerance_floor == 15.0,
		"tol=%.1f floor=%.1f" % [GameState.tolerance, GameState.tolerance_floor])

	GameState.raise_tolerance_floor(1000.0)
	_check("the floor itself clamps at 100", GameState.tolerance_floor == 100.0,
		str(GameState.tolerance_floor))
	_check("set_tolerance can't go below a raised floor",
		GameState.tolerance == 100.0, str(GameState.tolerance))
	GameState.set_tolerance(0.0)
	_check("...even asking for 0 explicitly", GameState.tolerance == 100.0,
		str(GameState.tolerance))

	GameState.clear_tolerance()
	_check("clear_tolerance resets BOTH tolerance and a raised floor",
		GameState.tolerance == 0.0 and GameState.tolerance_floor == 0.0,
		"tol=%.1f floor=%.1f" % [GameState.tolerance, GameState.tolerance_floor])

	print("\n== Tolerance: passive decay ==")
	GameState.set_tolerance(50.0)
	game._update_tolerance(1.0)
	_check("decays by exactly _TOLERANCE_DECAY_PER_SEC per second (no perk, no fasting)",
		is_equal_approx(GameState.tolerance, 46.0), "%.2f" % GameState.tolerance)

	GameState.clear_tolerance()
	GameState.raise_tolerance_floor(30.0)
	GameState.set_tolerance(32.0)
	game._update_tolerance(1.0)
	_check("decay stops AT the floor, not below it",
		is_equal_approx(GameState.tolerance, 30.0), "%.2f" % GameState.tolerance)

	GameState.clear_tolerance()
	GameState.set_tolerance(50.0)
	game.level.fasting = true
	game._update_tolerance(1.0)
	var fasting_drop: float = 50.0 - GameState.tolerance
	game.level.fasting = false
	GameState.clear_tolerance()
	GameState.set_tolerance(50.0)
	game._update_tolerance(1.0)
	var normal_drop: float = 50.0 - GameState.tolerance
	_check("a fasting level decays Tolerance faster (2.5x) than a normal one",
		is_equal_approx(fasting_drop, normal_drop * 2.5),
		"fasting=%.2f normal=%.2f" % [fasting_drop, normal_drop])

	print("\n== Dopamine: downregulation curve ==")
	GameState.clear_tolerance()
	GameState.streak_enabled = false
	GameState.streak = 0
	GameState.variable_rewards = false
	GameState.steady_payout = false
	GameState.lean_wave_active = false

	GameState.set_tolerance(0.0)
	var reward_t0: int = _defeat(15)
	_check("tolerance 0 pays the full base reward", reward_t0 == 15, str(reward_t0))

	GameState.set_tolerance(100.0)
	var reward_t100: int = _defeat(15)
	_check("tolerance 100 pays exactly 40% of base (round(15*0.4)=6)",
		reward_t100 == 6, str(reward_t100))
	_check("...strictly less than the tolerance-0 payout",
		reward_t100 < reward_t0, "%d vs %d" % [reward_t100, reward_t0])

	GameState.set_tolerance(50.0)
	var reward_t50: int = _defeat(15)
	_check("tolerance 50 sits between the two (round(15*0.7)=11)",
		reward_t50 == 11, str(reward_t50))

	GameState.set_tolerance(100.0)
	var reward_floor: int = _defeat(1)
	_check("a reward that rounds to 0 is floored at 1, never 0",
		reward_floor == 1, str(reward_floor))

	print("\n== Dopamine: lean waves pay nothing ==")
	GameState.set_tolerance(0.0)
	GameState.lean_wave_active = true
	var reward_lean: int = _defeat(15)
	GameState.lean_wave_active = false
	_check("a lean-wave defeat pays exactly 0 Dopamine", reward_lean == 0, str(reward_lean))

	print("\n== Dopamine: Streak multiplier compounds with Tolerance ==")
	GameState.streak_enabled = true
	GameState.set_tolerance(0.0)
	GameState.streak = 4
	var reward_streak4_t0: int = _defeat(15)
	_check("streak 4 alone: x1.6 (round(15*1.6)=24)", reward_streak4_t0 == 24,
		str(reward_streak4_t0))

	GameState.set_tolerance(100.0)
	var reward_streak4_t100: int = _defeat(15)
	_check("streak 4 AND tolerance 100 together: round(15*0.4*1.6)=10",
		reward_streak4_t100 == 10, str(reward_streak4_t100))

	GameState.streak_enabled = false
	GameState.streak = 10
	GameState.set_tolerance(0.0)
	var reward_streak_disabled: int = _defeat(15)
	_check("streak_enabled=false ignores the streak count entirely, even at 10",
		reward_streak_disabled == 15, str(reward_streak_disabled))
	GameState.streak = 0

	print("\n== Dopamine: variable-reward payout schedule ==")
	GameState.variable_rewards = true
	var total := 0
	var saw_jackpot := false
	const N_TRIALS := 300
	for i in range(N_TRIALS):
		var r: int = _defeat(100)
		total += r
		if r >= 250:  # jackpot pays 3x base; only the jackpot branch can reach this high
			saw_jackpot = true
	var mean: float = float(total) / float(N_TRIALS)
	_check("jackpot schedule's mean payout stays close to the flat 1.0x it replaces",
		mean > 70.0 and mean < 130.0, "mean=%.1f over %d trials" % [mean, N_TRIALS])
	_check("a jackpot (3x) actually occurs somewhere in %d trials" % N_TRIALS, saw_jackpot)
	GameState.variable_rewards = false

	print("\n== Dopamine: Steady Payout card is flat and deterministic ==")
	GameState.steady_payout = true
	var steady_rewards: Array = []
	for i in range(20):
		steady_rewards.append(_defeat(100))
	var all_same := true
	for r in steady_rewards:
		if r != 120:
			all_same = false
	_check("Steady Payout always pays exactly 1.2x, no variance (got %s)" % [steady_rewards],
		all_same)
	GameState.steady_payout = false

	print("\n== Dopamine: flat bonus modifiers apply after scaling, still floored at 1 ==")
	var effect := CardEffectData.new()
	effect.stat_type = ModifierManager.STAT_DOPAMINE_BONUS
	effect.target = "ALL"
	effect.is_percentage = false
	effect.value = 5.0
	var bonus_card := CardData.new()
	bonus_card.effects = [effect]
	ModifierManager.add_card(bonus_card)
	GameState.set_tolerance(0.0)
	var reward_with_bonus: int = _defeat(15)
	_check("a flat +5 dopamine_bonus card adds on top of the scaled reward (15+5=20)",
		reward_with_bonus == 20, str(reward_with_bonus))
	ModifierManager.reset()

	print("\n== Quick Hit ==")
	GameState.clear_tolerance()
	GameState.quick_hit_enabled = false
	game._quick_hit_cd = 0.0
	var dopamine_before_disabled: int = GameState.dopamine
	game.do_quick_hit()
	_check("refuses when quick_hit_enabled is false (no Dopamine, no Tolerance change)",
		GameState.dopamine == dopamine_before_disabled and GameState.tolerance == 0.0)

	GameState.quick_hit_enabled = true
	var payout_at_0: int = game.quick_hit_payout()
	_check("quick_hit_payout() at tolerance 0 is the base amount (15)",
		payout_at_0 == 15, str(payout_at_0))

	var dopamine_before: int = GameState.dopamine
	game.do_quick_hit()
	_check("do_quick_hit pays exactly what quick_hit_payout() promised",
		GameState.dopamine - dopamine_before == payout_at_0,
		str(GameState.dopamine - dopamine_before))
	_check("do_quick_hit raises Tolerance by exactly QUICK_HIT_SPIKE (18)",
		is_equal_approx(GameState.tolerance, 18.0), "%.2f" % GameState.tolerance)
	_check("do_quick_hit permanently raises the FLOOR by QUICK_HIT_FLOOR_GAIN (2)",
		is_equal_approx(GameState.tolerance_floor, 2.0), "%.2f" % GameState.tolerance_floor)

	var dopamine_before_cd: int = GameState.dopamine
	game.do_quick_hit()
	_check("refuses again immediately — still on cooldown",
		GameState.dopamine == dopamine_before_cd, str(GameState.dopamine - dopamine_before_cd))

	# Drain the cooldown the same way the real game does: repeated _update_tolerance ticks.
	for i in range(int(ceil(game.QUICK_HIT_COOLDOWN)) + 1):
		game._update_tolerance(1.0)
	_check("cooldown fully drained (%.1fs elapsed)" % (game.QUICK_HIT_COOLDOWN + 1.0),
		game._quick_hit_cd == 0.0, "%.2f" % game._quick_hit_cd)
	var dopamine_before_again: int = GameState.dopamine
	game.do_quick_hit()
	_check("available again once the cooldown clears",
		GameState.dopamine > dopamine_before_again,
		"%d -> %d" % [dopamine_before_again, GameState.dopamine])

	GameState.set_tolerance(100.0)
	var payout_at_100: int = game.quick_hit_payout()
	_check("quick_hit_payout shrinks with Tolerance, same curve as a kill (round(15*0.4)=6)",
		payout_at_100 == 6, str(payout_at_100))

	game.game_ended = true
	game._quick_hit_cd = 0.0
	var dopamine_before_ended: int = GameState.dopamine
	game.do_quick_hit()
	_check("refuses once the game has ended",
		GameState.dopamine == dopamine_before_ended,
		str(GameState.dopamine - dopamine_before_ended))
	game.game_ended = false

	print("\n== End-to-end: a real kill still pays through the same formula ==")
	GameState.clear_tolerance()
	GameState.streak = 0
	GameState.streak_enabled = false
	GameState.variable_rewards = false
	var spawn: Vector2i = game._random_spawn_cell()
	var before_real: int = GameState.dopamine
	var d = game.spawn_distraction(&"notification", spawn)
	await get_tree().process_frame
	d.take_direct_damage(99999)
	await get_tree().process_frame
	_check("a real spawn+kill still grants Dopamine through GameState",
		GameState.dopamine > before_real, "%d -> %d" % [before_real, GameState.dopamine])

	MetaProgression.current_save = real_save
	_restore_disk_save()
	_check("the real savegame.tres (if one existed) was restored to disk afterward",
		_had_save_file == FileAccess.file_exists(SAVE_PATH))

	completed = true
	print("\n%s (%d failures)" % ["PASSED" if fails == 0 else "FAILED", fails])
	get_tree().quit(1 if fails > 0 else 0)
