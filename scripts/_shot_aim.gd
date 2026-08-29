extends Node
## Osm vezi, kazda zamcena do jineho smeru -- kontrola osmismerneho artu hlavy.
## Docasny harness. NE --headless.

var _done := false
var _towers: Array = []

func _ready() -> void:
	GameState.max_focus = 999999
	GameState.focus = 999999
	for i in range(Data.get_level_count()):
		if Data.get_level(i).id == 98:
			GameState.current_level_index = i
			break
	GameState.designer_mode = true
	var game = load("res://scenes/Game.tscn").instantiate()
	add_child(game)
	var wd := Timer.new(); wd.wait_time = 60.0; wd.one_shot = true
	wd.timeout.connect(func():
		if not _done: print("SHOT FAILED"); get_tree().quit(1))
	add_child(wd); wd.start()
	await get_tree().process_frame

	GameState.dopamine = 100000
	GameState.bandwidth_used = 0
	var spots: Array = game.build_spots.keys()
	spots.sort_custom(func(a, b): return (a.x + a.y) < (b.x + b.y))
	var built := 0
	for sp: Vector2i in spots:
		if built >= 8:
			break
		GameState.selected_habit = "focus_timer"
		game._hover_cell = sp
		if not game._can_build(sp):
			continue
		game._build_on(sp)
		if game.is_aiming:
			game._end_aiming()
		var h = game.build_spots[sp].current_habit
		if h != null:
			# Osm smeru po 45 stupnich ve SVETOVEM uhlu -- presne to, co hrac zamkne.
			h.facing_angle = float(built) * PI / 4.0
			h._aim = h.facing_angle
			h.queue_redraw()
			_towers.append(h)
		built += 1
	for i in range(30):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	# Pozice AZ TED, ne pri stavbe. Souradnice viewportu se mezi stavbou a snimkem
	# posunou spolu s kamerou, takze vypis pri stavbe ukazoval na prazdno.
	for i in range(_towers.size()):
		var h = _towers[i]
		var scr: Vector2 = h.get_global_transform_with_canvas().origin
		print("vez %d: zadano %.0f  facing %.0f  aim %.0f  auto %s -> %s @ %d,%d" % [i,
			float(i) * 45.0, rad_to_deg(h.facing_angle), rad_to_deg(h._aim),
			str(h.auto_aim), h._head_dir_name(), scr.x, scr.y])
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://build/_aim_board.png")
	print("SHOT build/_aim_board.png")
	_done = true
	get_tree().quit(0)
