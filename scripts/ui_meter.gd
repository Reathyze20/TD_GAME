class_name UIMeter extends Control
## A horizontal bar readout. Two things a plain Label cannot do, and both matter here:
##
##  * A ratio is legible at a glance. "Focus: 21/30" makes the player do arithmetic in
##    the middle of a fight; a bar two-thirds full does not.
##  * It can show a SECOND, locked-in level underneath the live one. Tolerance needs
##    exactly that: the spike decays, the floor does not, and the floor being invisible
##    was why a permanent cost felt like a temporary one.

@export var value: float = 0.0: set = set_value
@export var max_value: float = 100.0: set = set_max_value
## Portion of the bar that can never drain (Tolerance's floor). 0 hides it.
@export var floor_value: float = 0.0: set = set_floor_value

@export var fill_color: Color = UI.FOCUS
@export var track_color: Color = UI.TRACK
## Drawn under the fill to mark the locked-in part. Deliberately a desaturated,
## darker relative of the fill so it reads as "the same thing, but stuck".
@export var floor_color: Color = Color("6b3a1c")

@export var caption: String = ""
@export var readout: String = ""
## Fill turns this colour below `danger_below` (as a fraction). 0 disables it.
@export var danger_below: float = 0.0
@export var danger_color: Color = UI.DANGER

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(180, 34)

func set_value(v: float) -> void:
	value = v
	queue_redraw()

func set_max_value(v: float) -> void:
	max_value = maxf(0.0001, v)
	queue_redraw()

func set_floor_value(v: float) -> void:
	floor_value = v
	queue_redraw()

## Sets everything a frame needs in one call, so callers don't trigger four redraws.
func update_meter(new_value: float, new_max: float, new_readout: String,
		new_floor: float = 0.0) -> void:
	value = new_value
	max_value = maxf(0.0001, new_max)
	readout = new_readout
	floor_value = new_floor
	queue_redraw()

func _draw() -> void:
	var font := ThemeDB.fallback_font
	var cap_h := 13.0 if caption != "" else 0.0
	var bar_rect := Rect2(0.0, cap_h, size.x, maxf(8.0, size.y - cap_h))

	if caption != "":
		draw_string(font, Vector2(1, 10), caption.to_upper(),
			HORIZONTAL_ALIGNMENT_LEFT, -1, UI.FS_MICRO, UI.TEXT_FAINT)

	draw_style_box(UI.flat(track_color, UI.BORDER, 1, UI.RADIUS_SM), bar_rect)

	# The fill is drawn INSET inside the track and with square corners. Rounding each
	# segment made the floor and the live fill read as two detached pills sitting in a
	# box, rather than as one bar with two zones — the inset border is what ties them
	# back together.
	const PAD := 2.0
	var inner := Rect2(bar_rect.position + Vector2(PAD, PAD),
		Vector2(maxf(0.0, bar_rect.size.x - PAD * 2.0), maxf(0.0, bar_rect.size.y - PAD * 2.0)))

	var ratio: float = clampf(value / max_value, 0.0, 1.0)
	var floor_ratio: float = clampf(floor_value / max_value, 0.0, 1.0)

	var col := fill_color
	if danger_below > 0.0 and ratio < danger_below:
		col = danger_color

	# Floor first and only as far as it goes; the live fill continues from there, so the
	# exposed remainder is exactly the part that will decay away.
	if floor_ratio > 0.0:
		var fw: float = inner.size.x * minf(floor_ratio, ratio if ratio > 0.0 else floor_ratio)
		if fw > 0.5:
			draw_rect(Rect2(inner.position, Vector2(fw, inner.size.y)), floor_color)

	if ratio > floor_ratio:
		var start: float = inner.size.x * floor_ratio
		var w: float = inner.size.x * ratio - start
		if w > 0.5:
			draw_rect(Rect2(inner.position + Vector2(start, 0), Vector2(w, inner.size.y)), col)

	# A brighter cap on the leading edge — reads as "this is the current level" and keeps
	# a nearly-empty bar visible.
	var tip: float = inner.size.x * ratio
	if tip > 2.0:
		draw_rect(Rect2(inner.position.x + tip - 2.0, inner.position.y, 2.0, inner.size.y),
			Color(col.r, col.g, col.b, 1.0).lightened(0.35))

	if readout != "":
		# Centred in the bar, not right-aligned. Pinned to the right edge it sat in the
		# empty remainder and read as a separate box tacked onto the end of the meter.
		var ts := font.get_string_size(readout, HORIZONTAL_ALIGNMENT_LEFT, -1, UI.FS_SMALL)
		var pos := Vector2(bar_rect.position.x + (bar_rect.size.x - ts.x) * 0.5,
			bar_rect.position.y + (bar_rect.size.y + ts.y) * 0.5 - 3.0)
		# Outlined so it stays readable over both the filled and empty halves.
		draw_string_outline(font, pos, readout, HORIZONTAL_ALIGNMENT_LEFT, -1,
			UI.FS_SMALL, 4, Color(0, 0, 0, 0.85))
		draw_string(font, pos, readout, HORIZONTAL_ALIGNMENT_LEFT, -1, UI.FS_SMALL, UI.TEXT)
