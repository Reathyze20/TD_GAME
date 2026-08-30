extends Node
## P7 (docs/refactor/PATHFINDING.MD): proves the spawn telegraph is load-bearing, not
## just visible. The task's own hard rule ("telegraf musí být pravdivý" — when you show a
## direction, the horde genuinely comes from there) is checked mechanically here, not by
## inspection, in three parts:
##
##  1. GATING PURITY — every sim tick from wave start, Game._pending_spawn_points() and
##     Game._active_spawn_point_cells() are compared against _expected_pending() below, an
##     INDEPENDENT reimplementation of the spec (not copied from game.gd — same reasoning
##     as _test_multispawn.gd's own _expected_active()), so a bug that made the two agree
##     by coincidence cannot hide. A point must never be both "pending" and "active" at
##     once, and the pending->live transition must happen EXACTLY once for the run.
##  2. PRODUCTION WIRING — Game._sim_tick() is called directly, the SAME number of times
##     with the SAME FIXED_TICK_DT the real fixed-tick accumulator uses (this project's
##     own testing convention — docs/REFACTOR_PLAN.md's Verification pattern, Q1's own
##     fixed-tick philosophy — favors exact tick-by-tick control over waiting on a real
##     timer), driving the REAL spawn_queue pop loop in _sim_tick(), not a re-
##     implementation. SignalBus.distraction_spawned captures the cell (and the sim-time
##     elapsed) of every real spawn AT THE INSTANT it happens, before that distraction's
##     own next _process() has any chance to move it off that cell.
##  3. THE PAYOFF — every spawn recorded BEFORE the point went live landed on the baseline
##     point, NEVER on the telegraphed cell (the gate genuinely withholds production, not
##     just the query functions), and at least one spawn recorded AFTER it went live
##     landed on EXACTLY sp.cell — the position announced by the telegraph and the
##     position a real distraction actually appears at are the literal same cell.
##
## Fixture: TWO spawn points on level id 1's real geometry (cloned the same way
## _test_multispawn.gd's own fixture is — known-good high_ground/objective/path_cells).
## CELL_BASE (active_from_wave 0, never gated — SpawnPointData.active_from_wave's own doc
## comment: "already active on wave 1", nothing to telegraph) is there so an early-
## scheduled entry has somewhere real to resolve to instead of crashing on an empty
## fallback (level.spawn_zones is deliberately empty, same as _test_multispawn's fixture)
## — and, more importantly, so "never leaks the telegraphed cell early" is an actually
## exercised check rather than one that passes only because nothing was scheduled early
## enough to test it. CELL_TELE (active_from_wave 1, telegraph_lead_time LEAD_TIME) is the
## point under test. A single wave_curve row spaces ENTRY_COUNT entries SPACING seconds
## apart, straddling the LEAD_TIME crossing with plenty on both sides. RNG is seeded
## (RUN_SEED) purely so the run is byte-reproducible — the "at least one post-crossing
## spawn hits CELL_TELE" check does not actually depend on the seed: with ~30 independent
## 50/50 draws after crossing, P(all miss) is astronomically small either way.
##
## Needs no --fixed-fps: every tick is driven by an explicit Game._sim_tick(FIXED_TICK_DT)
## call, never by Godot's own automatically-scheduled _physics_process(), so no real
## per-frame delta measurement is ever involved (see the loop in _run() — no `await`
## appears between game._on_start_wave_pressed() and the end of the tick loop, so Godot's
## own automatic scheduling never gets a chance to interleave with these manual calls).

var completed := false
var fails := 0

const TEST_LEVEL_ID := 762036
const CELL_BASE := Vector2i(0, 8)   ## active_from_wave 0 -- baseline, never gated
const CELL_TELE := Vector2i(0, 5)   ## active_from_wave 1 -- the point under test
const LEAD_TIME := 0.3
const SPACING := 0.1
const ENTRY_COUNT := 35
const RUN_SEED := 20260830
## Matches Game.FIXED_TICK_DT (game.gd's own const, 1.0/60.0 — the project's physics
## tick rate, see that const's own comment). Named separately here rather than reaching
## across the class boundary for it, so this file has no dependency on whether a plain
## class_name's const happens to be reachable as Game.FIXED_TICK_DT from outside.
const FIXED_TICK_DT := 1.0 / 60.0

var _game_ref: Game = null
## {"cell": Vector2i, "elapsed": float} for every real distraction_spawned this run, in
## spawn order — "elapsed" is game.wave_time AT THE INSTANT of that spawn, captured
## before anything can move the distraction off the cell it appeared on.
var _spawn_log: Array[Dictionary] = []


func _ready() -> void:
	var wd := Timer.new()
	wd.wait_time = 60.0
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


func _make_spawn(cell: Vector2i, active_from_wave: int, lead: float) -> SpawnPointData:
	var sp := SpawnPointData.new()
	sp.cell = cell
	sp.active_from_wave = active_from_wave
	sp.telegraph_lead_time = lead
	sp.direction_id = &"N"
	return sp


## Independent reimplementation of "is this point still pending", straight from P7's own
## task spec, NOT copied from game.gd's _pending_spawn_points()/_active_spawn_point_cells()
## — see this file's header for why that separation matters.
func _expected_pending(sp: SpawnPointData, wave_number: int, wave_elapsed: float) -> bool:
	if sp.requires_segment != &"":
		return false
	if sp.active_from_wave <= 0 or sp.active_from_wave != wave_number:
		return false
	return wave_elapsed < sp.telegraph_lead_time


## Clones level id 1's real geometry (objective/high_ground/path_cells), same known-good
## precedent _test_multispawn.gd's own fixture leans on. spawn_zones stays empty on
## purpose (see this file's header) — a gating bug that leaked into the fallback would
## either crash or silently produce from the wrong place, not quietly pass.
func _build_fixture_level(spawn_points: Array[SpawnPointData], curve_row: WaveCurveEntryData) -> LevelData:
	var base: LevelData = null
	for i in range(Data.get_level_count()):
		if Data.get_level(i).id == 1:
			base = Data.get_level(i)
			break
	if base == null or base.wave_curve.is_empty():
		return null

	var lv := LevelData.new()
	lv.id = TEST_LEVEL_ID
	lv.display_name = "P7 telegraph fixture (test-only, never a real campaign level)"
	lv.start_dopamine = base.start_dopamine
	lv.focus = 999   ## generous: this test is about spawn timing/position, not combat.
	lv.objective = base.objective
	lv.high_ground = base.high_ground.duplicate()
	lv.path_cells = base.path_cells.duplicate()
	lv.path_off_lane_cost = base.path_off_lane_cost
	lv.wave_count = 1
	lv.wave_curve = [curve_row]
	lv.spawn_zones = []
	lv.spawn_points = spawn_points
	return lv


## Same registration precedent _test_multispawn.gd's own header documents at length:
## append-then-resort onto Data's own _levels array is how every _test_*.gd fixture
## avoids being written to a .tres (CLAUDE.md forbids hand-editing level .tres files).
func _register_fixture(lv: LevelData) -> void:
	Data._levels.append(lv)
	Data._levels.sort_custom(func(a: LevelData, b: LevelData): return a.id < b.id)


func _on_spawned(node: Node2D) -> void:
	var d := node as Distraction
	if d == null or _game_ref == null:
		return
	_spawn_log.append({"cell": d.current_cell, "elapsed": _game_ref.wave_time})


func _run() -> void:
	var base_distraction: DistractionData = null
	for i in range(Data.get_level_count()):
		if Data.get_level(i).id == 1:
			var lvl := Data.get_level(i)
			if not lvl.wave_curve.is_empty():
				base_distraction = lvl.wave_curve[0].distraction
			break
	_check("level id 1 exists with a real distraction to clone", base_distraction != null)
	if base_distraction == null:
		completed = true
		print("\nFAILED (%d failures) — could not build fixture" % (fails + 1))
		get_tree().quit(1)
		return

	var sp_base := _make_spawn(CELL_BASE, 0, 0.0)
	var sp_tele := _make_spawn(CELL_TELE, 1, LEAD_TIME)

	var curve_row := WaveCurveEntryData.new()
	curve_row.distraction = base_distraction
	curve_row.from_wave = 1
	curve_row.base_count = ENTRY_COUNT
	curve_row.growth_per_wave = 0.0
	curve_row.spacing = SPACING
	curve_row.shape = WaveCurveEntryData.SpawnShape.STREAM

	var lv := _build_fixture_level([sp_base, sp_tele], curve_row)
	_check("fixture level built", lv != null)
	if lv == null:
		completed = true
		print("\nFAILED (%d failures) — could not build fixture" % (fails + 1))
		get_tree().quit(1)
		return

	var lv_index := Data.get_level_count()
	_register_fixture(lv)

	seed(RUN_SEED)
	GameState.current_level_index = lv_index
	var game: Game = load("res://scenes/Game.tscn").instantiate()
	_game_ref = game
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame

	var live_tele: SpawnPointData = null
	for sp: SpawnPointData in game.level.spawn_points:
		if sp.cell == CELL_TELE:
			live_tele = sp
	_check("fixture spawn point wired onto the live Game.level",
		live_tele != null and live_tele.telegraph_lead_time == LEAD_TIME,
		"" if live_tele == null else str(live_tele.telegraph_lead_time))
	if live_tele == null:
		game.queue_free()
		completed = true
		print("\nFAILED (%d failures) — spawn point not wired" % (fails + 1))
		get_tree().quit(1)
		return

	SignalBus.distraction_spawned.connect(_on_spawned)

	game._on_start_wave_pressed()
	_check("wave 1 actually started", not game.between_waves and game.wave_spawning)

	# -------------------------------------------------------------- checks 1 & 2: gating
	var pending_mismatch: Array[int] = []
	var active_mismatch: Array[int] = []
	var overlap_violation: Array[int] = []
	var crossing_ticks: Array[int] = []
	var saw_pending := false
	var prev_pending := _expected_pending(live_tele, 1, 0.0)   # true: LEAD_TIME > 0.0
	# Covers LEAD_TIME crossing (0.3s) and every one of the ENTRY_COUNT entries (last one
	# due at ENTRY_COUNT * SPACING = 3.5s) with margin.
	var total_ticks := int(4.0 / FIXED_TICK_DT)
	var tick := 0
	while tick < total_ticks:
		game._sim_tick(FIXED_TICK_DT)
		tick += 1
		var w := game.wave_index + 1
		var elapsed: float = game.wave_time
		var pending := game._pending_spawn_points(w, elapsed)
		var active := game._active_spawn_point_cells(w, elapsed)
		var is_pending := pending.has(live_tele)
		var is_active := active.has(CELL_TELE)
		var expect_pending := _expected_pending(live_tele, w, elapsed)

		if is_pending != expect_pending:
			pending_mismatch.append(tick)
		if is_active != not expect_pending:
			active_mismatch.append(tick)
		if is_pending and is_active:
			overlap_violation.append(tick)
		if is_pending:
			saw_pending = true
		if prev_pending and not is_pending:
			crossing_ticks.append(tick)
		prev_pending = is_pending

	SignalBus.distraction_spawned.disconnect(_on_spawned)

	_check("_pending_spawn_points() agreed with the spec reimplementation on every tick",
		pending_mismatch.is_empty(), "mismatches at ticks: %s" % str(pending_mismatch))
	_check("_active_spawn_point_cells() agreed with the spec reimplementation on every tick",
		active_mismatch.is_empty(), "mismatches at ticks: %s" % str(active_mismatch))
	_check("a point is never BOTH pending and active on the same tick",
		overlap_violation.is_empty(), "violations at ticks: %s" % str(overlap_violation))
	_check("the point actually WAS observed pending at some point in the run", saw_pending)
	_check("the telegraph crossed to live EXACTLY once (a single pending->live transition)",
		crossing_ticks.size() == 1, "transitions at ticks: %s" % str(crossing_ticks))

	# ----------------------------------------------------------- check 3: the payoff
	var before_wrong := 0
	var before_count := 0
	var after_hit_tele := 0
	var after_count := 0
	for rec: Dictionary in _spawn_log:
		var cell: Vector2i = rec.cell
		var elapsed: float = rec.elapsed
		if elapsed < LEAD_TIME:
			before_count += 1
			if cell != CELL_BASE:
				before_wrong += 1
		else:
			after_count += 1
			if cell == CELL_TELE:
				after_hit_tele += 1

	_check("some entries actually popped before the point went live (the check below means something)",
		before_count > 0, "before_count=%d" % before_count)
	_check("NOTHING spawned before lead time ever appeared at the telegraphed cell",
		before_wrong == 0, "%d/%d pre-crossing spawns were NOT CELL_BASE" % [before_wrong, before_count])
	_check("some entries popped after the point went live",
		after_count > 0, "after_count=%d" % after_count)
	_check("at least one real post-crossing spawn landed at the EXACT announced cell (sp.cell)",
		after_hit_tele > 0, "after_count=%d hit_tele=%d" % [after_count, after_hit_tele])
	_check("every spawn this run happened at exactly one of the two real points (no third cell)",
		before_wrong == 0 and _spawn_log.all(func(r): return r.cell == CELL_BASE or r.cell == CELL_TELE),
		"total spawns=%d" % _spawn_log.size())

	# Bonus (not required by the spec, cheap to check): on a LATER wave the same point is
	# active from elapsed=0 — the gate only ever holds back its OWN activation wave, never
	# re-telegraphing every wave (SpawnPointData.telegraph_lead_time's own doc comment).
	_check("on a later wave the point is active from elapsed=0 (no re-telegraphing)",
		game._active_spawn_point_cells(2, 0.0).has(CELL_TELE))

	game.queue_free()
	await get_tree().process_frame

	completed = true
	print("\n%s (%d failures)" % ["PASSED" if fails == 0 else "FAILED", fails])
	get_tree().quit(1 if fails > 0 else 0)
