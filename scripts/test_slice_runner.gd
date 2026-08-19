extends Node

var _game: Game
var _e1: Distraction
var _e2: Distraction
var _frames := 0

func _ready() -> void:
	print("--- Running Test Slice Runner ---")
	
	# Find level_iso
	var iso_idx := -1
	for i in range(Data.get_level_count()):
		var lvl := Data.get_level(i)
		if lvl.id == 99:
			iso_idx = i
			break
	
	if iso_idx < 0:
		push_error("FAIL: level_iso not found!")
		get_tree().quit(1)
		return
	
	print("Found level_iso at index %d" % iso_idx)
	GameState.current_level_index = iso_idx
	
	var game_scene: PackedScene = load("res://scenes/Game.tscn")
	_game = game_scene.instantiate()
	add_child(_game)
	
	print("Game instance added to scene.")
	print("Level ID: %d, Path cells: %d, High ground: %d, Build spots: %d" % [
		_game.level.id, _game.level.path_cells.size(), _game.high_ground.size(), _game.build_spots.size()
	])
	
	# Test placing 3 towers
	var spots: Array = _game.build_spots.keys()
	spots.sort_custom(func(a, b): return a.x < b.x)
	
	var spot1: Vector2i = spots[0]
	var spot2: Vector2i = spots[1]
	var spot3: Vector2i = spots[2]
	
	GameState.dopamine = 1000
	GameState.bandwidth_used = 0
	
	# Place focus_pillar
	GameState.selected_habit = "focus_pillar"
	_game._hover_cell = spot1
	assert(_game._can_build(spot1), "spot1 should be buildable")
	_game._build_on(spot1)
	if _game.is_aiming:
		_game._end_aiming()
	var bs1: BuildSpot = _game.build_spots[spot1]
	assert(bs1.current_habit != null, "bs1 should have habit")
	print("Built focus_pillar at %s (world pos: %s)" % [spot1, bs1.current_habit.position])
	
	# Place mindfulness
	GameState.selected_habit = "mindfulness"
	_game._hover_cell = spot2
	assert(_game._can_build(spot2), "spot2 should be buildable")
	_game._build_on(spot2)
	if _game.is_aiming:
		_game._end_aiming()
	var bs2: BuildSpot = _game.build_spots[spot2]
	assert(bs2.current_habit != null, "bs2 should have habit")
	print("Built mindfulness at %s (world pos: %s)" % [spot2, bs2.current_habit.position])
	
	# Place focus_timer
	GameState.selected_habit = "focus_timer"
	_game._hover_cell = spot3
	assert(_game._can_build(spot3), "spot3 should be buildable")
	_game._build_on(spot3)
	if _game.is_aiming:
		_game._end_aiming()
	var bs3: BuildSpot = _game.build_spots[spot3]
	assert(bs3.current_habit != null, "bs3 should have habit")
	print("Built focus_timer at %s (world pos: %s)" % [spot3, bs3.current_habit.position])
	
	# Start wave & spawn enemies
	_game.started = true
	_game.between_waves = false
	_game.wave_index = 0
	
	var spawn_pt: Vector2i = _game.spawn_zone_cells[0][0]
	_e1 = _game.spawn_distraction("energy_drink", spawn_pt)
	_e2 = _game.spawn_distraction("notification", spawn_pt)
	
	assert(_e1 != null)
	assert(_e2 != null)
	print("Spawned e1 at %s, e2 at %s" % [_e1.position, _e2.position])

func _process(_dt: float) -> void:
	_frames += 1
	if _frames % 30 == 0 and _e1 != null and is_instance_valid(_e1):
		print("Frame %d: e1 pos=%s facing=%s hp=%d" % [
			_frames, _e1.position, _e1.facing, _e1.current_health
		])
	
	if _frames >= 120:
		print("Simulation completed at frame %d!" % _frames)
		if _e1 != null and is_instance_valid(_e1):
			print("e1 final pos: %s, facing: %s" % [_e1.position, _e1.facing])
		var vp := get_viewport()
		var img := vp.get_texture().get_image()
		if img != null:
			img.save_png("iso_slice_test.png")
			print("Saved iso_slice_test.png successfully.")
		print("ALL ISOMETRIC SLICE TESTS PASSED!")
		get_tree().quit(0)
