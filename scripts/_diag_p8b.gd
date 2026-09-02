extends Node
## THROWAWAY diagnostic for P8b — delete after use (with its .gd.uid and .tscn).
## Surveys every shipped level's build spots against the rescaled Routine radius.

var completed := false


func _ready() -> void:
	var wd := Timer.new()
	wd.wait_time = 120.0
	wd.one_shot = true
	add_child(wd)
	wd.timeout.connect(func():
		if not completed:
			print("FAILED: watchdog fired")
			get_tree().quit(1))
	wd.start()
	call_deferred("_run")


func _run() -> void:
	print("CORE=%.0f ANCHOR=%.0f LAMP=%.0f DEF=%.0f PROJ=%.0f"
		% [Game.CORE_ROUTINE_RADIUS, Game.ANCHOR_ROUTINE_RADIUS, Game.TOWER_LAMP_RADIUS,
			Game.DEFENDER_LIGHT_RADIUS, Game.PROJECTILE_LIGHT_RADIUS])
	var all_blocks := {}
	for y in range(Data.GRID.rows):
		for x in range(Data.GRID.cols):
			all_blocks[Data.build_block(Vector2i(x, y))] = true

	for i in range(Data.get_level_count()):
		var ld: LevelData = Data.get_level(i)
		GameState.current_level_index = i
		var game: Game = load("res://scenes/Game.tscn").instantiate()
		add_child(game)
		await get_tree().process_frame
		GameState.max_focus = 999999
		GameState.focus = 999999
		await get_tree().process_frame

		var inside: Array = []
		var outside: Array = []
		for cell: Vector2i in game.build_spots:
			var p: Vector2 = game.cell_center(cell)
			if game.is_position_in_routine(p, game._routine_sources):
				inside.append([cell, roundi(p.distance_to(game.objective_pos))])
			else:
				outside.append([cell, roundi(p.distance_to(game.objective_pos))])
		var lit := 0
		for b in all_blocks:
			if game._lit_cells.has(b):
				lit += 1
		print("\n--- level id=%d  \"%s\"  objective=%s" % [ld.id, ld.display_name,
			ld.objective])
		print("    build spots: %d total, %d inside Routine, %d outside"
			% [game.build_spots.size(), inside.size(), outside.size()])
		print("    lit blocks at start: %d / %d" % [lit, all_blocks.size()])
		print("    inside : %s" % [inside])
		print("    outside: %s" % [outside])
		# Can an Anchor on an in-Routine spot reach any outside spot?
		var reachable: Array = []
		for a in inside:
			for o in outside:
				var d: float = game.cell_center(a[0]).distance_to(game.cell_center(o[0]))
				if d <= Game.ANCHOR_ROUTINE_RADIUS:
					reachable.append([a[0], o[0], roundi(d)])
		print("    anchor hops that open a new spot: %s" % [reachable])
		game.queue_free()
		await get_tree().process_frame

	completed = true
	print("DIAG DONE")
	get_tree().quit(0)
