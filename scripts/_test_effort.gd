extends Node
## Harness pro effort discounting (Salamone) — barieru z kolecka mysi.
##
## Jedna vec, kterou tady hlida kazda kontrola: **cena te snadne volby nesmi byt
## vymyslena.** Auto-aim vraci kuzel na domaci uhel habitu, kde jsou vsechny nasobice
## z ArcProfile presne 1.0 — takze hrac ztraci vyhradne to doladeni, ktere sam delal.
## Kdo s koleckem nikdy nehnul, neztraci nic. To musi platit ciselne, ne v komentari.
##
## Druha polovina hlida, ze to neni trest: nic se nestalo tezsim na VYHRANI, jen
## otravnejsim na DELANI, a vzit si mireni zpatky vrati i puvodni nastaveni.
##
## Jede na iso levelu (id 98) — cista TD, takze nic jineho do Tolerance nemluvi.

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

func _run() -> void:
	for i in range(Data.get_level_count()):
		if Data.get_level(i).id == 98:
			GameState.current_level_index = i
			break

	var game: Game = load("res://scenes/Game.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	GameState.max_focus = 999999
	GameState.focus = 999999
	GameState.dopamine = 999999
	GameState.designer_mode = false
	Mirror.begin_level(98)
	await get_tree().process_frame

	print("\n-- bariera: mireni tezkne s Toleranci")
	GameState.set_tolerance(0.0)
	var fresh: float = game.aim_step()
	_check("cerstvy hrac ma plny krok", is_equal_approx(fresh, game.AIM_STEP_FRESH),
		"%.1f deg" % fresh)
	GameState.set_tolerance(game.EFFORT_STRAIN)
	_check("na prahu se jeste nic nezmenilo",
		is_equal_approx(game.aim_step(), game.AIM_STEP_FRESH), "%.1f" % game.aim_step())
	GameState.set_tolerance(100.0)
	var tired: float = game.aim_step()
	_check("vycerpany hrac ma kratky krok", is_equal_approx(tired, game.AIM_STEP_TIRED),
		"%.1f deg" % tired)
	# To je ta bariera vycislena: stejny uhel stoji 2.5x tolik kliknuti.
	_check("stejne doladeni stoji vic prace", tired < fresh * 0.6,
		"%.1fx kliknuti" % (fresh / tired))

	print("\n-- nabidka prijde, az kdyz je bariera citit")
	GameState.set_tolerance(0.0)
	game._effort_offered = false
	game._update_effort_offer()
	_check("bez Tolerance zadna nabidka", not game._effort_offered)

	# Postav neco, na cem se da mirit.
	var spots: Array = []
	for cell in game.build_spots.keys():
		# _can_build, ne jen EMPTY: stavet jde vyhradne v dosahu Routine, a misto mimo ni
		# tise selze na _flash_error. Prvni verze tohohle testu na tom padala.
		if game._can_build(cell):
			spots.append(cell)
	_check("mame kam stavet", spots.size() >= 2, "%d mist" % spots.size())
	GameState.dopamine = 999999
	GameState.select_habit("focus_timer")
	game._build_on(spots[0])
	game._end_aiming()
	await get_tree().process_frame
	var h = game.build_spots[spots[0]].current_habit
	_check("navyk stoji", h is Habit)

	GameState.set_tolerance(70.0)
	game._update_effort_offer()
	_check("nad prahem se nabidka objevi", game._effort_offered)
	_check("nabidka je v logu", Mirror.count(&"effort_offer") >= 1)
	game._update_effort_offer()
	_check("a nabidne se jen jednou za level", Mirror.count(&"effort_offer") == 1)

	print("\n-- cena te snadne volby neni vymyslena")
	# Doladene uzko: ArcProfile z toho odvodi damage_mult > 1.0.
	h.set_arc_angle(ArcProfile.ARC_MIN)
	var tuned_mult: float = h.arc_profile().damage_mult
	var tuned_arc: float = h.arc_angle
	var tuned_facing: float = h.facing_angle
	_check("uzky kuzel opravdu neco pridava", tuned_mult > 1.0, "%.2fx" % tuned_mult)

	game.toggle_auto_aim()
	await get_tree().process_frame
	_check("auto-aim se zapnul", h.auto_aim)
	_check("kuzel skocil na domaci uhel", is_equal_approx(h.arc_angle, h.def.arc_angle),
		"%.0f deg" % h.arc_angle)
	# Tohle je ta kontrola, o kterou tu jde: na domacim uhlu je nasobic presne 1.0,
	# takze zadna penalizace navic neexistuje — ztraci se jen to doladeni.
	_check("na domacim uhlu je nasobic presne 1.0",
		is_equal_approx(h.arc_profile().damage_mult, 1.0),
		"%.3f" % h.arc_profile().damage_mult)
	_check("zaznamenalo se, co hrac odevzdal",
		is_equal_approx(h.surrendered_mult, tuned_mult),
		"%.2f" % h.surrendered_mult)
	_check("odevzdani je v logu", Mirror.count(&"auto_aim_on") >= 1)

	print("\n-- vzit si mireni zpatky neni trest")
	game.toggle_auto_aim()
	await get_tree().process_frame
	_check("auto-aim se vypnul", not h.auto_aim)
	_check("puvodni uhel se vratil", is_equal_approx(h.arc_angle, tuned_arc),
		"%.0f deg" % h.arc_angle)
	_check("puvodni smer se vratil", is_equal_approx(h.facing_angle, tuned_facing))

	print("\n-- kdo nikdy neladil, neztraci nic")
	GameState.dopamine = 999999
	GameState.select_habit("focus_timer")
	game._build_on(spots[1])
	game._end_aiming()
	await get_tree().process_frame
	var h2 = game.build_spots[spots[1]].current_habit
	h2.set_arc_angle(h2.def.arc_angle)
	h2.set_auto_aim(true)
	_check("neladeny navyk odevzdal presne 1.0",
		is_equal_approx(h2.surrendered_mult, 1.0), "%.3f" % h2.surrendered_mult)
	h2.set_auto_aim(false)

	print("\n-- auto-aim se opravdu otaci za nepratelem")
	h.set_auto_aim(true)
	h.facing_angle = 0.0
	var spawn: Vector2i = game._random_spawn_cell()
	var d := game.spawn_distraction(&"notification", spawn)
	await get_tree().process_frame
	# Postav ji tesne k navyku, at je v dosahu a viditelna.
	d.global_position = h.global_position + Vector2(0.0, 60.0)
	d.position = d.global_position
	game.started = true
	game.between_waves = false
	h._auto_aim_cd = 0.0
	h._tick_auto_aim(0.016)
	# Zem je 2:1, takze cil primo "pod" vezi lezi ve smeru +Y v pozemnim prostoru.
	_check("otocil se dolu za ni", absf(h.facing_angle - PI * 0.5) < 0.4,
		"%.2f rad" % h.facing_angle)

	print("\n-- ucetnka to umi pojmenovat")
	Mirror.history.clear()
	Mirror.begin_level(98)
	Mirror.mark(&"auto_aim_on", 1.28)
	Mirror.mark(&"auto_aim_wave")
	Mirror.mark(&"auto_aim_wave")
	var summary: Dictionary = Mirror.summarise()
	_check("pocita se to po vlnach", int(summary.get("auto_aim_waves", 0)) == 2,
		str(summary.get("auto_aim_waves", 0)))
	var head: Dictionary = Receipt._headline(summary, {})
	_check("headline rekne, kolik to stalo",
		String(head.get("value", "")) == "28%", String(head.get("value", "")))
	_check("a rekne to bez rozsudku",
		String(head.get("caption", "")).contains("handed it back"),
		String(head.get("caption", "")))
	# Kdo nic neodevzdal, nesmi dostat vymysleny nalez.
	Mirror.history.clear()
	Mirror.begin_level(98)
	Mirror.mark(&"auto_aim_on", 1.0)
	var head0: Dictionary = Receipt._headline(Mirror.summarise(), {})
	_check("nula odevzdaneho = zadny headline o mireni",
		not String(head0.get("caption", "")).contains("handed it back"),
		String(head0.get("caption", "")))

	completed = true
	print("\n%s (%d failures)" % ["PASSED" if fails == 0 else "FAILED", fails])
	get_tree().quit(1 if fails > 0 else 0)
