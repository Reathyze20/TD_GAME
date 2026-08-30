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
## Screen-space Y offset applied only in _draw() — see the block comment in setup().
## Zero everywhere except built-on-high_ground in the isometric renderer.
var _iso_lift := 0.0
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

	position = Data.cell_center(Vector2i(col, row))
	# PURELY VISUAL — a built habit standing on high_ground visually sits at ground
	# level, not on top of the WALL_HEIGHT-raised plateau it is built on (see
	# IsoWallSegment / IsoTopSegment in game.gd, and the matching lift the hover
	# placement preview already applies at game.gd:1126 for the SAME reason).
	#
	# The first attempt at this fix subtracted WALL_HEIGHT from `position` directly, and
	# was reverted: `position` is also this node's y-sort key (entities.y_sort_enabled)
	# AND the point every range/distance/targeting check measures from. Raising it
	# sorted the habit as if it were further back than the plateau it stands on (drew it
	# BEHIND its own wall top — invisible, strictly worse than sitting on the ground),
	# and would have silently shrunk every combat range by 48px against enemies that
	# stay at ground level and share none of the offset.
	#
	# So the lift lives here instead: a value the DRAW methods (Habit._draw(),
	# Barracks._draw()) apply as a canvas transform, exactly the split IsoTopSegment
	# already uses — node position stays at ground level for sorting and gameplay math,
	# the raised look is only ever a transform around the draw calls.
	if game != null and game.high_ground.has(Vector2i(col, row)):
		_iso_lift = game.WALL_HEIGHT

	_setup_specific(initial_facing, initial_arc)

	# Driven by Game's fixed-tick accumulator from here on, not Godot's automatic
	# per-frame call (Q1, docs/refactor/PATHFINDING.MD) — see tower.gd/barracks.gd's own
	# _process() header comments. Unlike a Distraction a habit never lingers with a
	# death animation after removal, so this is a one-way flip: nothing re-enables it.
	set_process(false)

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
