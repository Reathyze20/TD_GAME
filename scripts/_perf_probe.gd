extends Node
## Zmeri, kde se ztraci cas po zjemneni mrizky. Nehada -- rozdeli praci na kusy a kazdy
## kus vypne, aby bylo videt, kolik stal.
##
## Spusteni (NE --headless, mlha potrebuje skutecny renderer):
##   godot --path <proj> --main-scene res://scenes/_perf_probe.tscn -- --n 140

var completed := false
var _game: Game = null


func _ready() -> void:
	call_deferred("_run")


func _arg(name: String, fallback: String) -> String:
	var args := OS.get_cmdline_user_args()
	for i in range(args.size()):
		if args[i] == name and i + 1 < args.size():
			return args[i + 1]
	return fallback


## Prumer a nejhorsi snimek za `frames` snimku. Nejhorsi snimek je to, co hrac citi
## jako seknuti -- prumer sam o sobe trhani schova.
func _mer(frames: int) -> Dictionary:
	# Merime OBOJI: TIME_PROCESS je skriptova prace, wall-clock je to, co hrac citi.
	# Kdyz je wall-clock vyrazne vetsi nez process, ceka se na grafiku, ne na kod.
	var proc: Array[float] = []
	var wall: Array[float] = []
	for i in range(frames):
		var t0 := Time.get_ticks_usec()
		await get_tree().process_frame
		wall.append((Time.get_ticks_usec() - t0) / 1000.0)
		proc.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
	proc.sort()
	wall.sort()
	var sp := 0.0
	for c in proc:
		sp += c
	var sw := 0.0
	for c in wall:
		sw += c
	return {"prumer": sp / proc.size(), "p95": proc[int(proc.size() * 0.95)],
		"max": proc[proc.size() - 1], "wall": sw / wall.size(),
		"wall_max": wall[wall.size() - 1]}


func _radek(tag: String, m: Dictionary) -> void:
	print("  %-14s skript %6.2f ms (max %6.2f)   snimek %6.2f ms (max %6.2f) = %4.1f FPS"
		% [tag, m["prumer"], m["max"], m["wall"], m["wall_max"],
			1000.0 / maxf(m["wall"], 0.001)])


func _run() -> void:
	var n := int(_arg("--n", "140"))
	var wd := Timer.new()
	wd.wait_time = 120.0
	wd.one_shot = true
	add_child(wd)
	wd.timeout.connect(func():
		if not completed:
			print("FAILED: probe nedobehl")
			get_tree().quit(1))
	wd.start()

	# Bez vsync, jinak se vsechno pod 60 FPS tvari jako presne 16,7 ms a nejde poznat,
	# kolik rezervy tam ve skutecnosti je.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0

	_game = load("res://scenes/Game.tscn").instantiate()
	add_child(_game)
	await get_tree().process_frame
	GameState.max_focus = 999999
	GameState.focus = 999999
	GameState.dopamine = 100000
	await get_tree().process_frame

	var g := Data.GRID
	print("\nmrizka %d x %d po %d px, %d bunek" % [g.cols, g.rows, g.tile,
		int(g.cols) * int(g.rows)])

	print("\nPRAZDNE POLE")
	var m1 := await _mer(120)
	_radek("mlha ZAP", m1)
	_game.fog_enabled = false
	await get_tree().process_frame
	var m2 := await _mer(120)
	_radek("mlha VYP", m2)
	_game.fog_enabled = true
	await get_tree().process_frame

	# Nasypat distrakce na volnou podlahu.
	var volne: Array[Vector2i] = []
	for cy in range(int(g.rows)):
		for cx in range(int(g.cols)):
			var c := Vector2i(cx, cy)
			if not _game.high_ground.has(c) and c != _game.objective_cell:
				volne.append(c)
	var druhy := ["notification", "autoplay", "doomscroll", "phantom_buzz",
		"clickbait", "adult_content", "group_chat", "energy_drink", "jackpot"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260818
	var t0 := Time.get_ticks_usec()
	for i in range(n):
		_game.spawn_distraction(StringName(druhy[i % druhy.size()]),
			volne[rng.randi() % volne.size()])
	var t_spawn := (Time.get_ticks_usec() - t0) / 1000.0
	await get_tree().process_frame
	print("\n%d DISTRAKCI  (spawn vcetne %d hledani cesty trval %.1f ms)" % [n, n, t_spawn])
	var m3 := await _mer(180)
	_radek("mlha ZAP", m3)
	_game.fog_enabled = false
	await get_tree().process_frame
	var m4 := await _mer(180)
	_radek("mlha VYP", m4)

	# Jedno prohledani cesty pres celou desku, samostatne.
	var start: Vector2i = _game.spawn_zone_cells[0][0]
	t0 = Time.get_ticks_usec()
	for i in range(50):
		_game.astar.get_id_path(start, _game.objective_cell)
	print("\n  jedno get_id_path pres desku:      %.3f ms"
		% ((Time.get_ticks_usec() - t0) / 1000.0 / 50.0))

	completed = true
	print("\nHOTOVO")
	get_tree().quit(0)
