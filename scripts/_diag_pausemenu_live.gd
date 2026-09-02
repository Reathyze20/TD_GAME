extends Node
## Jednorázová diagnostika: spustí Game.tscn doopravdy, zavolá SKUTEČNÝ
## _open_pause_menu() (stejná metoda co Esc/P v živé hře), počká na layout
## a uloží screenshot v reálném okenním měřítku (4x nearest upscale z
## interního 480x270 bufferu, protože get_viewport().get_texture() vrací
## jen ten interní buffer pod stretch/mode="viewport"). Smaž po použití.

func _ready() -> void:
	for i in range(Data.get_level_count()):
		if Data.get_level(i).id == 98:
			GameState.current_level_index = i
			break

	var game: Game = load("res://scenes/Game.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	GameState.max_focus = 999999
	GameState.focus = 999999
	GameState.dopamine = 999999
	await get_tree().process_frame
	await get_tree().process_frame

	print("calling real _open_pause_menu()...")
	game._open_pause_menu()
	# Nekolik snimku, at CenterContainer opravdu dosedne na finalni layout.
	for i in range(5):
		await get_tree().process_frame

	if game._pause_menu == null or not is_instance_valid(game._pause_menu):
		print("FAIL: _pause_menu je null po _open_pause_menu()")
		get_tree().quit(1)
		return
	print("pause_menu instance: %s  size=%s  visible=%s" % [
		game._pause_menu, game._pause_menu.size, game._pause_menu.visible])

	var img: Image = get_viewport().get_texture().get_image()
	img.resize(img.get_width() * 4, img.get_height() * 4, Image.INTERPOLATE_NEAREST)
	var out_path := "res://.dev/screenshots/_diag_pausemenu_live.png"
	var err := img.save_png(out_path)
	print("saved %s err=%s" % [out_path, err])
	get_tree().quit(0 if err == OK else 1)
