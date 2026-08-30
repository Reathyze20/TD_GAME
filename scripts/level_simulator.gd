class_name LevelSimulator
extends Node
## S2 (docs/refactor/SYSTEMS.MD): headless, scripted driver that plays a level
## according to a SimStrategy with no render and no human input, and returns the
## result: survived/died, remaining Focus, final Tolerance, total Dopamine. Seeded via
## the global RNG stream (see run()), so the SAME seed run twice gives a bit-identical
## result — provided the process itself is launched with `--fixed-fps 60` (see
## docs/DEBT.md / PROGRESS.md's 2026-08-29 S2 entry for why: Godot's own per-frame
## delta, AND every create_tween() this game uses for intervention effects, only
## become byte-identical across runs under that flag — Engine.time_scale is not a
## substitute, since it scales a still-really-measured delta rather than replacing it
## with an exact synthetic constant).
##
## Drives the SAME functions the UI calls (GameState.select_habit/Game._build_on,
## Habit.facing_angle/set_arc_angle, Game._on_start_wave_pressed, Game.do_quick_hit,
## Game._on_card_picked/_on_draft_skip) rather than reimplementing any game logic —
## the project's own existing _test_*.gd harnesses already establish this as the
## precedented approach (GDScript has no real access control, so calling a
## leading-underscore method on an instantiated Game node is not a hack, just the only
## way to drive the game without a real UI).
##
## Survives Game._game_over()/_level_complete()'s otherwise-destructive
## change_scene_to_file() (which frees the CURRENT SCENE's entire subtree, including
## whatever this simulator's own root node is a child of) by disconnecting
## Game._on_bus_game_over from SignalBus.game_over immediately after the level is
## ready and connecting its own handler instead — the same pattern _test_phase3.gd and
## _test_phase4.gd already use. This also means GameState.last_run_stats is NEVER
## populated in this mode (it is only written inside the bypassed function bodies);
## every result field is read directly from live GameState instead.

## Generous safety cap, not a real budget: 10 simulated minutes at 60fps. A level that
## has neither won nor lost by then is treated as a stalled decision script (e.g. a
## strategy that never calls start_wave()), not a crash.
const DEFAULT_MAX_FRAMES := 36000

var game: Game = null
var result: Dictionary = {}

var _strategy: SimStrategy = null
var _done := false
var _frame := 0

## Plays `level_id` to completion (or until `max_frames` is exceeded) using
## `strategy`, seeding the shared global RNG stream from `run_seed` first so every
## unseeded randf()/randi() draw anywhere in the game — including
## GameState.reset_for_level()'s own `run_seed = randi()` line — becomes reproducible
## from this one call. Returns the result dictionary (also left on `self.result`):
## {victory, timed_out, frame, focus, max_focus, tolerance, dopamine, kills, wave}.
##
## `speed_index` drives the SAME mechanism the interactive game's speed button uses
## (Game.set_speed_index() / Game.SPEED_STEPS — Q1, docs/refactor/PATHFINDING.MD), not a
## parallel implementation: this is what lets _test_timecontrol.gd prove the REAL shipped
## speed control is deterministic rather than a stand-in that merely happens to be.
## Defaults to Game.DEFAULT_SPEED_INDEX (1.0×, its own pre-Q1 default) so every existing
## caller that never mentions speed keeps behaving exactly as before.
func run(level_id: int, run_seed: int, strategy: SimStrategy,
		max_frames: int = DEFAULT_MAX_FRAMES, speed_index: int = -1) -> Dictionary:
	seed(run_seed)
	_strategy = strategy
	_done = false
	_frame = 0
	result = {}

	var level_index := -1
	for i in range(Data.get_level_count()):
		if Data.get_level(i).id == level_id:
			level_index = i
			break
	if level_index < 0:
		push_error("LevelSimulator: level id %d not found" % level_id)
		return {}

	GameState.current_level_index = level_index
	game = load("res://scenes/Game.tscn").instantiate()
	add_child(game)
	# Two frames, matching _test_phase4.gd's own warm-up: the first lets Game._ready()
	# (build spots, wave manager, HUD wiring, @onready refs) actually run; harnesses
	# that only await once are relying on that first _ready() having already happened
	# by coincidence of call order, which this driver does not want to depend on.
	await get_tree().process_frame
	await get_tree().process_frame

	SignalBus.game_over.disconnect(game._on_bus_game_over)
	SignalBus.game_over.connect(_on_game_over)
	GameState.designer_mode = false
	# -1 (the param default) means "leave Game's own default alone" rather than baking
	# Game.DEFAULT_SPEED_INDEX in here too, so the two never drift apart.
	if speed_index >= 0:
		game.set_speed_index(speed_index)

	while not _done and _frame < max_frames:
		await get_tree().process_frame
		_frame += 1
		_step()

	if not _done:
		result = _snapshot(false, true, _frame)

	# Without this, a second run() call on a DIFFERENT LevelSimulator instance (the
	# normal way to sweep many levels/strategies — see S3) would still fire this run's
	# _on_game_over, against a `game` this run already freed below, the moment ANY
	# later game instance emits game_over on the same shared SignalBus.
	SignalBus.game_over.disconnect(_on_game_over)
	game.queue_free()
	return result

func is_build_phase() -> bool:
	return game.between_waves

## Empty, currently-Routine-lit cells a build() call would actually succeed on right
## now (same gate the UI's green/red placement tint uses) — sorted top-to-bottom,
## left-to-right so a strategy that builds at all of them does so in a stable,
## reproducible order rather than whatever order Dictionary.keys() happens to return.
func buildable_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for cell: Vector2i in game.build_spots:
		var spot: BuildSpot = game.build_spots[cell]
		if spot.state == BuildSpot.State.EMPTY and game._can_build(cell):
			cells.append(cell)
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y < b.y if a.y != b.y else a.x < b.x)
	return cells

func is_draft_pending() -> bool:
	return is_instance_valid(game._draft_overlay)

func draft_options() -> Array[CardData]:
	return game._draft_options

## Snaps `cell` to the build block the UI itself snaps to (Data.build_block) and
## builds `type_key` there via the same two-call sequence the UI's own click handler
## uses. A fresh attack-habit build auto-enters aiming mode at the type's default
## angle/width (see aim()) — safe to call speculatively; an unaffordable or
## already-occupied cell just no-ops, matching a real click doing nothing.
func build(cell: Vector2i, type_key: String) -> BaseHabit:
	var snapped := Data.build_block(cell)
	GameState.select_habit(type_key)
	game._build_on(snapped)
	if not game.build_spots.has(snapped):
		return null
	return game.build_spots[snapped].current_habit

## Sets `habit`'s facing (degrees) and cone width (degrees) and immediately commits
## via Game._end_aiming(). The commit call matters: _select_habit, _select_intervention,
## Game._on_start_wave_pressed and Game._show_draft_screen all call _cancel_aiming()
## first, which SILENTLY ROLLS BACK an un-ended aim to its pre-aim angle/width — so an
## aim left uncommitted before the strategy's next top-level action would simply
## vanish, the same trap a real player forgetting to left-click to lock would fall into.
func aim(habit: Habit, facing_deg: float, arc_deg: float) -> void:
	if habit == null or not is_instance_valid(habit):
		return
	habit.facing_angle = deg_to_rad(facing_deg)
	habit.set_arc_angle(arc_deg)
	game._end_aiming()

## Game.do_quick_hit() is fully self-guarded (level-data availability, a real
## cooldown, game_ended) — safe to call every tick and let it no-op when unavailable,
## exactly like the button being disabled would for a real player.
func quick_hit() -> void:
	game.do_quick_hit()

func start_wave() -> void:
	game._on_start_wave_pressed()

func pick_card(card: CardData) -> void:
	game._on_card_picked(card)

func skip_draft() -> void:
	game._on_draft_skip()

func _on_game_over(victory: bool) -> void:
	game.game_ended = true
	result = _snapshot(victory, false, _frame)
	_done = true

func _snapshot(victory: bool, timed_out: bool, frame: int) -> Dictionary:
	return {
		"victory": victory,
		"timed_out": timed_out,
		"frame": frame,
		"focus": GameState.focus,
		"max_focus": GameState.max_focus,
		"tolerance": GameState.tolerance,
		"dopamine": GameState.dopamine,
		"kills": GameState.kills,
		"wave": game.wave_index,
	}

func _step() -> void:
	if _done:
		return
	if is_draft_pending():
		var choice := _strategy.on_draft(self, draft_options())
		if choice != null and draft_options().has(choice):
			pick_card(choice)
		else:
			skip_draft()
		return
	if game.between_waves:
		_strategy.on_build_tick(self)
	else:
		_strategy.on_wave_tick(self)
