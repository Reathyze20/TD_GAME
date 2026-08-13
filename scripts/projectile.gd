class_name Projectile
extends Node2D
# Directional energy projectile fired by habits — flies straight along the barrel
# orientation, sweeping a segment each frame and piercing up to MAX_PIERCE bodies.
# Features motion trailing, directional rotation, glowing core, and impact FX.

signal finished(p: Projectile)

var direction_vec := Vector2.RIGHT
var max_travel_distance := 300.0
var distance_traveled := 0.0

var willpower: int = 0
var awareness: int = 0
var speed := 560.0
var _color: Color
var dead := false
var game: Node = null

var _trail: Array[Vector2] = []
const MAX_TRAIL := 6

# ---------------------------------------------------------------- hit resolution
#
# A directional shot used to be a point test against `radius + 8` on a bullet moving
# 560 px/s — about 9.3px per frame at 60fps — and it stopped on the first body it
# touched. Two consequences the horde hid and every sparse wave exposed: fast crossers
# slipped between frames entirely, and a single-target habit could never out-damage an
# uncapped AoE pulse because it spent a whole shot per enemy.
#
# Now the shot sweeps a SEGMENT each frame and PIERCES. The pierce cap is deliberate and
# mirrors the AoE target cap in tower.gd: a cone habit is "area, bounded", a projectile
# habit is "line, bounded". Both archetypes stay distinct and neither scales without limit.

const HIT_PADDING := 16.0
const MAX_PIERCE := 4

## Distractions this shot has already damaged, so a pierce doesn't re-hit the same body
## on the following frame while it is still inside the hit window.
var _hit: Array = []
var _pierced := 0

## The habit that fired this shot, credited for panel stats on every hit. Object, not
## a hard reference type: the tower can be sold while the shot is mid-flight, so every
## use goes through is_instance_valid first.
var source: Object = null

func setup_directional(_game: Node, dir_angle: float, max_dist: float, wp: int, aw: int,
		color: Color, _source: Object = null) -> void:
	game = _game
	source = _source
	direction_vec = Vector2.RIGHT.rotated(dir_angle)
	rotation = dir_angle
	max_travel_distance = max_dist
	distance_traveled = 0.0
	willpower = wp
	awareness = aw
	_color = color
	_trail.clear()
	_hit.clear()
	_pierced = 0
	dead = false
	queue_redraw()

func _process(delta: float) -> void:
	if dead:
		return

	# Save position for trail
	_trail.append(global_position)
	if _trail.size() > MAX_TRAIL:
		_trail.pop_front()

	var step: float = speed * delta

	# Straight directional flight along turret barrel orientation. The segment from
	# where we were to where we now are is what gets tested — a point test at the new
	# position alone lets anything narrower than one frame of travel through.
	var from_pos: Vector2 = global_position
	global_position += direction_vec * step
	distance_traveled += step

	if game != null:
		for d in game.get_live_distractions():
			if not is_instance_valid(d) or d.dead or _hit.has(d):
				continue
			var closest: Vector2 = Geometry2D.get_closest_point_to_segment(
				d.global_position, from_pos, global_position)
			if closest.distance_to(d.global_position) > d.def.radius + HIT_PADDING:
				continue
			d.take_damage(willpower, awareness,
				source if is_instance_valid(source) else null)
			_hit.append(d)
			_create_impact_fx()
			_pierced += 1
			if _pierced >= MAX_PIERCE:
				_destroy()
				return

	if distance_traveled >= max_travel_distance:
		_destroy()
		return

	queue_redraw()

func _draw() -> void:
	# 1. Tapered Plasma Flame Tail (stretching backward along local -X axis)
	var tail_len := 24.0
	var tail_pts := PackedVector2Array([
		Vector2(3.0, -4.5),
		Vector2(-tail_len, -1.5),
		Vector2(-tail_len - 10.0, 0.0),
		Vector2(-tail_len, 1.5),
		Vector2(3.0, 4.5)
	])
	draw_colored_polygon(tail_pts, Color(_color.r, _color.g, _color.b, 0.45))
	
	# Inner blazing hot flame core tail
	var inner_tail := PackedVector2Array([
		Vector2(3.0, -2.5),
		Vector2(-tail_len * 0.65, 0.0),
		Vector2(3.0, 2.5)
	])
	draw_colored_polygon(inner_tail, Color(1, 1, 1, 0.9))

	# 2. Motion trail dots
	if _trail.size() > 1:
		for i: int in range(_trail.size() - 1):
			var alpha: float = float(i + 1) / float(_trail.size()) * 0.45
			var p1: Vector2 = to_local(_trail[i])
			var p2: Vector2 = to_local(_trail[i + 1])
			draw_line(p1, p2, Color(_color.r, _color.g, _color.b, alpha), 6.0 * alpha + 1.0)

	# 3. Heavy Cannon Shell Body (Armored Capsule / Bullet Head pointing along +X)
	var head_col := Color(_color.r, _color.g, _color.b, 1.0)
	var glow_col := Color(_color.r, _color.g, _color.b, 0.35)
	
	# Outer energy halo
	draw_circle(Vector2.ZERO, 9.0, glow_col)
	
	# Bullet Shell Geometry
	var shell_pts := PackedVector2Array([
		Vector2(9.0, 0.0),    # Tip
		Vector2(5.0, -4.5),   # Top curve
		Vector2(-4.0, -4.5),  # Top back
		Vector2(-5.0, 0.0),   # Back center
		Vector2(-4.0, 4.5),   # Bottom back
		Vector2(5.0, 4.5)     # Bottom curve
	])
	draw_colored_polygon(shell_pts, head_col)
	shell_pts.append(shell_pts[0])
	draw_polyline(shell_pts, Color(1.0, 1.0, 1.0, 0.8), 1.5)
	
	# Hot glowing center core
	draw_circle(Vector2(2.0, 0.0), 3.0, Color.WHITE)

func _create_impact_fx() -> void:
	if game != null and "impact_fx_pool" in game:
		var fx = game.impact_fx_pool.acquire()
		if fx != null:
			fx.global_position = global_position
			fx.play(_color)
			# The pool handles listening to the 'finished' signal for release



func _destroy() -> void:
	if dead:
		return
	dead = true
	finished.emit(self)
