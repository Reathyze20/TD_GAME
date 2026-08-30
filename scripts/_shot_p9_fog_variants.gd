extends Node
## P9 — "brainfog jako vizuál". Vyfotí ČTYŘI varianty téhož momentu hry, aby uživatel mohl
## vybrat, jak by měla vypadat neosvětlená (nebo dřív viděná, ale teď mimo dosah) plocha:
##
##   p9_fog_baseline.png       shipped brain_fog.gdshader, beze změny (srovnávací základ)
##   p9_fog_blur.png           tma je rozostřený pohled na svět (screen-space box blur)
##   p9_fog_desaturate.png     tma je odbarvený pohled na svět (drain k luminanci)
##   p9_fog_blur_desaturate.png obojí najednou
##
## Scéna (postavené návyky v různých úhlech/šířkách) je zkopírovaná z _shot_fog.gd, aby byly
## čtyři snímky srovnatelné s existující fog fotkou a ne jen mezi sebou.
##
## Technika rozostření/odbarvení: shaders/brain_fog_preview.gdshader, dočasně nasazený na
## STEJNÝ _fog_rect uzel, který hra už staví v _build_fog_layer(). Žádná herní logika se
## nemění — jen se čtyřikrát vymění material na jednom uzlu a vyfotí.
##
## Spuštění (NE --headless, kreslení potřebuje skutečný renderer; --main-scene, ne --script):
##   godot --path <proj> --main-scene res://scenes/_shot_p9_fog_variants.tscn -- --out-dir .dev/screenshots

const HABIT := "focus_timer"


func _ready() -> void:
	call_deferred("_run")


func _arg(name: String, fallback: String) -> String:
	var args := OS.get_cmdline_user_args()
	for i in range(args.size()):
		if args[i] == name and i + 1 < args.size():
			return args[i + 1]
	return fallback


func _save(img: Image, path: String) -> bool:
	if img.save_png(path) != OK:
		printerr("_shot_p9_fog_variants: uložení selhalo: %s" % path)
		return false
	print("_shot_p9_fog_variants: %s  %dx%d" % [path, img.get_width(), img.get_height()])
	return true


func _run() -> void:
	var out_dir := _arg("--out-dir", ".dev/screenshots")
	if not DirAccess.dir_exists_absolute(out_dir):
		DirAccess.make_dir_recursive_absolute(out_dir)

	var game: Game = load("res://scenes/Game.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	# Bez obrany jádro vyhoří a _game_over() přepne scénu ještě před fotkou (viz _shot_fog.gd).
	GameState.max_focus = 999999
	GameState.focus = 999999
	GameState.dopamine = 100000
	await get_tree().process_frame

	# Stejná sada úhlů/šířek jako _shot_fog.gd — jedna úzká daleká výseč, jedna široká mělká,
	# aby bylo na fotce vidět, jak rozostření/odbarvení dopadá na obě.
	var uhly := [0.0, PI * 0.5, PI, PI * 1.5, PI * 0.25]
	var siroko := [30.0, 60.0, 90.0, 120.0, 45.0]

	var kandidati: Array = []
	for cell: Vector2i in game.build_spots:
		var bs = game.build_spots[cell]
		if bs.state != BuildSpot.State.EMPTY \
				or not game.is_position_in_routine(game.cell_center(cell),
					game._routine_sources):
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
	game._end_aiming()
	GameState.select_habit(null)
	print("_shot_p9_fog_variants: postaveno %d návyků" % i)

	for _f in range(60):
		await get_tree().process_frame

	if game._fog_rect == null or game._fog_mat == null or game._light_viewport == null:
		printerr("_shot_p9_fog_variants: fog layer se nepostavil (fog_enabled?)")
		get_tree().quit(1)
		return

	# --- 1. baseline: shipped shader, beze změny -----------------------------------------
	await get_tree().process_frame
	var ok := true
	ok = _save(get_viewport().get_texture().get_image(),
		out_dir.path_join("p9_fog_baseline.png")) and ok

	# --- 2..4: preview shader, čtyři kombinace blur_px / desaturate_amount ----------------
	var preview_mat := ShaderMaterial.new()
	preview_mat.shader = load("res://shaders/brain_fog_preview.gdshader")
	preview_mat.set_shader_parameter("light_mask", game._light_viewport.get_texture())
	# fog_color/fog_alpha are left unset here on purpose: brain_fog_preview.gdshader declares
	# the SAME defaults as the shipped shader (0.055,0.025,0.105 / 0.88), and game._fog_mat
	# never overrides them from GDScript either (_build_fog_layer only ever sets light_mask
	# and _update_fog only ever touches reveal) — so both shaders already agree without a copy.
	preview_mat.set_shader_parameter("reveal", 0.0)
	preview_mat.set_shader_parameter("haze_mix", 0.45)
	game._fog_rect.material = preview_mat

	var variants := [
		{"name": "p9_fog_blur.png", "blur_px": 3.0, "desaturate_amount": 0.0},
		{"name": "p9_fog_desaturate.png", "blur_px": 0.0, "desaturate_amount": 1.0},
		{"name": "p9_fog_blur_desaturate.png", "blur_px": 3.0, "desaturate_amount": 1.0},
	]
	for v: Dictionary in variants:
		preview_mat.set_shader_parameter("blur_px", v["blur_px"])
		preview_mat.set_shader_parameter("desaturate_amount", v["desaturate_amount"])
		# Pár snímků na usazení SCREEN_TEXTURE backbufferu a parametrů, i když UPDATE_ALWAYS
		# na masce by to zvládl za jeden.
		for _f in range(3):
			await get_tree().process_frame
		ok = _save(get_viewport().get_texture().get_image(),
			out_dir.path_join(String(v["name"]))) and ok

	get_tree().quit(0 if ok else 1)
