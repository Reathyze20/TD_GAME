extends Node
## Correctness + bench harness for FlowField (docs/refactor/PATHFINDING.MD P1).
##
## Two halves, deliberately on different data:
##  * Correctness runs on a small SYNTHETIC maze (built here, not loaded from data/)
##    so the wall layout and the expected-unreachable pocket are exact and legible —
##    a real level's high_ground would work too, but a reader would have to go count
##    cells in a .tres to see WHY a given cell is supposed to be unreachable.
##  * The bench runs on the REAL, currently-shipped grid and level geometry
##    (Data.GRID + a real level's high_ground/objective), because P1's own "Hotovo"
##    text asks for "největší mapě" — the actual largest map that exists, not a
##    synthetic stand-in.

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
#   0 1 2 3 4 5 6 7   x
# 0 T . . # . . . .
# 1 . . . # . . . .
# 2 . . . # . . . .
# 3 . . . # . . . .
# 4 . . . # . . . .
# 5 . . . # . . . .
# 6 . . . . . . . P
# 7 . . . . . . P P
# y
#
# T = target (0,0). # = wall, spanning y 0..5 at x=3 -- everything right of it must
# detour through the open row at y=6/7 to reach the target, which is what actually
# exercises multi-step gradient descent rather than a straight line.
# P = the isolated pocket: (7,7)'s only two in-bounds neighbors, (6,7) and (7,6), are
# both walled, so (7,7) itself is free but has no route to the target at all.
const MAZE_COLS := 8
const MAZE_ROWS := 8
const MAZE_TARGET := Vector2i(0, 0)
const MAZE_UNREACHABLE := Vector2i(7, 7)

func _build_maze() -> Dictionary:
	var blocked := {}
	for y in range(0, 6):
		blocked[Vector2i(3, y)] = true
	blocked[Vector2i(6, 7)] = true
	blocked[Vector2i(7, 6)] = true
	return blocked

func _run_correctness() -> void:
	print("\n== correctness: synthetic maze ==")
	var blocked := _build_maze()
	var field := FlowField.build(MAZE_COLS, MAZE_ROWS, MAZE_TARGET, blocked)

	_check("target has distance 0", field.distance(MAZE_TARGET) == 0,
		"(got %d)" % field.distance(MAZE_TARGET))
	_check("target's own direction is ZERO (nowhere closer to go)",
		field.direction(MAZE_TARGET) == Vector2i.ZERO)

	# The one thing a shared field must never do: confuse "unreachable" with "just far".
	_check("the walled-off pocket has NO record at all",
		not field.has_cell(MAZE_UNREACHABLE))
	_check("...and querying it anyway returns the documented sentinels, not garbage",
		field.distance(MAZE_UNREACHABLE) == -1 and field.direction(MAZE_UNREACHABLE) == Vector2i.ZERO)

	# The actual "gradient" property, checked from EVERY free cell (not just a sampled
	# path): the neighbor named by this cell's own direction must be one step closer to
	# the target. If that holds everywhere, following direction() from any reachable
	# cell is guaranteed to reach the target in exactly distance() steps.
	var checked := 0
	var descent_ok := true
	var bad_cell := Vector2i.ZERO
	for y in range(MAZE_ROWS):
		for x in range(MAZE_COLS):
			var cell := Vector2i(x, y)
			if blocked.has(cell) or cell == MAZE_TARGET or not field.has_cell(cell):
				continue
			checked += 1
			var dir: Vector2i = field.direction(cell)
			var stepped: Vector2i = cell + dir
			var d: int = field.distance(cell)
			if not field.has_cell(stepped) or field.distance(stepped) != d - 1:
				descent_ok = false
				bad_cell = cell
				break
		if not descent_ok:
			break
	_check("every free reachable cell's gradient points one step closer to the target",
		descent_ok and checked > 0,
		"checked %d cells%s" % [checked, "" if descent_ok else (" — first failure at %s" % bad_cell)])

	# Exact reachable count, not just "some cells reached": 8x8=64 cells, 6 wall cells,
	# 2 pocket-sealing cells, 1 unreachable free cell (the pocket) = 64-6-2-1 = 55.
	var expected_reached := MAZE_COLS * MAZE_ROWS - blocked.size() - 1
	_check("exactly the expected number of cells were reached",
		field.reached_cells().size() == expected_reached,
		"(got %d, expected %d)" % [field.reached_cells().size(), expected_reached])

	# A target that is itself blocked, or off the grid, is a valid question with a valid
	# (empty) answer -- never a crash.
	var solid_target := FlowField.build(MAZE_COLS, MAZE_ROWS, Vector2i(3, 3), blocked)
	_check("a blocked target yields an empty field, not a crash",
		solid_target.reached_cells().is_empty())
	var oob_target := FlowField.build(MAZE_COLS, MAZE_ROWS, Vector2i(-1, -1), blocked)
	_check("an out-of-bounds target yields an empty field, not a crash",
		oob_target.reached_cells().is_empty())

# ---------------------------------------------------------------- bench, on the real map

const BENCH_ITERATIONS := 50
const BENCH_BUDGET_USEC := 5000  # P1's own "Hotovo": pod 5 ms na největší mapě.

func _run_bench() -> void:
	print("\n== bench: real grid ==")
	var g = Data.GRID
	var level: LevelData = Data.get_level(0)
	var blocked := {}
	for c: Vector2i in level.high_ground:
		blocked[c] = true

	# One untimed warm-up build so a first-run JIT/allocation hiccup (if any) doesn't
	# skew the very first timed sample.
	FlowField.build(int(g.cols), int(g.rows), level.objective, blocked)

	var start := Time.get_ticks_usec()
	for _i in range(BENCH_ITERATIONS):
		FlowField.build(int(g.cols), int(g.rows), level.objective, blocked)
	var elapsed := Time.get_ticks_usec() - start
	var avg_usec := elapsed / float(BENCH_ITERATIONS)

	_check("recompute averages under %d us (%.1f ms) on the %dx%d grid (level %d, %d walls)"
			% [BENCH_BUDGET_USEC, BENCH_BUDGET_USEC / 1000.0, int(g.cols), int(g.rows),
				level.id, blocked.size()],
		avg_usec < BENCH_BUDGET_USEC,
		"avg=%.1f us over %d runs" % [avg_usec, BENCH_ITERATIONS])

func _run() -> void:
	_run_correctness()
	_run_bench()

	completed = true
	if fails > 0:
		print("\n%d FAILED" % fails)
		get_tree().quit(1)
	else:
		print("\nALL PASS")
		get_tree().quit(0)
