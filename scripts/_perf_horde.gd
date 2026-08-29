extends Node
## T11 (docs/refactor/MIGRATION.MD): horde scaling bench. Spawns distractions into the
## spawn zone (so they actually walk the path, not just sit scattered on open floor)
## and measures wall-clock frametime with N = 50, 100, 200, 500, 1000 live at once,
## cumulatively (each step tops the population up to the next N rather than resetting
## the level), then writes docs/PERF.md as a table. Pure measurement — NEOPTIMALIZUJ.
##
## Wall-clock around `await get_tree().process_frame`, not Performance.TIME_PROCESS:
## TIME_PROCESS is smoothed/stale (measured 82ms vs an actual 4.16ms frame on this
## project before). Vsync forced off, otherwise everything under 60 FPS reads as a flat
## 16.7ms and hides how much headroom is left. See _perf_probe.gd for the same pattern.
##
## Spusteni (NE --headless, potrebuje realny renderer):
##   godot --path <proj> --main-scene res://scenes/_perf_horde.tscn

var completed := false
var _game = null

const N_STEPS := [50, 100, 200, 500, 1000]
const DRUHY := ["notification", "autoplay", "doomscroll", "phantom_buzz",
	"clickbait", "adult_content", "group_chat", "energy_drink", "jackpot"]

func _ready() -> void:
	call_deferred("_run")

## Average and worst frame over `frames` frames. The worst frame is what a player
## actually feels as a stutter — an average alone hides it.
func _mer(frames: int) -> Dictionary:
	var wall: Array[float] = []
	for i in range(frames):
		var t0 := Time.get_ticks_usec()
		await get_tree().process_frame
		wall.append((Time.get_ticks_usec() - t0) / 1000.0)
	wall.sort()
	var sw := 0.0
	for c in wall:
		sw += c
	return {"avg": sw / wall.size(), "max": wall[wall.size() - 1]}

func _run() -> void:
	var wd := Timer.new()
	wd.wait_time = 180.0
	wd.one_shot = true
	add_child(wd)
	wd.timeout.connect(func():
		if not completed:
			print("FAILED: bench nedobehl")
			get_tree().quit(1))
	wd.start()

	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0

	# Iso level 99: the default level's objective sits outside the current 24x24 grid
	# (a leftover from a prior grid migration, see PROGRESS.md T0) and breaks
	# pathfinding entirely. Level 99's objective is in-bounds.
	for i in range(Data.get_level_count()):
		if Data.get_level(i).id == 99:
			GameState.current_level_index = i
			break

	_game = load("res://scenes/Game.tscn").instantiate()
	add_child(_game)
	await get_tree().process_frame
	GameState.max_focus = 999999
	GameState.focus = 999999
	GameState.dopamine = 100000
	await get_tree().process_frame

	var spawn_pool: Array = _game.spawn_zone_cells[0]
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260829

	var rows: Array[String] = []
	var spawned := 0
	for n in N_STEPS:
		var t0 := Time.get_ticks_usec()
		while spawned < n:
			_game.spawn_distraction(StringName(DRUHY[spawned % DRUHY.size()]),
				spawn_pool[rng.randi() % spawn_pool.size()])
			spawned += 1
		var t_spawn := (Time.get_ticks_usec() - t0) / 1000.0
		await get_tree().process_frame
		var m: Dictionary = await _mer(120)
		var fps: float = 1000.0 / maxf(m["avg"], 0.001)
		print("N=%4d  avg %6.2f ms (%5.1f FPS)  worst %6.2f ms  (spawn+path took %.1f ms)"
			% [n, m["avg"], fps, m["max"], t_spawn])
		rows.append("| %d | %.2f | %.1f | %.2f |" % [n, m["avg"], fps, m["max"]])

	var out := "# Horde performance (T11)\n\n"
	out += "Frametime scaling with N live distractions all walking the path, on level 99 "
	out += "(Isometric Vertical Slice), vsync off. Cumulative: each N tops up the population "
	out += "from the previous step rather than resetting the level. Measured, not optimized "
	out += "— see docs/refactor/MIGRATION.MD T11.\n\n"
	out += "Machine: this dev machine, single run, %s.\n\n" % Time.get_datetime_string_from_system()
	out += "| N | avg frame (ms) | avg FPS | worst frame (ms) |\n"
	out += "|---|---|---|---|\n"
	for r in rows:
		out += r + "\n"

	var f := FileAccess.open("res://docs/PERF.md", FileAccess.WRITE)
	f.store_string(out)
	f.close()

	completed = true
	print("\nHOTOVO — docs/PERF.md written")
	get_tree().quit(0)
