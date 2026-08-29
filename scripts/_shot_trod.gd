extends Node
## Tri snimky teze desky: pred telegrafem, s telegrafem, po otevreni trodu.
## Docasny harness -- po pouziti smazat. NE --headless (dummy renderer nema viewport
## texturu); pusti se pres --main-scene, viz reference-godot-binary.

var _done := false
var game

func _shot(name: String) -> void:
	for i in range(20):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute("res://build")
	img.save_png("res://build/_trod_%s.png" % name)
	print("SHOT %s" % name)

func _ready() -> void:
	GameState.max_focus = 999999
	GameState.focus = 999999
	for i in range(Data.get_level_count()):
		if Data.get_level(i).id == 98:
			GameState.current_level_index = i
			break
	GameState.designer_mode = true
	game = load("res://scenes/Game.tscn").instantiate()
	add_child(game)
	var wd := Timer.new()
	wd.wait_time = 60.0
	wd.one_shot = true
	wd.timeout.connect(func():
		if not _done:
			print("SHOT FAILED"); get_tree().quit(1))
	add_child(wd); wd.start()
	await get_tree().process_frame

	# Par vezi kolem stare trasy, at je videt, co hraci "prestane sedet".
	GameState.dopamine = 100000
	GameState.bandwidth_used = 0
	var spots: Array = game.build_spots.keys()
	spots.sort_custom(func(a, b): return (a.x + a.y) < (b.x + b.y))
	# Po jedne od kazdeho druhu, at je na jednom snimku videt cela rodina vezi na desce.
	var order := ["focus_timer", "mindfulness", "exercise", "real_hobby",
			"accountability", "anchor", "zen_pulsar", "focus_pillar"]
	var built := 0
	var oi := 0
	for sp: Vector2i in spots:
		if oi >= order.size():
			break
		GameState.selected_habit = order[oi]
		game._hover_cell = sp
		if game._can_build(sp):
			game._build_on(sp)
			if game.is_aiming:
				game._end_aiming()
			built += 1
			oi += 1
	print("postaveno %d vezi" % built)

	game.wave_index = 0
	game._static_overlay.queue_redraw()
	await _shot("1_pred")

	game.wave_index = 1                       # vlna 2: telegraf sviti
	game._static_overlay.queue_redraw()
	await _shot("2_telegraf")

	game.wave_index = 2                       # vlna 3: otevre se
	game._open_due_trods(3)
	await _shot("3_otevreno")

	_done = true
	get_tree().quit(0)
