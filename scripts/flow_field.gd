class_name FlowField
extends RefCounted
## Single distance field computed by one BFS from a target cell, shared by every unit
## that needs a direction toward it (docs/refactor/PATHFINDING.MD P1) — one flood fill
## instead of one A* search per distraction.
##
## 4-connectivity only, matching every other pathfinding engine already in this
## project (game.gd's `AStarGrid2D` has `diagonal_mode = DIAGONAL_MODE_NEVER`;
## `PathMetrics`' own `NEIGHBORS` is the same four offsets) — same connectivity, same
## notion of "blocked", so a unit moved onto this field sees the same maze it saw on
## A*.
##
## Deliberately UNWEIGHTED, matching P1's own wording ("Jeden distance field BFS").
## `PathMetrics`' header already draws this line for a sibling module: game.gd's live
## `AStarGrid2D` is WEIGHTED (it honors `LevelData.path_off_lane_cost`) and answers "the
## cheapest route under the live game's own rules"; this answers a different, simpler
## question ("how many steps to the target, and which way is that"). Whether — and
## how — live distractions should read this field instead of their own A* search is a
## separate decision the queue names explicitly (P4, "jednotky na flow fieldu"); this
## class does not touch game.gd's movement and nothing calls `build()` from live code
## yet.
##
## A cell the BFS never reaches (walled off from the target, or simply out of bounds)
## carries NO entry in either dictionary below — not a sentinel distance like -1 stored
## alongside real ones. That is the one thing a shared field must get right: every unit
## reads the SAME field, so "never computed" and "computed but unreachable" must be
## impossible to confuse from the outside. `has_cell()` is the one true reachability
## check; `distance()`/`direction()` exist for callers that already checked it.

const NEIGHBORS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
]

var cols: int = 0
var rows: int = 0
var target: Vector2i = Vector2i.ZERO

## Vector2i -> int. Absent means the BFS never reached that cell.
var _distance: Dictionary = {}
## Vector2i -> Vector2i, one of NEIGHBORS. The single axis step that decreases
## distance by exactly 1 — i.e. the gradient. Vector2i.ZERO at the target itself
## (nowhere closer to go). Absent wherever `_distance` is absent, always.
var _direction: Dictionary = {}

## `blocked` is a Dictionary used as a set (Vector2i -> true), matching every other
## solid-cell set in this codebase (game.gd's own `high_ground`). A target that is
## itself blocked, or outside [0,cols)x[0,rows), yields a field with nothing in it
## rather than an error — "no path exists" is a valid answer, not a crash.
static func build(cols: int, rows: int, target: Vector2i, blocked: Dictionary) -> FlowField:
	var field := FlowField.new()
	field._compute(cols, rows, target, blocked)
	return field

func _compute(cols_: int, rows_: int, target_: Vector2i, blocked: Dictionary) -> void:
	cols = cols_
	rows = rows_
	target = target_
	_distance.clear()
	_direction.clear()

	if not _in_bounds(target) or blocked.has(target):
		return

	_distance[target] = 0
	_direction[target] = Vector2i.ZERO

	# Array + a head index, NOT pop_front(): pop_front() on a GDScript Array is O(n)
	# (it shifts every remaining element down), which would turn this BFS quadratic on
	# a board with hundreds of free cells. Indexing forward through a single Array that
	# only ever grows keeps every step O(1) amortized.
	var frontier: Array[Vector2i] = [target]
	var head := 0
	while head < frontier.size():
		var cell: Vector2i = frontier[head]
		head += 1
		var d: int = _distance[cell]
		for step: Vector2i in NEIGHBORS:
			var n: Vector2i = cell + step
			if not _in_bounds(n) or blocked.has(n) or _distance.has(n):
				continue
			_distance[n] = d + 1
			# n was discovered FROM cell (n == cell + step), so the step that walks
			# from n back toward the lower-distance side is the reverse of `step`.
			_direction[n] = -step
			frontier.append(n)

func _in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < cols and c.y < rows

## The one true reachability check — see the class header for why a caller must use
## this rather than inferring reachability from `distance()`'s return value.
func has_cell(cell: Vector2i) -> bool:
	return _distance.has(cell)

## -1 for a cell with no entry. Callers that have not called `has_cell()` first get an
## unambiguous sentinel rather than a silent wrong number (0 would collide with the
## target itself).
func distance(cell: Vector2i) -> int:
	return _distance.get(cell, -1)

## Vector2i.ZERO for a cell with no entry (indistinguishable from "already at the
## target" by design — a caller that skips `has_cell()` gets "don't move", never a
## direction pointing into a wall or off the board).
func direction(cell: Vector2i) -> Vector2i:
	return _direction.get(cell, Vector2i.ZERO)

## Every cell the BFS reached, for callers that need to iterate the whole field
## (benchmarks, tests) rather than query it cell by cell.
func reached_cells() -> Array:
	return _distance.keys()
