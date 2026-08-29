class_name PathMetrics
extends RefCounted
## Render-independent path/maze analysis (docs/refactor/MIGRATION.MD T9). Everything
## here operates on plain cell lists (Array of Vector2i) and screen positions via
## GridProjection.cell_center() — no Game, no scene tree, no live AStarGrid2D
## reference required. Built because at least five places in this codebase each
## reimplement "is there a path" or "how long is it" slightly differently
## (tools/map_editor.gd's hand-rolled BFS, scripts/_test_levels.gd's inline
## connectivity loop, and three one-line test-file wrappers — see PROGRESS.md's T9
## entry) — and because NOTHING anywhere computed real-world path length; every
## existing "length" check measures Array.size() (step count), not distance.
##
## Deliberately does NOT replace game.gd's live AStarGrid2D usage, which is WEIGHTED
## (honors LevelData.path_off_lane_cost) and tightly coupled to live Game state
## (repathing every distraction whenever the maze changes) — that answers a
## genuinely different question (the cheapest route under the live game's own rules)
## from what this module answers (an unweighted, stateless "is this reachable / how
## long is the plain shortest route", and "given a route someone already found, what
## can be said about it"). Existing duplicate implementations are not migrated onto
## this in the same change that introduces it — see PROGRESS.md for why.

## The four cardinal neighbor offsets. 4-connectivity only, matching every
## pathfinding engine already in this project (game.gd's AStarGrid2D has
## diagonal_mode = DIAGONAL_MODE_NEVER; map_editor.gd's BFS is 4-way only too).
const NEIGHBORS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

## True if every consecutive pair of cells in `cells` is a legal single 4-connected
## step (differs by exactly one cardinal neighbor offset). A path of length 0 or 1 is
## trivially contiguous — there is nothing between them to check. Catches a
## corrupted/malformed route (e.g. built by concatenating two unrelated cell lists)
## that a length or reachability check alone would not notice.
static func is_contiguous(cells: Array) -> bool:
	for i in range(cells.size() - 1):
		var delta: Vector2i = cells[i + 1] - cells[i]
		if not NEIGHBORS.has(delta):
			return false
	return true

## Real-world length of walking `cells` in order: the sum of the screen distance
## between each consecutive pair's cell_center(). Deliberately NOT cell count — see
## the file header. A path that revisits a cell (doubles back on itself) is walked
## exactly as given: revisited ground is counted again, because that is what actually
## walking it costs.
static func path_length(cells: Array) -> float:
	var total := 0.0
	for i in range(cells.size() - 1):
		total += GridProjection.cell_center(cells[i]).distance_to(GridProjection.cell_center(cells[i + 1]))
	return total

## Cumulative real-world distance from cells[0] to cells[upto_index] (inclusive).
## Clamped to the path's own ends: an index below 0 reads as 0 (distance 0), an index
## past the last cell reads as the last cell (the whole path's length).
static func distance_along(cells: Array, upto_index: int) -> float:
	if cells.is_empty():
		return 0.0
	var idx := clampi(upto_index, 0, cells.size() - 1)
	var total := 0.0
	for i in range(idx):
		total += GridProjection.cell_center(cells[i]).distance_to(GridProjection.cell_center(cells[i + 1]))
	return total

## The screen position `distance` world-units along `cells`, measured from cells[0].
## Interpolates linearly between the two cells straddling that distance. Clamped: a
## distance at or below 0 returns the first cell's center, a distance at or beyond the
## path's total length returns the last cell's center — this never extrapolates past
## either end. A single-cell path always returns that one cell's center.
static func position_at_distance(cells: Array, distance: float) -> Vector2:
	if cells.is_empty():
		return Vector2.ZERO
	if cells.size() == 1 or distance <= 0.0:
		return GridProjection.cell_center(cells[0])
	var remaining := distance
	for i in range(cells.size() - 1):
		var a := GridProjection.cell_center(cells[i])
		var b := GridProjection.cell_center(cells[i + 1])
		var seg := a.distance_to(b)
		if remaining <= seg:
			return a.lerp(b, 0.0 if seg <= 0.0 else remaining / seg)
		remaining -= seg
	return GridProjection.cell_center(cells[cells.size() - 1])

## Unweighted 4-connectivity shortest path from `from` to `to`, treating every cell in
## `solid` as impassable. Returns the cell list INCLUSIVE of both ends, or an empty
## array if `to` is unreachable — including when `from`/`to` is itself solid or out of
## a `cols`x`rows` grid. Plain BFS: see the file header for why this does not need to
## be (and deliberately is not) the weighted search game.gd's live routing uses.
static func shortest_path(from: Vector2i, to: Vector2i, solid: Dictionary, cols: int, rows: int) -> Array:
	if from.x < 0 or from.x >= cols or from.y < 0 or from.y >= rows:
		return []
	if to.x < 0 or to.x >= cols or to.y < 0 or to.y >= rows:
		return []
	if solid.has(from) or solid.has(to):
		return []
	if from == to:
		return [from]

	var came_from := {from: from}
	var queue: Array = [from]
	var head := 0
	while head < queue.size():
		var cur: Vector2i = queue[head]
		head += 1
		if cur == to:
			break
		for off in NEIGHBORS:
			var n: Vector2i = cur + off
			if n.x < 0 or n.x >= cols or n.y < 0 or n.y >= rows:
				continue
			if solid.has(n) or came_from.has(n):
				continue
			came_from[n] = cur
			queue.append(n)

	if not came_from.has(to):
		return []
	var path: Array = [to]
	var walk: Vector2i = to
	while walk != from:
		walk = came_from[walk]
		path.append(walk)
	path.reverse()
	return path

## True if `to` is reachable from `from` under the same rules as shortest_path().
static func is_reachable(from: Vector2i, to: Vector2i, solid: Dictionary, cols: int, rows: int) -> bool:
	return not shortest_path(from, to, solid, cols, rows).is_empty()
