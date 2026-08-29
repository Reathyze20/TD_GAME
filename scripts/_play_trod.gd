extends Node
## Hratelny playground pro ZIVOU MAPU (trody) -- jedna scena, zadne editovani .tres.
##
## Bootuje level 98 "First Light", ktery ma zapadni trod otevirajici se ve vlne 3.
## Designer mod je zapnuty, takze se z tohohle behu NEZAPISUJE telemetrie ani runlog
## (game.gd i mirror.gd se na designer_mode ptaji) -- hrani si nezkazi cisla.
##
## Spusteni: v Godotu otevri scenes/_play_trod.tscn a dej F6 (Run Current Scene).
## Z prikazove radky:  godot --path <proj> --main-scene res://scenes/_play_trod.tscn
## NE --headless, je to na divani.

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	for i in range(Data.get_level_count()):
		if Data.get_level(i).id == 98:
			GameState.current_level_index = i
			break
	GameState.designer_mode = true
	var game = load("res://scenes/Game.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	GameState.add_dopamine(2000)
	print("""
=== ZIVA MAPA: TRODY ===
  F8        otevri dalsi trod HNED (nemusis hrat do vlny 3)
  F1        +500 Dopamine
  F3        turbo 5x
  F4        smaz vlnu
  mezernik  zavolat vlnu

  Co sledovat:
   1) Postav par vezi na VYCHODNI strane -- tam dnes horda chodi.
   2) Pred vlnou 3 se na ZAPADE objevi slaby jantarovy nadech. To je telegraf.
   3) Vlna 3 (nebo F8): zapadni trod se otevre, napis "A new trod has opened
      to the west", a horda zacne chodit zapadem.
   4) Tecovane cary od spawnu = nahled trasy. Prepnou se okamzite.

  Otazka, na kterou to ma odpovedet: musis stavet znovu, nebo staci presunout?
""")
