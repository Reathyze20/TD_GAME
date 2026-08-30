class_name MapComposer
extends RefCounted
## Builds ONE flat, playable LevelData out of a chain of referenced LevelData links
## (docs/refactor/PATHFINDING.MD P8, "MapSegmentData a skládání levelů").
##
## THE SHAPE. A level points at the level it extends through `LevelData.base`, so
## "Level N+1 = LevelData N + segment" is a REFERENCE, never a copy of N's cells. Each
## link may also carry a `LevelData.segment` header (MapSegmentData): a link WITH one is
## optional — its geometry joins the board only while the header's `unlock_condition` is
## satisfied, shifted by the header's `anchor_offset`. A link WITHOUT one is the spine and
## is always present. compose() walks that chain, unions the geometry of the links that
## are in play, and returns a fresh flat level. Nothing here mutates the input.
##
## THE HARD LIMIT: THE COMPOSED BOARD MUST FIT ON ONE SCREEN. A scrolling map breaks the
## concentration this game is about (Doucet, Defender's Quest), which the queue names as
## the reason the limit exists at all. Two things enforce it, and neither is a promise
## made in prose:
##
##   1. Composition NEVER grows Data.GRID. The grid IS the screen (measured below), so
##      content that would leave the screen would also leave the grid, where pathfinding
##      and building simply do not reach. Segments grow the map by filling parts of the
##      grid the base level left empty, not by enlarging it.
##   2. A segment whose offset geometry lands outside board_budget() is DROPPED, with a
##      push_error naming it. Refusing to compose an oversized segment is the only way
##      the limit can be structural instead of advisory.
##
## MEASURED, 2026-08-30, not assumed (scripts/_test_segments.gd re-derives all of it
## independently and fails if it drifts):
##   viewport 480x270, Data.GRID 30 cols x 14 rows @ tile 16, origin (0, 17),
##   HUD bars 17 px top and 24 px bottom.
##   -> columns that fit right of origin_x: 480/16 = 30. EXACTLY the grid. Zero
##      horizontal headroom, which is why nothing here ever grows the board sideways and
##      why the grid must never shrink below 29 columns: both shipped levels put the
##      objective on x = 28, and an objective outside the grid breaks pathfinding
##      outright (the T0 failure recorded in PROGRESS.md).
##   -> rows that fit between the two HUD bars: (270 - 24 - 17)/16 = 14. Also EXACTLY the
##      grid. The queue's planning figure of 17 visible rows came from 270/16 and did not
##      subtract the HUD bars; the true number is 14, and Data.GRID is already sized to
##      it. So the vertical room segments grow into is the rows the LEVELS leave empty —
##      0, 1, 12 and 13, since level_1 and level_98 both occupy only y = 2..11 — plus
##      column 29. Shrinking Data.GRID to 12 rows, as the planning note assumed, would
##      have HANDED BACK two of those four free rows rather than creating any, so the
##      constant is deliberately left alone. See PROGRESS.md's P8 entry.
##
## WHICH FIELDS COMPOSE, and which the played level always wins on. This list is the
## contract; anything not named here is "played level wins" by construction, because the
## composed result starts as a deep copy of it.
##
##   COMPOSED (union of every live link, offset by its anchor):
##     high_ground   set union, deduplicated, canonically sorted by (y, x)
##     path_cells    set union, deduplicated, canonically sorted by (y, x)
##     spawn_points  union of each live link's own spawn_points plus, for a segment link,
##                   its header's adds_spawns; deduplicated by CELL (first wins in
##                   canonical order), canonically sorted by (y, x)
##     terrain_tiles merged; first writer of a cell wins (the spine owns its own cells)
##     tile_overrides  ditto
##     decor         concatenated in canonical order, positions shifted by anchor * tile
##     trods         concatenated in canonical order, each one's cells shifted
##
##   PLAYED LEVEL ALWAYS WINS (never composed):
##     objective     the Focus core is the level's identity and its whole goal. A segment
##                   that could move it would invalidate every wall the player already
##                   learned, which is the one thing docs/core/17_living_map.md's trods
##                   are built to avoid.
##     spawn_zones   carried through untouched. NOTE the authoring rule this implies: a
##                   level that composes segments should author `spawn_points`, not
##                   `spawn_zones`, because Game._random_spawn_cell() ignores spawn_zones
##                   entirely once spawn_points is non-empty (P6). Composition warns when
##                   it sees both rather than silently rewriting one into the other.
##     id, display_name, everything economic (start_dopamine, focus, ...), every lesson
##     switch (cue_phase, fasting, ...), wave_count, wave_curve, lean_waves, bait_waves,
##     draft_interval, boss, ads, path_off_lane_cost, fog/shadows/routine_gates.
##                   All of them are decisions about the RUN, not about the board, and a
##                   segment is a piece of board.
##
## DETERMINISM. The composed board depends on WHICH segments are live and never on the
## order they were applied in: unconditional links compose root-first (a property of the
## chain, which is fixed), then live segment links compose in ascending `segment.id`
## order. Every cell collection is a deduplicated set emitted in (y, x) order, so even
## that ordering only shows up in the two places where order is genuinely meaningful —
## decor paint order and trod order — and there the id sort pins it. Two chains carrying
## the same segments in different positions compose to the identical board; so do two
## calls that enumerate the same unlock set in different insertion orders.

## Chain length beyond which `base` is assumed to be cyclic or malicious. A campaign is
## nowhere near this deep; the guard exists so a bad graph errors instead of hanging.
const MAX_CHAIN := 64

# ---------------------------------------------------------------- the screen budget

## Whole tiles of board that actually fit on screen, between the two HUD bars.
## `Game._HUD_BOTTOM_H` is read rather than copied so the two can never drift; the top
## bar is already accounted for by `Data.GRID.origin_y`, which data.gd's own comment
## requires to clear it.
static func visible_tile_budget() -> Vector2i:
	var g := Data.GRID
	var tile: int = int(g.tile)
	if tile <= 0:
		return Vector2i.ZERO
	var vw: int = int(ProjectSettings.get_setting("display/window/size/viewport_width", 480))
	var vh: int = int(ProjectSettings.get_setting("display/window/size/viewport_height", 270))
	var cols: int = int(floor(float(vw - int(g.origin_x)) / float(tile)))
	var rows: int = int(floor(float(vh - Game._HUD_BOTTOM_H - int(g.origin_y)) / float(tile)))
	return Vector2i(maxi(cols, 0), maxi(rows, 0))

## The cell rectangle composition is allowed to fill: the SMALLER of the grid and the
## visible budget, on each axis independently. Today they are identical (30x14); taking
## the minimum means a future grid change can only ever tighten this, never let content
## off screen by accident.
static func board_budget() -> Vector2i:
	var g := Data.GRID
	var vis := visible_tile_budget()
	return Vector2i(mini(int(g.cols), vis.x), mini(int(g.rows), vis.y))

static func _cell_in_budget(cell: Vector2i, budget: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < budget.x and cell.y < budget.y

# ---------------------------------------------------------------- reading the chain

## Every link of `level`'s base chain, ROOT FIRST, ending with `level` itself.
## Returns an empty array (after a push_error) if the chain is cyclic or absurdly long —
## callers must treat that as "do not compose", never as "no links".
static func chain_of(level: LevelData) -> Array[LevelData]:
	var reversed: Array[LevelData] = []
	var seen: Dictionary = {}
	var node: LevelData = level
	while node != null:
		var key := node.get_instance_id()
		if seen.has(key) or reversed.size() >= MAX_CHAIN:
			push_error("MapComposer: LevelData.base chain is cyclic or longer than %d links, refusing to compose (level id %d)"
				% [MAX_CHAIN, level.id])
			return [] as Array[LevelData]
		seen[key] = true
		reversed.append(node)
		node = node.base
	var chain: Array[LevelData] = []
	for i in range(reversed.size() - 1, -1, -1):
		chain.append(reversed[i])
	return chain

## Every cell a single link claims in its OWN space, before its anchor is applied.
## Deliberately includes the spawn points that come from the link's segment header, since
## those land on the board exactly like the link's own cells do.
static func _link_cells(link: LevelData) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	cells.append_array(link.high_ground)
	cells.append_array(link.path_cells)
	for sp: SpawnPointData in link.spawn_points:
		cells.append(sp.cell)
	for t: TrodData in link.trods:
		cells.append_array(t.cells)
	for k in link.terrain_tiles.keys():
		cells.append(k)
	for k in link.tile_overrides.keys():
		cells.append(k)
	if link.segment != null:
		for sp: SpawnPointData in link.segment.adds_spawns:
			cells.append(sp.cell)
	return cells

## True if every cell this link would contribute lands inside `budget` once anchored.
## The one gate that makes "the segment must fit on one screen" structural.
static func _link_fits(link: LevelData, offset: Vector2i, budget: Vector2i) -> bool:
	for c: Vector2i in _link_cells(link):
		if not _cell_in_budget(c + offset, budget):
			return false
	return true

## Segment ids of every link in `level`'s chain whose unlock condition MetaProgression
## currently satisfies. The only place the persistent save is consulted; compose_with()
## below takes the answer as data so tests (and any future preview UI) can ask "what
## would this board look like with these segments" without touching the save file.
static func live_unlocks(level: LevelData) -> Dictionary:
	var unlocked: Dictionary = {}
	for link: LevelData in chain_of(level):
		if link.segment == null:
			continue
		if MetaProgression.is_segment_unlocked(link.segment.unlock_condition):
			unlocked[link.segment.id] = true
	return unlocked

# ---------------------------------------------------------------- composing

## The flat, playable level for `source` as the save file currently stands.
static func compose(source: LevelData) -> LevelData:
	if source == null:
		return null
	return compose_with(source, live_unlocks(source))

## `unlocked` is a Dictionary used as a set of MapSegmentData ids (StringName -> true),
## matching every other set-shaped Dictionary in this codebase. Its ITERATION ORDER IS
## NEVER READ — it is only ever queried with has() — which is what makes the result
## depend on the set and not on how it was built.
##
## Always returns a NEW, fully independent LevelData; `source` and everything it
## references are read-only here. A level with no base and no segment header (every level
## on disk today) takes the early path and comes back as a plain deep copy, byte for byte
## the `level.duplicate(true)` game.gd did before P8 — so composition is a no-op wherever
## nobody has authored a chain.
static func compose_with(source: LevelData, unlocked: Dictionary) -> LevelData:
	if source == null:
		return null

	var out := _flat_copy(source)
	# `active_segments` is a runtime field, so duplicate() does not carry it — it is
	# restated here on purpose. Carrying it across the early path is what makes
	# compose(compose(x)) == compose(x): an ALREADY composed level is flat, so it takes
	# that path, and a level still standing on four segments must not forget them just
	# because it was handed through composition a second time.
	out.active_segments = source.active_segments.duplicate()
	if source.base == null and source.segment == null:
		return out

	var chain := chain_of(source)
	if chain.is_empty():
		return out   # cyclic chain; chain_of() already reported it
	# A level that has a chain is being composed from scratch; whatever it claimed to
	# stand on before is about to be recomputed from the unlock set.
	out.active_segments = []

	# Canonical composition order: the unconditional spine root-first (chain order is a
	# fixed property of the graph), then the live segments sorted by id. See the class
	# header's DETERMINISM note for why the second half must not simply follow the chain.
	var spine: Array[LevelData] = []
	var segments: Array[LevelData] = []
	var budget := board_budget()
	for link: LevelData in chain:
		if link.segment == null:
			spine.append(link)
			continue
		if not unlocked.has(link.segment.id):
			continue
		if not _link_fits(link, link.segment.anchor_offset, budget):
			push_error("MapComposer: segment '%s' anchored at %s does not fit the %s-tile board, dropping it (level id %d)"
				% [link.segment.id, str(link.segment.anchor_offset), str(budget), source.id])
			continue
		segments.append(link)
	segments.sort_custom(func(a: LevelData, b: LevelData) -> bool:
		return String(a.segment.id) < String(b.segment.id))

	var order: Array[LevelData] = []
	order.append_array(spine)
	order.append_array(segments)

	var high: Dictionary = {}          # Vector2i -> true
	var lanes: Dictionary = {}
	var tiles: Dictionary = {}
	var overrides: Dictionary = {}
	var decor: Array[Dictionary] = []
	var trods: Array[TrodData] = []
	var points: Array[SpawnPointData] = []
	var seen_point: Dictionary = {}    # Vector2i -> true
	var tile_px: int = int(Data.GRID.tile)

	for link: LevelData in order:
		var off := Vector2i.ZERO
		if link.segment != null:
			off = link.segment.anchor_offset
			out.active_segments.append(link.segment.id)

		for c: Vector2i in link.high_ground:
			high[c + off] = true
		for c: Vector2i in link.path_cells:
			lanes[c + off] = true
		for k in link.terrain_tiles.keys():
			var tk: Vector2i = (k as Vector2i) + off
			if not tiles.has(tk):
				tiles[tk] = link.terrain_tiles[k]
		for k in link.tile_overrides.keys():
			var ok: Vector2i = (k as Vector2i) + off
			if not overrides.has(ok):
				overrides[ok] = link.tile_overrides[k]
		for d: Dictionary in link.decor:
			var moved := d.duplicate(true)
			if moved.has("pos"):
				moved["pos"] = (moved["pos"] as Vector2) + Vector2(off * tile_px)
			decor.append(moved)
		for t: TrodData in link.trods:
			var moved_trod: TrodData = t.duplicate(true)
			var moved_cells: Array[Vector2i] = []
			for c: Vector2i in t.cells:
				moved_cells.append(c + off)
			moved_trod.cells = moved_cells
			trods.append(moved_trod)

		var link_points: Array[SpawnPointData] = []
		link_points.append_array(link.spawn_points)
		if link.segment != null:
			link_points.append_array(link.segment.adds_spawns)
		for sp: SpawnPointData in link_points:
			var moved_cell: Vector2i = sp.cell + off
			if seen_point.has(moved_cell):
				continue
			seen_point[moved_cell] = true
			var copy: SpawnPointData = sp.duplicate(true)
			copy.cell = moved_cell
			points.append(copy)

	out.high_ground = _sorted_cells(high.keys())
	out.path_cells = _sorted_cells(lanes.keys())
	out.terrain_tiles = tiles
	out.tile_overrides = overrides
	out.decor = decor
	out.trods = trods
	points.sort_custom(func(a: SpawnPointData, b: SpawnPointData) -> bool:
		return _cell_before(a.cell, b.cell))
	out.spawn_points = points

	if not out.spawn_points.is_empty() and not out.spawn_zones.is_empty():
		# Not fatal, and deliberately not "fixed" silently: Game._random_spawn_cell()
		# stops reading spawn_zones the moment spawn_points is non-empty (P6), so this
		# level's zone-based spawns have just been replaced rather than joined. Rewriting
		# the zones into points here would change the draw distribution on any level with
		# more than one zone, which is a design decision, not a composition detail.
		push_warning("MapComposer: level id %d composes spawn_points but still has %d spawn_zones — the zones are now unused (P6). Author spawn_points on a level that takes segments."
			% [source.id, out.spawn_zones.size()])
	return out

## A deep copy of `source` with the composition links cut, so the result is FLAT: it
## carries no `base` and no `segment`, which makes compose(compose(x)) == compose(x) and
## keeps a composed level from being composed a second time by anything downstream.
##
## The shallow duplicate first is what cuts the links BEFORE the deep one runs, so the
## deep copy never walks the base chain at all — cheaper than game.gd's old
## duplicate(true), and it cannot recurse into a cyclic graph.
static func _flat_copy(source: LevelData) -> LevelData:
	var detached: LevelData = source.duplicate(false)
	detached.base = null
	detached.segment = null
	var out: LevelData = detached.duplicate(true)
	out.base = null
	out.segment = null
	return out

## Reading order: top row first, left to right within a row. The same (y, x) ordering the
## map editor's bake already uses for path cells, so a composed board and a baked one read
## the same way in a diff.
static func _cell_before(a: Vector2i, b: Vector2i) -> bool:
	if a.y != b.y:
		return a.y < b.y
	return a.x < b.x

static func _sorted_cells(keys: Array) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	cells.assign(keys)
	cells.sort_custom(_cell_before)
	return cells

# ---------------------------------------------------------------- inspecting a board

## Every cell a COMPOSED (or plain) level occupies, for the screen-fit check. Includes
## the objective and spawn-zone corners: a board whose core or spawn sits off screen is
## exactly as broken as one whose walls do.
static func occupied_cells(level: LevelData) -> Array[Vector2i]:
	var cells: Array[Vector2i] = _link_cells(level)
	cells.append(level.objective)
	for z: Rect2i in level.spawn_zones:
		cells.append(z.position)
		cells.append(z.position + z.size - Vector2i.ONE)
	return cells

## Bounding rectangle of occupied_cells(), or a zero-size rect at the origin for a level
## that occupies nothing at all.
static func extent(level: LevelData) -> Rect2i:
	var cells := occupied_cells(level)
	if cells.is_empty():
		return Rect2i(Vector2i.ZERO, Vector2i.ZERO)
	var lo := cells[0]
	var hi := cells[0]
	for c: Vector2i in cells:
		lo.x = mini(lo.x, c.x)
		lo.y = mini(lo.y, c.y)
		hi.x = maxi(hi.x, c.x)
		hi.y = maxi(hi.y, c.y)
	return Rect2i(lo, hi - lo + Vector2i.ONE)

## True if every cell the board occupies is inside board_budget() — i.e. the map needs no
## scrolling and no cell falls outside the grid pathfinding works on.
static func fits_on_screen(level: LevelData) -> bool:
	var budget := board_budget()
	for c: Vector2i in occupied_cells(level):
		if not _cell_in_budget(c, budget):
			return false
	return true
