extends Node
## Jednorazova sonda: kresli hra podlahu tam, kam Data.cell_center() umistuje entity?
func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	for i in range(Data.get_level_count()):
		if Data.get_level(i).id == 98:
			GameState.current_level_index = i
			break
	var game = load("res://scenes/Game.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	GameState.max_focus = 999999
	GameState.focus = 999999
	var pl: TileMapLayer = game.get("path_layer")
	if pl == null:
		print("PROBE: path_layer chybi")
		get_tree().quit(1)
		return
	print("PROBE: path_layer.position = ", pl.position)
	for c in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(5, 5), Vector2i(13, 10)]:
		var from_tiles: Vector2 = pl.map_to_local(c) + pl.position
		var from_data: Vector2 = Data.cell_center(c)
		print("PROBE: bunka %s  dlazdice %s  cell_center %s  rozdil %s"
			% [str(c), str(from_tiles), str(from_data), str(from_tiles - from_data)])
	get_tree().quit(0)
