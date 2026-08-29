extends Node
## Overuje "zivou mapu": trod se otevre ve spravnou vlnu, zkrati cestu, a hlavne
## SPLYNE se starou trasou u jadra. To posledni je designove pravidlo z trod_data.gd
## prelozene do testu -- kdyby nova cesta mela vlastni koncovy usek, vez postavena
## u jadra by prisla o hodnotu a level by cetl jako podraz.

var completed := false
var fails := 0

func _ok(name: String, cond: bool, detail: String = "") -> void:
	if not cond:
		fails += 1
	print(("  OK   " if cond else "  FAIL ") + name + ("  " + detail if detail != "" else ""))

func _route(game: Game) -> Array:
	var zone: Array = game.spawn_zone_cells[0]
	return Array(game.astar.get_id_path(zone[0], game.objective_cell))

func _ready() -> void:
	var idx := -1
	for i in range(Data.get_level_count()):
		if Data.get_level(i).id == 98:
			idx = i
	if idx < 0:
		print("FAILED: level 98 nenalezen"); get_tree().quit(1); return
	GameState.current_level_index = idx

	var t := Timer.new()
	t.wait_time = 60.0
	t.one_shot = true
	add_child(t)
	t.timeout.connect(func():
		if not completed:
			print("FAILED: watchdog"); get_tree().quit(1))
	t.start()

	var game: Game = load("res://scenes/Game.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	GameState.max_focus = 999999
	GameState.focus = 999999

	print("=== trod: ziva mapa na levelu 98 ===")
	_ok("level ma trod", game.level.trods.size() == 1,
		"%d" % game.level.trods.size())
	var trod: TrodData = game.level.trods[0]
	var painted: int = game.level.path_cells.size()
	var lanes0: int = game.lane_cells.size()
	var route0 := _route(game)
	print("  trasa pred otevrenim: %d bunek, pruh %d" % [route0.size(), lanes0])

	# --- vlna 1 a 2: zavreno, ale od vlny 2 uz musi byt videt telegraf
	game.wave_index = 0
	game._open_due_trods(1)
	_ok("po vlne 1 zavreno", game.lane_cells.size() == lanes0)
	game.wave_index = 1
	_ok("telegraf sviti vlnu predem", game.pending_trod() == trod)
	game._open_due_trods(2)
	_ok("po vlne 2 porad zavreno", game.lane_cells.size() == lanes0)

	# --- vlna 3: otevre se
	game.wave_index = 2
	game._open_due_trods(3)
	var lanes1: int = game.lane_cells.size()
	var route1 := _route(game)
	print("  trasa po otevreni:    %d bunek, pruh %d" % [route1.size(), lanes1])

	_ok("pruh se rozrostl", lanes1 == lanes0 + trod.cells.size(),
		"%d -> %d (+%d)" % [lanes0, lanes1, lanes1 - lanes0])
	_ok("namalovana data levelu se nezmenila", game.level.path_cells.size() == painted,
		"%d" % game.level.path_cells.size())
	_ok("trasa se zmenila", route0 != route1)
	_ok("trasa se zkratila", route1.size() < route0.size(),
		"%d -> %d" % [route0.size(), route1.size()])
	_ok("telegraf zhasnul", game.pending_trod() == null)
	game._open_due_trods(4)
	_ok("neotevre se podruhe", game.lane_cells.size() == lanes1)

	# --- KONVERGENCNI PRAVIDLO (trod_data.gd): u jadra musi nova trasa zustat v dosahu
	# veze postavene pro tu starou, jinak level znehodnoti praci hrace.
	#
	# NEMERI se shodou bunek. Prvni verze tohohle testu to delala a spadla na tom, ze
	# obe trasy jdou TYMZ tripolovym koridorem (x12-14), jen jinymi sloupci -- vada byla
	# v meridle, ne v mape. Spravna otazka nezni "slape to na stejne dlazdice", ale
	# "dosahne tam vez, kterou uz mam". Proto se meri vzdalenost ve svete proti
	# NEJKRATSIMU utocnemu dosahu ve hre (260 px, mindfulness): kdyz to pokryje ta
	# nejslabsi vez, pokryji to vsechny.
	var reach := 260.0
	var covered := 0
	for i in range(route1.size() - 1, -1, -1):
		var p: Vector2 = game.cell_center(route1[i])
		var near := false
		for c in route0:
			if p.distance_to(game.cell_center(c)) <= reach:
				near = true
				break
		if not near:
			break
		covered += 1
	print("  koncovy usek nove trasy v dosahu stare: %d z %d bunek" % [covered, route1.size()])
	_ok("nova trasa je u jadra v dosahu stare obrany (>= 6 bunek)", covered >= 6,
		"%d" % covered)
	# --- vahy: otevrene bunky uz nesmi mit prirazku
	var w_ok := true
	for c: Vector2i in trod.cells:
		if game.astar.is_in_bounds(c.x, c.y) and not game.high_ground.has(c):
			if game.astar.get_point_weight_scale(c) > 1.001:
				w_ok = false
	_ok("otevrene bunky maji vahu 1.0", w_ok)

	print("=== %s (%d chyb) ===" % ["ALL PASS" if fails == 0 else "FAILED", fails])
	completed = true
	get_tree().quit(1 if fails > 0 else 0)
