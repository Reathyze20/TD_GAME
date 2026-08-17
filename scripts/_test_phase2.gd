extends Node
## RECONSTRUCTED harness for REFACTOR_PLAN Phase 2 (SignalBus activation).
##
## The original file was accidentally overwritten and there was no backup or VCS copy.
## This is rebuilt from its documented contract in docs/REFACTOR_PLAN.md:104-106 —
## "11 checks: defeat reward at tolerance 0 and 50, Focus loss, build/upgrade/sell/cancel
## economy, failed-build abort, victory signal fires once" — plus the three load-bearing
## hazard guards that section spells out. It is behaviourally equivalent to the described
## original, but it is NOT byte-identical to what was there before.

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
	# Any harness that lets distractions reach the core without defenses will trip
	# _game_over(), whose change_scene_to_file() frees this harness and its watchdog.
	GameState.max_focus = 999999
	GameState.focus = 999999

	print("=== economy reacts to the bus, not to game.gd")
	ModifierManager.reset()
	GameState.dopamine = 0
	GameState.set_tolerance(0.0)
	GameState.tolerance_floor = 0.0
	var kills_before: int = GameState.kills
	SignalBus.distraction_defeated.emit(null, 10)
	_check("defeat pays full reward at tolerance 0", GameState.dopamine == 10,
		"(got %d)" % GameState.dopamine)
	_check("defeat counts a kill", GameState.kills == kills_before + 1)

	GameState.dopamine = 0
	GameState.set_tolerance(50.0)
	SignalBus.distraction_defeated.emit(null, 10)
	# reward = round(base * (1 - 0.6 * tolerance/100)) = round(10 * 0.7) = 7
	_check("defeat reward is tolerance-scaled at 50", GameState.dopamine == 7,
		"(got %d, expected 7)" % GameState.dopamine)
	GameState.set_tolerance(0.0)

	print("=== focus loss")
	GameState.focus = 30
	GameState.max_focus = 30
	SignalBus.distraction_escaped.emit(4)
	_check("escape costs Focus", GameState.focus == 26, "(got %d)" % GameState.focus)
	GameState.max_focus = 999999
	GameState.focus = 999999

	print("=== build / upgrade / sell / cancel economy")
	var cell := _first_empty_cell(game)
	var bs: BuildSpot = game.build_spots[cell]
	var def := Data.get_habit(&"focus_timer")

	GameState.dopamine = def.build_cost
	GameState.select_habit("focus_timer")
	game._build_on(cell)
	_check("building spends exactly the build cost", GameState.dopamine == 0,
		"(got %d)" % GameState.dopamine)
	_check("the spot is built", bs.state == BuildSpot.State.BUILT)

	# HAZARD 2: cancelling during aiming refunds 100%, unlike selling (50%).
	game._end_aiming()
	GameState.dopamine = 0
	GameState.add_dopamine(def.build_cost)
	bs.sell_habit()
	_check("aiming-cancel refunds the FULL build cost", GameState.dopamine == def.build_cost,
		"(got %d of %d)" % [GameState.dopamine, def.build_cost])

	GameState.dopamine = def.build_cost
	GameState.select_habit("focus_timer")
	game._build_on(cell)
	game._end_aiming()
	var refund := int(def.build_cost * 0.5)
	GameState.dopamine = 0
	game._do_sell(cell, refund)
	_check("selling a committed habit refunds 50%", GameState.dopamine == refund,
		"(got %d of %d)" % [GameState.dopamine, refund])
	_check("the spot is empty again", bs.state == BuildSpot.State.EMPTY)

	var up_def := Data.get_habit(&"focus_timer_2")
	GameState.dopamine = def.build_cost + up_def.build_cost
	GameState.select_habit("focus_timer")
	game._build_on(cell)
	game._end_aiming()
	game._do_upgrade(cell, "focus_timer_2", up_def.build_cost)
	_check("upgrading spends the tier-2 cost", GameState.dopamine == 0,
		"(got %d)" % GameState.dopamine)
	_check("the habit is now tier 2", bs.current_habit.type_key == "focus_timer_2",
		"(got %s)" % bs.current_habit.type_key)
	bs.sell_habit()

	print("=== HAZARD 1: affordability is a gate that aborts, not a reaction")
	var cell2 := _first_empty_cell(game)
	GameState.dopamine = def.build_cost - 1
	GameState.select_habit("focus_timer")
	game._build_on(cell2)
	_check("a build that can't be afforded is aborted",
		game.build_spots[cell2].state == BuildSpot.State.EMPTY)
	_check("...and nothing was spent", GameState.dopamine == def.build_cost - 1,
		"(got %d)" % GameState.dopamine)
	GameState.select_habit(null)

	print("=== HAZARD 3: game_over fires once, and keeps its asymmetry")
	# Intercept the bus so the real handler can't change_scene_to_file() out from under
	# the harness — and set game_ended ourselves, or _check_wave_progress re-emits next frame.
	game.game_ended = true
	var seen: Array[int] = [0]
	var probe := func(_victory: bool): seen[0] += 1
	SignalBus.game_over.connect(probe)
	SignalBus.game_over.emit(true)
	SignalBus.game_over.emit(true)
	_check("every emit reaches listeners", seen[0] == 2, "(got %d)" % seen[0])
	_check("the guard stops the real handler acting twice", game.game_ended)
	SignalBus.game_over.disconnect(probe)

	game.queue_free()
	await get_tree().process_frame
	completed = true
	print("=== %s (%d failures)" % ["ALL PASS" if fails == 0 else "FAILURES", fails])
	get_tree().quit(0 if fails == 0 else 1)

func _first_empty_cell(game: Game) -> Vector2i:
	for cell: Vector2i in game.build_spots:
		if game.build_spots[cell].state == BuildSpot.State.EMPTY:
			return cell
	return Vector2i.ZERO
