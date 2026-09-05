extends Node
## Regression coverage for Distraction._tick_fog_speed() (enemy.gd): standing in Brain
## Fog's darkness makes a distraction faster, standing in the Routine's light does not,
## the change ramps rather than snaps, and it is a hard no-op with fog disabled. See
## docs/core/14_brain_fog_and_bandwidth.md and CLAUDE.md's "Testy jsou smlouva".
##
## Verification pattern (docs/REFACTOR_PLAN.md): completed sentinel + Timer watchdog,
## run via --main-scene (never --script — autoloads are not registered there).

var completed := false
var fails := 0

func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("  ok   %s %s" % [label, detail])
	else:
		fails += 1
		print("  FAIL %s %s" % [label, detail])

func _ready() -> void:
	var wd := Timer.new()
	wd.wait_time = 90.0
	wd.one_shot = true
	add_child(wd)
	wd.timeout.connect(func():
		if not completed:
			print("FAILED: watchdog fired")
			get_tree().quit(1))
	wd.start()
	call_deferred("_run")

## The farthest-from-objective walkable, reachable, non-objective cell that is currently
## LIT, and the farthest one that is currently DARK — with no habits built yet, the core
## is the only light source, so this reduces to "just outside CORE_ROUTINE_RADIUS" and
## "the far side of the board". Farthest rather than first-found (which
## _test_fog_bandwidth.gd's raster scan uses) on purpose: it gives each test subject the
## most travel budget before it could wander into the OTHER lighting state and
## contaminate its own reading, and it never depends on `_lit_cells`' own block-quantised
## key shape the way a raw `_lit_cells.has(cell)` scan would.
func _pick_test_cells(game: Game) -> Dictionary:
	var best_lit := Vector2i(-999, -999)
	var best_dark := Vector2i(-999, -999)
	var best_lit_d := -1.0
	var best_dark_d := -1.0
	for y in range(Data.GRID.rows):
		for x in range(Data.GRID.cols):
			var c := Vector2i(x, y)
			if c == game.objective_cell or game.high_ground.has(c):
				continue
			if game.flow_field == null or not game.flow_field.has_cell(c):
				continue
			var d: float = game.cell_center(c).distance_to(game.objective_pos)
			if game.is_pos_visible(game.cell_center(c)):
				if d > best_lit_d:
					best_lit_d = d
					best_lit = c
			elif d > best_dark_d:
				best_dark_d = d
				best_dark = c
	return {"lit": best_lit, "dark": best_dark}

## Advances `d` for `ticks` fixed steps with NO `await` between them, so Game's own
## background _physics_process (live from the moment Game.tscn entered the tree) can
## never interleave uncontrolled movement into the measurement — the same precaution
## _test_telegraph.gd documents and relies on.
func _walk(d: Distraction, ticks: int) -> Array[float]:
	var steps: Array[float] = []
	for i in range(ticks):
		var before: Vector2 = d.position
		d._process(Game.FIXED_TICK_DT)
		steps.append(before.distance_to(d.position))
	return steps

func _sum(steps: Array[float]) -> float:
	var total := 0.0
	for s in steps:
		total += s
	return total

## Straight-line distance from `d`'s CURRENT position to the centre of its next
## waypoint — the maze walk's own `dist`, recomputed from outside rather than
## duplicated by guesswork. Arriving at a waypoint clamps that tick's displacement to
## whatever distance was left (enemy.gd: `if dist <= step: position = target`), which is
## a pre-existing property of the walk formula with nothing to do with fog speed — but
## it means a strict "distance over N ticks" check goes flaky the moment a measurement
## window happens to straddle an arrival. `_safe_ticks` below uses this to pick a window
## short enough that no arrival can occur inside it, so the formula checks can be exact.
func _dist_to_waypoint(game: Game, d: Distraction) -> float:
	var next_cell: Vector2i = d.current_cell + game.flow_field.direction(d.current_cell)
	var target: Vector2 = game.cell_center(next_cell) + d._scatter
	return d.position.distance_to(target)

## The largest tick count that provably cannot reach `d`'s next waypoint at the given
## per-tick step size, with a 15% margin. At least 1.
func _safe_ticks(game: Game, d: Distraction, step: float) -> int:
	return maxi(1, int(floor(_dist_to_waypoint(game, d) / step * 0.85)))

func _run() -> void:
	var game: Game = load("res://scenes/Game.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	# The _game_over trap (CLAUDE.md): with no towers built, an unchecked distraction
	# reaching the core would drop Focus to 0, _game_over() would change_scene_to_file(),
	# and that deletes this harness node and its own watchdog mid-test.
	GameState.max_focus = 999999
	GameState.focus = 999999
	# The fixture owns its own preconditions rather than trusting whichever level
	# GameState.current_level_index happens to default to (level 1 ships fog=false) —
	# see _test_fog_bandwidth.gd's own note on exactly this trap.
	game.fog_enabled = true
	game.routine_gates_enabled = true
	game._update_fog(0.0)

	var cells := _pick_test_cells(game)
	var lit_cell: Vector2i = cells["lit"]
	var dark_cell: Vector2i = cells["dark"]
	_check("found a usable lit test cell", lit_cell.x > -999)
	_check("found a usable dark test cell", dark_cell.x > -999)
	_check("the lit cell is actually lit", game.is_pos_visible(game.cell_center(lit_cell)))
	_check("the dark cell is actually dark", not game.is_pos_visible(game.cell_center(dark_cell)))

	# Ticks needed to fully clear the ramp, plus a small margin.
	var ramp_ticks: int = int(ceil(Distraction.FOG_SPEED_RAMP / Game.FIXED_TICK_DT)) + 2

	print("\n== steady-state speed: dark vs lit ==")
	var d_dark: Distraction = game.spawn_distraction("notification", dark_cell)
	var d_lit: Distraction = game.spawn_distraction("notification", lit_cell)
	_walk(d_dark, ramp_ticks)   # clear the ramp before measuring either one
	_walk(d_lit, ramp_ticks)
	# Short, geometry-derived windows (see _safe_ticks) so neither subject can arrive at
	# a waypoint mid-measurement — that clamps a tick's step short, which is a real
	# property of the walk formula but has nothing to do with fog speed.
	var lit_step: float = d_lit.current_speed * Game.FIXED_TICK_DT
	var dark_step: float = d_dark.current_speed * Distraction.FOG_SPEED_BOOST * Game.FIXED_TICK_DT
	var measure_ticks: int = mini(_safe_ticks(game, d_lit, lit_step), _safe_ticks(game, d_dark, dark_step))
	var dark_steps := _walk(d_dark, measure_ticks)
	var lit_steps := _walk(d_lit, measure_ticks)
	var dark_dist := _sum(dark_steps)
	var lit_dist := _sum(lit_steps)
	_check("dark subject stayed in the dark for the whole measurement",
		not game.is_pos_visible(d_dark.global_position))
	_check("lit subject stayed in the light for the whole measurement",
		game.is_pos_visible(d_lit.global_position))
	_check("dark distraction covers more ground than a lit one at steady state",
		dark_dist > lit_dist * 1.35, "dark=%.2f lit=%.2f ticks=%d" % [dark_dist, lit_dist, measure_ticks])
	var expected_lit: float = lit_step * float(measure_ticks)
	_check("lit-cell speed is unchanged from before this feature (current_speed * delta)",
		absf(lit_dist - expected_lit) < 0.01, "got=%.3f want=%.3f" % [lit_dist, expected_lit])
	var expected_dark: float = dark_step * float(measure_ticks)
	_check("dark-cell steady speed matches current_speed * FOG_SPEED_BOOST",
		absf(dark_dist - expected_dark) < 0.01, "got=%.3f want=%.3f" % [dark_dist, expected_dark])

	print("\n== ramp: speed rises rather than snaps ==")
	var d_ramp: Distraction = game.spawn_distraction("notification", dark_cell)
	var ramp_steps := _walk(d_ramp, ramp_ticks)
	_check("first tick in the dark is still close to lit speed, not the full boost",
		ramp_steps[0] < lit_step * 1.15, "first_step=%.3f lit_step=%.3f" % [ramp_steps[0], lit_step])
	_check("the last tick of the ramp window is faster than the first",
		ramp_steps[ramp_steps.size() - 1] > ramp_steps[0],
		"first=%.3f last=%.3f" % [ramp_steps[0], ramp_steps[ramp_steps.size() - 1]])

	print("\n== fog disabled: no-op everywhere ==")
	game.fog_enabled = false
	game._update_fog(0.0)
	var d_off: Distraction = game.spawn_distraction("notification", dark_cell)
	var off_step: float = d_off.current_speed * Game.FIXED_TICK_DT
	var off_ticks: int = _safe_ticks(game, d_off, off_step)
	var off_dist := _sum(_walk(d_off, off_ticks))
	var expected_off: float = off_step * float(off_ticks)
	_check("fog disabled: the dark cell still moves at 1.0x",
		absf(off_dist - expected_off) < 0.01, "got=%.3f want=%.3f" % [off_dist, expected_off])
	game.fog_enabled = true
	game._update_fog(0.0)

	print("\n== entered_light fires exactly once on the dark-to-light crossing ==")
	# Reuses `dark_cell` (the farthest dark point on the board, already proven dark and
	# reachable above) rather than hand-placing a point just outside the light: the fog
	# grid is quantised to 48px blocks (Data.BUILD_BLOCK) and is_pos_visible() reads the
	# block's own centre, so a point placed a small, fixed distance outside
	# CORE_ROUTINE_RADIUS can still read as lit — and a hand-placed offset risks landing
	# off the board entirely on a small level. The flow field guarantees this walker
	# eventually nears the objective, so it WILL cross into the core's light; the only
	# question this asks is whether it does so exactly once.
	var d_cross: Distraction = game.spawn_distraction("notification", dark_cell)
	# A one-element array as a mutable box: GDScript lambdas capture outer locals BY
	# VALUE, so `crossed += 1` inside a `func(): crossed += 1` closure would silently
	# mutate a private copy and never touch this variable — Array/Object captures carry
	# a reference instead, so mutating the BOXED int's slot does propagate.
	var crossed := [0]
	d_cross.entered_light.connect(func(_d): crossed[0] += 1)
	_check("crossing subject starts outside the light",
		not game.is_pos_visible(d_cross.global_position))
	var cap := 3000   # generous: comfortably covers a maze detour from the far corner
	var i := 0
	while i < cap and crossed[0] == 0 and not d_cross.dead:
		d_cross._process(Game.FIXED_TICK_DT)
		i += 1
	_check("entered_light fired exactly once walking from dark ground into the light",
		crossed[0] == 1, "fired %d times over %d ticks" % [crossed[0], i])

	completed = true
	print("\n%d FAIL(S)" % fails if fails > 0 else "\nALL PASS")
	get_tree().quit(1 if fails > 0 else 0)
