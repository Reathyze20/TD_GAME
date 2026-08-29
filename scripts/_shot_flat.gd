extends Node
## Vyfotí ISO pole třikrát při rostoucí Toleranci — s "depth channel" zapnutým.
##
## Předmětem zkoušky je JEDEN designový nápad: v isometrii nemá Tolerance šedit obraz,
## ale ZHASÍNAT SVĚTLA. Anhedonie není šedá, je plochá — lidi ji nepopisují jako
## "vybledlé", ale jako "všechno stejné, nic nevystupuje". Otázka, na kterou tenhle
## harness odpovídá, zní: říká to ta scéna doopravdy, nebo to jenom vypadá jako když
## se rozbila světla?
##
## Odpovídá se to jedině tak, že se to vykreslí v herním měřítku a porovná — viz
## docs/design/dopamine_mechanics.md §3 a poznámka o kanálech v game.gd.
##
## Potřebuje SKUTEČNÝ renderer (--main-scene, NE --headless: světla a stíny počítá GPU
## a tohle čte pixely zpátky z viewportu) — stejně jako _shot_shadows.gd.
##
## Spuštění:
##   godot --path <proj> --main-scene res://scenes/_shot_flat.tscn -- --out build/flat

const TOWER := "focus_timer"
## Tolerance, při kterých se fotí. 0 = jak je level nasvícený autorsky, 95 = plocho.
const STEPS := [0.0, 50.0, 95.0]


func _ready() -> void:
	call_deferred("_run")


func _arg(name: String, fallback: String) -> String:
	var args := OS.get_cmdline_user_args()
	for i in range(args.size()):
		if args[i] == name and i + 1 < args.size():
			return args[i + 1]
	return fallback


func _save(img: Image, path: String) -> void:
	var dir := path.get_base_dir()
	if dir != "" and not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	if img.save_png(path) != OK:
		printerr("_shot_flat: uložení selhalo: ", path)
		return
	print("_shot_flat: %s  %dx%d" % [path, img.get_width(), img.get_height()])


## Prázdná místa uvnitř Routine, nejdál od jádra — stejný výběr jako _shot_shadows.gd.
## Daleko od jádra proto, že tam lampa věže naráží na zeď a stín je vidět.
func _candidates(game) -> Array:
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


func _build(game, type_key: String, cell: Vector2i, facing: float, arc: float):
	GameState.select_habit(type_key)
	game._build_on(cell)
	game._end_aiming()
	var h = game.build_spots[cell].current_habit
	if h is Habit:
		h.facing_angle = facing
		h.set_arc_angle(arc)
	return h


## Průměrný jas obrázku, 0..1. Číslo vedle fotky: "plocho" musí být měřitelně tmavší A
## měřitelně méně kontrastní, jinak je to jen ztlumený obraz pod jiným jménem.
func _stats(img: Image) -> Dictionary:
	var sum := 0.0
	var sum_sq := 0.0
	var n := 0
	# Vzorkuje po 4 px — celý 1080p obrázek po jednom pixelu je zbytečně pomalý a na
	# průměr i rozptyl to nemá vliv.
	for y in range(0, img.get_height(), 4):
		for x in range(0, img.get_width(), 4):
			var v: float = img.get_pixel(x, y).get_luminance()
			sum += v
			sum_sq += v * v
			n += 1
	var mean: float = sum / maxf(float(n), 1.0)
	return {"mean": mean, "sd": sqrt(maxf(sum_sq / float(n) - mean * mean, 0.0))}


func _run() -> void:
	var out_prefix := _arg("--out", "build/flat")

	# Iso level je id 99; Data řadí podle id, takže index se musí najít, ne hádat.
	var iso_index := -1
	for i in range(Data.get_level_count()):
		if Data.get_level(i).id == 99:
			iso_index = i
			break
	if iso_index < 0:
		printerr("_shot_flat: level s id 99 (iso) nenalezen")
		get_tree().quit(1)
		return
	GameState.current_level_index = iso_index

	var game = load("res://scenes/Game.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame

	# game.gd:_ready vypíná stíny pro id 99 (slice je má záměrně mimo scope). Tady jsou
	# ale předmětem zkoušky, takže zpátky ON — a mlha OFF, aby se do měření nepletl
	# druhý celoobrazovkový stmívač.
	game.shadow_enabled = true
	game.fog_enabled = false
	GameState.max_focus = 999999
	GameState.focus = 999999
	GameState.dopamine = 999999
	await get_tree().process_frame

	print("_shot_flat: occluder count = %d" % game._shadow_occluder_count)
	print("_shot_flat: depth channel active = %s" % str(game._depth_channel_active()))

	# Jeden Anchor co nejdál (největší lampa) + pár běžných věží.
	var first_pass := _candidates(game)
	var anchor_cell := Vector2i(-999, -999)
	if not first_pass.is_empty():
		anchor_cell = first_pass[0]
		_build(game, "anchor", anchor_cell, 0.0, 60.0)
	await get_tree().process_frame

	var uhly := [0.0, PI * 0.5, PI, PI * 1.5]
	var siroko := [30.0, 60.0, 90.0, 45.0]
	var built: Array = [anchor_cell]
	var i := 0
	for cell: Vector2i in _candidates(game):
		if i >= uhly.size():
			break
		var too_close := false
		for prev: Vector2i in built:
			if game.cell_center(cell).distance_to(game.cell_center(prev)) < 120.0:
				too_close = true
				break
		if too_close:
			continue
		_build(game, TOWER, cell, uhly[i], siroko[i])
		built.append(cell)
		i += 1
	print("_shot_flat: postaveno %d věží" % built.size())
	for cell: Vector2i in built:
		if cell.x <= -999:
			continue
		var hh: bool = game.high_ground.has(cell)
		var h = game.build_spots[cell].current_habit if game.build_spots.has(cell) else null
		print("_shot_flat:   cell=%s  high_ground=%s  habit.pos=%s  cell_center=%s"
			% [cell, hh, (h.position if h != null else "?"), game.cell_center(cell)])

	for _f in range(30):
		await get_tree().process_frame

	# Přiblížení na první NEkotevní věž (ne Anchor, ne jádro) — tam se to má vidět
	# nejjasněji, protože nemá vlastní velký kruh, který by pohled zaplnil.
	# `trect` je zvednuté nad cyklus, protože ho pozdější sweep měřítka znovu použije
	# jako záběr — uvnitř `for` by po skončení cyklu zmizelo z dosahu.
	var trect := Rect2i()
	for cell: Vector2i in built:
		if cell == anchor_cell or cell.x <= -999:
			continue
		var tower_pos: Vector2 = game.cell_center(cell)
		trect = Rect2i(int(tower_pos.x - 220), int(tower_pos.y - 220), 440, 440)
		trect = trect.intersection(Rect2i(Vector2i.ZERO, get_viewport().get_visible_rect().size))
		var timg := get_viewport().get_texture().get_image()
		_save(timg.get_region(trect), "%s_tower_closeup.png" % out_prefix)
		break

	# Výřez kolem Anchoru — tam je lampa největší, takže tam je i největší rozdíl mezi
	# "nasvíceno" a "plocho".
	var focus_pos: Vector2 = game.cell_center(anchor_cell) if anchor_cell.x > -999 else game.objective_pos
	var zoom_rect := Rect2i(int(focus_pos.x - 320), int(focus_pos.y - 240), 640, 480)
	zoom_rect = zoom_rect.intersection(Rect2i(Vector2i.ZERO, get_viewport().get_visible_rect().size))

	for step: float in STEPS:
		GameState.set_tolerance(step)
		# Wash se dojíždí lerpem (game.gd:_update_attention), takže se musí nechat dojet.
		for _f in range(40):
			await get_tree().process_frame
		var img := get_viewport().get_texture().get_image()
		var st := _stats(img)
		var tag := "t%02d" % int(step)
		print("_shot_flat: tolerance %3d  jas %.4f  kontrast %.4f" % [int(step), st.mean, st.sd])
		_save(img, "%s_%s_wide.png" % [out_prefix, tag])
		if zoom_rect.size.x > 0 and zoom_rect.size.y > 0:
			var z := img.get_region(zoom_rect)
			_save(z, "%s_%s_zoom.png" % [out_prefix, tag])

	# --- Kontrola: SAMOTNÁ SVĚTLA (depth channel), bez flatten shaderu ------------
	#
	# Tohle je měření, které ten nápad vyvrátilo, a je tu proto, aby šlo zopakovat, až
	# pod pole přibude CanvasModulate (viz komentář u `depth_channel` v game.gd).
	#
	# Shader se izoluje ZRUŠENÍM _wash uzlu, ne schováním: _update_attention si
	# viditelnost každý snímek přepíná zpátky podle Tolerance, takže `visible = false`
	# vydrží jeden snímek a naměří se nesmysl. `_wash = null` je stav, na který se ta
	# funkce ptá.
	game._wash.queue_free()
	game._wash = null
	await get_tree().process_frame

	# --- SPIKE: klesající zdi -----------------------------------------------------
	# Fotí se BEZ flatten shaderu (_wash je výše zrušený), aby bylo vidět, co udělá
	# samotná eroze geometrie, a ne co udělá filtr přes obrazovku.
	game.sinking_walls = true
	var sink_pos: Vector2 = game.cell_center(game._sink_block)
	var sink_rect := Rect2i(int(sink_pos.x - 320), int(sink_pos.y - 240), 640, 480)
	sink_rect = sink_rect.intersection(Rect2i(Vector2i.ZERO, get_viewport().get_visible_rect().size))
	for step: float in [0.0, 70.0]:
		GameState.set_tolerance(step)
		game._update_sinking(0.016)
		for _f in range(20):
			await get_tree().process_frame
		var img3 := get_viewport().get_texture().get_image()
		print("_shot_flat: [sink] tolerance %3d  propadlo=%s" % [int(step), str(game._sunk)])
		if sink_rect.size.x > 0 and sink_rect.size.y > 0:
			_save(img3.get_region(sink_rect), "%s_sink_t%02d.png" % [out_prefix, int(step)])
	GameState.set_tolerance(0.0)
	game._update_sinking(0.016)
	game.sinking_walls = false
	await get_tree().process_frame

	# --- Srovnání měřítka sprite ("moc velké") -----------------------------------
	# Data.pixel_scale() dnes vychází ze staré čtvercové mřížky (GRID.tile=32,
	# TERRAIN_ART_PX=16 -> 2.0x), přenesené beze změny na iso diamant 64x32 s recyklovaným
	# plochým artem. Sweep přes několik hodnot NA STEJNÉM záběru s věžemi i nepřítelem
	# pohromadě, ať je vidět poměr k dlaždici, ne jen izolovaná postavička.
	var enemy = game.spawn_distraction(&"notification", anchor_cell)
	await get_tree().process_frame
	if enemy != null and is_instance_valid(enemy):
		enemy.global_position = sink_pos + Vector2(60, 20)

	for sc: float in [2.0, 1.5, 1.25, 1.0]:
		Data.pixel_scale_override = sc
		for spot in game.build_spots.values():
			if is_instance_valid(spot) and spot.current_habit != null:
				spot.current_habit.queue_redraw()
		if enemy != null and is_instance_valid(enemy):
			enemy.queue_redraw()
		for _f in range(6):
			await get_tree().process_frame
		var simg := get_viewport().get_texture().get_image()
		var tag2 := "%.2f" % sc
		_save(simg.get_region(trect if trect.size.x > 0 else zoom_rect),
			"%s_scale_%s.png" % [out_prefix, tag2])
	Data.pixel_scale_override = -1.0
	for spot in game.build_spots.values():
		if is_instance_valid(spot) and spot.current_habit != null:
			spot.current_habit.queue_redraw()

	game.depth_channel = true
	await get_tree().process_frame
	for step: float in [0.0, 95.0]:
		GameState.set_tolerance(step)
		for _f in range(40):
			await get_tree().process_frame
		var img2 := get_viewport().get_texture().get_image()
		var st2 := _stats(img2)
		print("_shot_flat: [jen svetla] tolerance %3d  jas %.4f  kontrast %.4f"
			% [int(step), st2.mean, st2.sd])
		_save(img2, "%s_lightsonly_t%02d_zoom.png" % [out_prefix, int(step)])

	print("HOTOVO")
	get_tree().quit(0)
