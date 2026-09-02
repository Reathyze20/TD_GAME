class_name Minimap
extends Control
## The board at a glance, in the corner (P12, PATHFINDING.MD). Exists because Brain Fog
## takes the board away: once a habit only lights a wedge, a player who cannot see the
## whole map cannot plan a maze on it, and fog stops being a challenge and becomes an
## annoyance.
##
## THE ONE RULE IT MUST NOT BREAK: it may never show more than the player has already been
## able to see. A minimap that quietly draws the unexplored map is not a convenience, it
## is a fog-of-war system with a hole in it — every wall placement the fog was supposed to
## make interesting is readable off the corner instead.
##
## WHY THE CONTENT IS A FUNCTION AND NOT JUST _draw(). `_draw()` output cannot be asserted
## on: a test would have to read pixels back, which needs a real renderer (the
## _test_shadow_occlusion problem) and would still only prove something about colours.
## `terrain_cells()` and `live_blips()` return exactly what `_draw()` is allowed to paint,
## so `_test_minimap` can check the rule directly and headlessly, and `_draw()` cannot
## drift away from what was verified because it has no other source of truth.
##
## TERRAIN IS REMEMBERED, LIVE BODIES ARE NOT — and that split is the point. Walls stay on
## the map once seen (`is_explored`), because knowing a place is permanent. Distractions
## only appear where the board is lit RIGHT NOW (`is_pos_visible`), because knowing where
## something *was* is not knowing where it is. A minimap that tracked bodies through the
## dark would hand back the exact information the fog exists to take away.

## Screen pixels per board cell. 2 on a 30x14 board gives a 60x28 map — small, but this is
## a 480x270 canvas integer-scaled 4x, so it lands as 240x112 real pixels.
const CELL_PX := 2.0
## Distance from the canvas edge, matching the bottom bar's own inset.
const MARGIN := 4.0

var game: Game = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var g = Data.GRID
	custom_minimum_size = Vector2(float(g.cols) * CELL_PX, float(g.rows) * CELL_PX)
	size = custom_minimum_size
	# Bottom-left, ABOVE the build bar. The first pass anchored to the canvas bottom and
	# landed the whole map inside the bar (seen in .dev/screenshots/p_hudrescale_gameplay).
	# Offset from Game._HUD_BOTTOM_H rather than a copied number, so moving the bar moves
	# the map with it.
	position = Vector2(MARGIN, 270.0 - Game._HUD_BOTTOM_H - size.y - MARGIN)


func _process(_delta: float) -> void:
	if game != null and is_instance_valid(game):
		queue_redraw()


## Board cells the map is ALLOWED to paint terrain for: explored ones, and nothing else.
## `is_explored()` short-circuits to true when a level ships with no fog, which is why a
## fogless level shows its whole board here rather than an empty rectangle.
func terrain_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if game == null or not is_instance_valid(game):
		return out
	var g = Data.GRID
	for y in range(int(g.rows)):
		for x in range(int(g.cols)):
			var cell := Vector2i(x, y)
			if game.is_explored(Data.cell_center(cell)):
				out.append(cell)
	return out


## World positions of distractions the map is ALLOWED to paint: only those standing where
## the board is lit right now. Deliberately NOT gated on `is_explored` — remembering that
## a wall is there is fair, remembering where an enemy went is not.
func live_blips() -> Array[Vector2]:
	var out: Array[Vector2] = []
	if game == null or not is_instance_valid(game):
		return out
	for d in game.get_live_distractions():
		if not is_instance_valid(d) or d.dead:
			continue
		if not game.is_pos_visible(d.global_position):
			continue
		out.append(d.global_position)
	return out


## Cell -> where it lands on this control.
func _cell_to_local(cell: Vector2i) -> Vector2:
	return Vector2(float(cell.x) * CELL_PX, float(cell.y) * CELL_PX)


func _world_to_local(pos: Vector2) -> Vector2:
	return _cell_to_local(Data.world_to_cell(pos))


func _draw() -> void:
	if game == null or not is_instance_valid(game):
		return
	var cs := Vector2(CELL_PX, CELL_PX)
	# The frame is drawn whatever the fog hides, so the map reads as a map rather than as
	# a smear that appears out of nowhere when the first cell is explored.
	draw_rect(Rect2(Vector2(-1.0, -1.0), size + Vector2(2.0, 2.0)), UI.TRACK)
	draw_rect(Rect2(Vector2(-1.0, -1.0), size + Vector2(2.0, 2.0)), UI.BORDER, false, 1.0)

	for cell in terrain_cells():
		var col: Color = UI.SURFACE
		if game.high_ground.has(cell):
			col = UI.BORDER_HI
		draw_rect(Rect2(_cell_to_local(cell), cs), col)

	# The core, then habits, then live bodies — painted last so nothing hides them.
	if game.is_explored(game.objective_pos):
		draw_rect(Rect2(_world_to_local(game.objective_pos), cs), UI.FOCUS)

	for spot in game.build_spots.values():
		if not is_instance_valid(spot) or spot.state != BuildSpot.State.BUILT:
			continue
		if not is_instance_valid(spot.current_habit):
			continue
		if not game.is_explored(spot.current_habit.global_position):
			continue
		draw_rect(Rect2(_world_to_local(spot.current_habit.global_position), cs), UI.ACCENT)

	for p in live_blips():
		draw_rect(Rect2(_world_to_local(p), cs), UI.DANGER)
