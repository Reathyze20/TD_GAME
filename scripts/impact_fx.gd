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
## Rezim "rozplacnute rajce". Zapina ho Projectile u strel, ktere maji vlastni sprite
## (assets/towers/shot_*.png) -- kulicka, co doleti a zmizi v bilem zabesku, vypada
## jako kulka. Duzina musi CAKNOUT, a hlavne DOPREDU: splat, ktery strika rovnomerne
## do kruhu, cte jako vybuch, ne jako naraz.
var _splat := false
var _splat_dir := Vector2.RIGHT

## `travel` je smer letu strely; kdyz neni nulovy, prepne se na splat.
##
## `hold` je sev pro harnessy: nespusti se tween, takze si volajici rizne `_progress`
## sam a muze vykreslit libovolnou fazi. Bez nej se faze daji chytat jen nacasovanim
## snimku a vsechny vyjdou v prvni desetine zivota, kde je splat jeste bod.
func play(color: Color, scale_mult: float = 1.0, travel: Vector2 = Vector2.ZERO,
		hold: bool = false) -> void:
	_color = color
	_scale = scale_mult
	_progress = 0.0
	_particles.clear()
	_splat = travel.length_squared() > 0.0001
	if _splat:
		_splat_dir = travel.normalized()

	var count := 9 if scale_mult <= 1.0 else 14
	if _splat:
		count = 12
	for i in range(count):
		var angle := randf_range(0.0, TAU)
		var speed := randf_range(50.0, 130.0) * scale_mult
		var dir := Vector2.RIGHT.rotated(angle) * speed
		if _splat:
			# Vejir +-70 stupnu kolem letu, a ZPLOSTELY: deska je 2:1, takze duzina
			# odletujici "na sever" ma na obrazovce urazit polovinu. Bez toho by kazdy
			# splat vypadal jako kruh polozeny na stojato.
			var base: float = _splat_dir.angle()
			var a: float = base + randf_range(-1.22, 1.22)
			var sp: float = randf_range(40.0, 150.0) * scale_mult
			dir = Vector2(cos(a), sin(a) * 0.5) * sp
		# Whole art pixels only — a death burst throws a few double-size chunks.
		var size := 1
		if scale_mult > 1.0 and randf() < 0.4:
			size = 2
		_particles.append({"dir": dir, "size": size})

	if hold:
		queue_redraw()
		return

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

	if _splat:
		# SMOUHA: zplostela skvrna, ktera rychle vyskoci a pak bledne. Zadny bily
		# stred -- rajce nesviti, rozplacne se. Svetly bod je jen lesk na duzine.
		# Skvrna je nejvetsi HNED a pak bledne. Prvni verze ji nechavala rust pres
		# 0,18 zivota a cetla se jako kroužek, co se rozjizdi -- rozplacnute rajce se
		# nerozjizdi, ono placne.
		var grow: float = minf(1.0, _progress / 0.06)
		var rx: float = (5.0 + 8.0 * grow) * _scale
		for i in range(12):
			var a: float = TAU * float(i) / 12.0 + 0.31
			_px(Vector2(cos(a) * rx, sin(a) * rx * 0.5), 1.0,
				Color(_color.r, _color.g, _color.b, alpha * 0.85))
		if _progress < 0.5:
			var cu: float = 3.0 if _progress < 0.2 else 2.0
			_px(Vector2.ZERO, cu, Color(_color.r, _color.g, _color.b, alpha))
			_px(Vector2(-PX, -PX), 1.0, _color.lightened(0.5))
	else:
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
