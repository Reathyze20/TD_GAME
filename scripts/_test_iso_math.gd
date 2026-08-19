extends SceneTree

const Data = preload("res://scripts/data.gd")

func _initialize() -> void:
	print("--- Running Isometric Projection Math Verification ---")
	var g = Data.GRID
	var cols: int = int(g.cols)
	var rows: int = int(g.rows)
	var errors := 0
	
	for y in range(rows):
		for x in range(cols):
			var cell := Vector2i(x, y)
			var pos := Data.cell_center(cell)
			var back := Data.world_to_cell(pos)
			if back != cell:
				printerr("Mismatch for cell %s: pos %s -> world_to_cell returned %s" % [cell, pos, back])
				errors += 1
				
	if errors == 0:
		print("SUCCESS: 100%% of %d grid cells passed cell_center <-> world_to_cell roundtrip test!" % (cols * rows))
	else:
		printerr("FAILED with %d errors" % errors)
		quit(1)
		return
		
	# Test AStar with LevelIso
	print("--- Testing AStar pathfinding on level_iso ---")
	var level = load("res://data/levels/level_iso.tres") as LevelData
	if level == null:
		printerr("Could not load level_iso.tres")
		quit(1)
		return
		
	var astar := AStarGrid2D.new()
	astar.region = Rect2i(0, 0, cols, rows)
	astar.cell_size = Vector2(1, 1)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar.update()
	
	for c in level.high_ground:
		if c != level.objective and astar.is_in_bounds(c.x, c.y):
			astar.set_point_solid(c, true)
			
	var spawn_cell = level.spawn_zones[0].position + Vector2i(1, 1)
	var path = astar.get_id_path(spawn_cell, level.objective)
	print("AStar Path from %s to %s has %d steps:" % [spawn_cell, level.objective, path.size()])
	if path.is_empty():
		printerr("FAILED: No path found from spawn to objective!")
		quit(1)
		return
		
	print("SUCCESS: Path found! Length: %d cells." % path.size())
	quit(0)
