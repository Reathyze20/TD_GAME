extends Node
## Characterization harness for PathMetrics (docs/refactor/MIGRATION.MD T9). Pure
## math, no Game instantiation needed — everything under test takes plain cell lists
## and a `solid` dictionary, never a live Game/AStarGrid2D.
##
## Degenerate cases named explicitly in T9's own "hotovo když": a path of length 1,
## a path that doubles back over itself, and a maze with a dead-end branch.

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

## Shorthand: real distance between two cells' centers, for building expected values
## without hardcoding grid geometry the test would otherwise have to keep in sync with.
func _d(a: Vector2i, b: Vector2i) -> float:
	return GridProjection.cell_center(a).distance_to(GridProjection.cell_center(b))

func _run() -> void:
	print("\n== is_contiguous ==")
	_check("a straight 4-cell line is contiguous",
		PathMetrics.is_contiguous([Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)]))
	_check("an empty path is trivially contiguous", PathMetrics.is_contiguous([]))
	_check("a length-1 path is trivially contiguous (nothing to check between)",
		PathMetrics.is_contiguous([Vector2i(5, 5)]))
	_check("a diagonal jump is NOT a legal step",
		not PathMetrics.is_contiguous([Vector2i(0, 0), Vector2i(1, 1)]))
	_check("a teleport gap is NOT contiguous",
		not PathMetrics.is_contiguous([Vector2i(0, 0), Vector2i(5, 0)]))
	_check("a path that doubles back over itself is STILL contiguous (each step is legal)",
		PathMetrics.is_contiguous([Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0),
			Vector2i(1, 0), Vector2i(0, 0)]))

	print("\n== path_length ==")
	_check("empty path has zero length", is_equal_approx(PathMetrics.path_length([]), 0.0))
	_check("a length-1 path has zero length (nowhere to walk)",
		is_equal_approx(PathMetrics.path_length([Vector2i(3, 3)]), 0.0))
	var a := Vector2i(2, 2)
	var b := Vector2i(3, 2)
	var c := Vector2i(3, 3)
	var straight_expected := _d(a, b) + _d(b, c)
	_check("a 3-cell path sums exactly the two real segment distances",
		is_equal_approx(PathMetrics.path_length([a, b, c]), straight_expected),
		"%.3f vs %.3f" % [PathMetrics.path_length([a, b, c]), straight_expected])
	var backtrack := [a, b, c, b, a]
	var backtrack_expected := straight_expected * 2.0
	_check("a path that doubles back over itself counts the return trip too, not deduped",
		is_equal_approx(PathMetrics.path_length(backtrack), backtrack_expected),
		"%.3f vs %.3f" % [PathMetrics.path_length(backtrack), backtrack_expected])

	print("\n== distance_along ==")
	var path := [a, b, c]
	_check("distance_along index 0 is zero", is_equal_approx(PathMetrics.distance_along(path, 0), 0.0))
	_check("distance_along the last index equals the whole path_length",
		is_equal_approx(PathMetrics.distance_along(path, 2), PathMetrics.path_length(path)))
	_check("distance_along a middle index matches the partial sum",
		is_equal_approx(PathMetrics.distance_along(path, 1), _d(a, b)))
	_check("a negative index clamps to 0 (distance 0)",
		is_equal_approx(PathMetrics.distance_along(path, -5), 0.0))
	_check("an index past the end clamps to the full length",
		is_equal_approx(PathMetrics.distance_along(path, 99), PathMetrics.path_length(path)))
	_check("distance_along an empty path is zero", is_equal_approx(PathMetrics.distance_along([], 0), 0.0))

	print("\n== position_at_distance ==")
	_check("distance 0 returns the first cell's center",
		PathMetrics.position_at_distance(path, 0.0).is_equal_approx(GridProjection.cell_center(a)))
	_check("a negative distance clamps to the first cell too",
		PathMetrics.position_at_distance(path, -50.0).is_equal_approx(GridProjection.cell_center(a)))
	_check("a distance at exactly the first segment's length lands on cell b",
		PathMetrics.position_at_distance(path, _d(a, b)).is_equal_approx(GridProjection.cell_center(b)))
	_check("a distance beyond the whole path clamps to the last cell",
		PathMetrics.position_at_distance(path, PathMetrics.path_length(path) + 1000.0)
			.is_equal_approx(GridProjection.cell_center(c)))
	var halfway := GridProjection.cell_center(a).lerp(GridProjection.cell_center(b), 0.5)
	_check("halfway into the first segment lerps between its two cells",
		PathMetrics.position_at_distance(path, _d(a, b) * 0.5).is_equal_approx(halfway),
		"%s vs %s" % [PathMetrics.position_at_distance(path, _d(a, b) * 0.5), halfway])
	_check("a length-1 path returns that cell regardless of distance asked",
		PathMetrics.position_at_distance([c], 500.0).is_equal_approx(GridProjection.cell_center(c)))
	_check("an empty path returns Vector2.ZERO rather than crashing",
		PathMetrics.position_at_distance([], 10.0) == Vector2.ZERO)

	print("\n== shortest_path / is_reachable — open grid ==")
	var open := {}
	var sp := PathMetrics.shortest_path(Vector2i(0, 0), Vector2i(3, 0), open, 10, 10)
	_check("a straight open corridor finds the direct 4-cell route",
		sp == [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)], str(sp))
	_check("is_reachable agrees", PathMetrics.is_reachable(Vector2i(0, 0), Vector2i(3, 0), open, 10, 10))
	_check("from == to returns the single-cell path",
		PathMetrics.shortest_path(Vector2i(2, 2), Vector2i(2, 2), open, 10, 10) == [Vector2i(2, 2)])

	print("\n== shortest_path — blocked / out of bounds ==")
	var wall := {}
	for y in range(10):
		wall[Vector2i(5, y)] = true
	_check("a solid column with no gap makes the far side unreachable",
		not PathMetrics.is_reachable(Vector2i(0, 0), Vector2i(9, 0), wall, 10, 10))
	_check("shortest_path returns empty (not a partial route) when unreachable",
		PathMetrics.shortest_path(Vector2i(0, 0), Vector2i(9, 0), wall, 10, 10) == [])
	wall.erase(Vector2i(5, 4))
	_check("opening exactly one gap in the wall makes it reachable again",
		PathMetrics.is_reachable(Vector2i(0, 0), Vector2i(9, 0), wall, 10, 10))
	_check("a solid `from` cell is unreachable from anywhere",
		not PathMetrics.is_reachable(Vector2i(5, 0), Vector2i(0, 0), wall, 10, 10))
	_check("a solid `to` cell can't be reached",
		not PathMetrics.is_reachable(Vector2i(0, 0), Vector2i(5, 0), wall, 10, 10))
	_check("an out-of-bounds `from` is unreachable, not a crash",
		not PathMetrics.is_reachable(Vector2i(-1, 0), Vector2i(0, 0), open, 10, 10))
	_check("an out-of-bounds `to` is unreachable, not a crash",
		not PathMetrics.is_reachable(Vector2i(0, 0), Vector2i(50, 50), open, 10, 10))

	print("\n== shortest_path — a maze with a dead-end branch ==")
	# 5x5 grid. Solid everywhere except a straight corridor along y=2 from x=0 to x=4,
	# PLUS a dead-end branch poking up from (2,2) to (2,0) that leads nowhere useful.
	# The real route from (0,2) to (4,2) must ignore the branch entirely.
	var maze := {}
	for y in range(5):
		for x in range(5):
			maze[Vector2i(x, y)] = true
	for x in range(5):
		maze.erase(Vector2i(x, 2))
	maze.erase(Vector2i(2, 1))
	maze.erase(Vector2i(2, 0))
	var maze_path := PathMetrics.shortest_path(Vector2i(0, 2), Vector2i(4, 2), maze, 5, 5)
	_check("the dead-end branch doesn't fool the search into a longer/wrong route",
		maze_path == [Vector2i(0, 2), Vector2i(1, 2), Vector2i(2, 2), Vector2i(3, 2), Vector2i(4, 2)],
		str(maze_path))
	_check("reachability is unaffected by the dead-end branch's presence",
		PathMetrics.is_reachable(Vector2i(0, 2), Vector2i(4, 2), maze, 5, 5))
	_check("the dead end itself is reachable too (it's open ground, just goes nowhere new)",
		PathMetrics.is_reachable(Vector2i(0, 2), Vector2i(2, 0), maze, 5, 5))
	_check("but the dead end is NOT on the shortest route to the real objective",
		not maze_path.has(Vector2i(2, 0)) and not maze_path.has(Vector2i(2, 1)))

	completed = true
	print("\n%s (%d failures)" % ["PASSED" if fails == 0 else "FAILED", fails])
	get_tree().quit(1 if fails > 0 else 0)
