extends Node
## Vizuální retest všeho, co přibylo: série, cue conditioning, effort discounting,
## mapa levelu 98 a obrazovka mezi levely.
##
## Headless testy říkají "spočítalo se to správně". Neříkají "je to na obrazovce vidět",
## a půlka těchhle mechanik JE jenom to, co hráč vidí — série musí být čitelná na první
## pohled, cue musí viditelně zesílit, účtenka musí mít řádky. To se dá zkontrolovat
## jedině tak, že se to vykreslí a někdo se na to podívá.
##
## Potřebuje SKUTEČNÝ renderer (--main-scene, NE --headless: čte pixely zpátky
## z viewportu), stejně jako _shot_flat.gd.
##
## Spuštění:
##   godot --path <proj> --main-scene res://scenes/_shot_verify.tscn -- --out build/verify

var _out := "build/verify"

func _ready() -> void:
	call_deferred("_run")

func _arg(name: String, fallback: String) -> String:
	var args := OS.get_cmdline_user_args()
	for i in range(args.size()):
		if args[i] == name and i + 1 < args.size():
			return args[i + 1]
	return fallback

func _save(img: Image, name: String) -> void:
	var path := "%s/%s.png" % [_out, name]
	var dir := path.get_base_dir()
	if dir != "" and not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	if img.save_png(path) != OK:
		printerr("_shot_verify: ulozeni selhalo: ", path)
		return
	print("_shot_verify: %s  %dx%d" % [path, img.get_width(), img.get_height()])

## Dva snimky viewportu po sobe — jeden nestaci, prvni casto chyti frame pred tim, nez
## se zmena UI propsala.
func _grab() -> Image:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()

func _shot(name: String, crop := Rect2i()) -> void:
	var img: Image = await _grab()
	if crop.size.x > 0:
		var r := crop.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
		if r.size.x > 0 and r.size.y > 0:
			img = img.get_region(r)
	_save(img, name)

func _level_index(id: int) -> int:
	for i in range(Data.get_level_count()):
		if Data.get_level(i).id == id:
			return i
	return 0

func _run() -> void:
	_out = _arg("--out", _out)
	GameState.designer_mode = false
	GameState.current_level_index = _level_index(98)

	var game: Game = load("res://scenes/Game.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	GameState.dopamine = 99999
	GameState.forget_conditioning()

	# --- 1. mapa levelu 98, prazdna: cte se ta spirala? -----------------------
	await _shot("01_level98_prazdna")

	# --- 2. postavene navyky: sedi na podlozkach, jsou v Routine? -------------
	var built := 0
	for cell in game.build_spots.keys():
		if built >= 4:
			break
		if not game._can_build(cell):
			continue
		GameState.dopamine = 99999
		GameState.select_habit("focus_timer" if built % 2 == 0 else "mindfulness")
		game._build_on(cell)
		game._end_aiming()
		built += 1
		await get_tree().process_frame
	print("_shot_verify: postaveno %d navyku" % built)
	await _shot("02_level98_postaveno")

	# --- 3. HUD se serii ------------------------------------------------------
	var hud_rect := Rect2i(0, 0, 1200, 130)
	GameState.streak = 0
	GameState.begin_wave_streak_window()
	for i in range(4):
		GameState.begin_wave_streak_window()
		GameState.note_wave_cleared()
	await _shot("03_hud_serie_bezi", hud_rect)

	# --- 4. HUD po zlomu + plovouci text --------------------------------------
	game.started = true
	game.between_waves = false
	SignalBus.distraction_escaped.emit(1)
	await get_tree().process_frame
	await _shot("04_hud_serie_zlomena", hud_rect)
	# A cely obraz, at je videt, kde ten plovouci text vylezl.
	await _shot("05_zlom_cely_obraz")

	# --- 5. cue slaby vs silny -------------------------------------------------
	var cue_rect := Rect2i(0, 0, 320, 180)
	GameState.forget_conditioning()
	GameState.condition_cue(true)
	game._fire_cue(true)
	await _shot("06_cue_slaby", cue_rect)
	for i in range(8):
		GameState.condition_cue(true)
	game._fire_cue(true)
	await _shot("07_cue_silny", cue_rect)

	# --- 6. effort discounting: nabidka a auto-aim -----------------------------
	GameState.set_tolerance(70.0)
	game._effort_offered = false
	game._update_effort_offer()
	await get_tree().process_frame
	await _shot("08_nabidka_auto_aim")
	game.toggle_auto_aim()
	await get_tree().process_frame
	await _shot("09_auto_aim_zapnuty")

	game.queue_free()
	await get_tree().process_frame

	# --- 7. obrazovka mezi levely: karta s citaci + uctenka s radky ------------
	# Dva zaznamy, aby uctenka mela s cim parovat — to je cely duvod, proc level 98
	# vznikl, takze je to ta nejdulezitejsi vec na tehle strance.
	Mirror.history.clear()
	Mirror.begin_level(98)
	Mirror.mark(&"prep_span", 26.0)
	Mirror.mark(&"cue_pull", 0.35)
	Mirror.mark(&"streak", 3)
	Mirror.end_level()
	Mirror.begin_level(99)
	Mirror.mark(&"prep_span", 4.0)
	Mirror.mark(&"cue_pull", 0.9)
	Mirror.mark(&"cue_reinstated", 0.9)
	Mirror.mark(&"streak", 7)
	Mirror.mark(&"streak_broken", 7)
	Mirror.mark(&"bait_kill", &"fomo")
	Mirror.end_level()
	GameState.current_level_index = _level_index(99)
	GameState.last_run_stats = {"stars": 2, "kills": 84, "waves_cleared": 5,
		"max_wave": 5, "focus": 14, "max_focus": 20}
	var edu = load("res://scenes/Education.tscn").instantiate()
	add_child(edu)
	await get_tree().process_frame
	await _shot("10_mezi_levely")

	print("_shot_verify: hotovo")
	get_tree().quit(0)
