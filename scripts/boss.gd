class_name Boss
extends Distraction
## Final-wave elite. Two mechanics layered on the base Distraction, both plain
## countdown timers in the style of Barracks._ally_spawn_timer:
##
## Denial Shield — periodically immune to take_damage() (regular shots, AoE
## pulses, Ally melee all route through it), but NOT to Boredom, which lands
## through take_direct_damage() directly. Forces a real choice: hold fire and
## wait it out, burst it down before it goes up, or lean on Mindfulness towers
## that bypass it entirely.
##
## Minion spawns — periodically calls the same public spawn_distraction() any
## other spawner uses, so adds get full pathing/tracking/HUD treatment for free.

signal shield_toggled(active: bool)

var _shield_active := false
var _shield_timer := 0.0
var _minion_timer := 0.0

func setup(_game, _type_key: String) -> void:
	super.setup(_game, _type_key)
	_shield_timer = def.shield_interval
	_minion_timer = def.minion_interval

func _process(delta: float) -> void:
	super._process(delta)
	if dead:
		return  # Boredom can finish it off mid-tick, same guard the base class uses
	_tick_shield(delta)
	_tick_minions(delta)

func _tick_shield(delta: float) -> void:
	if def.shield_interval <= 0.0:
		return
	_shield_timer -= delta
	if _shield_timer > 0.0:
		return
	_shield_active = not _shield_active
	_shield_timer = def.shield_duration if _shield_active else def.shield_interval
	shield_toggled.emit(_shield_active)
	queue_redraw()

func _tick_minions(delta: float) -> void:
	if def.minion_interval <= 0.0 or def.minion_type == null or def.minion_count <= 0:
		return
	_minion_timer -= delta
	if _minion_timer > 0.0:
		return
	_minion_timer = def.minion_interval
	var spawn_cell: Vector2i = game.world_to_cell(global_position)
	for i in range(def.minion_count):
		game.spawn_distraction(def.minion_type.id, spawn_cell)

## Direct hits are blocked while shielded; take_direct_damage() (Boredom) is untouched.
func take_damage(willpower: int, awareness: int, source: Object = null) -> void:
	if _shield_active:
		return
	super.take_damage(willpower, awareness, source)

## Public read for DistractionAnimator, which owns the on-body shield visual — every
## boss gets an animator, so the fallback ring in _draw() below never renders.
func is_shielded() -> bool:
	return _shield_active

func _draw() -> void:
	var r: float = def.radius
	draw_set_transform(_hit_wobble, 0.0, Vector2.ONE)   # cosmetic-only, see enemy.gd

	if animator == null:
		if status_manager.has_boredom():
			draw_circle(Vector2.ZERO, r + 5.0, Color(0.55, 0.58, 0.62, 0.30))

		match def.shape:
			"circle":
				draw_circle(Vector2.ZERO, r, _color)
			"rect":
				draw_rect(Rect2(-r, -r, r * 2.0, r * 2.0), _color)
			"triangle":
				var pts := PackedVector2Array([Vector2(0, -r), Vector2(r, r), Vector2(-r, r)])
				draw_colored_polygon(pts, _color)

		if status_manager.has_reframe():
			var seg: float = TAU / 8.0
			for i: int in range(4):
				var a: float = float(i) * seg * 2.0
				draw_arc(Vector2.ZERO, r + 4.0, a, a + seg, 6, Color(1, 1, 1, 0.85), 2.0)

		# Denial Shield tell — a solid ring
		if _shield_active:
			draw_arc(Vector2.ZERO, r + 10.0, 0, TAU, 32, Color("ffd479"), 3.0)

	# Always-visible boss health bar (base class only draws one once damaged).
	var w: float = 90.0
	var y: float = -r - 22.0
	draw_rect(Rect2(-w / 2.0 - 2.0, y - 2.0, w + 4.0, 10.0), Color(0, 0, 0, 0.7))
	var ratio: float = clampf(float(current_health) / float(max_health), 0.0, 1.0)
	draw_rect(Rect2(-w / 2.0, y, w * ratio, 6.0), Color("ff6b6b"))
