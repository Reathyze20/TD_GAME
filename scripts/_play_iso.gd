extends Node
## Hratelný playground pro ISO slice — jedna scéna, jeden příkaz, žádné editování .tres.
##
## Existuje proto, že tři věci, které se dají posoudit JEDINĚ okem, se bez něj posoudit
## nedají vůbec:
##
##   * flatten shader (shaders/flatten.gdshader) — jak Tolerance vypadá
##   * eskalace Quick Hit tlačítka — jak Tolerance přitahuje
##   * propad zdi (SPIKE) — co Tolerance stojí
##
## Všechny tři řídí Tolerance. Iso level (99) uz `quick_hit` zapnuty ma, takze se s ni
## pohnout DA — ale pomalu, a tenhle harness ji chce hned. Tenhle harness zapne designer mód (F5/F6 hýbou
## Tolerancí, F7 přepíná propad zdi) a rovnou nabootuje iso level se `sinking_walls`.
##
## Spuštění (NE --headless, je to na dívání):
##   godot --path <proj> --main-scene res://scenes/_play_iso.tscn
##
## Klávesy:
##   F5 / F6   Tolerance -20 / +20   ← tohle je ten přepínač
##   F7        propad zdi ON/OFF
##   F1        +500 Dopamine (na stavění)
##   F3        turbo 5×
##   mezerník  zavolat vlnu

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	for i in range(Data.get_level_count()):
		if Data.get_level(i).id == 99:
			GameState.current_level_index = i
			break

	# Designer mód se normálně zapíná jen playtestem z map editoru. Tady je zapnutý
	# rovnou — což zároveň znamená, že se z tohohle běhu NEZAPISUJE telemetrie ani
	# runlog (game.gd i mirror.gd se na designer_mode ptají), takže si hraní v tomhle
	# harnessu nezkazí čísla na účtence.
	GameState.designer_mode = true

	var game = load("res://scenes/Game.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	game.sinking_walls = true
	game.shadow_enabled = true

	print("""
=== ISO PLAYGROUND ===
  F5 / F6   Tolerance -20 / +20
  F7        propad zdi ON/OFF (teď: ON)
  F1        +500 Dopamine
  F3        turbo 5x
  mezernik  zavolat vlnu

  Co sledovat:
   * Tolerance 0 -> 95  barvy vyprchaji a rozsah se sesype (flatten shader)
   * Tolerance >= 60    nejvzdalenejsi ZASTAVENY blok prestane byt zdi
   * Tolerance <= 45    zed se vrati
   * distrakce u odkryteho navyku ho PRERUSI (napis "exposed"), nezvnici
""")
