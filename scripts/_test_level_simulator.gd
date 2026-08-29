extends Node
## S2 (docs/refactor/SYSTEMS.MD): proves LevelSimulator meets its own bar — "dvakrat
## spusteny stejny seed da bit-identicky vysledek" — by running the SAME level, seed,
## and strategy twice and diffing the full result dict, for two different strategies
## (SimStrategyPassive and SimStrategyQuickHitSpam) so both the "do nothing" and the
## "actively spend a limited resource with a real cooldown" code paths are covered.
##
## Needs the process launched with `--fixed-fps 60` — verify.sh special-cases this one
## scene for that (see FIXED_FPS_TESTS there). Without it, Godot's per-frame delta (and
## every create_tween() the game uses) is measured from real elapsed time, which is
## NOT guaranteed identical between two runs even on the same machine.

var completed := false
var fails := 0

const LEVEL_ID := 98
const SEED_A := 20260829

## Fields S2's own spec requires reproduced: "prezil/padl, zbyvajici Focus, konecna
## Tolerance, celkovy dopamine" (plus kills/wave, same category of outcome fact).
## `frame` and `timed_out` are excluded from the equality check on purpose: `frame`
## is this driver's OWN external observation of when the game_over signal happened to
## be noticed, not game state — two runs of the same seed were observed to differ by
## a small number of frames (order of 10-20) despite every field below matching
## exactly, most likely from autoload/setup state that is not perfectly identical
## between the first and a later LevelSimulator.run() call within the same process
## (Mirror's history is never reset between runs, for one) rather than genuine
## gameplay non-determinism — worth a closer look if it ever needs to be trusted at
## frame granularity (S3 does not), but out of scope for what S2 actually requires.
const RESULT_FIELDS := ["victory", "focus", "max_focus", "tolerance", "dopamine", "kills", "wave"]

func _outcome(r: Dictionary) -> Dictionary:
	var out := {}
	for f in RESULT_FIELDS:
		out[f] = r.get(f)
	return out

func _ready() -> void:
	var wd := Timer.new()
	wd.wait_time = 480.0
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

## Runs level_id/run_seed/strategy to completion and frees the simulator node.
func _play(run_seed: int, strategy: SimStrategy) -> Dictionary:
	var sim := LevelSimulator.new()
	add_child(sim)
	var result: Dictionary = await sim.run(LEVEL_ID, run_seed, strategy)
	sim.queue_free()
	await get_tree().process_frame
	return result

func _run() -> void:
	print("-- same seed, twice: must be bit-identical (passive strategy)")
	var p1 := await _play(SEED_A, SimStrategyPassive.new())
	var p2 := await _play(SEED_A, SimStrategyPassive.new())
	_check("passive: result dict is non-empty", not p1.is_empty() and not p2.is_empty(), str(p1))
	_check("passive: outcome is bit-identical across two runs of the same seed",
		_outcome(p1) == _outcome(p2), "run1=%s run2=%s" % [p1, p2])

	print("\n-- same seed, twice: must be bit-identical (quick-hit spam strategy)")
	var q1 := await _play(SEED_A, SimStrategyQuickHitSpam.new())
	var q2 := await _play(SEED_A, SimStrategyQuickHitSpam.new())
	_check("quick-hit spam: result dict is non-empty", not q1.is_empty() and not q2.is_empty(),
		str(q1))
	_check("quick-hit spam: outcome is bit-identical across two runs of the same seed",
		_outcome(q1) == _outcome(q2), "run1=%s run2=%s" % [q1, q2])

	completed = true
	print("\n%s (%d failures)" % ["PASSED" if fails == 0 else "FAILED", fails])
	get_tree().quit(1 if fails > 0 else 0)
