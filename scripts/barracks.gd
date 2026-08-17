class_name Barracks
extends BaseHabit
## The Nutrition Guild (data name: accountability line). Fields a RECIPE of three
## defender slots instead of firing: each slot names a DefenderData type, the guild
## keeps exactly one live unit per slot, and a slot whose unit falls respawns it after
## `def.ally_spawn_cooldown` seconds — as whatever type the slot names AT THAT MOMENT.
## That last clause is the whole slot design: changing a slot mid-fight never executes
## the veteran on the field, it re-provisions the position when it next opens.
##
## The rally point is the guild's one aiming decision. Units form up around it, leash
## to it (guard_radius measures from the rally, not the tower), and re-form when the
## player moves it — combat re-aims the same way the cone habits re-aim their wedge.

var owned_allies: Array = []                 # live DefenderUnits, all slots
var slots: Array[StringName] = []            # recipe: slot index -> DefenderData id
var _slot_units: Array = []                  # slot index -> DefenderUnit or null
var _slot_timers: Array[float] = []          # slot index -> respawn countdown (<=0 idle)

var rally_point := Vector2.ZERO

const _FORMATION_OFFSETS := [Vector2(0, -4), Vector2(-16, 12), Vector2(16, 12)]

## Body sprite, same file scheme as tower.gd heads (head_<type_key>.png + _frame_N) with
## the tier-2 fallback. The barracks used to render as a bare 3px rally dot — the only
## habit with no body at all.
var _base_tex: Texture2D
var _body_tex: Texture2D
var _body_frames: Array[Texture2D] = []
var _anim_t := 0.0
const BODY_FPS := 8.0

func _setup_specific(_initial_facing: float, _initial_arc: float) -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if FileAccess.file_exists("res://assets/towers/tower_base.png"):
		_base_tex = load("res://assets/towers/tower_base.png")
	var key := type_key
	if not FileAccess.file_exists("res://assets/towers/head_%s.png" % key) \
			and not FileAccess.file_exists("res://assets/towers/head_%s_frame_1.png" % key):
		key = String(Data.habit_family(type_key))
	var static_path := "res://assets/towers/head_%s.png" % key
	if FileAccess.file_exists(static_path):
		_body_tex = load(static_path)
	for i in range(1, 33):
		var p := "res://assets/towers/head_%s_frame_%d.png" % [key, i]
		if not FileAccess.file_exists(p):
			break
		_body_frames.append(load(p))
	if _body_tex == null and not _body_frames.is_empty():
		_body_tex = _body_frames[0]

	rally_point = global_position
	# Default recipe: one of each, in display order — a balanced kitchen until the
	# player reads the wave and reorders it.
	slots.clear()
	_slot_units.clear()
	_slot_timers.clear()
	for i in range(_FORMATION_OFFSETS.size()):
		slots.append(Data.DEFENDER_ORDER[i % Data.DEFENDER_ORDER.size()])
		_slot_units.append(null)
		_slot_timers.append(0.0)
		_spawn_slot(i)
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for a in owned_allies:
			if is_instance_valid(a):
				a.queue_free()

func _process(delta: float) -> void:
	# Out of Routine the guild goes dark like every other habit: the flag freezes and
	# fallen slots do NOT refill until the connection returns. Defenders already on the
	# field keep fighting — they are out of the pantry and on their own legs — so the
	# real cost of a cut-off guild is that its line, once it falls, stays down.
	# (game.routine_gates_enabled is the harness bypass, same as the build gate's.)
	if not in_routine and (game == null or game.routine_gates_enabled):
		queue_redraw()
		return

	# Body animation runs even between waves — the kiosk flag should wave while building.
	if not _body_frames.is_empty():
		_anim_t += delta
		queue_redraw()

	# Respawn ticks on WALL time, unlike combat effects — deliberately. The units are
	# free and permanent, so there is nothing to exploit by waiting; gating the timer on
	# waves would only mean sometimes entering a wave a defender short because the last
	# one died at the previous wave's final second.
	for i in range(slots.size()):
		if _slot_units[i] == null and _slot_timers[i] > 0.0:
			_slot_timers[i] -= delta
			if _slot_timers[i] <= 0.0:
				_spawn_slot(i)

# ---------------------------------------------------------------- slots / recipe

## Cycle a slot to the next defender type. The LIVE unit is untouched — it fights its
## post until it dies; the new type arrives with the slot's next respawn.
func cycle_slot(i: int) -> void:
	var order := Data.DEFENDER_ORDER
	var at := order.find(slots[i])
	slots[i] = order[(at + 1) % order.size()]

func slot_label(i: int) -> String:
	var d := Data.get_defender(slots[i])
	if d == null:
		return String(slots[i])
	var live = _slot_units[i]
	if live == null and _slot_timers[i] > 0.0:
		return "%s (%.0fs)" % [d.display_name, ceilf(_slot_timers[i])]
	return d.display_name

## True while the slot's live unit is a DIFFERENT type than the recipe now names —
## the "will swap on death" state the panel wants to mark.
func slot_pending_change(i: int) -> bool:
	var live = _slot_units[i]
	return live != null and is_instance_valid(live) and live.type_key != slots[i]

func _spawn_slot(i: int) -> void:
	var ddata := Data.get_defender(slots[i])
	if ddata == null:
		push_warning("Barracks: unknown defender type %s" % slots[i])
		return
	var u := DefenderUnit.new()
	u.slot_index = i
	u.setup_from_data(game, ddata, rally_point, _FORMATION_OFFSETS[i],
		def.guard_radius, def.defender_hp_mult, def.defender_damage_mult)
	u.died.connect(_on_unit_died)
	u.global_position = global_position   # walks out of the pantry to the rally
	_slot_units[i] = u
	owned_allies.append(u)
	game.entities.add_child(u)

func _on_unit_died(unit) -> void:
	owned_allies.erase(unit)
	var i: int = unit.slot_index
	if i >= 0 and i < slots.size() and _slot_units[i] == unit:
		_slot_units[i] = null
		_slot_timers[i] = def.ally_spawn_cooldown

# ---------------------------------------------------------------- rally point

## Clamped into the guild's reach and off the walls, then pushed to every live unit —
## they walk over rather than teleporting, which also re-forms them mid-wave.
func set_rally_point(pos: Vector2) -> void:
	var to := pos - global_position
	if to.length() > def.guard_radius:
		pos = global_position + to.normalized() * def.guard_radius
	if game != null and game.high_ground.has(game.world_to_cell(pos)):
		return   # a rally inside a wall would strand the formation; keep the old one
	rally_point = pos
	for u in owned_allies:
		if is_instance_valid(u):
			u.rally_point = rally_point
			if u.state == DefenderUnit.State.IDLE:
				u.state = DefenderUnit.State.MOVE_TO_RALLY
	queue_redraw()

# ---------------------------------------------------------------- draw

func _draw() -> void:
	var tile: int = Data.GRID.tile

	# Socket base + kiosk body, native size x whole zoom like every other habit.
	if _base_tex != null:
		var b_zoom := maxf(1.0, floorf(float(tile) / _base_tex.get_width()))
		var b_size := Vector2(_base_tex.get_size()) * b_zoom
		draw_texture_rect(_base_tex, Rect2(-b_size / 2.0, b_size), false, Color.WHITE)
	var body := _body_tex
	if not _body_frames.is_empty():
		body = _body_frames[int(_anim_t * BODY_FPS) % _body_frames.size()]
	# Dimmed when cut off, same read as a support head out of Routine (tower.gd).
	var body_tint := Color.WHITE if in_routine else Color(0.6, 0.6, 0.6, 0.8)
	if body != null:
		var zoom := maxf(1.0, floorf(float(tile) / body.get_width()))
		var size := Vector2(body.get_size()) * zoom
		draw_texture_rect(body, Rect2(-size / 2.0, size), false, body_tint)
	else:
		draw_circle(Vector2.ZERO, 3.0, body_tint)

	if not in_routine:
		var flash_a := (sin(Time.get_ticks_msec() * 0.008) * 0.35) + 0.65
		draw_string(ThemeDB.fallback_font, Vector2(-34, -tile * 0.42 - 14), "⚠ NO ROUTINE",
			HORIZONTAL_ALIGNMENT_CENTER, -1, 13, Color(1.0, 0.8, 0.2, flash_a))

	# Rally marker + leash zone, drawn around the RALLY, not the tower — the circle is
	# a promise about where the defenders will fight, and it has to be drawn where that
	# promise actually holds.
	var rp := to_local(rally_point)
	if rp.length() > 4.0:
		PixelDraw.line(self, Vector2.ZERO, rp, Color(1.0, 1.0, 1.0, 0.25), 1.0, 2.0)
	draw_line(rp + Vector2(0, -10), rp, Color("e8e4d8"), 2.0)
	var flag := PackedVector2Array([rp + Vector2(0, -10), rp + Vector2(7, -7), rp + Vector2(0, -4)])
	draw_colored_polygon(flag, Color(_color.r, _color.g, _color.b))
	if show_range_indicator:
		PixelDraw.arc(self, rp, def.guard_radius, Color(1.0, 1.0, 1.0, 0.4), 1.0, 2.0)
		draw_circle(rp, def.guard_radius, Color(1.0, 1.0, 1.0, 0.05))
	else:
		PixelDraw.arc(self, rp, def.guard_radius, Color(1.0, 1.0, 1.0, 0.08), 1.0, 3.0)
