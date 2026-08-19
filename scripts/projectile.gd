class_name Projectile
extends Node2D
# Directional energy projectile fired by a habit into its sector — it flies straight
# along the angle it was given, sweeping a segment each frame and piercing up to
# `pierce_max` bodies. It has no target and never had one; the habit that fired it did
# not have one either. Features motion trailing, directional rotation, and impact FX.

signal finished(p: Projectile)

var direction_vec := Vector2.RIGHT
var max_travel_distance := 300.0
var distance_traveled := 0.0
## Slab the shot was fired from; that one wall does not stop it. -2 = not set yet.
var _origin_platform: int = -2

var willpower: int = 0
var awareness: int = 0
var speed := 560.0
var _color: Color
var dead := false
var game: Node = null

## Damage-over-time this shot leaves on what it hits. Boredom used to be reachable only
## through the AoE branch in tower.gd, so a DoT habit HAD to be a cone pulse — flipping
## Deep Reading to directional fire would have silently deleted its whole identity and
## left a weak popgun behind. Carried per-shot rather than read off the habit because the
## tower can be sold mid-flight.
var boredom: float = 0.0
var boredom_duration: float = 0.0

## Radians per second the sprite tumbles, and how flat to draw it. Nonzero turns the bolt
## into a tumbling sheet — the Tome fires pages, not energy. Pooled projectiles are shared
## by every habit, so this resets on every setup like all the rest of the state.
var spin: float = 0.0
var _spin_t: float = 0.0

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
# The shot therefore sweeps a SEGMENT each frame and PIERCES. What used to be two
# constants here is now carried per shot, because the firing habit's cone width decides
# both: narrow fire pierces deep through a thin window, wide fire dies on the first body
# it touches but is fat enough to be hard to slip past. See ArcProfile.

## Bodies this shot may pass through, and how far off-centre still counts as a hit. Both
## arrive from the habit's ArcProfile at spawn; the defaults are the home-angle values.
var pierce_max: int = 2
var hit_padding: float = ArcProfile.BASE_HIT_PADDING

## Physical response on hit — one or the other, never both (a cone is either narrower
## than its home angle or wider). `knockback` is pixels of shove along the flight
## direction; `stagger_factor` is a shallow, short slow. 0.0 / 1.0 mean off.
var knockback: float = 0.0
var stagger_factor: float = 1.0

## Distractions this shot has already damaged, so a pierce doesn't re-hit the same body
## on the following frame while it is still inside the hit window.
var _hit: Array = []
var _pierced := 0

## The habit that fired this shot, credited for panel stats on every hit. Object, not
## a hard reference type: the tower can be sold while the shot is mid-flight, so every
## use goes through is_instance_valid first.
var source: Object = null

func setup_directional(_game: Node, dir_angle: float, max_dist: float, wp: int, aw: int,
		color: Color, _source: Object = null, dot: float = 0.0, dot_duration: float = 0.0,
		spin_rate: float = 0.0, pierce: int = 2,
		padding: float = ArcProfile.BASE_HIT_PADDING,
		knock: float = 0.0, stagger: float = 1.0) -> void:
	game = _game
	source = _source
	# Captured at spawn, not read per frame: once the shot leaves the platform it was
	# fired from, "the platform I am over" is no longer "the platform that must not stop
	# me". -2 means "no game yet", which is neither a slab nor open ground.
	_origin_platform = -2 if game == null else game.platform_at(global_position)
	direction_vec = Vector2.RIGHT.rotated(dir_angle)
	rotation = dir_angle
	max_travel_distance = max_dist
	distance_traveled = 0.0
	willpower = wp
	awareness = aw
	_color = color
	boredom = dot
	boredom_duration = dot_duration
	spin = spin_rate
	pierce_max = maxi(1, pierce)
	hit_padding = padding
	knockback = knock
	stagger_factor = stagger
	_spin_t = 0.0
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

	if spin != 0.0:
		_spin_t += spin * delta

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
			if closest.distance_to(d.global_position) > d.def.radius + hit_padding:
				continue
			# Hidden in the Brain Fog: the shot flies on THROUGH the body rather than
			# dying on it. Fog is absence of sight, not a wall — the wall death below
			# stays the only thing that stops a shot early. Tested AFTER the geometry
			# rejection on purpose: this loop is projectiles x enemies per frame, the
			# game's hottest, and the fog lookup should only run on actual hit
			# candidates — a handful per frame instead of every pair.
			if not game.is_pos_visible(d.global_position):
				continue
			var src: Object = source if is_instance_valid(source) else null
			d.take_damage(willpower, awareness, src)
			# Impulse before the DoT, so a body that dies to this hit still gets shoved
			# on the frame it dies — the push is what sells the hit, and a corpse that
			# stands perfectly still while the next shot arrives reads as a missed frame.
			if knockback > 0.0:
				d.apply_knockback(direction_vec, knockback)
			if stagger_factor < 1.0:
				d.apply_slow(stagger_factor, ArcProfile.STAGGER_TIME)
			if boredom > 0.0:
				# Same source semantics as the AoE branch: several Deep Readings stack
				# their own dps, but one habit's own stream of shots does not stack with
				# itself — it just keeps refreshing its own timer, which is what a
				# sustained burst should do.
				d.apply_boredom(boredom, boredom_duration, src)
			_hit.append(d)
			_create_impact_fx()
			_pierced += 1
			if _pierced >= pierce_max:
				_destroy()
				return

	# Walls stop shots. Mirrors the LOS filter in tower targeting and the shaded wedge
	# preview — all three share game.high_ground and the same slab rule, so they cannot
	# drift.
	#
	# The slab the shot was FIRED FROM does not stop it. This used to be a flat "24px
	# grace ... to clear the muzzle", which treated the symptom: every habit stands on
	# high ground, so without it every shot died a half-tile out. A distance grace also
	# said the wrong thing — it let a shot punch a fixed way into a foreign wall, and it
	# still killed shots travelling along their own platform past 24px, which is exactly
	# what the truncated wedge preview was showing the player.
	if game != null and _origin_platform != -2 \
			and game.high_ground.has(game.world_to_cell(global_position)) \
			and game.platform_at(global_position) != _origin_platform:
		_create_impact_fx()
		_destroy()
		return

	if distance_traveled >= max_travel_distance:
		_destroy()
		return

	queue_redraw()

## One art pixel of the world's raster: terrain is 16px art scaled x3, so effects draw in
## 3px blocks too. The old plasma polygons, glow circles and smooth trail lines were the
## sharpest thing on screen — exactly the vector-against-pixel clash the art pass removed
## from towers and enemies.
const PX := 3.0

## A single raster block centred on `pos` (local space), `units` art pixels wide.
func _px(pos: Vector2, units: float, col: Color) -> void:
	var s := PX * units
	draw_rect(Rect2(pos - Vector2(s, s) * 0.5, Vector2(s, s)), col)

func _draw() -> void:
	# Motion trail: lone fading blocks snapped to the raster, so the wake flickers in
	# place like dropped pixels instead of sliding smoothly behind the shot.
	if _trail.size() > 1:
		for i: int in range(_trail.size() - 1):
			var alpha: float = float(i + 1) / float(_trail.size()) * 0.4
			var p: Vector2 = to_local(_trail[i]).snapped(Vector2(PX, PX))
			_px(p, 1.0, Color(_color.r, _color.g, _color.b, alpha))

	if spin != 0.0:
		# A torn page, not a bolt: a flat sheet tumbling end over end. Drawn as a square
		# scaled on one axis by cos(t), so it foreshortens to a hairline edge-on and back
		# — the same trick a spinning card uses, and it costs one cos per frame.
		var flat: float = absf(cos(_spin_t))
		var half_w: float = PX * (0.6 + 1.7 * flat)
		var half_h: float = PX * 1.3
		draw_rect(Rect2(-half_w, -half_h, half_w * 2.0, half_h * 2.0),
			Color(_color.r, _color.g, _color.b, 0.9))
		# Lit leading edge, so the sheet reads as catching light rather than as a smear.
		draw_rect(Rect2(half_w - PX * 0.5, -half_h, PX * 0.5, half_h * 2.0),
			_color.lightened(0.45))
		return

	# Bolt: 3x2-block body, lit tip ahead, dimmer block behind, white-hot core.
	draw_rect(Rect2(-PX * 1.5, -PX, PX * 3.0, PX * 2.0), _color)
	_px(Vector2(PX * 2.0, 0.0), 1.0, _color.lightened(0.4))
	_px(Vector2(-PX * 2.0, 0.0), 1.0, Color(_color.r, _color.g, _color.b, 0.55))
	_px(Vector2.ZERO, 1.0, Color(1, 1, 1, 0.95))

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
