class_name BaseHabit
extends Node2D
## Base class for placed habits defending attention.
## Splits into Habit (ranged cone combat, or support like the Anchor) and Barracks (ally training).

var def: HabitData
var type_key: String
var col: int
var row: int
var _color: Color
var game  # reference to the Game node
## Whether this habit sits inside the player's Routine — the reach of the Focus core,
## extended by Anchors. A habit outside it stops working: a habit with nothing in your
## day to hang it on doesn't hold, however good the intention behind it was.
## (Was `is_powered`, a sci-fi power grid with no place in this game's theme.)
var in_routine: bool = true:
	set(value):
		if in_routine != value:
			in_routine = value
			queue_redraw()

# Setter-driven redraw: blockers return early from _process() and would otherwise never
# repaint when this is toggled, leaving the selected barracks' zone invisible.
var show_range_indicator := false:
	set(value):
		if show_range_indicator != value:
			show_range_indicator = value
			queue_redraw()

## Per-tower combat record, shown in the panel. Credited by Distraction when damage
## lands with this habit as `source` — clamped to health actually lost, so overkill
## doesn't inflate the number. BuildSpot.upgrade_habit() copies both to the new tier.
var kills := 0
var damage_dealt := 0

func record_damage(amount: int) -> void:
	damage_dealt += amount

func record_kill() -> void:
	kills += 1

func setup(_game, _type_key: String, _col: int, _row: int, initial_facing: float = 0.0, initial_arc: float = 60.0) -> void:
	game = _game
	type_key = _type_key
	def = Data.get_habit(type_key)
	col = _col
	row = _row
	_color = Color(def.color)

	var tile: int = Data.GRID.tile
	position = Vector2(col * tile + tile / 2.0 + Data.GRID.origin_x,
		row * tile + tile / 2.0 + Data.GRID.origin_y)

	_setup_specific(initial_facing, initial_arc)

## Virtual method for subclass-specific setup.
func _setup_specific(_initial_facing: float, _initial_arc: float) -> void:
	pass

# ------------------------------------------------------------------------------
# No-op stubs for UI panel (prevents need for type casting in game.gd)

func has_work_cycle() -> bool:
	return false

func is_resting() -> bool:
	return false

func take_break(_forced: bool = false) -> void:
	pass
