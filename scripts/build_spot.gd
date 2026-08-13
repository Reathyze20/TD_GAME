class_name BuildSpot
extends Node
# Tracks the state of one high-ground build cell.
# Created in code by Game._build_field() — no .tscn needed for the prototype.
# Manages the Habit instance on its cell: build, upgrade, sell.

enum State { EMPTY, BUILT }

var state := State.EMPTY
var current_habit: BaseHabit = null
var grid_cell: Vector2i
var game  # Game node reference

func setup(_game, cell: Vector2i) -> void:
	game = _game
	grid_cell = cell

# ---- Public API ----

func build_habit(type_key: String, facing_angle: float = 0.0, arc_angle: float = 60.0) -> BaseHabit:
	assert(state == State.EMPTY, "BuildSpot already occupied")
	var def := Data.get_habit(type_key)
	var h: BaseHabit
	if def.is_blocker:
		h = Barracks.new()
	else:
		h = Habit.new()
	game.entities.add_child(h)
	h.setup(game, type_key, grid_cell.x, grid_cell.y, facing_angle, arc_angle)
	current_habit = h
	state = State.BUILT
	return h

func upgrade_habit(new_type_key: String) -> BaseHabit:
	assert(state == State.BUILT and current_habit != null, "Nothing to upgrade")
	var old_facing: float = current_habit.facing_angle if current_habit is Habit else 0.0
	var old_arc: float = current_habit.arc_angle if current_habit is Habit else 60.0
	# The upgrade REPLACES the node, so anything the old tower accumulated has to be
	# carried across by hand or it silently resets on every upgrade.
	var old_kills: int = current_habit.kills
	var old_damage: int = current_habit.damage_dealt
	var old_mode: int = current_habit.target_mode if current_habit is Habit else 0

	current_habit.queue_free()
	current_habit = null

	var def := Data.get_habit(new_type_key)
	var h: BaseHabit
	if def.is_blocker:
		h = Barracks.new()
	else:
		h = Habit.new()
	game.entities.add_child(h)
	h.setup(game, new_type_key, grid_cell.x, grid_cell.y, old_facing, old_arc)
	h.kills = old_kills
	h.damage_dealt = old_damage
	if h is Habit:
		h.target_mode = old_mode as Habit.TargetMode
	current_habit = h
	# state stays BUILT
	return h

## Returns the Dopamine refund amount (50% of current tier build cost).
func sell_habit() -> int:
	assert(state == State.BUILT and current_habit != null, "Nothing to sell")
	var refund := int(Data.get_habit(current_habit.type_key).build_cost * 0.5)
	current_habit.queue_free()
	current_habit = null
	state = State.EMPTY
	return refund

func get_current_type_key() -> String:
	if current_habit == null:
		return ""
	return current_habit.type_key
