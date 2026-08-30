extends Node
## Sedí plošší kotva vedle už vybraných Phase 0 kusů? 8 kandidátů z
## assets/raw/anchor_flat/ (mode=pro, BEZ style_character_id — kandidát na
## NOVOU kotvu, ne variace staré, viz tools/anchor_flat_candidates.py) vedle
## vybraného prop_focus_core cand_00 a focus_timer cand_04.
##
##   godot --path <proj> --main-scene res://scenes/_shot_anchor_flat.tscn
##
## NENÍ `--headless` — jako každý `_shot_*.gd` potřebuje skutečnou viewport texturu.
##
## Syrové PNG, žádná paleta (reduce_colors se na kandidáty, které se ještě
## nevybíraly, zbytečně neplatí — stejná disciplína jako u
## _shot_phase0_candidates.gd). NEVYBÍRÁ, NEHODNOTÍ nic.

const OUT_PATH := "res://.dev/screenshots/anchor_flat_candidates.png"
const WINDOW_UPSCALE := 4.0
const SHEET_W := 2200.0

## (skupina, cesta, popisek) — "referencni" skupina jsou už vybrané Phase 0 kusy,
## "kandidat" je jeden ze 8 nových. Oddělené sekce, aby bylo hned vidět, co se s čím
## srovnává, ne 10 stejně důležitých dlaždic v jedné řadě.
const REFERENCE: Array[Dictionary] = [
	{"path": "res://assets/raw/prop_focus_core/cand_00.png", "label": "prop_focus_core cand_00 (vybráno)"},
	{"path": "res://assets/raw/focus_timer/cand_04.png", "label": "focus_timer cand_04 (vybráno)"},
]
const CANDIDATE_COUNT := 8
const CANDIDATE_DIR := "res://assets/raw/anchor_flat"

var completed := false


static func _load_png(path: String) -> Image:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var bytes := f.get_buffer(f.get_length())
	f.close()
	var img := Image.new()
	return img if img.load_png_from_buffer(bytes) == OK else null


static func _save(img: Image, path: String) -> void:
	var dir := path.get_base_dir()
	if dir != "" and not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	if img.save_png(path) != OK:
		printerr("_shot_anchor_flat: zapis selhal: ", path)
		return
	print("ulozeno %s  (%dx%d)" % [path, img.get_width(), img.get_height()])


func _load_group(items: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for it: Dictionary in items:
		var img := _load_png(it["path"])
		if img == null:
			print("  CHYBI %s" % it["path"])
			continue
		out.append({
			"label": "%s  %dpx" % [it["label"], img.get_width()],
			"tex": ImageTexture.create_from_image(img),
			"w": img.get_width(), "h": img.get_height(),
		})
	return out


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var scale := Data.pixel_scale() * WINDOW_UPSCALE
	print("== plossi kotva vs. vybrane Phase 0 kusy ==  meritko %.0fx" % scale)

	var reference := _load_group(REFERENCE)
	var candidates: Array[Dictionary] = []
	for i in range(CANDIDATE_COUNT):
		candidates.append({
			"path": "%s/cand_%02d.png" % [CANDIDATE_DIR, i],
			"label": "anchor_flat cand_%02d" % i,
		})
	candidates = _load_group(candidates)
	print("  reference: %d, kandidati: %d" % [reference.size(), candidates.size()])

	var sv := SubViewport.new()
	sv.transparent_bg = false
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(sv)
	var painter := Sheet.new()
	painter.reference = reference
	painter.candidates = candidates
	painter.draw_scale = scale
	painter.sheet_w = SHEET_W
	sv.add_child(painter)
	await get_tree().process_frame
	sv.size = painter.computed_size()

	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw

	var img := sv.get_texture().get_image()
	_save(img, OUT_PATH)

	completed = true
	get_tree().quit(0)


class Sheet extends Node2D:
	var reference: Array[Dictionary] = []
	var candidates: Array[Dictionary] = []
	var draw_scale := 4.0
	var sheet_w := 2200.0

	const MARGIN := 40.0
	const CELL_GAP := 40.0
	const ROW_GAP := 34.0
	const SECTION_GAP := 60.0
	const LABEL_H := 20.0
	const LABEL_FONT_SIZE := 13

	var _size := Vector2(sheet_w, 500.0)

	func _ready() -> void:
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_layout()
		queue_redraw()

	func computed_size() -> Vector2i:
		return Vector2i(_size)

	func _cell_w(font: Font, it: Dictionary) -> float:
		var sprite_w := float(it["w"]) * draw_scale
		var label_w: float = font.get_string_size(
			it["label"], HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT_SIZE).x
		return maxf(sprite_w, label_w)

	## Spočítá výšku jedné vodorovně zabalené skupiny (titulek + řádky buněk).
	func _group_h(font: Font, title: String, items: Array[Dictionary]) -> float:
		var y := LABEL_H + 16.0
		var x := MARGIN
		var row_h := 0.0
		for it: Dictionary in items:
			var cw := _cell_w(font, it)
			var h := LABEL_H + float(it["h"]) * draw_scale
			if x > MARGIN and x + cw > MARGIN + sheet_w - MARGIN:
				x = MARGIN
				y += row_h + ROW_GAP
				row_h = 0.0
			x += cw + CELL_GAP
			row_h = maxf(row_h, h)
		return y + row_h

	func _layout() -> void:
		var font := ThemeDB.fallback_font
		var y := MARGIN
		y += _group_h(font, "vybráno (Phase 0)", reference) + SECTION_GAP
		y += _group_h(font, "anchor_flat — 8 kandidátů, bez kotvy", candidates) + MARGIN
		_size = Vector2(sheet_w, y)

	func _draw() -> void:
		var font := ThemeDB.fallback_font
		draw_rect(Rect2(Vector2.ZERO, _size), Game.SQUARE_GROUND_COLOR)
		var y := MARGIN
		y = _draw_group(font, "vybráno (Phase 0)", reference, y) + SECTION_GAP
		_draw_group(font, "anchor_flat — 8 kandidátů, bez kotvy", candidates, y)

	func _draw_group(font: Font, title: String, items: Array[Dictionary], top: float) -> float:
		draw_string(font, Vector2(MARGIN, top + 16.0), title,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1, 1, 1))
		var y := top + LABEL_H + 16.0
		var x := MARGIN
		var row_h := 0.0
		var row_start_y := y
		for it: Dictionary in items:
			var cw := _cell_w(font, it)
			var h := float(it["h"]) * draw_scale
			var cell_h := LABEL_H + h
			if x > MARGIN and x + cw > MARGIN + sheet_w - MARGIN:
				x = MARGIN
				row_start_y += row_h + ROW_GAP
				row_h = 0.0
			_draw_cell(font, it, x, row_start_y, float(it["w"]) * draw_scale, h)
			x += cw + CELL_GAP
			row_h = maxf(row_h, cell_h)
		return row_start_y + row_h

	func _draw_cell(font: Font, it: Dictionary, x: float, y: float, w: float, h: float) -> void:
		draw_string(font, Vector2(x, y + 14.0), it["label"],
			HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT_SIZE, Color(0.9, 0.92, 0.96))
		draw_texture_rect(it["tex"], Rect2(Vector2(x, y + LABEL_H), Vector2(w, h)), false)
