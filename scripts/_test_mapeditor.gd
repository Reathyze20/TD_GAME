extends Node
## Harness pro blokové malování v MapEditoru.
##
## Geometrie bloků je přesně ten druh věci, kde se člověk splete o půl dlaždice a pozná
## to až očima — a to je pozdě, protože to znamená mapu, která se hraje jinak, než jak
## vypadala. Proto se to tady DOKAZUJE čísly.
##
## Nejdůležitější kontrola je ta třetí: že blok namalovaný na vrstvě s dlaždicí
## (3*tile_w, 3*tile_h) leží na obrazovce PŘESNĚ tam, kde hra kreslí prostřední buňku
## toho bloku. Kdyby to neplatilo, editor by zase ukazoval něco jiného než hra — což je
## ta vada, kvůli které tohle celé vzniklo.
##
## Spuštění:
##   godot --headless --path <proj> --main-scene res://scenes/_test_mapeditor.tscn

var ME: GDScript = load("res://tools/map_editor.gd")

var completed := false
var fails := 0

func _ready() -> void:
	var wd := Timer.new()
	wd.wait_time = 60.0
	wd.one_shot = true
	add_child(wd)
	wd.timeout.connect(func():
		if not completed:
			print("FAILED: watchdog fired")
			get_tree().quit(1))
	wd.start()
	call_deferred("_run")

func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("  ok   %s %s" % [label, detail])
	else:
		fails += 1
		print("  FAIL %s %s" % [label, detail])

func _level(id: int) -> LevelData:
	for i in range(Data.get_level_count()):
		if Data.get_level(i).id == id:
			return Data.get_level(i)
	return null

func _run() -> void:
	var ed = ME.new()
	add_child(ed)
	ed.build_layers()
	await get_tree().process_frame

	print("\n-- vrstvy vznikly")
	for n in ["BlockTiles", "BlockPath", "BlockSpawn", "BlockGoal",
			"HighGroundTiles", "PathTiles"]:
		_check("vrstva %s" % n, ed.get_node_or_null(n) != null)

	print("\n-- vsechny malovaci vrstvy jsou izometricke")
	for n in ["BlockTiles", "BlockPath", "BlockSpawn", "BlockGoal",
			"HighGroundTiles", "PathTiles"]:
		var l: TileMapLayer = ed.get_node_or_null(n)
		if l == null or l.tile_set == null:
			_check("%s ma tileset" % n, false)
			continue
		_check("%s je ISOMETRIC" % n,
			l.tile_set.tile_shape == TileSet.TILE_SHAPE_ISOMETRIC)
		_check("%s je DIAMOND_DOWN" % n,
			l.tile_set.tile_layout == TileSet.TILE_LAYOUT_DIAMOND_DOWN)

	print("\n-- blok pokryva spravne bunky")
	var cells: Array = ME.block_cells(Vector2i(1, 2))
	_check("blok (1,2) ma 9 bunek", cells.size() == 9, str(cells.size()))
	_check("blok (1,2) zacina na (3,6)", cells[0] == Vector2i(3, 6), str(cells[0]))
	_check("blok (1,2) konci na (5,8)", cells[8] == Vector2i(5, 8), str(cells[8]))
	_check("stred bloku (1,2) je (4,7)",
		ME.block_center_cell(Vector2i(1, 2)) == Vector2i(4, 7),
		str(ME.block_center_cell(Vector2i(1, 2))))

	print("\n-- DUKAZ: blokova vrstva lezi presne na herni mrizce")
	# Tohle je jadro celeho prevodu. map_to_local() blokove vrstvy musi vratit tentyz
	# bod jako Data.cell_center() prostredni bunky -- jinak editor kresli jinam nez hra.
	var bl: TileMapLayer = ed.get_node_or_null("BlockTiles")
	var worst := 0.0
	for by in range(8):
		for bx in range(8):
			var b := Vector2i(bx, by)
			var from_layer: Vector2 = bl.map_to_local(b) + bl.position
			var from_game: Vector2 = Data.cell_center(ME.block_center_cell(b))
			worst = maxf(worst, from_layer.distance_to(from_game))
	for probe in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(2, 3)]:
		print("     blok %s: vrstva %s   hra %s" % [str(probe),
			str(bl.map_to_local(probe) + bl.position),
			str(Data.cell_center(ME.block_center_cell(probe)))])
	_check("vsech 64 bloku sedi na 0.01 px", worst < 0.01, "nejhorsi odchylka %.4f px" % worst)

	print("\n-- nacteni skutecneho levelu (98)")
	var lvl := _level(98)
	if lvl == null:
		_check("level 98 existuje", false)
		_finish()
		return
	ed.target_level = lvl
	ed._load_from_level()
	await get_tree().process_frame

	var high: Array = ed._high_cells()
	var want := {}
	for c: Vector2i in lvl.high_ground:
		want[c] = true
	var got := {}
	for c: Vector2i in high:
		got[c] = true
	_check("vysoka zem se nacetla beze ztraty", got.size() == want.size(),
		"%d vs %d" % [got.size(), want.size()])
	var missing := 0
	for c in want:
		if not got.has(c):
			missing += 1
	_check("zadna bunka nechybi", missing == 0, str(missing))

	_check("cil se cte z namalovaneho bloku", ed._read_objective() == lvl.objective,
		"%s vs %s" % [str(ed._read_objective()), str(lvl.objective)])

	var zones: Array = ed._read_zones()
	_check("spawny se nacetly", zones.size() > 0, str(zones.size()))
	# Kazda puvodni spawn bunka musi lezet v nejake nactene zone.
	var lost := 0
	for rect: Rect2i in lvl.spawn_zones:
		for y in range(rect.position.y, rect.position.y + rect.size.y):
			for x in range(rect.position.x, rect.position.x + rect.size.x):
				var inside := false
				for z: Rect2i in zones:
					if z.has_point(Vector2i(x, y)):
						inside = true
						break
				if not inside:
					lost += 1
	_check("zadna spawn bunka se neztratila", lost == 0, str(lost))

	print("\n-- cesta nikdy nelezi pod terasou")
	var lanes: Array = ed._lane_cells()
	var clash := 0
	for c: Vector2i in lanes:
		if got.has(c):
			clash += 1
	_check("zadny prunik cesty a vysoke zeme", clash == 0, str(clash))

	print("\n-- blok se maluje jednim klikem a da 9 bunek")
	ed.get_node("BlockTiles").clear()
	ed.get_node("HighGroundTiles").clear()
	ed.get_node("BlockTiles").set_cell(Vector2i(2, 2), 0, Vector2i.ZERO)
	var one: Array = ed._high_cells()
	_check("jeden namalovany blok = 9 bunek", one.size() == 9, str(one.size()))
	_check("a je to platne stavebni misto (stred sedi na 3x+1)",
		one.has(Vector2i(7, 7)), str(ME.block_center_cell(Vector2i(2, 2))))

	print("
-- Nova mapa vyrobi PLATNY zacatek")
	ed.scaffold_starter_map()
	await get_tree().process_frame
	var h: Dictionary = ed.map_health()
	_check("semafor nehlasi rozbito", String(h.get("level", "")) != "broken",
		"%s / %s" % [String(h.get("level", "")), String(h.get("headline", ""))])
	for a in h.get("advice", []):
		print("     rada: %s" % String(a))
	_check("cil je na strede bloku",
		ed._read_objective().x % 3 == 1 and ed._read_objective().y % 3 == 1,
		str(ed._read_objective()))
	_check("spawn existuje", ed._read_zones().size() > 0, str(ed._read_zones().size()))
	_check("stavebnich mist v Routine je v rozmezi",
		int(ed._health.get("spots_core", 0)) >= ed.TARGET_CORE_SPOTS_MIN
		and int(ed._health.get("spots_core", 0)) <= ed.TARGET_CORE_SPOTS_MAX,
		"%d (cil %d-%d)" % [int(ed._health.get("spots_core", 0)),
			ed.TARGET_CORE_SPOTS_MIN, ed.TARGET_CORE_SPOTS_MAX])
	_check("nepratele se dostanou k cili", bool(ed._health.get("any_route", false)))
	_check("zadna spawn bunka neni zazdena",
		int(ed._health.get("unreachable_spawn", -1)) == 0,
		str(ed._health.get("unreachable_spawn", -1)))
	_check("detour je nad cilem", float(ed._health.get("detour", 0.0)) >= ed.TARGET_DETOUR,
		"%.2f (cil %.2f)" % [float(ed._health.get("detour", 0.0)), ed.TARGET_DETOUR])
	_check("nejkratsi cesta je dost dlouha",
		int(ed._health.get("shortest", 0)) >= ed.TARGET_MIN_SPAWN_PATH,
		"%d (cil %d)" % [int(ed._health.get("shortest", 0)), ed.TARGET_MIN_SPAWN_PATH])

	_test_art_overrides(ed)

	_finish()

func _finish() -> void:
	completed = true
	print("\n%s (%d failures)" % ["PASSED" if fails == 0 else "FAILED", fails])
	get_tree().quit(1 if fails > 0 else 0)

## Ruční výběr dlaždic: paleta ze souborů, přepis přežije Bake i Load, a hra ho vidí.
func _test_art_overrides(ed: MapEditor) -> void:
	print("\n-- vyber dlazdic podle grafiky")
	var names: Array = ed.art_tile_paths()
	_check("paleta se poskladala ze souboru", names.size() > 0, "%d dlazdic" % names.size())
	_check("obsahuje terén i cestu",
		names.any(func(n): return n.begins_with("ground/"))
		and names.any(func(n): return n.begins_with("lane/")), str(names.slice(0, 3)))
	var art: TileMapLayer = ed.get_node_or_null("ArtTiles")
	_check("vrstva ArtTiles existuje", art != null)
	if art == null or names.is_empty():
		return
	_check("paleta ma tileset se zdroji",
		art.tile_set != null and art.tile_set.get_source_count() > 0,
		str(art.tile_set.get_source_count()) if art.tile_set else "-")
	# Namaluj konkretni dlazdici a zkontroluj, ze Bake ulozi JMENO, ne id.
	var pick := names.find("ground/ground_03")
	if pick < 0:
		pick = 0
	art.clear()
	art.set_cell(Vector2i(5, 5), pick, Vector2i.ZERO)
	var lvl := LevelData.new()
	lvl.objective = ed._read_objective()
	var overrides := {}
	for c: Vector2i in art.get_used_cells():
		var sid := art.get_cell_source_id(c)
		if sid >= 0 and sid < names.size():
			overrides[c] = names[sid]
	_check("prepis se uklada jako jmeno souboru",
		String(overrides.get(Vector2i(5, 5), "")) == String(names[pick]),
		String(overrides.get(Vector2i(5, 5), "<nic>")))
	_check("a to jmeno ukazuje na existujici PNG",
		ResourceLoader.exists("res://assets/terrain/iso/%s.png" % String(names[pick])),
		String(names[pick]))
