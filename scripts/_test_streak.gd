extends Node
## Harness pro serii (loss aversion).
##
## Serie je jediná mechanika ve hře, kterou hráč pozná z vlastního telefonu — a přesně
## proto na ní záleží, aby byla POCTIVÁ. Není to past: bonus je skutečný a hrát opatrně
## kvůli němu je skutečně správná hra. Co se mění, je rámec — od třetí vlny už
## nevyděláváš, ale chráníš.
##
## Kontroly jdou po třech vlastnostech, které se dají snadno "opravit" špatně:
##
##   1. Bonus je opravdový a nikdy nepřeteče přes strop.
##   2. Láme se v OKAMŽIKU průsaku, ne v souhrnu po vlně. Ztráta musí být moment.
##   3. Po zlomu není nic těžšího — jen se přestal platit bonus, který ještě nebyl
##      vyplacený. To je celý ten nález a účtenka to musí umět říct bez rozsudku.
##
## Jede na iso levelu 98, kde je serie zapnutá a Tolerance zůstává na nule, takže do
## výplaty nemluví downregulace.

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

	var game = load("res://scenes/Game.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	GameState.max_focus = 999999
	GameState.focus = 999999
	GameState.designer_mode = false
	Mirror.begin_level(98)
	await get_tree().process_frame

	print("\n-- zapnuti a vychozi stav")
	_check("level 98 ma serii zapnutou", GameState.streak_enabled)
	_check("zacina na nule", GameState.streak == 0, str(GameState.streak))
	_check("bez serie je nasobic presne 1.0",
		is_equal_approx(GameState.streak_mult(), 1.0), "%.2f" % GameState.streak_mult())
	_check("HUD chip existuje", game._streak_label != null)

	print("\n-- roste za ciste vlny")
	var seen: Array = []
	GameState.streak_changed.connect(func(v: int, m: float): seen.append(v))
	for i in range(4):
		GameState.begin_wave_streak_window()
		GameState.note_wave_cleared()
	_check("ctyri ciste vlny = serie 4", GameState.streak == 4, str(GameState.streak))
	_check("nasobic vyrostl", GameState.streak_mult() > 1.0,
		"x%.2f" % GameState.streak_mult())
	_check("HUD to dostal", seen.size() == 4, str(seen))
	_check("HUD text ukazuje obe cisla", game._streak_label.text.contains("4")
		and game._streak_label.text.contains("x"), game._streak_label.text)

	print("\n-- strop drzi")
	for i in range(40):
		GameState.begin_wave_streak_window()
		GameState.note_wave_cleared()
	_check("nasobic nepretece pres strop",
		is_equal_approx(GameState.streak_mult(), GameState.STREAK_MAX_MULT),
		"x%.2f" % GameState.streak_mult())

	print("\n-- bonus je opravdovy")
	# Stejny nepritel, jednou bez serie a jednou s ni. Tolerance 0 a variable_rewards
	# vypnute, takze do rozdilu nemluvi nic jineho.
	GameState.set_tolerance(0.0)
	GameState.variable_rewards = false
	GameState.streak = 0
	var spawn: Vector2i = game._random_spawn_cell()
	var before_plain: int = GameState.dopamine
	var d1 = game.spawn_distraction(&"notification", spawn)
	await get_tree().process_frame
	d1.take_direct_damage(99999)
	await get_tree().process_frame
	var plain: int = GameState.dopamine - before_plain
	GameState.streak = 4
	var before_streak: int = GameState.dopamine
	var d2 = game.spawn_distraction(&"notification", spawn)
	await get_tree().process_frame
	d2.take_direct_damage(99999)
	await get_tree().process_frame
	var boosted: int = GameState.dopamine - before_streak
	_check("se serii plati vic", boosted > plain, "%d -> %d" % [plain, boosted])

	print("\n-- lame se v OKAMZIKU pruseku, ne po vlne")
	GameState.streak = 6
	GameState.begin_wave_streak_window()
	SignalBus.distraction_escaped.emit(1)
	await get_tree().process_frame
	_check("prusek srazil serii hned", GameState.streak == 0, str(GameState.streak))
	_check("zlom je v logu s velikosti", Mirror.peak(&"streak_broken") >= 6.0,
		"%.0f" % Mirror.peak(&"streak_broken"))
	_check("HUD ukazuje pomlcku", game._streak_label.text == "—", game._streak_label.text)
	# A dokonceni te same vlny uz serii nevrati - prusek uz nastal.
	GameState.note_wave_cleared()
	_check("dokonceni vlny s prusekem serii nevrati", GameState.streak == 0,
		str(GameState.streak))
	# Dalsi ciste vlna uz zase pocita od jedne.
	GameState.begin_wave_streak_window()
	GameState.note_wave_cleared()
	_check("dalsi ciste vlna zacina od jedne", GameState.streak == 1,
		str(GameState.streak))

	print("\n-- po zlomu neni nic tezsi")
	# Tohle je ten nalez: ztratil se bonus, ktery jeste nebyl vyplaceny. Nic jineho.
	GameState.streak = 0
	var after_break: int = GameState.dopamine
	var d3 = game.spawn_distraction(&"notification", spawn)
	await get_tree().process_frame
	d3.take_direct_damage(99999)
	await get_tree().process_frame
	_check("vyplata je zpatky na normalu, ne pod nim",
		GameState.dopamine - after_break == plain,
		"%d vs %d" % [GameState.dopamine - after_break, plain])

	print("\n-- novy level serii nedrzi")
	GameState.streak = 5
	GameState.reset_for_level(Data.get_level(GameState.current_level_index))
	_check("reset_for_level serii vynuluje", GameState.streak == 0,
		str(GameState.streak))

	print("\n-- ucetnka")
	Mirror.history.clear()
	Mirror.begin_level(98)
	for i in range(7):
		Mirror.mark(&"streak", i + 1)
	Mirror.mark(&"streak_broken", 7)
	var summary: Dictionary = Mirror.summarise()
	_check("nejdelsi serie je vrchol, ne soucet",
		int(summary.get("streak_best", -1)) == 7, str(summary.get("streak_best", -1)))
	_check("ztracena serie se pocita zvlast",
		int(summary.get("streak_lost", -1)) == 7, str(summary.get("streak_lost", -1)))
	var head: Dictionary = Receipt._headline(summary, {})
	_check("headline pojmenuje ztratu", String(head.get("value", "")) == "7",
		String(head.get("value", "")))
	_check("a rekne, ze to nebylo vyplacene",
		String(head.get("caption", "")).contains("had not been paid yet"),
		String(head.get("caption", "")))
	# Kratka serie jeste nema ramec, ktery by slo ztratit.
	Mirror.history.clear()
	Mirror.begin_level(98)
	Mirror.mark(&"streak", 2)
	Mirror.mark(&"streak_broken", 2)
	var head2: Dictionary = Receipt._headline(Mirror.summarise(), {})
	_check("kratka serie zadny headline nedostane",
		not String(head2.get("caption", "")).contains("had not been paid yet"),
		String(head2.get("caption", "")))

	completed = true
	print("\n%s (%d failures)" % ["PASSED" if fails == 0 else "FAILED", fails])
	get_tree().quit(1 if fails > 0 else 0)
