extends Node
## Characterization harness for GridProjection.MODE_SQUARE (docs/refactor/MIGRATION.MD
## T5's "Nová čtvercová projekce dostane vlastní fixtures" — CLAUDE.md, Testy jsou
## smlouva). Pure math, no Game instantiation needed: this only exercises
## GridProjection itself, temporarily switched into square mode and switched back to
## MODE_ISO (the live default) when done, since active_mode is a shared static and
## this project's other fixtures assume iso unless they say otherwise.
##
## Deliberately does NOT test layer_origin()/diamond_corners()/cell_diamond() — those
## stay iso-only on purpose (see grid_projection.gd's own doc comments); there is no
## square equivalent to characterize yet.

var completed := false
var fails := 0

func _ready() -> void:
	var wd := Timer.new()
	wd.wait_time = 30.0
	wd.one_shot = true
	add_child(wd)
	wd.timeout.connect(func():
		if not completed:
			print("FAILED: watchdog fired")
			GridProjection.set_mode(GridProjection.MODE_ISO)
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
	GridProjection.set_mode(GridProjection.MODE_SQUARE)

	_check("set_mode flips active_mode", GridProjection.active_mode == GridProjection.MODE_SQUARE)
	_check("set_mode sets GROUND_Y_SCALE to 1.0 (no squash in top-down)",
		is_equal_approx(GridProjection.GROUND_Y_SCALE, 1.0),
		"%.2f" % GridProjection.GROUND_Y_SCALE)

	print("\n-- cell_center / world_to_cell round-trip over every cell --")
	var g = Data.GRID
	var cols: int = int(g.cols)
	var rows: int = int(g.rows)
	var round_trip_fails := 0
	for y in range(rows):
		for x in range(cols):
			var cell := Vector2i(x, y)
			var back := GridProjection.world_to_cell(GridProjection.cell_center(cell))
			if back != cell:
				round_trip_fails += 1
	_check("every cell round-trips through cell_center()->world_to_cell() (%dx%d grid)"
		% [cols, rows], round_trip_fails == 0, "%d mismatches" % round_trip_fails)

	print("\n-- cell_center is a plain axis-aligned grid, not a diamond --")
	var t: float = float(g.get("tile", 32))
	var c00 := GridProjection.cell_center(Vector2i(0, 0))
	var c10 := GridProjection.cell_center(Vector2i(1, 0))
	var c01 := GridProjection.cell_center(Vector2i(0, 1))
	_check("moving +1 in grid X moves screen X by exactly one tile, Y by 0",
		is_equal_approx(c10.x - c00.x, t) and is_equal_approx(c10.y - c00.y, 0.0),
		"delta=%s" % (c10 - c00))
	_check("moving +1 in grid Y moves screen Y by exactly one tile, X by 0",
		is_equal_approx(c01.y - c00.y, t) and is_equal_approx(c01.x - c00.x, 0.0),
		"delta=%s" % (c01 - c00))

	print("\n-- in_bounds is unaffected by projection mode --")
	_check("origin cell is in bounds", GridProjection.in_bounds(Vector2i(0, 0)))
	_check("last cell is in bounds", GridProjection.in_bounds(Vector2i(cols - 1, rows - 1)))
	_check("one past the edge is not", not GridProjection.in_bounds(Vector2i(cols, 0)))
	_check("negative is not", not GridProjection.in_bounds(Vector2i(-1, 0)))

	print("\n-- to_ground / to_screen are the identity when there is no squash --")
	var v := Vector2(37.0, -19.0)
	_check("to_ground(v) == v", GridProjection.to_ground(v).is_equal_approx(v), str(GridProjection.to_ground(v)))
	_check("to_screen(v) == v", GridProjection.to_screen(v).is_equal_approx(v), str(GridProjection.to_screen(v)))
	_check("ground_distance == plain Euclidean distance",
		is_equal_approx(GridProjection.ground_distance(Vector2.ZERO, Vector2(3.0, 4.0)), 5.0),
		"%.2f" % GridProjection.ground_distance(Vector2.ZERO, Vector2(3.0, 4.0)))

	print("\n-- ground_dir_to_screen is a plain unit vector, no squash --")
	var dir := GridProjection.ground_dir_to_screen(0.0)
	_check("angle 0 -> (1, 0) exactly", dir.is_equal_approx(Vector2(1.0, 0.0)), str(dir))
	var dir90 := GridProjection.ground_dir_to_screen(PI / 2.0)
	_check("angle 90deg -> (0, 1), not (0, 0.5) like iso would give",
		is_equal_approx(dir90.y, 1.0), "%.3f" % dir90.y)

	print("\n-- screen_dir_to_grid_axes is the identity: grid axes ARE screen axes --")
	var axes := GridProjection.screen_dir_to_grid_axes(Vector2(5.0, -3.0))
	_check("no tilt, no cross-mixing", axes.is_equal_approx(Vector2(5.0, -3.0)), str(axes))

	print("\n-- board_bounds is a plain rect, not an iso diamond AABB --")
	var bounds := GridProjection.board_bounds()
	var expected_origin := Vector2(float(g.origin_x), float(g.origin_y))
	_check("origin corner matches Data.GRID.origin exactly (no diamond overhang)",
		bounds.position.is_equal_approx(expected_origin), str(bounds.position))
	_check("size is exactly cols*tile x rows*tile",
		is_equal_approx(bounds.size.x, float(cols) * t) and is_equal_approx(bounds.size.y, float(rows) * t),
		str(bounds.size))

	GridProjection.set_mode(GridProjection.MODE_ISO)
	_check("restored to MODE_ISO for every other fixture", GridProjection.active_mode == GridProjection.MODE_ISO)
	_check("GROUND_Y_SCALE restored to 2.0", is_equal_approx(GridProjection.GROUND_Y_SCALE, 2.0))

	completed = true
	print("\n%s (%d failures)" % ["PASSED" if fails == 0 else "FAILED", fails])
	get_tree().quit(1 if fails > 0 else 0)
