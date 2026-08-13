class_name FloatingText
extends Node2D

signal finished(node: FloatingText)

var _text: String = ""
var _color: Color = Color("35ff8d")
var _alpha: float = 1.0
var _offset: Vector2 = Vector2.ZERO

func setup(pos: Vector2, text: String, color: Color = Color("35ff8d")) -> void:
	global_position = pos
	_text = text
	_color = color
	_alpha = 1.0
	_offset = Vector2.ZERO
	
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "_offset", Vector2(randf_range(-8.0, 8.0), -36.0), 0.65).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "_alpha", 0.0, 0.65).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(func(): finished.emit(self))
	queue_redraw()

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if _alpha <= 0.01 or _text.is_empty():
		return
	var font = ThemeDB.fallback_font
	var draw_col = Color(_color.r, _color.g, _color.b, _alpha)
	var shadow_col = Color(0.05, 0.05, 0.1, _alpha * 0.75)
	# Subtle dark shadow offset for readability over dark/bright background
	draw_string(font, _offset + Vector2(1, 1), _text, HORIZONTAL_ALIGNMENT_CENTER, -1, 14, shadow_col)
	draw_string(font, _offset, _text, HORIZONTAL_ALIGNMENT_CENTER, -1, 14, draw_col)
