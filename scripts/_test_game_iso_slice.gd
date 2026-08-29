extends SceneTree

const DataScript = preload("res://scripts/data.gd")
const GameStateScript = preload("res://scripts/game_state.gd")
const MetaProgressionScript = preload("res://scripts/meta_progression.gd")
const ModifierManagerScript = preload("res://scripts/modifier_manager.gd")
const SignalBusScript = preload("res://scripts/signal_bus.gd")

func _init() -> void:
	print("--- Starting Isometric Slice Integration Test ---")
	
	# Instantiate autoload singletons if not in tree
	var data_node = DataScript.new()
	data_node.name = "Data"
	root.add_child(data_node)
	data_node._ready()
	
	var game_state_node = GameStateScript.new()
	game_state_node.name = "GameState"
	root.add_child(game_state_node)
	
	var meta_prog_node = MetaProgressionScript.new()
	meta_prog_node.name = "MetaProgression"
	root.add_child(meta_prog_node)
	meta_prog_node._ready()
	
	var mod_mgr_node = ModifierManagerScript.new()
	mod_mgr_node.name = "ModifierManager"
	root.add_child(mod_mgr_node)
	
	var signal_bus_node = SignalBusScript.new()
	signal_bus_node.name = "SignalBus"
	root.add_child(signal_bus_node)
	
	# 1. Set current level to level_iso (find index in Data)
	var iso_idx := -1
	for i in range(data_node.get_level_count()):
		var lvl := data_node.get_level(i)
		if lvl.id == 99:
			iso_idx = i
			break
	
	if iso_idx < 0:
		push_error("FAIL: level_iso (id 99) not found in Data!")
		quit(1)
		return
	
	print("Found level_iso at index %d" % iso_idx)
	game_state_node.current_level_index = iso_idx
	
	# 2. Instantiate Game scene
	var game_scene: PackedScene = load("res://scenes/Game.tscn")
	var game: Game = game_scene.instantiate()
	root.add_child(game)
	
	print("Game instance added to scene tree.")
	print("Level ID: %d, Path cells: %d, High ground: %d, Build spots: %d" % [
		game.level.id, game.level.path_cells.size(), game.high_ground.size(), game.build_spots.size()
	])
	
	assert(game.build_spots.size() > 0, "Build spots must not be empty!")
	
	# 3. Test building towers
	var spots: Array = game.build_spots.keys()
	spots.sort_custom(func(a, b): return a.x < b.x)
	
	var spot1: Vector2i = spots[0]
	var spot2: Vector2i = spots[1]
	var spot3: Vector2i = spots[2]
	
	print("Testing placement on spots: %s, %s, %s" % [spot1, spot2, spot3])
	
	game_state_node.dopamine = 1000
	game_state_node.bandwidth_used = 0
	
	# Place focus_pillar
	game_state_node.selected_habit = "focus_pillar"
	game._hover_cell = spot1
	assert(game._can_build(spot1), "Should be able to build on spot1")
	var t1 := game._build_habit(spot1, "focus_pillar")
	assert(t1 != null, "Tower 1 (focus_pillar) must be created")
	print("Built focus_pillar at %s (world pos: %s)" % [spot1, t1.position])
	
	# Place mindfulness
	game_state_node.selected_habit = "mindfulness"
	game._hover_cell = spot2
	assert(game._can_build(spot2), "Should be able to build on spot2")
	var t2 := game._build_habit(spot2, "mindfulness")
	assert(t2 != null, "Tower 2 (mindfulness) must be created")
	print("Built mindfulness at %s (world pos: %s)" % [spot2, t2.position])
	
	# Place focus_timer
	game_state_node.selected_habit = "focus_timer"
	game._hover_cell = spot3
	assert(game._can_build(spot3), "Should be able to build on spot3")
	var t3 := game._build_habit(spot3, "focus_timer")
	assert(t3 != null, "Tower 3 (focus_timer) must be created")
	print("Built focus_timer at %s (world pos: %s)" % [spot3, t3.position])
	
	# 4. Start wave & spawn enemies
	game.started = true
	game.between_waves = false
	game.wave_index = 0
	
	print("Spawning energy_drink and notification...")
	var spawn_pt: Vector2i = game.spawn_zone_cells[0][0]
	var e1: Distraction = game._spawn_distraction("energy_drink", spawn_pt)
	var e2: Distraction = game._spawn_distraction("notification", spawn_pt)
	
	assert(e1 != null, "Enemy 1 (energy_drink) must spawn")
	assert(e2 != null, "Enemy 2 (notification) must spawn")
	print("Spawned e1 at %s, e2 at %s" % [e1.position, e2.position])
	
	# 5. Simulate 60 physics frames (1.0 sec)
	for f in range(60):
		game._physics_process(1.0 / 60.0)
		if f % 20 == 0:
			print("Frame %d: e1 pos=%s facing=%s hp=(%d,%d)" % [
				f, e1.position, e1.facing, e1.willpower, e1.awareness
			])
	
	print("Simulation successful! e1 final pos: %s, facing: %s" % [e1.position, e1.facing])
	print("ALL ISOMETRIC SLICE TESTS PASSED!")
	quit(0)
