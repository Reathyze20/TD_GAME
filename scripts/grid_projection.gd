class_name GridProjection
extends RefCounted
## Canonical grid<->screen conversion layer (docs/refactor/MIGRATION.MD T4). EVERY
## place that converts a grid cell to a screen position, a screen position back to a
## cell, or corrects for the board's isometric Y-squash, is meant to go through here.
##
## Still isometric today — this is a pure move, not a behavior change (T4's own
## contract: "chování se nemění"). T5 adds a square top-down variant and switches to
## it. See docs/MIGRATION_AUDIT.md for the full inventory this was built from, and its
## §1.4 for the open question this deliberately does NOT resolve: several radii
## (Routine, Brain Fog, intervention AoE, guard zones) still measure raw screen-space
## distance rather than routing through to_ground()/ground_distance() below. That is
## unchanged on purpose — changing it would be a behavior change T5 should own, not T4.

## How much the board's projection squashes screen-Y relative to true "ground"
## distance. 2.0 for the current 2:1 diamond isometric; a square top-down projection
## would use 1.0 (see T5).
const GROUND_Y_SCALE := 2.0

## Grid cell -> screen position (the cell's center). Moved verbatim from
## Data.cell_center(), which now re-exports this.
static func cell_center(cell: Vector2i) -> Vector2:
	var g = Data.GRID
	var tw: float = float(g.get("tile_w", 64))
	var th: float = float(g.get("tile_h", 32))
	var ox: float = float(g.origin_x)
	var oy: float = float(g.origin_y)
	return Vector2(
		ox + (cell.x - cell.y) * (tw * 0.5),
		oy + (cell.x + cell.y + 1) * (th * 0.5))

## Screen position -> grid cell, clamped to the board. Moved verbatim from
## Data.world_to_cell(), which now re-exports this.
static func world_to_cell(pos: Vector2) -> Vector2i:
	var g = Data.GRID
	var tw: float = float(g.get("tile_w", 64))
	var th: float = float(g.get("tile_h", 32))
	var dx: float = pos.x - float(g.origin_x)
	var dy: float = pos.y - float(g.origin_y)
	var col := int(floorf(dx / tw + dy / th))
	var row := int(floorf(dy / th - dx / tw))
	return Vector2i(clampi(col, 0, int(g.cols) - 1), clampi(row, 0, int(g.rows) - 1))

## Moved verbatim from Data.in_bounds(), which now re-exports this.
static func in_bounds(c: Vector2i) -> bool:
	var g = Data.GRID
	return c.x >= 0 and c.x < int(g.cols) and c.y >= 0 and c.y < int(g.rows)

## Screen-space delta -> ground-space delta (undoes the Y-squash). Ground space is
## where combat range, cones and line-of-sight are measured — a raw screen vector aims
## short in Y, since one screen pixel of Y covers GROUND_Y_SCALE of ground truth.
static func to_ground(screen_delta: Vector2) -> Vector2:
	return Vector2(screen_delta.x, screen_delta.y * GROUND_Y_SCALE)

## Ground-space delta -> screen-space delta (re-applies the Y-squash). The inverse of
## to_ground() — used whenever a direction computed in ground space (an aim angle, a
## line-of-sight ray) needs to become an actual screen-space step or draw vector again.
static func to_screen(ground_delta: Vector2) -> Vector2:
	return Vector2(ground_delta.x, ground_delta.y / GROUND_Y_SCALE)

## Euclidean distance between two screen positions, measured in ground space. What
## "range" means everywhere combat checks it (tower cone, line of sight, auto-aim).
static func ground_distance(a: Vector2, b: Vector2) -> float:
	return to_ground(b - a).length()

## A ground-space angle (e.g. a tower's facing_angle) as a screen-space direction
## vector — for spawning a shot or scattering a split along the direction a habit
## is actually facing. Deliberately NOT normalized after the squash: callers that
## multiply this by a ground-space step (projectile speed*delta, muzzle offset) rely on
## its length already being correct in screen space for that step to land right.
static func ground_dir_to_screen(angle_ground: float) -> Vector2:
	return to_screen(Vector2.RIGHT.rotated(angle_ground))

## Decomposes a screen-space direction into its (grid +X, grid +Y) axis components —
## the same skew world_to_cell() applies to a position, but for a direction rather
## than a point. Used to classify a movement vector into one of the four grid-cardinal
## facings (see Enemy.note_heading()): grid +X and -X land on screen SE/NW diagonals,
## grid +Y and -Y on SW/NE, because the projection tilts the axes.
static func screen_dir_to_grid_axes(dir: Vector2) -> Vector2:
	return Vector2(dir.x / GROUND_Y_SCALE + dir.y, dir.y - dir.x / GROUND_Y_SCALE)

## Position to give a DIAMOND_DOWN isometric TileMapLayer so its own map_to_local()
## agrees with cell_center() above, instead of landing half a tile to its right.
## Godot's own map_to_local() for TILE_LAYOUT_DIAMOND_DOWN returns
## ((x-y+1)*w/2, (x+y+1)*h/2) — the X term carries a "+1" that cell_center()'s
## ((x-y)*w/2, (x+y+1)*h/2) does not, so the two disagree by exactly w/2 in X (Y
## already matches). Offsetting the layer's own `position` by this Vector2 folds that
## difference away once, instead of it recurring at every call site that reads the
## layer back out. `span` is how many grid cells wide ONE of the layer's own tiles is:
## 1 for a normal per-cell layer, a larger value (e.g. Data.BUILD_BLOCK) for a layer
## whose TileSet tile_size was scaled up by that same span for block-resolution
## painting — the correction scales with it too, since it is a fraction of the
## layer's OWN (larger) tile. See docs/MIGRATION_AUDIT.md §1.3 rows 25-30; measured
## drift (scripts/_probe_align.gd, 2026-08-21) was (32, 0) px at tile_w=64, span=1.
static func layer_origin(span: int = 1) -> Vector2:
	var g = Data.GRID
	var tw: float = float(g.get("tile_w", 64))
	var ox: float = float(g.origin_x)
	var oy: float = float(g.origin_y)
	return Vector2(ox - tw * 0.5 * span, oy)

## The four corners of a grid-cell diamond as OFFSETS from a cell's center, in
## screen space, fixed order top/right/bottom/left. This is the corner math that
## used to be hand-written at every diamond-drawing site (docs/MIGRATION_AUDIT.md
## §1.3 rows 18-24) as `Vector2(0,-th*0.5)`, `Vector2(tw*0.5,0)`, `Vector2(0,th*0.5)`,
## `Vector2(-tw*0.5,0)` in that exact order — moved here verbatim so it exists once.
static func diamond_corners() -> PackedVector2Array:
	var g = Data.GRID
	var tw: float = float(g.get("tile_w", 64))
	var th: float = float(g.get("tile_h", 32))
	return PackedVector2Array([
		Vector2(0.0, -th * 0.5),
		Vector2(tw * 0.5, 0.0),
		Vector2(0.0, th * 0.5),
		Vector2(-tw * 0.5, 0.0)
	])

## The four corners of a single cell's diamond in absolute screen space
## (top, right, bottom, left), centered on cell_center(cell). Equivalent to
## `cell_center(cell) + diamond_corners()[i]` for each corner.
static func cell_diamond(cell: Vector2i) -> PackedVector2Array:
	var c := cell_center(cell)
	var out := PackedVector2Array()
	for p in diamond_corners():
		out.append(c + p)
	return out

## The bounding box of the whole iso-diamond board, in screen space. This is a
## VERBATIM move of Game.board_bounds()'s own closed-form derivation (not
## reconstructed from cell_diamond/diamond_corners — see MIGRATION_AUDIT.md §1.3
## row 24; it feeds Camera2D limits, so it is kept as the exact same floating-point
## operations in the exact same order rather than an algebraically-equivalent but
## differently-rounded reformulation).
static func board_bounds() -> Rect2:
	var g = Data.GRID
	var cols: float = float(g.cols)
	var rows: float = float(g.rows)
	var tw: float = float(g.get("tile_w", 64))
	var th: float = float(g.get("tile_h", 32))
	var ox: float = float(g.origin_x)
	var oy: float = float(g.origin_y)
	return Rect2(ox - rows * tw * 0.5, oy,
		(cols + rows) * tw * 0.5, (cols + rows) * th * 0.5)
