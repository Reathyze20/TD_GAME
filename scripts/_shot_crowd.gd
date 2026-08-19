extends Node
## Vyfoti pole zaplavene distrakcemi. Presne ta otazka, kvuli ktere se menil rastr:
## "az jich tam budou stovky, pujde to jeste precist?"
##
## Spusteni (NE --headless, kresleni potrebuje skutecny renderer):
##   godot --path <proj> --main-scene res://scenes/_shot_crowd.tscn -- --out build/crowd.png --n 120

var _done := false


func _ready() -> void:
	call_deferred("_run")


func _arg(name: String, fallback: String) -> String:
	var args := OS.get_cmdline_user_args()
	for i in range(args.size()):
		if args[i] == name and i + 1 < args.size():
			return args[i + 1]
	return fallback


func _run() -> void:
	var out := _arg("--out", "build/crowd.png")
	var n := int(_arg("--n", "120"))

	var game = load("res://scenes/Game.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	# Bez obrany jadro vyhori a _game_over() prehodi scenu jeste pred fotkou -- a vzal
	# by s sebou i tenhle uzel, protoze harness je RODIC Game. Viz reference-godot-binary.
	GameState.max_focus = 999999
	GameState.focus = 999999
	game.fog_enabled = false
	await get_tree().process_frame

	# Rozeset je po VOLNE podlaze, ne po jedne draze: chceme videt, jak husty dav je,
	# ne jak vypada zastup.
	var g = Data.GRID
	var volne: Array[Vector2i] = []
	for cy in range(int(g.rows)):
		for cx in range(int(g.cols)):
			var c := Vector2i(cx, cy)
			if not game.high_ground.has(c) and c != game.objective_cell:
				volne.append(c)

	var druhy := ["notification", "autoplay", "doomscroll", "phantom_buzz",
		"clickbait", "adult_content", "group_chat", "energy_drink", "jackpot"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260818
	var spawnuto := 0
	for i in range(n):
		var cell: Vector2i = volne[rng.randi() % volne.size()]
		var d = game.spawn_distraction(StringName(druhy[i % druhy.size()]), cell)
		if d != null:
			spawnuto += 1
	await get_tree().process_frame
	await get_tree().process_frame

	var img := get_viewport().get_texture().get_image()
	img.save_png(out)
	print("shot_crowd: %s  %dx%d  |  %d distrakci na poli" % [out, img.get_width(),
		img.get_height(), spawnuto])
	_done = true
	get_tree().quit(0)
