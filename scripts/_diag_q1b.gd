extends Node
## TEMPORARY diagnostic for Q1b — DELETE after use (with its .gd.uid and .tscn).
##
## Q1's BLOCKED.md entry says 1x and 4x land on reproducibly different kill counts for
## SimStrategyCheapEven and asks: find the FIRST point where a value, not just a tick
## offset, actually differs. This answers that by logging every strategy ACTION against
## the authoritative clock (Game._sim_tick_count) instead of against the real frame
## number, so the two speeds are directly comparable tick-for-tick.
##
## Hypothesis under test: LevelSimulator.run()'s driver loop calls the strategy once per
## `process_frame` (level_simulator.gd:91-94), while the simulation advances in
## _physics_process() at `_current_speed()` ticks per frame (game.gd:3696-3720). At 1x
## that is 1 tick per strategy call; at 4x it is 4. So the strategy observes and acts on
## a 4x coarser grid of SIMULATED time, and any decision whose timing matters lands on a
## different sim tick. If true, the build/start_wave ticks below will differ between the
## two speeds — which would make this a DRIVER/harness artifact, not proof that the
## game's own fixed-tick mechanism is speed-dependent.
##
## Run: godot --headless --path . --main-scene res://scenes/_diag_q1b.tscn --fixed-fps 60

const LEVEL_ID := 98
const SEED_A := 20260830
const SPEED_1X := 1
const SPEED_4X := 3

var completed := false


## Wraps the real SimStrategyCheapEven and records (sim_tick, action) for everything it
## does. Subclasses rather than reimplements so the decisions under test stay EXACTLY
## the shipped ones — a reimplementation that drifted would answer a different question.
class LoggingCheapEven extends SimStrategyCheapEven:
	var log_lines: Array[String] = []
	var _sim: LevelSimulator = null

	func _tick_of() -> int:
		return _sim.game._sim_tick_count if _sim != null and is_instance_valid(_sim.game) else -1

	## Occupied build spots — the observable "how many habits are standing" count,
	## read the same way LevelSimulator.buildable_cells() reads the spot state.
	static func _built(game: Node) -> int:
		var n := 0
		for cell: Vector2i in game.build_spots:
			var spot: BuildSpot = game.build_spots[cell]
			if spot.state != BuildSpot.State.EMPTY:
				n += 1
		return n

	## When > 0, the strategy refuses to act until the sim clock reaches `gate`, then
	## bumps the gate by GATE_STEP. This is the CONTROL: it pins each decision to a point
	## in SIMULATED time both speeds can actually reach, instead of to "whenever the
	## driver's next render frame happens to land". If outcomes match under this gating
	## but not without it, the divergence is the driver's decision cadence and nothing
	## else; if they still differ even with every action on the same tick, something in
	## the engine itself is genuinely speed-dependent and the gating rules the driver out.
	const GATE_STEP := 600
	var gate := 0

	func on_build_tick(sim: LevelSimulator) -> void:
		_sim = sim
		if gate > 0 and _tick_of() < gate:
			return
		var before := _built(sim.game)
		var dop_before := GameState.dopamine
		var was_between: bool = sim.game.between_waves
		super.on_build_tick(sim)
		var after := _built(sim.game)
		if after != before or was_between != sim.game.between_waves:
			if gate > 0:
				gate = _tick_of() + GATE_STEP
			log_lines.append("tick=%d built=%d->%d dopamine=%d->%d wave=%d between=%s->%s" % [
				_tick_of(), before, after, dop_before, GameState.dopamine,
				sim.game.wave_index, was_between, sim.game.between_waves])


func _ready() -> void:
	var wd := Timer.new()
	wd.wait_time = 420.0
	wd.one_shot = true
	add_child(wd)
	wd.timeout.connect(func():
		if not completed:
			print("FAILED: watchdog fired")
			get_tree().quit(1))
	wd.start()
	call_deferred("_run")


func _play(speed_index: int, gate: int) -> Array:
	var strat := LoggingCheapEven.new()
	strat.gate = gate
	var sim := LevelSimulator.new()
	add_child(sim)
	var result: Dictionary = await sim.run(
		LEVEL_ID, SEED_A, strat, LevelSimulator.DEFAULT_MAX_FRAMES, speed_index)
	sim.queue_free()
	await get_tree().process_frame
	return [result, strat.log_lines]


func _compare(title: String, gate: int) -> void:
	print("\n=== %s ===" % title)
	var a := await _play(SPEED_1X, gate)
	var r1: Dictionary = a[0]
	var l1: Array = a[1]
	var b := await _play(SPEED_4X, gate)
	var r4: Dictionary = b[0]
	var l4: Array = b[1]

	for i in range(maxi(l1.size(), l4.size())):
		var s1: String = l1[i] if i < l1.size() else "<none>"
		var s4: String = l4[i] if i < l4.size() else "<none>"
		print("  [%d] %s" % [i, "SAME" if s1 == s4 else "DIFF"])
		print("      1x  %s" % s1)
		print("      4x  %s" % s4)

	var outcome_same: bool = (
		r1.get("kills") == r4.get("kills")
		and r1.get("dopamine") == r4.get("dopamine")
		and r1.get("focus") == r4.get("focus")
		and r1.get("wave") == r4.get("wave"))
	print("  OUTCOME %s" % ("IDENTICAL" if outcome_same else "DIVERGENT"))
	print("    1x kills=%s dopamine=%s focus=%s wave=%s frame=%s" % [
		r1.get("kills"), r1.get("dopamine"), r1.get("focus"), r1.get("wave"), r1.get("frame")])
	print("    4x kills=%s dopamine=%s focus=%s wave=%s frame=%s" % [
		r4.get("kills"), r4.get("dopamine"), r4.get("focus"), r4.get("wave"), r4.get("frame")])


func _run() -> void:
	print("Q1b: strategy actions keyed to Game._sim_tick_count (not real frame)")
	# B: every decision pinned to the same simulated-time gate at both speeds.
	await _compare("CONTROL — tick-gated decisions (same sim tick at both speeds)", 600)
	completed = true
	get_tree().quit(0)
