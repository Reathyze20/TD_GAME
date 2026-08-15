class_name PixelDraw
## Chunky raster line and arc helpers — the pixel replacement for draw_line / draw_arc in
## every overlay (range rings, Routine tethers, aim lines, reticles). Blocks are snapped
## to the world's 3px grid (16px art x3) and spaced slightly apart, so long guides read as
## dashed pixel trails instead of anti-aliased vector strokes. Snapped duplicates are
## skipped: translucent colours would double up wherever two steps land on one block.

const PX := 3.0

## `flow` shifts every block along the line by that many pixels (wrapped to the step), so
## a value that grows with time makes the blocks march from `from` toward `to` — a cheap
## way to show energy flowing through a tether without any extra nodes.
static func line(cv: CanvasItem, from: Vector2, to: Vector2, col: Color,
		units: float = 1.0, spacing: float = 2.0, flow: float = 0.0) -> void:
	var delta := to - from
	var length := delta.length()
	var s := PX * units
	if length < 0.001:
		cv.draw_rect(Rect2((from / PX).floor() * PX, Vector2(s, s)), col)
		return
	var step := PX * spacing
	var dirn := delta / length
	var d := fposmod(flow, step)
	var last := Vector2.INF
	while d <= length:
		var p := ((from + dirn * d) / PX).floor() * PX
		if p != last:
			last = p
			cv.draw_rect(Rect2(p, Vector2(s, s)), col)
		d += step

## A bright energy packet running along the line: a glowing 2-block head with a white-hot
## core and a short fading tail. `travel` is the head's distance from `from` in pixels —
## drive it with time and wrap with fposmod(t * speed, length + pause) so the packet runs,
## arrives, and after a beat runs again. This is what says "something is being DELIVERED";
## a uniformly marching dash can only say "these two are connected".
static func packet(cv: CanvasItem, from: Vector2, to: Vector2, col: Color, travel: float) -> void:
	var delta := to - from
	var length := delta.length()
	if length < 0.001 or travel > length:
		return
	var dirn := delta / length
	var head := clampf(travel, 0.0, length)
	# Tail: fading blocks trailing the head.
	for i in range(1, 5):
		var d := head - float(i) * PX * 2.0
		if d < 0.0:
			break
		var p := ((from + dirn * d) / PX).floor() * PX
		cv.draw_rect(Rect2(p, Vector2(PX, PX)),
			Color(col.r, col.g, col.b, col.a * (1.0 - float(i) * 0.22)))
	# Head: double block in the line colour, single white-hot block on top.
	var hp := ((from + dirn * head) / PX).floor() * PX
	cv.draw_rect(Rect2(hp - Vector2(PX, PX) * 0.5, Vector2(PX, PX) * 2.0), col)
	cv.draw_rect(Rect2(hp, Vector2(PX, PX)), Color(1, 1, 1, col.a))

static func arc(cv: CanvasItem, centre: Vector2, radius: float, col: Color,
		units: float = 1.0, spacing: float = 2.0,
		from_angle: float = 0.0, to_angle: float = TAU) -> void:
	var sweep := to_angle - from_angle
	var n := maxi(int(absf(sweep) * radius / (PX * spacing)), 4)
	var s := PX * units
	var last := Vector2.INF
	for i in range(n + 1):
		var a := from_angle + sweep * (float(i) / float(n))
		var p := ((centre + Vector2.RIGHT.rotated(a) * radius) / PX).floor() * PX
		if p == last:
			continue
		last = p
		cv.draw_rect(Rect2(p, Vector2(s, s)), col)
