extends Node
## TEMPORARY diagnostic for Q2 (BLOCKED.md) — DELETE after use (with its .gd.uid and
## .tscn). Read-only measurement: plays every level currently in data/levels/ through
## S2 (LevelSimulator) with four SimStrategy baselines — do nothing, cheap habits
## evenly, spam Quick Hit, cheap habits + Quick Hit only in emergency — across three
## fixed seeds each, and prints survived/died, remaining Focus, final Tolerance, total
## Dopamine, kills, wave reached, and how many Quick Hit presses actually paid out
## (not how many times the strategy called quick_hit() — do_quick_hit() no-ops on
## cooldown, exactly like a real player mashing a disabled button).
##
## Counts a successful Quick Hit by watching Game._quick_hit_cd jump upward across a
## single strategy-tick call: do_quick_hit() sets it to QUICK_HIT_COOLDOWN (6.0) on
## success and never raises it otherwise, while it only ever decays between calls — so
## an increase can only mean a hit landed. Wraps the real, unmodified strategy classes
## rather than reimplementing their decisions, same reasoning _diag_q1b.gd used.
##
## Run: godot --headless --path . --main-scene res://scenes/_diag_q2.tscn --fixed-fps 60

const SEEDS := [20260902, 20260903, 20260904]
const STRATEGY_KEYS := ["passive", "cheap_even", "quick_hit_spam", "habits_emergency_qh"]

var completed := false


## Forwards every SimStrategy hook to `inner` unchanged, counting successful Quick
## Hits alongside whatever `inner` actually decides.
class QuickHitCounter extends SimStrategy:
	var inner: SimStrategy
	var uses := 0

	func _init(strategy: SimStrategy) -> void:
		inner = strategy

	func on_build_tick(sim: LevelSimulator) -> void:
		var before: float = sim.game._quick_hit_cd
		inner.on_build_tick(sim)
		_count(sim, before)

	func on_wave_tick(sim: LevelSimulator) -> void:
		var before: float = sim.game._quick_hit_cd
		inner.on_wave_tick(sim)
		_count(sim, before)

	func on_draft(sim: LevelSimulator, options: Array[CardData]) -> CardData:
		return inner.on_draft(sim, options)

	func _count(sim: LevelSimulator, before: float) -> void:
		if sim.game._quick_hit_cd > before:
			uses += 1


func _ready() -> void:
	var wd := Timer.new()
	wd.wait_time = 3000.0
	wd.one_shot = true
	add_child(wd)
	wd.timeout.connect(func():
		if not completed:
			print("FAILED: watchdog fired")
			get_tree().quit(1))
	wd.start()
	call_deferred("_run")


func _make_strategy(key: String) -> SimStrategy:
	match key:
		"passive":
			return SimStrategyPassive.new()
		"cheap_even":
			return SimStrategyCheapEven.new()
		"quick_hit_spam":
			return SimStrategyQuickHitSpam.new()
		"habits_emergency_qh":
			return SimStrategyHabitsEmergencyQuickHit.new()
	push_error("unknown strategy key %s" % key)
	return null


func _play(level_id: int, run_seed: int, key: String) -> Dictionary:
	var counter := QuickHitCounter.new(_make_strategy(key))
	var sim := LevelSimulator.new()
	add_child(sim)
	var result: Dictionary = await sim.run(level_id, run_seed, counter)
	result["quick_hit_uses"] = counter.uses
	sim.queue_free()
	await get_tree().process_frame
	return result


func _run() -> void:
	for level_index in range(Data.get_level_count()):
		var level: LevelData = Data.get_level(level_index)
		print("\n=== Level id=%d '%s' (wave_count=%d, start_dopamine=%d, focus=%d) ===" % [
			level.id, level.display_name, level.wave_count, level.start_dopamine, level.focus])
		for key in STRATEGY_KEYS:
			print("  -- %s --" % key)
			for s in SEEDS:
				var r := await _play(level.id, s, key)
				print(("    seed=%d victory=%s timed_out=%s focus=%s/%s tolerance=%.1f " +
					"dopamine=%s kills=%s wave=%s qh_uses=%s") % [
					s, r.get("victory"), r.get("timed_out"), r.get("focus"), r.get("max_focus"),
					r.get("tolerance"), r.get("dopamine"), r.get("kills"), r.get("wave"),
					r.get("quick_hit_uses")])
	completed = true
	print("\nDONE")
	get_tree().quit(0)
