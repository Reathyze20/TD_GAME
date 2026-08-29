extends Node
## Harness pro §5.9 — taxonomii útoků na pozornost.
##
## Tři archetypy, tři otázky, a všechny tři jsou o tom, jestli mechanika opravdu DĚLÁ
## to, co ta psychologie tvrdí — ne jestli to nespadne:
##
##   fleeting (FOMO)          — je ignorování skutečně zadarmo? 0 Focus, žádná odměna.
##   splitter (Just One More) — pokračuje fronta tam, kde skončila, nebo se resetuje?
##   autoplay                 — ukradne build fázi, a nedá se to vzít zpátky?
##
## Čtvrtá část hlídá regresi, kterou nová pole snadno způsobí: stávající distrakce se
## nesmí hnout. Archetyp vypnutý nulou musí být opravdu vypnutý.
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
	# Mirror nezaznamenává designer runy, a půlka těchhle kontrol je o tom, co se
	# zapsalo do logu. Bez tohohle by celá sekce o účtence tiše prošla naprázdno.
	GameState.designer_mode = false
	Mirror.begin_level(99)
	# Archetypy tikají jen ve WAVE čase — bez tohohle se žádný odpočet nehne.
	game.started = true
	game.between_waves = false
	await get_tree().process_frame

	print("\n-- data: archetypy existují a jsou vypnuté všude jinde")
	var fomo: DistractionData = Data.get_distraction(&"fomo")
	var jom: DistractionData = Data.get_distraction(&"just_one_more")
	var auto: DistractionData = Data.get_distraction(&"autoplay")
	_check("fomo.tres se nacetl", fomo != null)
	_check("just_one_more.tres se nacetl", jom != null)
	_check("fleeting: lifetime > 0", fomo != null and fomo.lifetime_seconds > 0.0,
		"%.1fs" % (fomo.lifetime_seconds if fomo != null else -1.0))
	# Tohle je celá pointa archetypu. Kdyby FOMO někdy ubralo Focus, lekce se obrátí.
	_check("fleeting: focus_damage == 0", fomo != null and fomo.focus_damage == 0,
		str(fomo.focus_damage if fomo != null else -1))
	# A zároveň musí být lákavé — návnada není návnada, když se nevyplácí.
	_check("fleeting: odmena je opravdova", fomo != null and fomo.dopamine_reward >= 8,
		str(fomo.dopamine_reward if fomo != null else -1))
	_check("splitter: count i generations > 0",
		jom != null and jom.split_count > 0 and jom.split_generations > 0)
	_check("autoplay: deadline > 0", auto != null and auto.autoplay_seconds > 0.0,
		"%.1fs" % (auto.autoplay_seconds if auto != null else -1.0))
	var strays := 0
	for key in [&"notification", &"clickbait", &"doomscroll", &"energy_drink",
			&"group_chat", &"jackpot", &"phantom_buzz", &"adult_content"]:
		var d: DistractionData = Data.get_distraction(key)
		if d == null:
			continue
		if d.lifetime_seconds > 0.0 or d.split_count > 0 or d.autoplay_seconds > 0.0:
			strays += 1
	_check("stavajici distrakce zustaly nedotcene", strays == 0, "%d dotcenych" % strays)

	print("\n-- fleeting: ignorovat je zadarmo")
	var spawn: Vector2i = game._random_spawn_cell()
	var live_before: int = game._distractions.size()
	var f := game.spawn_distraction(&"fomo", spawn)
	await get_tree().process_frame
	_check("FOMO se spawnula", f != null and is_instance_valid(f))
	_check("ma natazeny odpocet", f != null and f._life_left > 0.0, "%.1fs" % f._life_left)
	# Odpočet NESMÍ běžet v build fázi: nabídka, kterou hráč nemohl stihnout, nic neučí.
	game.between_waves = true
	f._process(3.0)
	_check("v build fazi odpocet stoji", is_instance_valid(f)
		and is_equal_approx(f._life_left, fomo.lifetime_seconds), "%.2f" % f._life_left)
	game.between_waves = false
	var focus_before: int = GameState.focus
	var dop_before: int = GameState.dopamine
	# Uteče čas — ne život.
	for i in range(20):
		if is_instance_valid(f) and not f.dead:
			f._process(0.5)
		await get_tree().process_frame
	_check("po vyprseni zmizela", not is_instance_valid(f) or f.dead)
	_check("nesebrala Focus", GameState.focus == focus_before,
		"%d -> %d" % [focus_before, GameState.focus])
	_check("nezaplatila Dopamine", GameState.dopamine == dop_before,
		"%d -> %d" % [dop_before, GameState.dopamine])
	_check("zmizela z ziveho seznamu", game._distractions.size() == live_before,
		str(game._distractions.size()))
	_check("log zapsal bait_expired", Mirror.count(&"bait_expired") >= 1)

	print("\n-- fleeting: zabit ji je to, co stoji")
	var f2 := game.spawn_distraction(&"fomo", spawn)
	await get_tree().process_frame
	f2.take_direct_damage(99999)
	await get_tree().process_frame
	_check("zabita se zapsala jako bait_kill", Mirror.count(&"bait_kill") >= 1)
	var summary: Dictionary = Mirror.summarise()
	_check("ucet vidi bait_kills", int(summary.get("bait_kills", 0)) >= 1,
		str(summary.get("bait_kills", 0)))

	print("\n-- splitter: fronta pokracuje, neresetuje se")
	# Vyprazdnene pole behem predchozi sekce nechalo hru vratit se do build faze
	# (_check_wave_progress se polluje kazdy snimek). Deadline archetypy tikaji jen
	# ve wave case, takze gate musi byt zpatky nahore, jinak testujeme ticho.
	game.started = true
	game.between_waves = false
	var live0: int = game._distractions.size()
	var j := game.spawn_distraction(&"just_one_more", spawn)
	await get_tree().process_frame
	# Posuň ho kus po cestě, ať je vidět, jestli děti startují odsud, nebo od vchodu.
	var mid: Vector2 = game.cell_center(spawn).lerp(game.objective_pos, 0.5)
	j.position = mid
	j.global_position = mid
	var gen0_hp: int = j.max_health
	j.take_direct_damage(99999)
	await get_tree().process_frame
	var kids: Array = []
	for d in game._distractions:
		if d.type_key == "just_one_more":
			kids.append(d)
	_check("po smrti zustaly kopie", kids.size() == jom.split_count,
		"%d z %d" % [kids.size(), jom.split_count])
	if not kids.is_empty():
		_check("kopie jsou generace 1", kids[0].generation == 1, str(kids[0].generation))
		_check("kopie jsou slabsi", kids[0].max_health < gen0_hp,
			"%d < %d" % [kids[0].max_health, gen0_hp])
		_check("kopie jsou mensi", kids[0].scale.x < 1.0, "%.2f" % kids[0].scale.x)
		# Tohle je ta mechanika: děti startují tam, kde rodič padl.
		var d_kid: float = kids[0].global_position.distance_to(game.objective_pos)
		var d_spawn: float = game.cell_center(spawn).distance_to(game.objective_pos)
		_check("kopie pokracuji, nezacinaji znovu", d_kid < d_spawn * 0.9,
			"%.0f < %.0f" % [d_kid, d_spawn])
		_check("kopie maji cestu", not kids[0].cell_path.is_empty(),
			"%d kroku" % kids[0].cell_path.size())
	_check("log zapsal split", Mirror.count(&"split") >= 1)

	# Řetěz se musí zastavit. Exponent bez stropu je zamrzlý snímek, ne špatné číslo.
	print("\n-- splitter: retez konci")
	var guard := 0
	var deepest := 0
	while guard < 400:
		guard += 1
		var alive: Array = []
		for d in game._distractions:
			if d.type_key == "just_one_more":
				alive.append(d)
		if alive.is_empty():
			break
		for d in alive:
			deepest = maxi(deepest, d.generation)
			d.take_direct_damage(99999)
		await get_tree().process_frame
	_check("retez se vycerpal", guard < 400, "%d kol" % guard)
	_check("nesel hloubeji nez smi", deepest <= jom.split_generations,
		"%d <= %d" % [deepest, jom.split_generations])
	_check("pole je zase ciste", game._distractions.size() == live0,
		str(game._distractions.size()))

	# Rodic bez cesty na netrasovatelne bunce: deti nesmi zustat stat a drzet vlnu
	# otevrenou. Bud maji cestu, nebo se vubec nespawnou -- treti moznost je zaseknuty run.
	print("
-- splitter: nezasekne vlnu, kdyz rodic nema cestu")
	var wall_cell: Vector2i = game.high_ground.keys()[0] if not game.high_ground.is_empty() else spawn
	var stuck := game.spawn_distraction(&"just_one_more", spawn)
	await get_tree().process_frame
	stuck.position = game.cell_center(wall_cell)
	stuck.global_position = stuck.position
	stuck.cell_path = []
	stuck.path_index = 0
	stuck.take_direct_damage(99999)
	await get_tree().process_frame
	var orphans := 0
	for d in game._distractions:
		if d.type_key == "just_one_more" and d.cell_path.is_empty() and not d.is_flying:
			orphans += 1
	_check("zadne dite nezustalo bez cesty", orphans == 0, "%d sirotku" % orphans)
	for d in game._distractions.duplicate():
		if d.type_key == "just_one_more":
			d.take_direct_damage(99999)
	await get_tree().process_frame

	print("\n-- autoplay: krade build fazi")
	# Vyprazdnene pole behem predchozi sekce nechalo hru vratit se do build faze
	# (_check_wave_progress se polluje kazdy snimek). Deadline archetypy tikaji jen
	# ve wave case, takze gate musi byt zpatky nahore, jinak testujeme ticho.
	game.started = true
	game.between_waves = false
	game._autoplay_left = -1.0
	var a := game.spawn_distraction(&"autoplay", spawn)
	await get_tree().process_frame
	_check("autoplay ma natazeny odpocet", a._autoplay_left > 0.0, "%.1fs" % a._autoplay_left)
	_check("build faze zatim neni ohrozena", game._autoplay_left < 0.0)
	a._process(auto.autoplay_seconds + 1.0)
	await get_tree().process_frame
	_check("po deadlinu se to natahlo", game._autoplay_left > 0.0,
		"%.1fs" % game._autoplay_left)
	_check("hlasi to log", Mirror.count(&"autoplay_armed") >= 1)
	# Zabít ho POTOM nesmí build fázi vrátit — to je celý smysl toho latche.
	var armed_at: float = game._autoplay_left
	a.take_direct_damage(99999)
	await get_tree().process_frame
	_check("zabiti po deadlinu uz nic nevrati",
		is_equal_approx(game._autoplay_left, armed_at), "%.1fs" % game._autoplay_left)
	# Odpočet hoří jen v build fázi — během vlny nemá co brát.
	game.between_waves = false
	game._update_autoplay(2.0)
	_check("behem vlny odpocet stoji", is_equal_approx(game._autoplay_left, armed_at),
		"%.1fs" % game._autoplay_left)
	game.between_waves = true
	game._update_autoplay(0.5)
	_check("v build fazi odpocet hori", game._autoplay_left < armed_at,
		"%.1fs" % game._autoplay_left)
	game._update_autoplay(999.0)
	await get_tree().process_frame
	_check("vlna se spustila sama", not game.between_waves,
		"between=%s wave=%d" % [game.between_waves, game.wave_index])
	_check("kradez je v logu", Mirror.count(&"autoplay_stole_prep") >= 1)
	_check("latch se uklidil", game._autoplay_left < 0.0, "%.1f" % game._autoplay_left)

	print("
-- comparison: uci se z toho, co jsi postavil")
	var comp: DistractionData = Data.get_distraction(&"comparison")
	_check("comparison.tres se nacetl", comp != null)
	_check("comparison: adapts_to_player", comp != null and comp.adapts_to_player)
	# Prázdná deska: není se z čeho učit, takže se nic nesmí vymyslet.
	var empty_spots: Array = []
	for cell in game.build_spots.keys():
		if game.build_spots[cell].state == BuildSpot.State.EMPTY:
			empty_spots.append(cell)
	_check("mame kam stavet", empty_spots.size() >= 3, "%d mist" % empty_spots.size())
	var c0 := game.spawn_distraction(&"comparison", spawn)
	await get_tree().process_frame
	_check("na prazdne desce se neadaptuje", c0.adapted_channel == &"",
		str(c0.adapted_channel))
	_check("odolnosti zustaly z def", c0.current_compulsion == comp.compulsion
		and c0.current_rationalization == comp.rationalization)
	c0.take_direct_damage(99999)
	await get_tree().process_frame

	# Awareness větev: mindfulness dělá 5 awareness a 0 willpower.
	GameState.dopamine = 999999
	GameState.select_habit("mindfulness")
	game._build_on(empty_spots[0])
	game._end_aiming()
	await get_tree().process_frame
	var prof: Dictionary = game.player_damage_profile()
	_check("deska hlasi awareness", int(prof.get("awareness", 0)) > 0, str(prof))
	var c1 := game.spawn_distraction(&"comparison", spawn)
	await get_tree().process_frame
	_check("adaptovala se na awareness", c1.adapted_channel == &"awareness",
		str(c1.adapted_channel))
	_check("tvrdne jen v jednom kanalu", c1.current_compulsion == comp.compulsion,
		"%d" % c1.current_compulsion)
	_check("awareness odolnost narostla", c1.current_rationalization > comp.rationalization,
		"%d > %d" % [c1.current_rationalization, comp.rationalization])
	_check("log zapsal adapted", Mirror.count(&"adapted") >= 1)
	c1.take_direct_damage(99999)
	await get_tree().process_frame

	# Willpower větev: exercise dělá 34 willpower a přebije mindfulness.
	GameState.dopamine = 999999
	GameState.select_habit("exercise")
	game._build_on(empty_spots[1])
	game._end_aiming()
	await get_tree().process_frame
	var c2 := game.spawn_distraction(&"comparison", spawn)
	await get_tree().process_frame
	_check("prepnula se na willpower", c2.adapted_channel == &"willpower",
		str(c2.adapted_channel))
	var bite: int = c2.current_compulsion
	_check("willpower odolnost narostla", bite > comp.compulsion,
		"%d > %d" % [bite, comp.compulsion])
	_check("awareness uz netvrdne", c2.current_rationalization == comp.rationalization,
		"%d" % c2.current_rationalization)
	c2.take_direct_damage(99999)
	await get_tree().process_frame

	# Klíčová pojistka: stavět VÍC nesmí nepřítele posílit, jinak archetyp trestá hraní.
	GameState.dopamine = 999999
	GameState.select_habit("exercise")
	game._build_on(empty_spots[2])
	game._end_aiming()
	await get_tree().process_frame
	var c3 := game.spawn_distraction(&"comparison", spawn)
	await get_tree().process_frame
	_check("druhy stejny navyk ho neposilil", c3.current_compulsion == bite,
		"%d == %d" % [c3.current_compulsion, bite])
	c3.take_direct_damage(99999)
	await get_tree().process_frame

	completed = true
	print("\n%s (%d failures)" % ["PASSED" if fails == 0 else "FAILED", fails])
	get_tree().quit(1 if fails > 0 else 0)
