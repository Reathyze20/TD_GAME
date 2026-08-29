class_name GridProjection
extends RefCounted
## Canonical grid<->screen conversion layer (docs/refactor/MIGRATION.MD T4/T5). EVERY
## place that converts a grid cell to a screen position, a screen position back to a
## cell, or corrects for the board's projection, is meant to go through here.
##
## Two modes exist: MODE_ISO (the 2:1 diamond isometric, live until 2026-08-29) and
## MODE_SQUARE (a plain top-down grid, added by T5, now the live default). Switching
## active_mode changes cell_center()/world_to_cell()/board_bounds()/
## screen_dir_to_grid_axes()/layer_origin() and, through GROUND_Y_SCALE, every formula
## built on to_ground()/to_screen() — but NOT diamond_corners()/cell_diamond(), which
## remain iso-only (see their own doc comments for why) and must not be called while
## MODE_SQUARE is active.
##
## Activated 2026-08-29 directly by the user (see BLOCKED.md's T5 entry for the full
## record): project.godot now targets a 480x270 canvas, integer-scaled 4x, and
## Data.GRID was re-derived at tile=16 (matching TERRAIN_ART_PX, so pixel_scale()
## stays 1.0 — unchanged from iso, no sprite-scale jump). What's still rough: the
## actual WALL VISUAL in square mode is a flat-color placeholder
## (Game._build_terrace_blocks()'s MODE_SQUARE branch), not the iso terrace art (which
## is diamond-shaped and does not fit a square cell), and every level was deleted
## pending real content authored for this grid. See docs/MIGRATION_AUDIT.md for the
## full inventory this was built from, and its §1.4 for a second open question T5 did
## not resolve either: several radii (Routine, Brain Fog, intervention AoE, guard
## zones) still measure raw screen-space distance rather than routing through
## to_ground()/ground_distance() below — mode-independent today, deliberately.

enum { MODE_ISO, MODE_SQUARE }

## Which projection is live. Change via set_mode(), never by writing this directly, so
## GROUND_Y_SCALE stays in sync with it.
static var active_mode: int = MODE_SQUARE

## How much the board's projection squashes screen-Y relative to true "ground"
## distance. 2.0 for MODE_ISO's 2:1 diamond; 1.0 for MODE_SQUARE, where screen space
## already IS ground space, so to_ground()/to_screen() become the identity. Kept in
## sync with active_mode by set_mode() — do not assign this directly.
static var GROUND_Y_SCALE := 1.0

## Switches the live projection. Only ever called by test fixtures today (T5 does not
## call this in the running game) — see the file header.
static func set_mode(mode: int) -> void:
	active_mode = mode
	GROUND_Y_SCALE = 1.0 if mode == MODE_SQUARE else 2.0

## Grid cell -> screen position (the cell's center).
## MODE_ISO: moved verbatim from Data.cell_center(), which now re-exports this.
## MODE_SQUARE: the plain top-down case — a cell is a `tile`-sized axis-aligned box,
## its center offset by half a tile from its top-left corner.
static func cell_center(cell: Vector2i) -> Vector2:
	var g := Data.GRID
	var ox: float = float(g.origin_x)
	var oy: float = float(g.origin_y)
	if active_mode == MODE_SQUARE:
		var t: float = float(g.get("tile", 32))
		return Vector2(ox + cell.x * t + t * 0.5, oy + cell.y * t + t * 0.5)
	var tw: float = float(g.get("tile_w", 64))
	var th: float = float(g.get("tile_h", 32))
	return Vector2(
		ox + (cell.x - cell.y) * (tw * 0.5),
		oy + (cell.x + cell.y + 1) * (th * 0.5))

## Screen position -> grid cell, clamped to the board.
## MODE_ISO: moved verbatim from Data.world_to_cell(), which now re-exports this.
## MODE_SQUARE: plain floor division by tile size — the exact inverse of cell_center()
## above (verified by _test_square_math.gd's round-trip check over every cell).
static func world_to_cell(pos: Vector2) -> Vector2i:
	var g := Data.GRID
	var dx: float = pos.x - float(g.origin_x)
	var dy: float = pos.y - float(g.origin_y)
	var col: int
	var row: int
	if active_mode == MODE_SQUARE:
		var t: float = float(g.get("tile", 32))
		col = int(floorf(dx / t))
		row = int(floorf(dy / t))
	else:
		var tw: float = float(g.get("tile_w", 64))
		var th: float = float(g.get("tile_h", 32))
		col = int(floorf(dx / tw + dy / th))
		row = int(floorf(dy / th - dx / tw))
	return Vector2i(clampi(col, 0, int(g.cols) - 1), clampi(row, 0, int(g.rows) - 1))

## Moved verbatim from Data.in_bounds(), which now re-exports this. Mode-independent:
## bounds are a property of cols/rows, not of the projection shape.
static func in_bounds(c: Vector2i) -> bool:
	var g := Data.GRID
	return c.x >= 0 and c.x < int(g.cols) and c.y >= 0 and c.y < int(g.rows)

## Screen-space delta -> ground-space delta (undoes the Y-squash). Ground space is
## where combat range, cones and line-of-sight are measured — a raw screen vector aims
## short in Y under MODE_ISO, since one screen pixel of Y covers GROUND_Y_SCALE of
## ground truth. Under MODE_SQUARE, GROUND_Y_SCALE is 1.0 and this is the identity —
## screen space already is ground space when there is no squash to undo.
static func to_ground(screen_delta: Vector2) -> Vector2:
	return Vector2(screen_delta.x, screen_delta.y * GROUND_Y_SCALE)

## Ground-space delta -> screen-space delta (re-applies the Y-squash, or does nothing
## under MODE_SQUARE). The inverse of to_ground() — used whenever a direction computed
## in ground space (an aim angle, a line-of-sight ray) needs to become an actual
## screen-space step or draw vector again.
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

## Decomposes a screen-space direction into its (grid +X, grid +Y) axis components.
## MODE_ISO: the same skew world_to_cell() applies to a position, but for a direction
## rather than a point. Used to classify a movement vector into one of the four
## grid-cardinal facings (see Enemy.note_heading()): grid +X and -X land on screen
## SE/NW diagonals, grid +Y and -Y on SW/NE, because the projection tilts the axes.
## MODE_SQUARE: grid axes ARE the screen axes — no tilt, so this is the identity. NOT
## simply "the ISO formula with GROUND_Y_SCALE=1" (that would still cross-mix x and y
## via the +/- terms); the tilt itself, not just its magnitude, is an iso-only feature.
static func screen_dir_to_grid_axes(dir: Vector2) -> Vector2:
	if active_mode == MODE_SQUARE:
		return dir
	return Vector2(dir.x / GROUND_Y_SCALE + dir.y, dir.y - dir.x / GROUND_Y_SCALE)

## Position to give a TileMapLayer so its own map_to_local() agrees with cell_center()
## above, for whichever cell size that layer's own TileSet was built at.
##
## MODE_ISO: a DIAMOND_DOWN layer's map_to_local() returns ((x-y+1)*w/2, (x+y+1)*h/2) —
## the X term carries a "+1" that cell_center()'s ((x-y)*w/2, (x+y+1)*h/2) does not, so
## the two disagree by exactly w/2 in X (Y already matches). Offsetting the layer's own
## `position` by this Vector2 folds that difference away once, instead of it recurring
## at every call site that reads the layer back out. See docs/MIGRATION_AUDIT.md §1.3
## rows 25-30; measured drift (scripts/_probe_align.gd, 2026-08-21) was (32, 0) px at
## tile_w=64, span=1.
##
## MODE_SQUARE: a plain TILE_SHAPE_SQUARE layer's map_to_local() already returns
## ((x+0.5)*t, (y+0.5)*t) — exactly cell_center()'s own formula minus the origin — so no
## correction term is needed at all, for any span (verified algebraically for
## Data.BUILD_BLOCK: a span-S layer's tile is S*t wide, and map_to_local(block) =
## (block+0.5)*S*t equals cell_center(block_center_cell(block)) - origin for the same
## reason, since block_center_cell's "+floor(S/2)" offset and the "+0.5" tile-center
## offset combine to the same S*t/2 either way).
##
## `span` is how many grid cells wide ONE of the layer's own tiles is: 1 for a normal
## per-cell layer, a larger value (e.g. Data.BUILD_BLOCK) for a layer whose TileSet
## tile_size was scaled up by that same span for block-resolution painting.
static func layer_origin(span: int = 1) -> Vector2:
	var g := Data.GRID
	var ox: float = float(g.origin_x)
	var oy: float = float(g.origin_y)
	if active_mode == MODE_SQUARE:
		return Vector2(ox, oy)
	var tw: float = float(g.get("tile_w", 64))
	return Vector2(ox - tw * 0.5 * span, oy)

## The four corners of a grid-cell diamond as OFFSETS from a cell's center, in
## screen space, fixed order top/right/bottom/left. This is the corner math that
## used to be hand-written at every diamond-drawing site (docs/MIGRATION_AUDIT.md
## §1.3 rows 18-24) as `Vector2(0,-th*0.5)`, `Vector2(tw*0.5,0)`, `Vector2(0,th*0.5)`,
## `Vector2(-tw*0.5,0)` in that exact order — moved here verbatim so it exists once.
##
## ISO-ONLY, not mode-aware: what "high ground" should even look like in a top-down
## square view (no visible wall faces the way an isometric terrace has them) is a
## visual design decision T5 does not make — see the file header and BLOCKED.md.
## Do not call this while active_mode is MODE_SQUARE; there is no square equivalent
## implemented yet.
static func diamond_corners() -> PackedVector2Array:
	var g := Data.GRID
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
## ISO-ONLY — see diamond_corners() above; do not call under MODE_SQUARE.
static func cell_diamond(cell: Vector2i) -> PackedVector2Array:
	var c := cell_center(cell)
	var out := PackedVector2Array()
	for p in diamond_corners():
		out.append(c + p)
	return out

## The bounding box of the whole board, in screen space.
## MODE_ISO: a VERBATIM move of Game.board_bounds()'s own closed-form derivation (not
## reconstructed from cell_diamond/diamond_corners — see MIGRATION_AUDIT.md §1.3
## row 24; it feeds Camera2D limits, so it is kept as the exact same floating-point
## operations in the exact same order rather than an algebraically-equivalent but
## differently-rounded reformulation).
## MODE_SQUARE: the plain axis-aligned rect from the grid's origin, cols, rows and
## tile size — there is no diamond to bound.
static func board_bounds() -> Rect2:
	var g := Data.GRID
	var cols: float = float(g.cols)
	var rows: float = float(g.rows)
	var ox: float = float(g.origin_x)
	var oy: float = float(g.origin_y)
	if active_mode == MODE_SQUARE:
		var t: float = float(g.get("tile", 32))
		return Rect2(ox, oy, cols * t, rows * t)
	var tw: float = float(g.get("tile_w", 64))
	var th: float = float(g.get("tile_h", 32))
	return Rect2(ox - rows * tw * 0.5, oy,
		(cols + rows) * tw * 0.5, (cols + rows) * th * 0.5)
