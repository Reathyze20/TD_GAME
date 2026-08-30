extends Node
## Harness pro SPIKE "klesající zdi" (game.gd: sinking walls).
##
## Spike má jednu úzkou otázku a tenhle soubor je ta otázka: **zvládne to pathfinding?**
## Bludiště se mění pod živými distrakcemi, a A* je jediná věc, která z toho může tiše
## spadnout — cesta se nenajde, nebo se najde stará skrz zeď, která se právě vrátila.
##
## Druhá polovina kontroluje, že to NENÍ smyčka smrti: práh má hysterezi, zeď se vrací,
## a odkrytý návyk se přeruší, ne zničí.
##
## Jede na iso levelu (id 99) — level 1 má objective mimo mřížku (pozůstatek migrace),
## takže by tam A* neodpověděl na nic.

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

func _path_len(game: Game, from: Vector2i) -> int:
	if not game.astar.is_in_boundsv(from):
		return -1
	return game.astar.get_id_path(from, game.objective_cell).size()

func _run() -> void:
	for i in range(Data.get_level_count()):
		if Data.get_level(i).id == 99:
			GameState.current_level_index = i
			break

	var game: Game = load("res://scenes/Game.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	GameState.max_focus = 999999
	GameState.focus = 999999
	GameState.dopamine = 999999
	game.sinking_walls = true
	await get_tree().process_frame

	print("\n-- výběr bloku")
	_check("spike si vybral blok", game._sink_block.x > -9998,
		str(game._sink_block))
	_check("blok má buňky", game._sink_cells.size() > 0,
		"%d buněk" % game._sink_cells.size())
	# Nejdál od jádra: bludiště se má třepit na okraji, ne u cíle.
	var d_sink: float = game.cell_center(game._sink_block).distance_to(game.objective_pos)
	var closer := 0
	for cell: Vector2i in game.build_spots:
		if game.cell_center(cell).distance_to(game.objective_pos) > d_sink:
			closer += 1
	_check("je to blok nejdál od jádra", closer == 0, "%d dál" % closer)

	var spawn: Vector2i = game._random_spawn_cell()
	var len_before := _path_len(game, spawn)
	_check("cesta existuje před propadem", len_before > 0, "%d buněk" % len_before)

	print("\n-- hystereze")
	GameState.set_tolerance(50.0)     # mezi SINK_OFF (45) a SINK_AT (60)
	game._update_sinking(0.016)
	_check("mezi prahy se nic neděje", not game._sunk)

	print("\n-- propad")
	GameState.set_tolerance(70.0)
	game._update_sinking(0.016)
	await get_tree().process_frame
	_check("blok se propadl", game._sunk)

	var still_solid := 0
	var still_hg := 0
	for c: Vector2i in game._sink_cells:
		if game.astar.is_in_bounds(c.x, c.y) and game.astar.is_point_solid(c):
			still_solid += 1
		if game.high_ground.has(c):
			still_hg += 1
	_check("buňky přestaly blokovat A*", still_solid == 0, "%d zbylo" % still_solid)
	_check("buňky zmizely z high_ground", still_hg == 0, "%d zbylo" % still_hg)

	# TOHLE je ta otázka. Cesta musí pořád existovat — propad zeď ODEBÍRÁ, takže smí
	# jen zkrátit; kdyby se nenašla, znamená to, že se rozsypal stav A*, ne geometrie.
	var len_sunk := _path_len(game, spawn)
	_check("cesta existuje i po propadu", len_sunk > 0, "%d buněk" % len_sunk)
	_check("cesta se nezdloužila", len_sunk <= len_before,
		"%d -> %d" % [len_before, len_sunk])

	print("\n-- živá distrakce se přepočítá")
	GameState.set_tolerance(0.0)
	game._update_sinking(0.016)
	await get_tree().process_frame
	var d := game.spawn_distraction(&"notification", spawn)
	await get_tree().process_frame
	_check("distrakce se spawnula", d != null and is_instance_valid(d))
	GameState.set_tolerance(70.0)
	game._update_sinking(0.016)
	await get_tree().process_frame
	# Po propadu nesmí žádný krok její cesty ležet ve zdi. P4 (docs/refactor/PATHFINDING.MD):
	# cesta uz neni pole na distrakci, je to sdileny flow_field -- trasujeme ji rucne odsud
	# az k cili stejnym direction(), jakym se ridi ziva distrakce sama.
	var in_wall := 0
	if d != null and is_instance_valid(d) and game.flow_field.has_cell(d.current_cell):
		var cell: Vector2i = d.current_cell
		var guard := 0
		while cell != game.objective_cell and guard < Data.GRID.cols * Data.GRID.rows:
			guard += 1
			if game.high_ground.has(cell):
				in_wall += 1
			cell += game.flow_field.direction(cell)
	_check("žádný krok cesty nevede zdí", in_wall == 0, "%d kroků ve zdi" % in_wall)

	print("\n-- návrat zdi")
	GameState.set_tolerance(20.0)
	game._update_sinking(0.016)
	await get_tree().process_frame
	_check("zeď se vrátila", not game._sunk)
	var back_solid := 0
	for c: Vector2i in game._sink_cells:
		if game.astar.is_in_bounds(c.x, c.y) and game.astar.is_point_solid(c):
			back_solid += 1
	_check("buňky zase blokují", back_solid == game._sink_cells.size(),
		"%d z %d" % [back_solid, game._sink_cells.size()])
	var len_back := _path_len(game, spawn)
	_check("cesta existuje po návratu", len_back > 0, "%d buněk" % len_back)
	_check("délka se vrátila na původní", len_back == len_before,
		"%d -> %d" % [len_before, len_back])

	print("\n-- odkrytý návyk se PŘERUŠÍ, nezničí")
	GameState.select_habit("focus_timer")
	game._build_on(game._sink_block)
	game._end_aiming()
	await get_tree().process_frame
	var h = game.build_spots[game._sink_block].current_habit
	_check("na bloku stojí návyk", h is Habit)
	GameState.set_tolerance(70.0)
	game._update_sinking(0.016)
	await get_tree().process_frame
	_check("propadlý blok hlásí odkrytý návyk", game.exposed_habit() != null)

	if h is Habit:
		# Distrakce přímo na návyku — přerušení se má spustit.
		var near := game.spawn_distraction(&"notification", game._sink_block)
		await get_tree().process_frame
		if near != null and is_instance_valid(near):
			near.global_position = h.global_position
		game._exposed_cd = 0.0
		game._tick_exposed(0.016)
		_check("blízká distrakce návyk přerušila", h.disrupted_left > 0.0,
			"%.2fs" % h.disrupted_left)
		_check("návyk PŘEŽIL (přerušení, ne zničení)", is_instance_valid(h)
			and game.build_spots[game._sink_block].state == BuildSpot.State.BUILT)

	completed = true
	print("\n%s (%d failures)" % ["PASSED" if fails == 0 else "FAILED", fails])
	get_tree().quit(1 if fails > 0 else 0)
