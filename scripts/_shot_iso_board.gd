extends Node
## Snimek iso desky pro posouzeni artu. Docasny harness -- po pouziti smazat.
##
## Bezi pres --main-scene (ne --script), protoze SceneTree skript nema autoloady
## (Data, GameState) -- viz reference-godot-binary.
##
## NE --headless: dummy renderer nema viewport texturu a get_image() vrati null.
##   godot --path <proj> --main-scene res://scenes/_shot_iso_board.tscn

var _done := false

func _ready() -> void:
	# Bez veze se Focus vycerpa a _game_over() prepne scenu i s timhle uzlem -- vypada
	# to jako tichy zasek. Viz reference-godot-binary, "Game-over scene-swap gotcha".
	GameState.max_focus = 999999
	GameState.focus = 999999
	for i in range(Data.get_level_count()):
		if Data.get_level(i).id == 99:
			GameState.current_level_index = i
			break
	GameState.designer_mode = true
	var game: Game = load("res://scenes/Game.tscn").instantiate()
	add_child(game)
	var wd := Timer.new()
	wd.wait_time = 40.0
	wd.one_shot = true
	wd.timeout.connect(func():
		if not _done:
			print("SHOT FAILED: nedobehlo")
			get_tree().quit(1))
	add_child(wd); wd.start()
	await get_tree().process_frame
	# Postav po jedne od kazdeho habitu, at je videt cela rodina vezi na desce naraz.
	GameState.dopamine = 100000
	GameState.bandwidth_used = 0
	var spots: Array = game.build_spots.keys()
	spots.sort_custom(func(a, b): return (a.x + a.y) < (b.x + b.y))
	var order := ["focus_pillar", "mindfulness", "focus_timer", "exercise",
			"real_hobby", "zen_pulsar", "accountability", "anchor"]
	var i2 := 0
	for h in order:
		while i2 < spots.size():
			var sp: Vector2i = spots[i2]
			i2 += 1
			GameState.selected_habit = h
			game._hover_cell = sp
			if game._can_build(sp):
				game._build_on(sp)
				if game.is_aiming:
					game._end_aiming()
				print("postaveno %s na %s" % [h, sp])
				break
	for i in range(45):
		await get_tree().process_frame
	# Musi se pockat na frame_post_draw, jinak je viewport textura jeste null.
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute("res://build")
	var err := img.save_png("res://build/iso_board.png")
	print("SHOT: %s %dx%d err=%d" % ["build/iso_board.png", img.get_width(), img.get_height(), err])
	_done = true
	get_tree().quit(0)
