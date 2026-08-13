class_name ImpactFX
extends Node2D

signal finished(fx: ImpactFX)

var _color: Color = Color.WHITE
var _progress: float = 0.0
var _particles: Array = []

func play(color: Color) -> void:
	_color = color
	_progress = 0.0
	_particles.clear()
	
	# Generate 8-10 spark particles radiating outward
	for i in range(9):
		var angle := randf_range(0.0, TAU)
		var speed := randf_range(50.0, 130.0)
		var dir := Vector2.RIGHT.rotated(angle) * speed
		var size := randf_range(2.5, 4.5)
		_particles.append({"dir": dir, "size": size})
		
	var tw := create_tween()
	tw.tween_method(func(v: float): 
		_progress = v
		queue_redraw()
	, 0.0, 1.0, 0.28)
	tw.tween_callback(func(): finished.emit(self))

func _draw() -> void:
	if _progress >= 1.0:
		return
		
	var alpha := 1.0 - _progress
	var col := Color(_color.r, _color.g, _color.b, alpha)
	var core_col := Color(1.0, 1.0, 1.0, alpha * 0.8)
	
	# Shockwave ring expanding
	var shockwave_r := 4.0 + _progress * 24.0
	draw_arc(Vector2.ZERO, shockwave_r, 0.0, TAU, 24, Color(_color.r, _color.g, _color.b, alpha * 0.7), 1.8)
	
	# Center flash dot
	if _progress < 0.4:
		draw_circle(Vector2.ZERO, (1.0 - _progress * 2.5) * 5.0, core_col)
	
	# Flying spark particles
	for p in _particles:
		var p_pos: Vector2 = p.dir * (_progress * 0.28)
		var p_size: float = p.size * alpha
		draw_circle(p_pos, p_size, col)
