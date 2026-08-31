extends Node
## render-fx: "cheap fake-perspective" test — bere STEJNÝ topdown mockup jazyk (barvy
## z tools/flat_terrain.py, viz _shot_topdown_mockup.gd) a zkouší nejlevnější možnou
## iluzi hloubky: dlaždice zmáčknuté o ~12 % ve svislém směru (SQUASH_FACTOR).
##
## NEZÁVISLÉ na bodech 1-3 tohohle úkolu (pivot/stín/y-sort) — je to čistě o GEOMETRII
## DESKY, ne o ukotvení jednotek, které řeší _shot_defender_pivot.gd. Obě varianty
## (normální i zmáčknutá) kreslí STEJNÉ jednotkové značky (barevná tečka + malá
## kontaktní elipsa pod ní, na stejných buňkách se stejným seedem), aby šlo přímo
## srovnat "jen deska" vs. "deska + zmáčknutí" bez žádné jiné proměnné.
##
## Čistě pixel-buffer Image, žádný živý Game/sprite render (na rozdíl od
## _shot_defender_pivot.gd, které potřebuje skutečný viewport) — jde spustit i
## --headless. Pořád --main-scene, ne --script, kvůli Data autoloadu.
##
## Nekreslí verdikt, jen fotí obě varianty vedle sebe k porovnání.
##
## Spuštění:
##   godot --headless --path <proj> --main-scene res://scenes/_shot_squashed_tiles.tscn

const OUT_DIR := ".dev/screenshots"
## Přesně ty hodnoty, které tools/flat_terrain.py maluje na TOP FACE živého iso
## terénu (docs/art/iso_bible.md §2b) — viz _shot_topdown_mockup.gd, odkud je toto
## přebírá beze změny, aby oba mockupy zůstaly vizuálně srovnatelné.
const GROUND := Color8(20, 17, 41)
const LANE := Color8(78, 52, 16)
const TOP := Color8(184, 165, 135)
const SPAWN_TINT := Color8(0xC7, 0x0D, 0x53)
const OBJECTIVE_TINT := Color8(0x7D, 0xEF, 0x39)

## Rodinové barvy zjednodušené na dvě tečky — CLAUDE.md: "Habity kulaté a teplé,
## distrakce ostré a studeně jedovaté". Přesné odstíny z data/defenders/broccoli_knight
## (6fca3a) a data distractions/notification (ff3b30, viz distraction_animator.gd
## COLOR_NOTIF_BG), zase kvůli srovnatelnosti s existujícím artem.
const DEFENDER_DOT := Color8(0x6f, 0xca, 0x3a)
const DISTRACTION_DOT := Color8(0xff, 0x3b, 0x30)

const SQUASH_FACTOR := 0.88   ## "tiles vertically shortened by ~12%"
const UNIT_COUNT := 14
const SEED := 20260830

## Mirrors _shot_topdown_mockup.gd's KNOWN_BROKEN — level_1/level_2's objective sits
## outside the current grid (T6, blocked separately); not this task's concern.
const KNOWN_BROKEN := {1: true, 2: true}


func _ready() -> void:
	call_deferred("_run")


func _pick_level() -> LevelData:
	for i in range(Data.get_level_count()):
		var lv: LevelData = Data.get_level(i)
		if not KNOWN_BROKEN.has(lv.id):
			return lv
	return null


## Volná podlaha (ne high_ground, ne objective) — stejná selekce jako ostatní _shot_*.gd.
func _free_cells(lv: LevelData, cols: int, rows: int) -> Array[Vector2i]:
	var hg: Dictionary = {}
	for c in lv.high_ground:
		hg[c] = true
	var out: Array[Vector2i] = []
	for cy in range(rows):
		for cx in range(cols):
			var c := Vector2i(cx, cy)
			if not hg.has(c) and c != lv.objective:
				out.append(c)
	return out


## [buňka, je_obránce] dvojice, STEJNÉ pro obě vykreslení (flat i squashed) — jediná
## proměnná mezi nimi má být `squash`, ne rozestavění.
func _pick_units(free_cells: Array[Vector2i]) -> Array:
	var stride: int = maxi(1, free_cells.size() / UNIT_COUNT)
	var out: Array = []
	var idx := 0
	var i := 0
	while out.size() < UNIT_COUNT and idx < free_cells.size():
		out.append([free_cells[idx], i % 2 == 0])   # střídá obránce/distrakci
		idx += stride
		i += 1
	return out


## Pixelový rozsah [y0, výška) jednoho řádku dlaždic při daném zmáčknutí — počítáno
## z zaokrouhlených hranic (ne řádek*zaokrouhlená_výška), aby sousední řádky nikdy
## nenechaly mezeru ani se nepřekryly o víc než zaokrouhlovací chybu.
func _row_span(row: int, th: float) -> Vector2i:
	var y0 := int(round(float(row) * th))
	var y1 := int(round(float(row + 1) * th))
	return Vector2i(y0, maxi(1, y1 - y0))


func _render(lv: LevelData, tile: int, squash: float, units: Array) -> Image:
	var cols: int = Data.GRID.cols
	var rows: int = Data.GRID.rows
	var th: float = float(tile) * squash
	var total_h := _row_span(rows - 1, th)
	var img := Image.create(cols * tile, total_h.x + total_h.y, false, Image.FORMAT_RGB8)
	img.fill(GROUND)

	for cell: Vector2i in lv.path_cells:
		var span := _row_span(cell.y, th)
		img.fill_rect(Rect2i(cell.x * tile, span.x, tile, span.y), LANE)
	for cell: Vector2i in lv.high_ground:
		var span := _row_span(cell.y, th)
		img.fill_rect(Rect2i(cell.x * tile, span.x, tile, span.y), TOP)
	for rect: Rect2i in lv.spawn_zones:
		for y in range(rect.position.y, rect.position.y + rect.size.y):
			var span := _row_span(y, th)
			img.fill_rect(Rect2i(rect.position.x * tile, span.x, rect.size.x * tile, span.y), SPAWN_TINT)
	var obj_span := _row_span(lv.objective.y, th)
	img.fill_rect(Rect2i(lv.objective.x * tile, obj_span.x, tile, obj_span.y), OBJECTIVE_TINT)

	# Jednotkové značky: barevná tečka nad malou tmavou kontaktní elipsou, obojí
	# zmáčknuté stejným `squash` jako deska — stejný "stín ukotvuje ke zmáčknuté
	# podlaze" princip jako DistractionAnimator/DefenderUnit, jen zjednodušený na
	# ploché tvary místo sprite artu.
	for entry in units:
		var cell: Vector2i = entry[0]
		var is_def: bool = entry[1]
		var span := _row_span(cell.y, th)
		var cx: float = cell.x * tile + tile * 0.5
		var cy: float = float(span.x) + float(span.y) * 0.5
		_draw_ellipse(img, Vector2(cx, cy + tile * 0.22), tile * 0.32, tile * 0.32 * squash * 0.45, Color(0, 0, 0, 0.5))
		_draw_ellipse(img, Vector2(cx, cy - tile * 0.05), tile * 0.26, tile * 0.26 * squash, DEFENDER_DOT if is_def else DISTRACTION_DOT)

	return img


func _draw_ellipse(img: Image, center: Vector2, rx: float, ry: float, col: Color) -> void:
	if rx <= 0.0 or ry <= 0.0:
		return
	var x0: int = int(floor(center.x - rx))
	var x1: int = int(ceil(center.x + rx))
	var y0: int = int(floor(center.y - ry))
	var y1: int = int(ceil(center.y + ry))
	for y in range(maxi(0, y0), mini(img.get_height(), y1 + 1)):
		for x in range(maxi(0, x0), mini(img.get_width(), x1 + 1)):
			var dx: float = (float(x) - center.x) / rx
			var dy: float = (float(y) - center.y) / ry
			if dx * dx + dy * dy <= 1.0:
				if col.a >= 1.0:
					img.set_pixel(x, y, col)
				else:
					var under := img.get_pixel(x, y)
					img.set_pixel(x, y, under.lerp(col, col.a))


func _save(img: Image, path: String) -> void:
	var dir := path.get_base_dir()
	if dir != "" and not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	if img.save_png(path) != OK:
		printerr("_shot_squashed_tiles: uložení selhalo: ", path)
		return
	print("_shot_squashed_tiles: %s  %dx%d" % [path, img.get_width(), img.get_height()])


func _run() -> void:
	var lv := _pick_level()
	if lv == null:
		printerr("_shot_squashed_tiles: žádný použitelný level (všechny KNOWN_BROKEN?)")
		get_tree().quit(1)
		return
	var tile: int = Data.GRID.get("tile", 32)
	print("-- level %d (%s), tile=%d, squash=%.2f --" % [lv.id, lv.display_name, tile, SQUASH_FACTOR])

	var free_cells := _free_cells(lv, Data.GRID.cols, Data.GRID.rows)
	var units := _pick_units(free_cells)
	var n_def: int = units.filter(func(e): return e[1]).size()
	print("_shot_squashed_tiles: %d jednotkových značek (%d obránci, %d distrakce)" %
		[units.size(), n_def, units.size() - n_def])

	var flat := _render(lv, tile, 1.0, units)
	_save(flat, "%s/squashed_tiles_flat.png" % OUT_DIR)
	var flat_squint: Image = flat.duplicate()
	flat_squint.resize(maxi(1, flat.get_width() / 4), maxi(1, flat.get_height() / 4), Image.INTERPOLATE_NEAREST)
	_save(flat_squint, "%s/squashed_tiles_flat_squint.png" % OUT_DIR)

	var squashed := _render(lv, tile, SQUASH_FACTOR, units)
	_save(squashed, "%s/squashed_tiles_88pct.png" % OUT_DIR)
	var squashed_squint: Image = squashed.duplicate()
	squashed_squint.resize(maxi(1, squashed.get_width() / 4), maxi(1, squashed.get_height() / 4), Image.INTERPOLATE_NEAREST)
	_save(squashed_squint, "%s/squashed_tiles_88pct_squint.png" % OUT_DIR)

	print("\nhotovo")
	get_tree().quit(0)
