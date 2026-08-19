extends Node
## Stíní si věž vlastní plošinou?
##
## CO SE ROZBILO A PROČ TENHLE HARNESS EXISTUJE
##
## `cast_to_wall()` vyjímala z blokování jen buňku, VE KTERÉ paprsek začíná
## (`c != start_cell`). Záměr byl správný — „věže stojí na vyvýšenině a střílí ven" — ale
## rozsah ne: všech 200 stavebních míst v levelu stojí na vyvýšenině a ta je slepená do
## plošin po 48 buňkách. Věž mířící podél pásu, na kterém stojí, si ho tedy stínila sama.
##
## Naměřeno před opravou: paprsek umřel po 24 px proti dostřelu ~300 px, v 7 z 8 směrů.
## Hráč to viděl jako useknutý zelený kužel míření.
##
## Invariant, který se tu hlídá, je schválně nezávislý na levelu:
##
##     PAPRSEK SE NIKDY NESMÍ ZASTAVIT NA VLASTNÍ PLOŠINĚ STŘELCE.
##
## Cizí plošina blokovat smí a má — to je celá mechanika „zdi stíní palbu".

var completed := false
var fails := 0


func _ready() -> void:
	var wd := Timer.new()
	wd.wait_time = 60.0
	wd.one_shot = true
	add_child(wd)
	wd.timeout.connect(func():
		if not completed:
			print("FAILED: watchdog")
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
	var game: Game = load("res://scenes/Game.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	GameState.max_focus = 999999
	GameState.focus = 999999
	await get_tree().process_frame

	print("=== tvar terénu")
	var na_vyvysenine := 0
	for cell: Vector2i in game.build_spots:
		if game.high_ground.has(cell):
			na_vyvysenine += 1
	print("  %d z %d stavebních míst stojí na vyvýšenině"
		% [na_vyvysenine, game.build_spots.size()])
	_check("plošiny se rozpadly na víc než jeden kus",
		_pocet_plosin(game) > 1,
		"(%d kusů z %d buněk)" % [_pocet_plosin(game), game.high_ground.size()])

	print("=== paprsek se nezastaví na vlastní plošině")
	var dosah := 300.0
	var testovano := 0
	var nejblizsi_useknuti := dosah
	for cell: Vector2i in game.build_spots:
		if not game.high_ground.has(cell):
			continue
		testovano += 1
		if testovano > 40:      # čtyřicet míst je vzorek, ne důkaz — ale rychlý
			break
		var from: Vector2 = game.cell_center(cell)
		var own: int = game.platform_at(from)
		for i in range(16):
			var dir := Vector2.RIGHT.rotated(TAU * float(i) / 16.0)
			var d: float = game.cast_to_wall(from, dir, dosah)
			if d >= dosah:
				continue
			nejblizsi_useknuti = minf(nejblizsi_useknuti, d)
			var kde: Vector2 = from + dir * d
			if game.platform_at(kde) == own:
				_check("paprsek z %s pod %.0f° umřel na VLASTNÍ plošině" % [cell, rad_to_deg(dir.angle())],
					false, "(po %.0f px)" % d)
				completed = true
				get_tree().quit(1)
				return
	_check("žádný z %d×16 paprsků neumřel na vlastní plošině" % testovano, true,
		"(nejbližší cizí zeď %.0f px)" % nejblizsi_useknuti)
	_check("nejbližší useknutí je dál než jedna dlaždice",
		nejblizsi_useknuti > float(Data.GRID.tile),
		"(%.0f px vs dlaždice %d px)" % [nejblizsi_useknuti, Data.GRID.tile])

	print("=== zdi pořád stíní")
	# Kdyby oprava vypnula blokování úplně, tenhle test to chytí: někde na desce MUSÍ
	# být směr, který cizí plošina zastaví, jinak je celá mechanika mrtvá.
	var nasel_blok := false
	for cell: Vector2i in game.build_spots:
		if not game.high_ground.has(cell):
			continue
		var from: Vector2 = game.cell_center(cell)
		for i in range(16):
			if game.cast_to_wall(from, Vector2.RIGHT.rotated(TAU * float(i) / 16.0), dosah) < dosah:
				nasel_blok = true
				break
		if nasel_blok:
			break
	_check("cizí zeď pořád zastaví paprsek", nasel_blok)

	print("\n%s (%d chyb)" % ["ALL PASS" if fails == 0 else "FAILED", fails])
	completed = true
	get_tree().quit(1 if fails > 0 else 0)


func _pocet_plosin(game: Game) -> int:
	var videno := {}
	var n := 0
	for c: Vector2i in game.high_ground:
		if videno.has(c):
			continue
		n += 1
		var stack: Array = [c]
		videno[c] = true
		while not stack.is_empty():
			var cur: Vector2i = stack.pop_back()
			for dy in [-1, 0, 1]:
				for dx in [-1, 0, 1]:
					var nb: Vector2i = cur + Vector2i(dx, dy)
					if game.high_ground.has(nb) and not videno.has(nb):
						videno[nb] = true
						stack.push_back(nb)
	return n
