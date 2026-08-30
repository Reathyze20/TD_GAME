extends Node
## P6 (docs/refactor/PATHFINDING.MD): proves SpawnPointData's wave-gating actually works,
## in three checks that lean on nothing but each other's fixture:
##
##  1. REACHABILITY — builds ONE shared FlowField (P1) from a synthetic multi-spawn
##     level's objective/high_ground, exactly the way AntiBlockValidator (P2) already
##     does it (scripts/anti_block_validator.gd's own header), and confirms every spawn
##     point active on any given wave has a route. "Flow field se NEMĚNÍ" (P6's own
##     text) means this is ONE field build, read for every wave — not one per wave.
##  2. GATING WIRING — instantiates a real Game on that level and calls its ACTUAL
##     Game._active_spawn_point_cells()/_random_spawn_cell(), not a re-implementation,
##     to prove active_from_wave/requires_segment filtering is wired correctly per wave.
##  3. PLAYTHROUGH — LevelSimulator.run() (S2) plays the same level to completion with
##     the existing SimStrategyPassive, proving the wave-spawning code path that reads
##     spawn_points doesn't break the simulator.
##
## The fixture level is built ENTIRELY in memory (Resource.new() calls) and appended to
## Data._levels for the lifetime of this one process — NEVER written to a .tres. This
## project's CLAUDE.md forbids hand-editing an existing level's .tres; an in-memory-only
## fixture Resource is a different, unrestricted thing, the same spirit as
## _test_maze_validity.gd's own "sealed"/"open_level" LevelData.new() fixtures and
## _test_sink.gd's/_test_taxonomy.gd's direct `load("res://scenes/Game.tscn")`
## instantiation. Appending to Data's own `_levels` array leans on the same "GDScript has
## no real access control" precedent level_simulator.gd's header already normalizes for
## calling leading-underscore Game methods. Every verify.sh _test_*.tscn run gets a FRESH
## Godot process, so nothing needs to undo this registration afterward.
##
## Needs the process launched with --fixed-fps 60 (see verify.sh's FIXED_FPS_TESTS) for
## the same reason _test_level_simulator.gd/_test_timecontrol.gd do: it drives a real
## LevelSimulator playthrough.

var completed := false
var fails := 0

## Deliberately far outside the range real campaign levels use (those stay small — 1,
## 2, 98 exist today) so this can never collide with real content.
const TEST_LEVEL_ID := 762034

# Fixture geometry, cloned from level id 1's real high_ground/objective (known-good,
# already trusted by every other test that touches it) plus four spawn cells this test
# adds itself, spread across the board so no two share a quadrant.
const CELL_A := Vector2i(0, 5)     # active_from_wave 0 — already active on wave 1
const CELL_B := Vector2i(0, 8)     # active_from_wave 0 — already active on wave 1
const CELL_C := Vector2i(29, 0)    # active_from_wave 2 — joins on wave 2
const CELL_D := Vector2i(0, 13)    # active_from_wave 4 — joins on the final wave
# Sealed in a 1-cell pocket THIS fixture adds to high_ground (see _build_fixture_level)
# and marked requires_segment — must never need to be reachable, at any wave, because
# P8 (segment unlocking) does not exist yet so nothing can ever activate it. Proves
# check #1 demands a route only for spawns that are ACTUALLY active, not for every
# SpawnPointData a level happens to author.
const CELL_E := Vector2i(26, 12)
const POCKET_WALLS: Array[Vector2i] = [Vector2i(25, 12), Vector2i(27, 12), Vector2i(26, 11), Vector2i(26, 13)]

const WAVE_COUNT := 4

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

func _make_spawn(cell: Vector2i, active_from_wave: int, requires_segment: StringName = &"") -> SpawnPointData:
	var sp := SpawnPointData.new()
	sp.cell = cell
	sp.active_from_wave = active_from_wave
	sp.requires_segment = requires_segment
	return sp

## The same active-point filter Game._active_spawn_point_cells() applies, reimplemented
## here ONLY for check #1 (a pure-data reachability sweep with no Game involved at all) —
## check #2 below calls the REAL Game method directly instead of trusting this copy, so a
## bug that made the two disagree cannot hide.
func _expected_active(points: Array[SpawnPointData], wave_number: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for sp in points:
		if sp.active_from_wave > wave_number:
			continue
		if sp.requires_segment != &"":
			continue
		cells.append(sp.cell)
	return cells

func _cells_equal(a: Array[Vector2i], b: Array[Vector2i]) -> bool:
	if a.size() != b.size():
		return false
	var seen := {}
	for c in a:
		seen[c] = true
	for c in b:
		if not seen.has(c):
			return false
	return true

## Clones level id 1's real geometry (objective/high_ground/path settings/wave curve) so
## pathing and combat maths are values every other test already trusts, rather than an
## invented board. spawn_zones is left EMPTY on purpose: with no legacy fallback
## available, a gating bug shows up as a crash (indexing an empty spawn_zone_cells), not
## a silent pass.
func _build_fixture_level(spawn_points: Array[SpawnPointData]) -> LevelData:
	var base: LevelData = null
	for i in range(Data.get_level_count()):
		if Data.get_level(i).id == 1:
			base = Data.get_level(i)
			break
	if base == null:
		return null

	var lv := LevelData.new()
	lv.id = TEST_LEVEL_ID
	lv.display_name = "P6 multispawn fixture (test-only, never a real campaign level)"
	lv.start_dopamine = base.start_dopamine
	# Generous on purpose: this test is about spawn WIRING, not about surviving combat
	# (SimStrategyPassive builds nothing at all), so Focus must never be the thing that
	# ends the run before every wave — and every spawn point active in it — has run.
	lv.focus = 999
	lv.objective = base.objective
	lv.high_ground = base.high_ground.duplicate()
	lv.high_ground.append_array(POCKET_WALLS)
	lv.path_cells = base.path_cells.duplicate()
	lv.path_off_lane_cost = base.path_off_lane_cost
	lv.wave_count = WAVE_COUNT
	lv.wave_curve = base.wave_curve.duplicate()
	lv.spawn_zones = []
	lv.spawn_points = spawn_points
	lv.waves = Data.build_waves(lv)
	return lv

## Registers `lv` the same way Data._ready() registers every level loaded from disk
## (data.gd:249-252) — append then re-sort by id. See the file header for why mutating
## Data's own `_levels` array is the established, safe way to do this for one process.
func _register_fixture(lv: LevelData) -> void:
	Data._levels.append(lv)
	Data._levels.sort_custom(func(a: LevelData, b: LevelData): return a.id < b.id)

func _run_reachability(lv: LevelData, spawn_points: Array[SpawnPointData]) -> void:
	print("== 1: reachability (FlowField, built once) ==")
	var g = Data.GRID
	var blocked := {}
	for c: Vector2i in lv.high_ground:
		blocked[c] = true
	var field := FlowField.build(int(g.cols), int(g.rows), lv.objective, blocked)

	_check("sanity: the sealed pocket really is unreachable",
		not field.has_cell(CELL_E), str(CELL_E))

	var prev_active: Array[Vector2i] = []
	for wave in range(1, WAVE_COUNT + 1):
		var active := _expected_active(spawn_points, wave)
		var unreachable: Array[Vector2i] = []
		for cell in active:
			if not field.has_cell(cell):
				unreachable.append(cell)
		_check("wave %d: every active spawn (%d) has a route to the objective" % [wave, active.size()],
			unreachable.is_empty(), "unreachable: %s" % str(unreachable))
		_check("wave %d: the segment-gated, sealed spawn is never in the active set" % wave,
			not active.has(CELL_E))
		var grew := true
		for c in prev_active:
			if not active.has(c):
				grew = false
		_check("wave %d: active set only grows (never drops a spawn from an earlier wave)" % wave, grew)
		prev_active = active

	_check("by the final wave every non-segment-gated spawn is active",
		_cells_equal(_expected_active(spawn_points, WAVE_COUNT), [CELL_A, CELL_B, CELL_C, CELL_D]),
		str(_expected_active(spawn_points, WAVE_COUNT)))

func _run_gating_wiring(lv_index: int) -> void:
	print("\n== 2: gating wiring (real Game._active_spawn_point_cells / _random_spawn_cell) ==")
	GameState.current_level_index = lv_index
	var game: Game = load("res://scenes/Game.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame

	# Dictionary values can't be statically typed, so plain [A, B] literals stored in one
	# come back as untyped Array at read time — .assign() is the documented way to hand
	# that back into an Array[Vector2i] without a manual element-by-element copy.
	var expectations := {
		1: [CELL_A, CELL_B],
		2: [CELL_A, CELL_B, CELL_C],
		3: [CELL_A, CELL_B, CELL_C],
		4: [CELL_A, CELL_B, CELL_C, CELL_D],
	}
	for wave in expectations.keys():
		var want: Array[Vector2i] = []
		want.assign(expectations[wave])
		var got: Array[Vector2i] = game._active_spawn_point_cells(wave)
		_check("wave %d: Game._active_spawn_point_cells() matches expectations" % wave,
			_cells_equal(got, want), "got %s want %s" % [str(got), str(want)])
		_check("wave %d: the segment-gated spawn never appears" % wave, not got.has(CELL_E))

	# Wave far beyond the level's own wave_count: requires_segment must keep excluding
	# CELL_E regardless of how high the wave number goes — proving the exclusion is
	# really requires_segment, not a coincidence of active_from_wave.
	var far_future: Array[Vector2i] = game._active_spawn_point_cells(999)
	_check("segment-gated spawn stays excluded even at an absurdly high wave number",
		not far_future.has(CELL_E), str(far_future))

	# _random_spawn_cell() must never pick outside the active set for its wave — sampled
	# rather than proven exhaustively, matching this file's own scope (wiring, not RNG).
	for wave in expectations.keys():
		var want: Array[Vector2i] = []
		want.assign(expectations[wave])
		var out_of_set := 0
		for _i in range(30):
			var picked: Vector2i = game._random_spawn_cell(wave)
			if not want.has(picked):
				out_of_set += 1
		_check("wave %d: _random_spawn_cell() (30 draws) never leaves the active set" % wave,
			out_of_set == 0, "%d/30 out of set" % out_of_set)

	game.queue_free()
	await get_tree().process_frame

func _run_playthrough() -> void:
	print("\n== 3: playthrough (LevelSimulator + SimStrategyPassive) ==")
	var sim := LevelSimulator.new()
	add_child(sim)
	var result: Dictionary = await sim.run(TEST_LEVEL_ID, 20260830, SimStrategyPassive.new())
	sim.queue_free()
	await get_tree().process_frame

	_check("result dict is non-empty", not result.is_empty(), str(result))
	if result.is_empty():
		return
	_check("did not time out (10 simulated minutes were enough)", not result.get("timed_out", true),
		str(result))
	# LevelSimulator._snapshot()'s "wave" is Game.wave_index, which is 0-based and holds
	# steady at its last value (level.waves.size() - 1, i.e. WAVE_COUNT - 1) once
	# _check_wave_progress() fires game_over(true) on the final wave — it never becomes
	# WAVE_COUNT itself, since nothing increments it again after that.
	_check("the level actually reached its own final wave", result.get("wave", -1) == WAVE_COUNT - 1,
		"wave=%s (0-based, want %d)" % [str(result.get("wave")), WAVE_COUNT - 1])
	# 999 Focus against a worst case of 4 waves x <=11 doomscrolls x 2 focus_damage each
	# (roundi(5 + 2.0*3) = 11 on the last wave) is comfortably survivable even if every
	# single unit reaches the objective unimpeded (SimStrategyPassive builds nothing) —
	# so a real defeat here would mean spawning broke, not that the fixture was too harsh.
	_check("survived to victory (spawn_points wiring did not silently break the level)",
		result.get("victory", false) == true, str(result))

func _run() -> void:
	var spawn_points: Array[SpawnPointData] = [
		_make_spawn(CELL_A, 0),
		_make_spawn(CELL_B, 0),
		_make_spawn(CELL_C, 2),
		_make_spawn(CELL_D, 4),
		_make_spawn(CELL_E, 0, &"future_segment"),
	]
	var lv := _build_fixture_level(spawn_points)
	_check("fixture level built (level id 1 exists to clone geometry from)", lv != null)
	if lv == null:
		completed = true
		print("\nFAILED (%d failures) — could not build fixture" % (fails + 1))
		get_tree().quit(1)
		return

	_run_reachability(lv, spawn_points)

	var lv_index := Data.get_level_count()
	_register_fixture(lv)
	await _run_gating_wiring(lv_index)
	await _run_playthrough()

	completed = true
	print("\n%s (%d failures)" % ["PASSED" if fails == 0 else "FAILED", fails])
	get_tree().quit(1 if fails > 0 else 0)
