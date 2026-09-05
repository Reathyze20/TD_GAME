extends Node
## Hratelny playground pro PROTOTYP JADROVE SMYCKY Tolerance <-> Brain Fog -- jedna
## scena, zadne editovani .tres. Bootuje level 98 "First Light" (fog=true,
## quick_hit=true), ktery uz ma oba systemy zapnute a vyladene (PROGRESS.md
## "F1 hotovo" / "P11 hotovo").
##
## Smycka, kterou tenhle playground zhmotnuje:
##  1. Vysoka Tolerance zuzuje dosah kazdeho svetla (Game.sight_radius_mult()) --
##     kuzel veze vidi min.
##  2. Distrakce mimo svetlo jsou az FOG_SPEED_BOOSTx rychlejsi (enemy.gd).
##  3. Quick Hit da okamzity dopamine, ale zvedne Toleranci natrvalo (floor) --
##     uzavira smycku.
##
## Designer mod je zapnuty, takze se z tohohle behu NEZAPISUJE telemetrie ani runlog
## (game.gd i mirror.gd se na designer_mode ptaji) -- hrani si nezkazi cisla.
##
## Spusteni: v Godotu otevri scenes/_play_tolerance_loop.tscn a dej F6 (Run Current Scene).
## Z prikazove radky:  godot --path <proj> --main-scene res://scenes/_play_tolerance_loop.tscn
## NE --headless, je to na divani.

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	for i in range(Data.get_level_count()):
		if Data.get_level(i).id == 98:
			GameState.current_level_index = i
			break
	GameState.designer_mode = true
	var game: Game = load("res://scenes/Game.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	print("""
=== PROTOTYP: TOLERANCE <-> BRAIN FOG ===
  F1        +500 Dopamine
  F3        turbo 5x
  F4        smaz vlnu
  F5 / F6   Tolerance -20 / +20 (skokem, bez cekani na Quick Hit)
  mezernik  zavolat vlnu

  Co sledovat:
   1) F6 nekolikrat po sobe: sleduj, jak se svetlo kolem jadra a vezi
      zmensuje (Tolerance -> Game.sight_radius_mult()).
   2) Postav vez na kraji svetla a spust vlnu -- distrakce ve tme se
      viditelne zpomali, jakmile prekroci hranici do svetla (rampa 0,35 s,
      enemy.gd FOG_SPEED_BOOST/FOG_SPEED_RAMP).
   3) Zkus v krizi (hodne distrakci, malo dopaminu) misto stavby mackat
      Quick Hit -- vsimni si, ze kazde pouziti natrvalo zvedne podlahu
      Tolerance (HUD readout "floor"), takze svetlo uz se samo nevrati.

  Otazka, na kterou to ma odpovedet: je tahle smycka "aha, tohle je
  zavislost", nebo jen otravna?
""")
