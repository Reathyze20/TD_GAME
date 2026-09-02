extends Node
## Vyfotí hru SE ZAPNUTOU mlhou a s pár postavenými návyky, aby šlo okem zkontrolovat,
## jak vypadá osvětlená výseč.
##
## Doplněk k tools/shot_game.gd, který mlhu naopak vypíná — ten kontroluje rastr a kresbu,
## kde je tma na obtíž. Tady je tma předmět zkoušky.
##
## Spuštění (NE --headless, kreslení potřebuje skutečný renderer; a --main-scene, ne
## --script, protože stavění návyků potřebuje autoloady):
##   godot --path <proj> --main-scene res://scenes/_shot_fog.tscn -- --out build/fog.png

const HABIT := "focus_timer"


func _ready() -> void:
	call_deferred("_run")


func _arg(name: String, fallback: String) -> String:
	var args := OS.get_cmdline_user_args()
	for i in range(args.size()):
		if args[i] == name and i + 1 < args.size():
			return args[i + 1]
	return fallback


func _run() -> void:
	var out := _arg("--out", "build/fog.png")
	# PICK A LEVEL THAT SHIPS FOG, BEFORE Game is built. This harness's header promises a
	# photo "SE ZAPNUTOU mlhou" but never selected a level for it -- it took whatever
	# GameState happened to point at, which is level 1, and level 1 ships `fog = false`
	# (M3). So it was quietly photographing a FOGLESS board while being read as the fog
	# reference shot: worse than no picture, because it answers "does the fog look right?"
	# with a picture of no fog. Third instance of the inherited-subject bug, after
	# _test_fog_bandwidth (P8b) and _test_effort.
	#
	# And it has to be the LEVEL, not `game.fog_enabled = true` after the fact: Game only
	# builds the fog's SubViewport/shader layer in _ready(), and _build_fog_layer() returns
	# immediately when fog is off. Flipping the flag later gives you the gameplay grid
	# (_lit_cells, is_pos_visible) with no visual at all -- fine for the _test_fog* fixtures,
	# which measure exactly that grid, and useless for a screenshot.
	for i in range(Data.get_level_count()):
		if Data.get_level(i).fog:
			GameState.current_level_index = i
			break
	var game: Game = load("res://scenes/Game.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	# Bez obrany jádro vyhoří a _game_over() přepne scénu ještě před fotkou.
	GameState.max_focus = 999999
	GameState.focus = 999999
	GameState.dopamine = 100000
	await get_tree().process_frame

	# Postavit, co jde, a každému dát jiný směr a šířku — na jedné fotce má být vidět
	# jak úzký daleký kužel, tak široký mělký.
	var uhly := [0.0, PI * 0.5, PI, PI * 1.5, PI * 0.25]
	var siroko := [30.0, 60.0, 90.0, 120.0, 45.0]

	# Místa co NEJDÁL od jádra, ale kde SE OPRAVDU DÁ STAVĚT. U jádra by je jeho vlastní
	# světlo přesvítilo a na snímku by z výsečí nebylo nic vidět.
	#
	# Brána je `game._can_build()`, tedy TÁŽ funkce, kterou používá klik hráče — ne
	# `is_position_in_routine()` jako dřív. Ten proxy o `routine_gates_enabled` neví, takže
	# na levelu, který Routine bránu vypíná (level 98), odmítl KAŽDÉ místo a harness
	# vyfotil desku s nula návyky: samotné světlo jádra a ani jeden kužel — přesně to, co
	# má snímek ukazovat, chybělo.
	var kandidati: Array = []
	for cell: Vector2i in game.build_spots:
		var bs = game.build_spots[cell]
		if bs.state != BuildSpot.State.EMPTY or not game._can_build(cell):
			continue
		kandidati.append(cell)
	kandidati.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return game.cell_center(a).distance_to(game.objective_pos) \
			> game.cell_center(b).distance_to(game.objective_pos))

	var i := 0
	var posledni: Vector2i = Vector2i(-99, -99)
	for cell: Vector2i in kandidati:
		if i >= uhly.size():
			break
		# Rozestup, ať se dvě výseče nepřekryjí do jedné kaše.
		if i > 0 and game.cell_center(cell).distance_to(game.cell_center(posledni)) < 200.0:
			continue
		GameState.select_habit(HABIT)
		game._build_on(cell)
		game._end_aiming()
		var h = game.build_spots[cell].current_habit
		if h is Habit:
			h.facing_angle = uhly[i]
			h.set_arc_angle(siroko[i])
			posledni = cell
			i += 1
	# Náhled míření je UI a přes celou desku by kreslil kruh dostřelu — na fotku světla
	# nepatří.
	game._end_aiming()
	GameState.select_habit(null)
	print("_shot_fog: postaveno %d návyků" % i)

	for _f in range(60):
		await get_tree().process_frame

	var img := get_viewport().get_texture().get_image()
	var dir := out.get_base_dir()
	if dir != "" and not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	if img.save_png(out) != OK:
		printerr("_shot_fog: uložení selhalo")
		get_tree().quit(1)
		return
	print("_shot_fog: %s  %dx%d" % [out, img.get_width(), img.get_height()])
	get_tree().quit(0)
