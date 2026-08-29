class_name LevelValidator
extends RefCounted
## Structural maze validity (docs/refactor/MIGRATION.MD T10): can every spawn cell
## reach the objective? Built on PathMetrics (T9) — render-independent, no Game
## instantiation needed.
##
## "Hráč nemůže cestu úplně zazdít" (the player can never wall off the path) is
## already a STRUCTURAL guarantee of the existing architecture, not something to
## simulate here: build spots require an already-solid high_ground block
## (Game._build_field(), game.gd) and no live player action ever calls
## astar.set_point_solid() on a new cell — the only two call sites are
## Game._build_field() itself (the level's authored high_ground, once, at load) and
## the sinking-walls spike (Game._set_sunk()), which only ever REMOVES solid cells as
## Tolerance rises (docs/core/17_living_map.md: "žádnou cestu neodebírá"). So the one
## thing that can actually break is an AUTHORED high_ground layout that seals a spawn
## zone off from the objective before the level even starts — that's what this checks.
##
## tools/map_editor.gd's own _analyze() already computes this same "unreachable spawn
## cells" question (as an advisory BLOCKER row), but _bake_to_level() never gates on
## it — a level can be saved broken today, and only scripts/_test_levels.gd's live
## Game-instantiating smoke test would ever catch it. This module is what closes that
## gap once something calls it at save/bake time; not wired in yet (see PROGRESS.md's
## T10 entry for why that's left as a deliberate follow-up rather than done here).

## Every level cell that should block movement: high_ground, minus the objective
## itself (a level author is not required to keep it out of high_ground — Game
## carves the same exception out at load, game.gd's _build_field()).
static func _solid_cells(level: LevelData) -> Dictionary:
	var solid := {}
	for c: Vector2i in level.high_ground:
		if c != level.objective:
			solid[c] = true
	return solid

## Every spawn-zone cell that cannot reach the objective, empty if fully connected.
## Mirrors Game._build_field()'s own spawn_zone_cells filter exactly (in bounds, not
## solid, not the objective cell itself) so this checks the same candidate set the
## live game would actually try to spawn distractions on — not a superset that would
## flag cells nothing ever spawns at, or a subset that would miss a real one.
static func unreachable_spawn_cells(level: LevelData) -> Array:
	var solid := _solid_cells(level)
	var g = Data.GRID
	var cols: int = int(g.cols)
	var rows: int = int(g.rows)
	var bad: Array = []
	for zone: Rect2i in level.spawn_zones:
		for cx in range(zone.position.x, zone.position.x + zone.size.x):
			for cy in range(zone.position.y, zone.position.y + zone.size.y):
				var cell := Vector2i(cx, cy)
				if not Data.in_bounds(cell) or solid.has(cell) or cell == level.objective:
					continue
				if not PathMetrics.is_reachable(cell, level.objective, solid, cols, rows):
					bad.append(cell)
	return bad

## True if every spawn cell can reach the objective.
static func is_fully_reachable(level: LevelData) -> bool:
	return unreachable_spawn_cells(level).is_empty()
