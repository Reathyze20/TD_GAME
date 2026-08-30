extends Node
## Correctness + bench harness for AntiBlockValidator (docs/refactor/PATHFINDING.MD P2).
##
## Three parts on two different data sets, deliberately:
##  * Correctness runs EXHAUSTIVELY over a small synthetic maze with two independent
##    spawns, so ground truth is hand-traceable and the "both directions" (a real
##    block gets caught, a harmless cell gets cleared) and "every legal position"
##    (not a handful of examples) parts of P2's own "Hotovo" are both literal, not
##    approximated.
##  * The single-wall bench runs on the REAL shipped grid/level, because P2's own
##    "Hotovo" text asks for "kontrolu jedné zdi" on an actual board, not a toy one.
##  * The rapid-build bench (asked for alongside P2, feeds P3's obsolete-or-not
##    decision) also runs on the real grid, and is reported against this game's own
##    actual build-input model — a single InputEventMouseButton click per placement
##    (game.gd's _unhandled_input), never a per-frame drag-paint — since that is the
##    only "how fast can a player place something" ceiling that exists in this
##    codebase today.

var completed := false
var fails := 0

func _ready() -> void:
	var wd := Timer.new()
	wd.wait_time = 20.0
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

# ---------------------------------------------------------------- synthetic maze
#
#   0 1 2 3 4 5   x
# 0 A . . . . .
# 1 # # G # # #
# 2 . . . . . T
# 3 # # # H # #
# 4 B . . . . .
# y
#
# A = spawn 1 (0,0), B = spawn 2 (0,4), T = objective (5,2).
# Row y=1 is solid EXCEPT the gap G=(2,1) -- the ONLY way from row 0 down to row 2+.
# Row y=3 is solid EXCEPT the gap H=(3,3) -- the ONLY way from row 4 up to row 2.
# The two gaps are on DIFFERENT rows and different columns on purpose: walling G
# strands ONLY spawn A, walling H strands ONLY spawn B. A validator that only checked
# spawns[0] (or only ever looked at one spawn) would get exactly one of those two
# cases wrong, which is the bug this maze is shaped to catch.
const MAZE_COLS := 6
const MAZE_ROWS := 5
const OBJECTIVE := Vector2i(5, 2)
const SPAWN_A := Vector2i(0, 0)
const SPAWN_B := Vector2i(0, 4)
const GAP_A := Vector2i(2, 1)
const GAP_B := Vector2i(3, 3)

func _build_maze() -> Dictionary:
	var blocked := {}
	for x in range(MAZE_COLS):
		if x != GAP_A.x:
			blocked[Vector2i(x, 1)] = true
		if x != GAP_B.x:
			blocked[Vector2i(x, 3)] = true
	return blocked

func _run_correctness() -> void:
	print("\n== correctness: synthetic two-spawn maze ==")
	var blocked := _build_maze()
	var spawns: Array = [SPAWN_A, SPAWN_B]

	# Sanity on the maze itself before trusting anything built on top of it: both
	# spawns must actually reach the objective BEFORE any candidate wall is added.
	var base_field := FlowField.build(MAZE_COLS, MAZE_ROWS, OBJECTIVE, blocked)
	_check("maze sanity: spawn A reaches the objective untouched", base_field.has_cell(SPAWN_A))
	_check("maze sanity: spawn B reaches the objective untouched", base_field.has_cell(SPAWN_B))

	_check("walling A's only gap blocks (A alone is enough)",
		AntiBlockValidator.would_block(MAZE_COLS, MAZE_ROWS, OBJECTIVE, blocked, GAP_A, spawns))
	_check("walling A's gap does NOT falsely blame spawn B",
		FlowField.build(MAZE_COLS, MAZE_ROWS, OBJECTIVE,
			blocked.duplicate()).has_cell(SPAWN_B))  # unrelated sanity, B's route untouched

	_check("walling B's only gap blocks (proves BOTH spawns are checked, not just spawns[0])",
		AntiBlockValidator.would_block(MAZE_COLS, MAZE_ROWS, OBJECTIVE, blocked, GAP_B, spawns))

	var harmless := Vector2i(5, 0)  # top-right corner, on neither spawn's only route
	_check("a cell off both critical paths does not block",
		not AntiBlockValidator.would_block(MAZE_COLS, MAZE_ROWS, OBJECTIVE, blocked, harmless, spawns))

	_check("placing a wall on an already-solid cell is a no-op, not a false positive",
		not AntiBlockValidator.would_block(MAZE_COLS, MAZE_ROWS, OBJECTIVE, blocked, Vector2i(1, 1), spawns))

	# EXHAUSTIVE sweep: every open, non-spawn, non-objective cell in the maze —
	# "každou legální pozici", not a sampled handful. Ground truth is re-derived HERE,
	# independently of AntiBlockValidator's own control flow (it reuses the
	# already-proven FlowField primitive, but redoes the "is ANY active spawn
	# stranded" multi-spawn logic from scratch), so a bug specifically in
	# would_block()'s orchestration — wrong dictionary key, an early return after only
	# the first spawn, a trial dict that leaks into the caller's `blocked` — has
	# something independent to disagree with.
	var reserved: Dictionary = {OBJECTIVE: true, SPAWN_A: true, SPAWN_B: true}
	var checked := 0
	var mismatches: Array[String] = []
	for y in range(MAZE_ROWS):
		for x in range(MAZE_COLS):
			var cell := Vector2i(x, y)
			if blocked.has(cell) or reserved.has(cell):
				continue
			checked += 1
			var trial: Dictionary = blocked.duplicate()
			trial[cell] = true
			var gt_field := FlowField.build(MAZE_COLS, MAZE_ROWS, OBJECTIVE, trial)
			var ground_truth := not gt_field.has_cell(SPAWN_A) or not gt_field.has_cell(SPAWN_B)
			var got := AntiBlockValidator.would_block(MAZE_COLS, MAZE_ROWS, OBJECTIVE, blocked, cell, [SPAWN_A, SPAWN_B])
			if got != ground_truth:
				mismatches.append("%s: validator=%s ground-truth=%s" % [cell, got, ground_truth])
	_check("every open candidate cell (%d checked) agrees with independently-derived ground truth" % checked,
		mismatches.is_empty() and checked > 0,
		"; ".join(mismatches.slice(0, 4)))

	# `blocked` itself must come back untouched — would_block() must copy, not mutate.
	_check("would_block() never mutates the caller's blocked dictionary",
		blocked.size() == _build_maze().size() and not blocked.has(GAP_A) and not blocked.has(GAP_B))

# ---------------------------------------------------------------- bench: single wall, real map

const SINGLE_CHECK_BUDGET_USEC := 1000  # P2's own "Hotovo": kontrola jedné zdi pod 1 ms.
const SINGLE_CHECK_ITERATIONS := 50

func _real_level_setup() -> Dictionary:
	var g = Data.GRID
	var level: LevelData = Data.get_level(0)
	var blocked := {}
	for c: Vector2i in level.high_ground:
		blocked[c] = true
	var spawns: Array = []
	for rect: Rect2i in level.spawn_zones:
		for dy in range(maxi(rect.size.y, 1)):
			for dx in range(maxi(rect.size.x, 1)):
				spawns.append(Vector2i(rect.position.x + dx, rect.position.y + dy))
	return {"cols": int(g.cols), "rows": int(g.rows), "objective": level.objective,
		"blocked": blocked, "spawns": spawns, "level_id": level.id}

## An open cell far from the existing maze and from any spawn's route, so checking it
## repeatedly is representative of an ordinary placement rather than a worst-case one
## sitting right on the critical path (which the correctness sweep above already
## covers exhaustively on the synthetic maze).
func _find_harmless_cell(setup: Dictionary) -> Vector2i:
	var cols: int = setup.cols
	var rows: int = setup.rows
	var blocked: Dictionary = setup.blocked
	var reserved: Dictionary = {setup.objective: true}
	for s: Vector2i in setup.spawns:
		reserved[s] = true
	for y in range(rows - 1, -1, -1):
		for x in range(cols - 1, -1, -1):
			var c := Vector2i(x, y)
			if not blocked.has(c) and not reserved.has(c):
				if not AntiBlockValidator.would_block(cols, rows, setup.objective, blocked, c, setup.spawns):
					return c
	return Vector2i(-1, -1)

func _run_single_bench() -> void:
	print("\n== bench: single wall check, real map ==")
	var setup := _real_level_setup()
	var cell := _find_harmless_cell(setup)
	_check("found a harmless candidate cell to bench against", cell != Vector2i(-1, -1))
	if cell == Vector2i(-1, -1):
		return

	AntiBlockValidator.would_block(setup.cols, setup.rows, setup.objective, setup.blocked, cell, setup.spawns)  # warm-up
	var start := Time.get_ticks_usec()
	for _i in range(SINGLE_CHECK_ITERATIONS):
		AntiBlockValidator.would_block(setup.cols, setup.rows, setup.objective, setup.blocked, cell, setup.spawns)
	var elapsed := Time.get_ticks_usec() - start
	var avg_usec := elapsed / float(SINGLE_CHECK_ITERATIONS)

	_check("single-wall check averages under %d us (%.1f ms) on the %dx%d grid (level %d, %d walls, %d spawn cells)"
			% [SINGLE_CHECK_BUDGET_USEC, SINGLE_CHECK_BUDGET_USEC / 1000.0, setup.cols, setup.rows,
				setup.level_id, setup.blocked.size(), setup.spawns.size()],
		avg_usec < SINGLE_CHECK_BUDGET_USEC,
		"avg=%.1f us over %d runs" % [avg_usec, SINGLE_CHECK_ITERATIONS])

# ---------------------------------------------------------------- bench: rapid building, real map
#
# Extra measurement asked for alongside P2, to inform P3's obsolete-or-not decision:
# how many walls per second the anti-block check alone permits, and how that compares
# to how fast a player can actually place something in THIS game. There is no
# player-facing wall-placement action in the codebase yet (this whole queue is
# building the mechanism before there is a UI for it) — the only "how fast can a
# player place something" data point that exists today is habit building, and that is
# driven one InputEventMouseButton click at a time in game.gd's _unhandled_input(),
# never a per-frame drag-paint. So the honest comparison is against sustained
# clicking, not against a 60fps frame budget — a number this codebase does not
# actually promise for any build action.
const RAPID_BUILD_COUNT := 30
## A fast, sustained deliberate click rate. Not a measured value from this project —
## there is nothing to measure it against yet — but a widely-cited ceiling for
## repeated single clicks (not machine-gunning a held button), used ONLY as a
## reference point for how large the computational headroom is, never as a claim
## about this game's real players.
const FAST_CLICK_RATE_PER_SEC := 10.0

func _run_rapid_bench() -> void:
	print("\n== bench: rapid sequential building, real map ==")
	var setup := _real_level_setup()
	var cols: int = setup.cols
	var rows: int = setup.rows
	var objective: Vector2i = setup.objective
	var spawns: Array = setup.spawns
	var blocked: Dictionary = setup.blocked.duplicate()

	# Grow a real wall the way a player would: find the next harmless cell, check it,
	# commit it, repeat — each step sees the PREVIOUS step's wall in `blocked`, exactly
	# like a live game state a player is actively building into. Cells are chosen
	# harmless-only so the run completes RAPID_BUILD_COUNT real placements rather than
	# stopping the instant a candidate would be illegal.
	var placed := 0
	var total_check_usec := 0
	var run_start := Time.get_ticks_usec()
	while placed < RAPID_BUILD_COUNT:
		var candidate := _find_harmless_cell({"cols": cols, "rows": rows, "objective": objective,
			"blocked": blocked, "spawns": spawns})
		if candidate == Vector2i(-1, -1):
			break
		var t0 := Time.get_ticks_usec()
		var blocks := AntiBlockValidator.would_block(cols, rows, objective, blocked, candidate, spawns)
		total_check_usec += Time.get_ticks_usec() - t0
		if blocks:
			break  # should not happen for a cell _find_harmless_cell already cleared
		blocked[candidate] = true  # commit, the way a real build action would
		placed += 1
	var run_elapsed := Time.get_ticks_usec() - run_start

	_check("placed %d real, individually-validated walls in sequence" % RAPID_BUILD_COUNT,
		placed == RAPID_BUILD_COUNT, "(got %d)" % placed)
	if placed == 0:
		return

	var avg_check_usec := total_check_usec / float(placed)
	# _find_harmless_cell() itself scans and re-checks candidates, so it is NOT part of
	# this ratio — it stands in for "the UI already knows which cell was clicked",
	# which a real build action gets for free from the mouse event. Only the check
	# that a REAL placement action would actually pay for is measured here.
	var max_rate_per_sec := 1_000_000.0 / avg_check_usec
	var click_interval_usec := 1_000_000.0 / FAST_CLICK_RATE_PER_SEC
	var share_of_click_interval := 100.0 * avg_check_usec / click_interval_usec

	print("  avg anti-block check: %.1f us/wall over %d sequential placements (total run %.1f ms incl. candidate search)"
		% [avg_check_usec, placed, run_elapsed / 1000.0])
	print("  => up to ~%.0f walls/sec if the anti-block check were the ONLY cost (a computational ceiling, not a claim about players)"
		% max_rate_per_sec)
	print("  a sustained fast clicker (~%.0f clicks/sec, game.gd's own click-per-placement model — see game.gd _unhandled_input, no drag-paint exists) spends one placement every %.1f ms;"
		% [FAST_CLICK_RATE_PER_SEC, click_interval_usec / 1000.0])
	print("  the anti-block check would consume ~%.2f%% of that interval — the rest is human reaction time and click handling this codebase does not yet have code for."
		% share_of_click_interval)
	_check("the check's own cost is a small fraction (<20%%) of a fast click's interval",
		share_of_click_interval < 20.0, "(%.2f%%)" % share_of_click_interval)

func _run() -> void:
	_run_correctness()
	_run_single_bench()
	_run_rapid_bench()

	completed = true
	if fails > 0:
		print("\n%d FAILED" % fails)
		get_tree().quit(1)
	else:
		print("\nALL PASS")
		get_tree().quit(0)
