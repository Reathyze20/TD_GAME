extends Node
## Vyfotí pole se STEJNÝM postavením věží dvakrát — s game.shadow_enabled vypnutým a
## zapnutým — aby šlo přímo porovnat, jestli nové Light2D + LightOccluder2D vržené stíny
## opravdu něco mění, a ne jen "nespadlo to".
##
## Doplněk k _shot_fog.gd (ten testuje mlhu samotnou); tady je předmětem zkoušky
## SVĚTLO A STÍN NAVÍC KE MLZE (mlha zůstává default ZAPNUTÁ — to je stav, ve kterém
## systém reálně poběží).
##
## Spuštění (NE --headless, kreslení + stíny potřebují skutečný renderer; --main-scene,
## ne --script, protože stavění návyků potřebuje autoloady):
##   godot --path <proj> --main-scene res://scenes/_shot_shadows.tscn -- --out build/shadow

const TOWER := "focus_timer"


func _ready() -> void:
	call_deferred("_run")


func _arg(name: String, fallback: String) -> String:
	var args := OS.get_cmdline_user_args()
	for i in range(args.size()):
		if args[i] == name and i + 1 < args.size():
			return args[i + 1]
	return fallback


## Empty build spots inside the CURRENT Routine, farthest from the core first — same
## selection idea as _shot_fog.gd, re-run after each build because an Anchor extends
## _routine_sources and opens up spots that were dark a moment ago.
func _candidates(game: Game) -> Array:
	var out: Array = []
	for cell: Vector2i in game.build_spots:
		var bs = game.build_spots[cell]
		if bs.state != BuildSpot.State.EMPTY \
				or not game.is_position_in_routine(game.cell_center(cell), game._routine_sources):
			continue
		out.append(cell)
	out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return game.cell_center(a).distance_to(game.objective_pos) \
			> game.cell_center(b).distance_to(game.objective_pos))
	return out


func _build(game: Game, type_key: String, cell: Vector2i, facing: float, arc: float) -> Variant:
	GameState.select_habit(type_key)
	game._build_on(cell)
	game._end_aiming()
	var h = game.build_spots[cell].current_habit
	if h is Habit:
		h.facing_angle = facing
		h.set_arc_angle(arc)
	return h


func _save(img: Image, path: String) -> void:
	var dir := path.get_base_dir()
	if dir != "" and not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	if img.save_png(path) != OK:
		printerr("_shot_shadows: uložení selhalo: ", path)
		return
	print("_shot_shadows: %s  %dx%d" % [path, img.get_width(), img.get_height()])


func _run() -> void:
	var out_prefix := _arg("--out", "build/shadow")

	var game: Game = load("res://scenes/Game.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	# Bez obrany jádro vyhoří a _game_over() přepne scénu ještě před fotkou (viz
	# reference-godot-binary — harness je RODIČ Game, takže by o strom přišel i on).
	GameState.max_focus = 999999
	GameState.focus = 999999
	GameState.dopamine = 999999
	await get_tree().process_frame

	# 1) Jeden Anchor co nejdál od jádra, ještě v jeho světle — ANCHOR_ROUTINE_RADIUS
	# (260) je největší poloměr kromě jádra samotného, takže je nejpravděpodobnější, že
	# jeho lampa narazí na blízkou zeď a stín bude na fotce jasně vidět.
	var anchor_cell := Vector2i(-999, -999)
	var first_pass := _candidates(game)
	if not first_pass.is_empty():
		anchor_cell = first_pass[0]
		_build(game, "anchor", anchor_cell, 0.0, 60.0)
	await get_tree().process_frame  # nechat _update_routine_reach() zpracovat nový Anchor

	# 2) Pár běžných věží, různé úhly/šířky — stejná myšlenka jako _shot_fog.gd, teď na
	# větším dosahu díky Anchoru výše.
	var uhly := [0.0, PI * 0.5, PI, PI * 1.5, PI * 0.25]
	var siroko := [30.0, 60.0, 90.0, 120.0, 45.0]
	var built_cells: Array = [anchor_cell]
	var i := 0
	for cell: Vector2i in _candidates(game):
		if i >= uhly.size():
			break
		var too_close := false
		for prev: Vector2i in built_cells:
			if game.cell_center(cell).distance_to(game.cell_center(prev)) < 150.0:
				too_close = true
				break
		if too_close:
			continue
		_build(game, TOWER, cell, uhly[i], siroko[i])
		built_cells.append(cell)
		i += 1

	# 3) Jedna Nutrition Guild ("accountability", is_blocker=true -> Barracks) — ověřuje,
	# že "postavená věž" v tomhle novém systému znamená STEJNOU množinu jako ve mlze
	# (_building_sight_lights dává základní lampu KAŽDÉMU postavenému spotu, ne jen
	# Habit-um), ne jen turrety.
	var remaining := _candidates(game)
	if not remaining.is_empty():
		_build(game, "accountability", remaining[0], 0.0, 60.0)

	game._end_aiming()
	GameState.select_habit(null)
	print("_shot_shadows: anchor@%s, %d věží, postaveno celkem %d, bandwidth %d/%d"
		% [anchor_cell, i, game.build_spots.values().filter(
			func(s): return s.state == BuildSpot.State.BUILT).size(),
			GameState.bandwidth_used, GameState.bandwidth_max])

	# Zoom okno na Anchor — tam je stín nejlíp vidět. Anchor lampa má průměr 520 px, okno
	# 600x600 dá kolem ní i kus okolní zdi/chodby.
	var anchor_pos: Vector2 = game.cell_center(anchor_cell)
	# CANVAS-space window; converted to readback pixels per grab via UI.readback_rect(),
	# because stretch mode "canvas_items" renders at window resolution and the image that
	# comes back is 4x these coordinates (2026-09-05 — see the note in ui.gd).
	var zoom_canvas := Rect2(anchor_pos - Vector2(300, 300), Vector2(600, 600))

	for _f in range(30):
		await get_tree().process_frame

	# --- OFF ---
	game.shadow_enabled = false
	for _f in range(20):
		await get_tree().process_frame
	var img_off := get_viewport().get_texture().get_image()
	_save(img_off, out_prefix + "_off_wide.png")
	var zoom_off := img_off.get_region(
		UI.readback_rect(get_viewport(), img_off, zoom_canvas))
	# 2x the CANVAS crop, derived -- a blind *2 on a readback that is already 4x canvas
	# would write an 8x image (2026-09-05 stretch-mode change).
	var zup := maxi(1, int(round(2.0 / UI.readback_scale(get_viewport(), img_off))))
	if zup > 1:
		zoom_off.resize(zoom_off.get_width() * zup, zoom_off.get_height() * zup,
			Image.INTERPOLATE_NEAREST)
	_save(zoom_off, out_prefix + "_off_zoom.png")

	# --- ON ---
	game.shadow_enabled = true
	for _f in range(20):
		await get_tree().process_frame
	var img_on := get_viewport().get_texture().get_image()
	_save(img_on, out_prefix + "_on_wide.png")
	var zoom_on := img_on.get_region(
		UI.readback_rect(get_viewport(), img_on, zoom_canvas))
	if zup > 1:
		zoom_on.resize(zoom_on.get_width() * zup, zoom_on.get_height() * zup,
			Image.INTERPOLATE_NEAREST)
	_save(zoom_on, out_prefix + "_on_zoom.png")

	print("_shot_shadows: occluder count = %d" % game._shadow_occluder_count)
	print("HOTOVO")
	get_tree().quit(0)
