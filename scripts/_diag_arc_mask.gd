extends Node
## TEMPORARY diagnostic for _test_fog_bandwidth's "arc width does nothing" finding
## (docs/KNOWN_BROKEN.md) -- DELETE after use (with its .gd.uid and .tscn).
##
## Hypothesis under test: _building_sight_lights() (game.gd:1914-1944) gives every built
## habit an always-on TOWER_LAMP_RADIUS=28px circle regardless of arc, and the core's own
## light (_update_fog, game.gd:1972) unconditionally lights a CORE_ROUTINE_RADIUS=165px
## circle around itself BEFORE any habit's light is applied -- and since a habit can only
## be built inside that same 165px Routine radius, its wedge (reach=180 for focus_timer,
## centred on the HABIT, not the core) may mostly or entirely overlap cells the core
## already lit, via _mark_lit's own early-exit (game.gd:2016) skipping any cell that is
## already marked lit before that light's own radius/wedge test ever runs. If true, arc
## width changing _lit_cells.size() by zero is a masking interaction between two light
## sources, not a broken wedge computation -- and entirely a CPU-geometry question, no
## renderer involved anywhere in this chain.
##
## Run: godot --headless --path . --main-scene res://scenes/_diag_arc_mask.tscn

var completed := false


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


## Same selection as _test_fog_bandwidth.gd's _find_spot -- first EMPTY spot inside (or
## outside) the current Routine.
func _find_spot(game: Game, inside: bool) -> Vector2i:
	for cell: Vector2i in game.build_spots:
		var bs: BuildSpot = game.build_spots[cell]
		if bs.state != BuildSpot.State.EMPTY:
			continue
		var in_r: bool = game.is_position_in_routine(game.cell_center(cell), game._routine_sources)
		if in_r == inside:
			return cell
	return Vector2i(-999, -999)


func _run() -> void:
	var game: Game = load("res://scenes/Game.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	GameState.max_focus = 999999
	GameState.focus = 999999
	await get_tree().process_frame

	var in_cell := _find_spot(game, true)
	if in_cell.x <= -999:
		print("no empty in-Routine spot found -- cannot test")
		completed = true
		get_tree().quit(1)
		return

	var core_pos: Vector2 = game.objective_pos + game.position
	GameState.dopamine = 10000
	GameState.select_habit("focus_timer")
	game._build_on(in_cell)
	game._end_aiming()
	var hab: Habit = game.build_spots[in_cell].current_habit
	GameState.select_habit(null)
	if hab == null:
		print("habit failed to build -- cannot test")
		completed = true
		get_tree().quit(1)
		return

	var dist_to_core: float = hab.global_position.distance_to(core_pos)
	var reach: float = hab.current_attack_range * game.WEDGE_LIGHT_SCALE
	print("habit pos=%s  core pos=%s  dist_to_core=%.1f" % [hab.global_position, core_pos, dist_to_core])
	print("TOWER_LAMP_RADIUS=%.1f  CORE_ROUTINE_RADIUS=%.1f" % [game.TOWER_LAMP_RADIUS, game.CORE_ROUTINE_RADIUS])
	print("current_attack_range=%.1f  WEDGE_LIGHT_SCALE=%.1f  reach=%.1f  (wedge added only if reach > TOWER_LAMP_RADIUS: %s)" \
		% [hab.current_attack_range, game.WEDGE_LIGHT_SCALE, reach, reach > game.TOWER_LAMP_RADIUS])
	print("farthest the wedge can reach from the core (dist_to_core + reach) = %.1f  vs CORE_ROUTINE_RADIUS=%.1f  -> %.1f px past the core's own circle" \
		% [dist_to_core + reach, game.CORE_ROUTINE_RADIUS, dist_to_core + reach - game.CORE_ROUTINE_RADIUS])

	# facing_angle=0.0 (east) points STRAIGHT AT the core when the habit sits west of it,
	# as it does on this level/spot -- that would make the whole wedge sweep land inside
	# the core's own already-lit circle regardless of arc width, which is not the same
	# claim as "the wedge computation is broken". Test both: 0.0 (matches
	# _test_fog_bandwidth.gd exactly) and PI (facing away from the core) side by side.
	var dir_to_core: Vector2 = (core_pos - hab.global_position).normalized()
	var facing_toward_core: float = dir_to_core.angle()
	print("angle from habit to core = %.1f deg (facing_angle=0.0 means facing %.1f deg away from that)" \
		% [rad_to_deg(facing_toward_core), rad_to_deg(facing_toward_core)])

	for facing_label in [["toward core (0.0, matches _test_fog_bandwidth.gd)", 0.0],
			["away from core (PI)", PI]]:
		hab.facing_angle = facing_label[1]

		hab.set_arc_angle(ArcProfile.ARC_MIN)
		game._update_fog(0.0)
		var narrow_cells: Dictionary = game._lit_cells.duplicate()

		hab.set_arc_angle(ArcProfile.ARC_MAX)
		game._update_fog(0.0)
		var wide_cells: Dictionary = game._lit_cells.duplicate()

		var diff := 0
		for c in wide_cells:
			if not narrow_cells.has(c):
				diff += 1
		for c in narrow_cells:
			if not wide_cells.has(c):
				diff += 1
		print("facing %s: narrow=%d wide=%d cells differing=%d" \
			% [facing_label[0], narrow_cells.size(), wide_cells.size(), diff])

	hab.facing_angle = 0.0
	hab.set_arc_angle(ArcProfile.ARC_MIN)
	game._update_fog(0.0)
	var narrow_cells: Dictionary = game._lit_cells.duplicate()

	hab.set_arc_angle(ArcProfile.ARC_MAX)
	game._update_fog(0.0)
	var wide_cells: Dictionary = game._lit_cells.duplicate()

	var only_in_wide: Array = []
	for c in wide_cells:
		if not narrow_cells.has(c):
			only_in_wide.append(c)
	var only_in_narrow: Array = []
	for c in narrow_cells:
		if not wide_cells.has(c):
			only_in_narrow.append(c)

	print("narrow (%d deg): %d cells  |  wide (%d deg): %d cells" \
		% [ArcProfile.ARC_MIN, narrow_cells.size(), ArcProfile.ARC_MAX, wide_cells.size()])
	print("cells only in wide: %d  |  cells only in narrow: %d" % [only_in_wide.size(), only_in_narrow.size()])
	for c in only_in_wide:
		var d: float = game.cell_center(c).distance_to(core_pos)
		print("  wide-only cell %s  dist_to_core=%.1f" % [c, d])
	for c in only_in_narrow:
		var d: float = game.cell_center(c).distance_to(core_pos)
		print("  narrow-only cell %s  dist_to_core=%.1f" % [c, d])

	game._do_sell(in_cell, 1)

	completed = true
	print("\nDONE")
	get_tree().quit(0)
