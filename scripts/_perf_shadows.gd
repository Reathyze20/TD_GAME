extends Node
## Realistic-load performance harness for the cast-shadow system (Light2D +
## LightOccluder2D, game.gd shadow_enabled). Same measurement discipline as
## _perf_probe.gd (wall-clock around process_frame, NOT Performance.TIME_PROCESS —
## measured 20x off in this project before — and vsync/max_fps forced off, or every
## config under 60fps reads as an identical 16.7ms): see memory project-mereni-vykonu.
##
## What "realistic load" means here, per the brief: bandwidth spent close to the
## GameState.BASE_BANDWIDTH (120) cap across a mix of Anchors + attack habits + a Guild
## (order-of-ten-plus built structures, each now carrying a shadow-casting Light2D),
## AT THE SAME TIME as a horde on the scale of the earlier zero-tower baseline
## (reference-godot-binary memory: ~270-300 concurrent Distraction nodes held 60fps with
## ZERO towers). This harness builds the towers AND spawns the horde, then compares
## game.shadow_enabled false vs true at that combined load — the comparison the fog-only
## _perf_probe.gd cannot make since the shadow system did not exist yet.
##
## Not --headless: shadows are computed by the real GPU 2D lighting pipeline, and
## get_viewport()/Performance timings need the actual renderer running (matches
## _perf_probe.gd's own header note).
##
##   godot --path <proj> --main-scene res://scenes/_perf_shadows.tscn -- --n 280

var completed := false
var _game: Game = null

var _horde_n := 0
var _horde_free_cells: Array[Vector2i] = []
const _HORDE_TYPES := ["notification", "autoplay", "doomscroll", "phantom_buzz",
	"clickbait", "adult_content", "group_chat", "energy_drink", "jackpot"]


func _ready() -> void:
	call_deferred("_run")


func _arg(name: String, fallback: String) -> String:
	var args := OS.get_cmdline_user_args()
	for i in range(args.size()):
		if args[i] == name and i + 1 < args.size():
			return args[i + 1]
	return fallback


## Verbatim from _perf_probe.gd: average AND worst frame over `frames` frames. The worst
## frame is what a player feels as a stutter; an average alone hides it.
func _mer(frames: int) -> Dictionary:
	var proc: Array[float] = []
	var wall: Array[float] = []
	for i in range(frames):
		var t0 := Time.get_ticks_usec()
		await get_tree().process_frame
		wall.append((Time.get_ticks_usec() - t0) / 1000.0)
		proc.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
	proc.sort()
	wall.sort()
	var sp := 0.0
	for c in proc:
		sp += c
	var sw := 0.0
	for c in wall:
		sw += c
	return {"prumer": sp / proc.size(), "p95": proc[int(proc.size() * 0.95)],
		"max": proc[proc.size() - 1], "wall": sw / wall.size(),
		"wall_max": wall[wall.size() - 1]}


func _radek(tag: String, m: Dictionary) -> void:
	print("  %-28s skript %6.2f ms (max %6.2f)   snimek %6.2f ms (max %6.2f) = %5.1f FPS"
		% [tag, m["prumer"], m["max"], m["wall"], m["wall_max"],
			1000.0 / maxf(m["wall"], 0.001)])


## Empty build spots inside the CURRENT Routine, farthest from the core first — same
## selection idea _shot_fog.gd/_shot_shadows.gd already use.
func _candidates(game: Game) -> Array:
	var out: Array = []
	for cell: Vector2i in game.build_spots:
		var bs = game.build_spots[cell]
		if bs.state != BuildSpot.State.EMPTY \
				or not game.is_position_in_routine(game.cell_center(cell), game._routine_sources):
			continue
		out.append(cell)
	out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return game.cell_center(a).distance_to(game.objective_pos) \
			> game.cell_center(b).distance_to(game.objective_pos))
	return out


func _build_simple(game: Game, type_key: String, cell: Vector2i) -> void:
	GameState.select_habit(type_key)
	game._build_on(cell)
	game._end_aiming()


## Spends bandwidth toward GameState.BASE_BANDWIDTH, mixing Anchors (extend the Routine
## frontier so more spots open up) with attack habits + one Guild (the actual bandwidth-
## heavy load, and the "not just Habit" check the fog's own _building_sight_lights and
## this system's _sync_shadow_lights both have to get right). Stops when nothing more is
## affordable or reachable — this is a realistic mixed build, not a synthetic max-count.
func _fill_bandwidth(game: Game) -> void:
	var attack_types: Array[String] = [
		"focus_timer", "mindfulness", "exercise", "real_hobby", "zen_pulsar", "accountability"]
	var ti := 0
	var built := 0
	var anchors := 0
	var guard := 0
	while guard < 500:
		guard += 1
		var cands := _candidates(game)
		if cands.is_empty():
			break
		var free_bw := GameState.bandwidth_free()
		if free_bw < 3:
			break
		# Expand the frontier every few builds, or immediately once the frontier runs
		# thin — otherwise the loop stalls with bandwidth left unspent but no reachable
		# empty spot to spend it on.
		var want_anchor := cands.size() < 4 or (built > 0 and built % 4 == 0)
		var placed := false
		if want_anchor and free_bw >= Data.get_habit("anchor").bandwidth_cost:
			_build_simple(game, "anchor", cands[cands.size() - 1])   # farthest: reach
			anchors += 1
			placed = true
		else:
			var tried := 0
			while tried < attack_types.size():
				var key: String = attack_types[ti % attack_types.size()]
				ti += 1
				tried += 1
				if free_bw >= Data.get_habit(key).bandwidth_cost:
					_build_simple(game, key, cands[0])   # nearest: fill efficiently
					placed = true
					break
			if not placed and free_bw >= Data.get_habit("anchor").bandwidth_cost:
				_build_simple(game, "anchor", cands[cands.size() - 1])
				anchors += 1
				placed = true
		if not placed:
			break
		built += 1
		await get_tree().process_frame   # let _update_routine_reach absorb a new Anchor
	game._end_aiming()
	GameState.select_habit(null)
	print("  postaveno %d struktur (%d z toho Anchor), bandwidth %d/%d, occluderu %d"
		% [built, anchors, GameState.bandwidth_used, GameState.bandwidth_max,
			game._shadow_occluder_count])


## Clears any surviving distractions and spawns a fresh, identically-seeded batch of
## _horde_n. Used to reset the horde to the SAME population before every measured row in
## the "+ horda" section below — towers in this harness fight for real (that is the
## point: realistic load means active combat, not a frozen tableau), so left alone the
## population shrinks over each measurement window. Re-rolling it before every row stops
## that shrinkage from accumulating ACROSS rows and quietly making each successive row
## cheaper than the last for a reason that has nothing to do with shadow_enabled. A first
## pass at this harness measured all three rows on one aging population and got a
## monotonic ~40 -> 29 -> 20 ms sequence that tracked the horde dying, not the toggle —
## see docs/core/15_cast_shadows.md.
func _respawn_horde() -> void:
	for d in _game._distractions.duplicate():
		if is_instance_valid(d):
			d.queue_free()
	_game._distractions.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260818
	for i in range(_horde_n):
		_game.spawn_distraction(StringName(_HORDE_TYPES[i % _HORDE_TYPES.size()]),
			_horde_free_cells[rng.randi() % _horde_free_cells.size()])
	await get_tree().process_frame


func _run() -> void:
	var n := int(_arg("--n", "280"))
	var wd := Timer.new()
	wd.wait_time = 240.0
	wd.one_shot = true
	add_child(wd)
	wd.timeout.connect(func():
		if not completed:
			print("FAILED: probe nedobehl")
			get_tree().quit(1))
	wd.start()

	# Bez tohohle je vsechno pod 60 FPS nerozeznatelnych 16,7 ms (project-mereni-vykonu).
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0

	_game = load("res://scenes/Game.tscn").instantiate()
	add_child(_game)
	await get_tree().process_frame
	GameState.max_focus = 999999
	GameState.focus = 999999
	GameState.dopamine = 999999
	await get_tree().process_frame

	# Warm-up: the very first time shadow_enabled flips to true, the renderer compiles
	# the 2D shadow-map pipeline variant for the first time in this process — a one-time
	# stall that has nothing to do with the system's steady-state cost. Left in place, it
	# would land inside whichever measured row happened to be the first "stiny ZAP" and
	# make that ONE row look far worse than every later one for a reason that has nothing
	# to do with load. Eating it here, before any row is timed, is what _perf_probe.gd's
	# own "measure after one settle frame" already does for fog — this just needed a few
	# more frames because shader compilation is heavier than a viewport toggle.
	_game.shadow_enabled = true
	for _f in range(20):
		await get_tree().process_frame
	_game.shadow_enabled = false
	for _f in range(5):
		await get_tree().process_frame

	var g := Data.GRID
	print("\nmrizka %d x %d po %d px, %d bunek" % [g.cols, g.rows, g.tile,
		int(g.cols) * int(g.rows)])

	# ---------------------------------------------------------------- prazdne pole
	print("\nPRAZDNE POLE (mlha ZAP po celou dobu — realisticky shipped stav)")
	_game.shadow_enabled = false
	for _f in range(10):
		await get_tree().process_frame
	_radek("stiny VYP", await _mer(120))
	_game.shadow_enabled = true
	for _f in range(10):
		await get_tree().process_frame
	_radek("stiny ZAP", await _mer(120))

	# ---------------------------------------------------------------- plna bandwidth vezi
	_game.shadow_enabled = false
	await get_tree().process_frame
	_fill_bandwidth(_game)
	for _f in range(10):
		await get_tree().process_frame

	print("\nPLNA BANDWIDTH VEZI, ZADNA HORDA")
	_game.shadow_enabled = false
	for _f in range(10):
		await get_tree().process_frame
	_radek("stiny VYP", await _mer(120))
	_game.shadow_enabled = true
	for _f in range(10):
		await get_tree().process_frame
	_radek("stiny ZAP", await _mer(120))

	# ---------------------------------------------------------------- + horda
	_horde_n = n
	for cy in range(int(g.rows)):
		for cx in range(int(g.cols)):
			var c := Vector2i(cx, cy)
			if not _game.high_ground.has(c) and c != _game.objective_cell:
				_horde_free_cells.append(c)

	print("\nPLNA BANDWIDTH VEZI (%d struktur) + %d DISTRAKCI  <- hlavni scenar zadani"
		% [_game.build_spots.values().filter(
			func(s): return s.state == BuildSpot.State.BUILT).size(), n])

	_game.fog_enabled = true
	_game.shadow_enabled = false
	await _respawn_horde()
	for _f in range(10):
		await get_tree().process_frame
	_radek("mlha ZAP, stiny VYP (dnesni shipped stav)", await _mer(180))

	_game.shadow_enabled = true
	await _respawn_horde()
	for _f in range(10):
		await get_tree().process_frame
	_radek("mlha ZAP, stiny ZAP (novy system)", await _mer(180))

	# Isolates the shadow system's own cost from fog's pre-existing cost, at the same load.
	_game.fog_enabled = false
	await _respawn_horde()
	for _f in range(10):
		await get_tree().process_frame
	_radek("mlha VYP, stiny ZAP (izolovana cena stinu)", await _mer(180))
	_game.fog_enabled = true

	completed = true
	print("\nHOTOVO")
	get_tree().quit(0)
