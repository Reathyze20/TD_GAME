extends Node
## Smoke test kazde mapy v data/levels/.
##
## Neresi balanc ani zabavu. Resi jedinou otazku, na kterou se v Godotu neda kouknout:
## **da se ten level vubec dohrat?** Cil v mrizce, cesta z kazde spawn bunky do cile,
## aspon jedno misto na stavbu, a zadna plosina lezici na pruhu.
##
## Vznikl proto, ze `level_1` a `level_2` maji `objective` (109, 34) proti mrizce 24x24
## po migraci mrizky, takze `astar.get_id_path` nevrati nic a hra se rozjede do prazdna.
## Takova chyba je v .tres souboru se stovkami souradnic neviditelna a v editoru vypada
## mapa spravne. Tohle je jediny misto, kde se to da chytit levne.
##
## Levely, o kterych uz vime, ze jsou rozbite, jsou v KNOWN_BROKEN. Nejsou to vyjimky
## pro pohodli - je to seznam dluhu, ktery ma byt videt a ktery ma jednou byt prazdny.

## 2026-08-29: both entries removed. id 2's level (level_2.tres) no longer exists at
## all (T5 topdown migration deleted every pre-migration level, see BLOCKED.md's T5
## entry), and id 1 is now a freshly-built placeholder with a valid in-bounds
## objective — neither is "the same debt, still there", so keeping either row would
## have this dict silently skip validating levels that are not actually broken.
const KNOWN_BROKEN := {}

var completed := false
var fails := 0

func _ready() -> void:
	var wd := Timer.new()
	wd.wait_time = 90.0
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

func _run() -> void:
	var g := Data.GRID
	var b: int = Data.BUILD_BLOCK
	var broken_seen := {}

	for i in range(Data.get_level_count()):
		var lv: LevelData = Data.get_level(i)
		print("\n-- [%d] %s (id %d)" % [i, lv.display_name, lv.id])

		if KNOWN_BROKEN.has(lv.id):
			broken_seen[lv.id] = true
			print("     ZNAMY DLUH: %s" % KNOWN_BROKEN[lv.id])
			continue

		# --- staticke kontroly, na ktere netreba instanciovat hru ---------------
		var in_bounds: bool = lv.objective.x >= 0 and lv.objective.y >= 0 \
			and lv.objective.x < int(g.cols) and lv.objective.y < int(g.rows)
		_check("cil je v mrizce", in_bounds, str(lv.objective))
		if not in_bounds:
			continue
		# Cil na stredu bloku neni kosmetika: build_spots vznikaji jen na bunkach
		# x % 3 == 1 a y % 3 == 1, takze cil mimo stred sedi napul na dvou blocich.
		_check("cil sedi na stredu bloku",
			lv.objective.x % b == b / 2 and lv.objective.y % b == b / 2,
			"%d %% %d, %d %% %d" % [lv.objective.x, b, lv.objective.y, b])
		_check("ma spawn zonu", not lv.spawn_zones.is_empty(),
			"%d zon" % lv.spawn_zones.size())
		# Hra cil ze zdi tise vyhodi (game.gd preskoci cell == objective_cell), takze
		# by to nespadlo - jen by tam byla dira, ktere si nikdo nevsimne.
		var hg := {}
		for c: Vector2i in lv.high_ground:
			hg[c] = true
		_check("cil neni ve zdi", not hg.has(lv.objective))
		var lane_in_wall := 0
		for c: Vector2i in lv.path_cells:
			if hg.has(c):
				lane_in_wall += 1
		_check("zadna plosina nelezi na pruhu", lane_in_wall == 0,
			"%d bunek v konfliktu" % lane_in_wall)

		# --- ziva kontrola: postav level a nech A* odpovedet -------------------
		GameState.current_level_index = i
		var game: Game = load("res://scenes/Game.tscn").instantiate()
		add_child(game)
		await get_tree().process_frame

		_check("vznikla stavebni mista", game.build_spots.size() > 0,
			"%d mist" % game.build_spots.size())

		# Kolik mist je stavitelnych HNED. Stavet jde jen v dosahu Routine od jadra
		# (CORE_ROUTINE_RADIUS, ~3 bloky), takze mapa muze projit vsechny kontroly vyse
		# a pritom nejit rozehrat: hrac klikne a dostane "Outside your Routine". Prvni
		# verze levelu 98 mela presne tohle — cil na konci serpentiny a 6 z 8 mist mimo.
		var reachable := 0
		for cell in game.build_spots.keys():
			if game._can_build(cell):
				reachable += 1
		_check("neco se da postavit hned na zacatku", reachable > 0,
			"%d z %d v Routine" % [reachable, game.build_spots.size()])

		var zones: int = game.spawn_zone_cells.size()
		_check("spawn zony maji bunky", zones > 0, "%d zon" % zones)
		var unreachable := 0
		var checked := 0
		var shortest := 99999
		for zone: Array in game.spawn_zone_cells:
			for cell: Vector2i in zone:
				checked += 1
				if not game.astar.is_in_boundsv(cell):
					unreachable += 1
					continue
				var p: Array = game.astar.get_id_path(cell, game.objective_cell)
				if p.is_empty():
					unreachable += 1
				else:
					shortest = mini(shortest, p.size())
		_check("z kazde spawn bunky vede cesta do cile", unreachable == 0,
			"%d z %d bez cesty" % [unreachable, checked])
		if unreachable == 0 and checked > 0:
			# Kratka cesta znamena, ze veze nemaji na cem pracovat a level skonci driv,
			# nez si ho hrac stihne prohlednout.
			_check("cesta ma smysluplnou delku", shortest >= 12,
				"nejkratsi %d bunek" % shortest)

		# Vlny musi neco poslat, jinak level skonci sam od sebe.
		var total := 0
		for w in lv.waves:
			for batch in w.groups:
				total += batch.count
		_check("vlny neco posilaji", total > 0, "%d distrakci v %d vlnach"
			% [total, lv.waves.size()])

		game.queue_free()
		await get_tree().process_frame

		# Vyukova pulka hry. Karta se hleda podle lv.id, ne podle pozice v poli — to je
		# presne to, na cem to driv tise padalo do fallbacku, kdyz id prestala byt 1,2,3.
		var card: InsightCardData = Data.get_insight_card(lv.id)
		_check("ma vlastni insight kartu", card != null, "" if card != null
			else "chybi data/insight_cards pro id %d" % lv.id)
		if card != null:
			_check("karta ma citaci", card.citation != "", card.citation.substr(0, 40))
			_check("karta ma poucení", card.takeaway != "")
		# A cela obrazovka se musi postavit — vcetne uctenky, ktera cte Mirror.
		var edu = load("res://scenes/Education.tscn").instantiate()
		add_child(edu)
		await get_tree().process_frame
		_check("obrazovka mezi levely se postavi", is_instance_valid(edu))
		edu.queue_free()
		await get_tree().process_frame

	# Dluh, ktery uz neexistuje, ma z KNOWN_BROKEN zmizet - jinak seznam za rok lze.
	print("")
	for id in KNOWN_BROKEN.keys():
		var still: bool = broken_seen.has(id)
		_check("znamy dluh id %d je stale v datech" % id, still,
			"" if still else "uz neexistuje - smaz radek z KNOWN_BROKEN")

	completed = true
	print("\n%s (%d failures)" % ["PASSED" if fails == 0 else "FAILED", fails])
	get_tree().quit(1 if fails > 0 else 0)
