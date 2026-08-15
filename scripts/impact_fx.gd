class_name ImpactFX
extends Node2D

signal finished(fx: ImpactFX)

## Everything here is blocks on the world's 3px raster (16px art x3) — arcs and shrinking
## circles were the last smooth vector shapes flying around the pixel field. The same node
## plays two roles: a small quick burst on projectile hit (scale 1), and a bigger, slower
## one in the enemy's own colour when something dies, so a kill reads differently from a
## hit even in the corner of the eye.
const PX := 3.0

var _color: Color = Color.WHITE
var _progress: float = 0.0
var _particles: Array = []
var _scale := 1.0

func play(color: Color, scale_mult: float = 1.0) -> void:
	_color = color
	_scale = scale_mult
	_progress = 0.0
	_particles.clear()

	var count := 9 if scale_mult <= 1.0 else 14
	for i in range(count):
		var angle := randf_range(0.0, TAU)
		var speed := randf_range(50.0, 130.0) * scale_mult
		var dir := Vector2.RIGHT.rotated(angle) * speed
		# Whole art pixels only — a death burst throws a few double-size chunks.
		var size := 1
		if scale_mult > 1.0 and randf() < 0.4:
			size = 2
		_particles.append({"dir": dir, "size": size})

	var tw := create_tween()
	tw.tween_method(func(v: float):
		_progress = v
		queue_redraw()
	, 0.0, 1.0, 0.28 if scale_mult <= 1.0 else 0.4)
	tw.tween_callback(func(): finished.emit(self))

## A raster block centred near `pos`, snapped to the grid so debris lands ON pixels.
func _px(pos: Vector2, units: float, col: Color) -> void:
	var s := PX * units
	var q := (pos / PX).floor() * PX
	draw_rect(Rect2(q - Vector2(s, s) * 0.5, Vector2(s, s)), col)

func _draw() -> void:
	if _progress >= 1.0:
		return

	var alpha := 1.0 - _progress
	var col := Color(_color.r, _color.g, _color.b, alpha)

	# Shockwave: eight blocks stepping outward on fixed spokes — the raster cousin of an
	# expanding arc. The 0.39 offset keeps the spokes off the axes so it reads round-ish.
	var r := (4.0 + _progress * 24.0) * _scale
	for i in range(8):
		var dirv := Vector2.RIGHT.rotated(TAU * float(i) / 8.0 + 0.39)
		_px(dirv * r, 1.0, Color(_color.r, _color.g, _color.b, alpha * 0.6))

	# Centre flash collapses block by block instead of shrinking smoothly.
	if _progress < 0.4:
		var units := 3.0 if _progress < 0.15 else (2.0 if _progress < 0.28 else 1.0)
		_px(Vector2.ZERO, units * maxf(1.0, _scale * 0.75), Color(1, 1, 1, alpha * 0.9))

	# Flying debris; double chunks crumble to single ones halfway out.
	for p in _particles:
		var units: float = p.size if _progress < 0.5 else maxf(1.0, p.size - 1.0)
		_px(p.dir * (_progress * 0.28), units, col)
