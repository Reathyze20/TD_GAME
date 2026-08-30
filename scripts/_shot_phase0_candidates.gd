extends Node
## Kontaktní list VŠECH stažených kandidátů fáze 0 (28 = 4 prop_focus_core +
## 16 focus_timer + 8 broccoli_knight, z assets/raw/<entita>/cand_NN.png) —
## čistě mechanický nástroj pro porovnání, NEVYBÍRÁ a NEHODNOTÍ nic sám.
##
##   godot --path <proj> --main-scene res://scenes/_shot_phase0_candidates.tscn
##
## NENÍ `--headless` — jako každý `_shot_*.gd` potřebuje skutečnou viewport texturu.
##
## Dva výstupy, ne jeden:
##   .dev/screenshots/phase0_candidates_gen.png — každý kandidát tak, jak přišel
##     z generátoru (gen_px), v herním měřítku.
##   .dev/screenshots/phase0_candidates_art.png — týž kandidát PO downsamplu na
##     art_px (STYLE_BIBLE.md §5), pořád v herním měřítku — takže je vidět i
##     rozdíl ve skutečné velikosti na obrazovce, ne jen v kresbě.
## U focus_timer a prop_focus_core je art_px == gen_px (žádný downsample), takže
## se v druhém obrázku nezmění nic než popisek — to je záměr, ne chyba.
##
## Ke KAŽDÉMU kandidátovi patří jeho siluetová varianta přímo pod ním — plná
## černá výplň podle alfa masky (ne dvoutónový jasový práh jako v
## _shot_readability.gd; to je jiná otázka — "je silueta rozeznatelná", ne
## "kde je jas"). Nepoužívá se reduce_colors ani žádné jiné síťové volání:
## kandidáti se zobrazují syrově, jak jsou na disku — barevná korekce paletou
## je samostatná otázka od výběru tvaru, kterou tenhle list neřeší.

const OUT_DIR := "res://.dev/screenshots"
const WINDOW_UPSCALE := 4.0
const SHEET_W := 2200.0

const ENTITIES: Array[Dictionary] = [
	{"id": "prop_focus_core", "art_px": 96, "count": 4},
	{"id": "focus_timer", "art_px": 64, "count": 16},
	{"id": "broccoli_knight", "art_px": 32, "count": 8},
]

var completed := false


static func _load_png(path: String) -> Image:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var bytes := f.get_buffer(f.get_length())
	f.close()
	var img := Image.new()
	return img if img.load_png_from_buffer(bytes) == OK else null


## Plná černá výplň podle alfa masky — "je tenhle tvar rozeznatelný", ne
## "kde je jas" (to dělá _shot_readability.gd's dvoutónový _silhouette()).
static func _silhouette_fill(img: Image) -> Image:
	var out: Image = img.duplicate()
	out.convert(Image.FORMAT_RGBA8)
	for y in range(out.get_height()):
		for x in range(out.get_width()):
			var a := out.get_pixel(x, y).a
			out.set_pixel(x, y, Color(0.0, 0.0, 0.0, a))
	return out


static func _save(img: Image, path: String) -> void:
	var dir := path.get_base_dir()
	if dir != "" and not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	if img.save_png(path) != OK:
		printerr("_shot_phase0_candidates: zapis selhal: ", path)
		return
	print("  ulozeno %s  (%dx%d)" % [path, img.get_width(), img.get_height()])


func _ready() -> void:
	call_deferred("_run")


## Načte všechny kandidáty jedné entity, volitelně downsamplované na art_px.
## Vrací pole {label, tex, sil_tex, w, h} — w/h jsou PLNÉ rozměry PNG (ne obálka
## obsahu): tahle mřížka neřeší dotyk podkladu jako _shot_contact_sheet.gd, jen
## rovnoměrné buňky, takže ořez podle alfy by tu jen riskoval přesah do sousední
## buňky u kandidátů s nesouměrným okrajem.
func _load_entity(spec: Dictionary, downsample: bool) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var eid: String = spec["id"]
	var count: int = spec["count"]
	var art_px: int = spec["art_px"]
	for i in range(count):
		var path := "res://assets/raw/%s/cand_%02d.png" % [eid, i]
		var src := _load_png(path)
		if src == null:
			print("  %-18s cand_%02d CHYBI (%s)" % [eid, i, path])
			continue
		var shown: Image = src
		if downsample and src.get_width() != art_px:
			shown = src.duplicate()
			shown.resize(art_px, art_px, Image.INTERPOLATE_NEAREST)
		var sil := _silhouette_fill(shown)
		out.append({
			# Bez id entity: to uz nese nadpis sekce, a u nejmensich spritu
			# (broccoli_knight 32px -> bunka 128px) by zdvojene id popisek
			# roztahlo za hranici bunky do sousedni.
			"label": "cand_%02d  %dpx" % [i, shown.get_width()],
			"tex": ImageTexture.create_from_image(shown),
			"sil_tex": ImageTexture.create_from_image(sil),
			"w": shown.get_width(),
			"h": shown.get_height(),
		})
	return out


func _run() -> void:
	var scale := Data.pixel_scale() * WINDOW_UPSCALE
	print("== faze 0: kontaktni list vsech kandidatu ==  meritko %.0fx" % scale)

	for pass_name in ["gen", "art"]:
		var downsample: bool = pass_name == "art"
		var groups: Array[Dictionary] = []
		var total := 0
		for spec: Dictionary in ENTITIES:
			var items := _load_entity(spec, downsample)
			groups.append({"id": spec["id"], "items": items})
			total += items.size()
			print("  [%s] %-18s %d kandidatu" % [pass_name, spec["id"], items.size()])

		var sv := SubViewport.new()
		sv.transparent_bg = false
		sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(sv)
		var painter := Sheet.new()
		painter.groups = groups
		painter.draw_scale = scale
		painter.sheet_w = SHEET_W
		sv.add_child(painter)
		# Velikost viewportu se počítá AŽ v painter._ready(), protože se odvíjí
		# od skutečného obsahu (28 kandidátů v proměnlivých velikostech) — jinak
		# by 1920x1080 pro focus_timer samotné (16 kandidátů, dva řádky se
		# siluetou pod každým) nestačilo a obsah by tiše přetekl mimo snímek.
		await get_tree().process_frame
		sv.size = painter.computed_size()

		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw

		var img := sv.get_texture().get_image()
		_save(img, "%s/phase0_candidates_%s.png" % [OUT_DIR, pass_name])
		sv.queue_free()
		await get_tree().process_frame

	completed = true
	get_tree().quit(0)


## Vykreslení: jedna sekce na entitu, kandidáti zabalení do řádků; v každé
## buňce kandidát nahoře, jeho siluetová varianta přímo pod ním.
class Sheet extends Node2D:
	var groups: Array[Dictionary] = []
	var draw_scale := 4.0
	var sheet_w := 2200.0

	const MARGIN := 40.0
	const CELL_GAP := 36.0
	const ROW_GAP := 30.0
	const SECTION_GAP := 70.0
	const LABEL_H := 20.0
	const LABEL_FONT_SIZE := 13
	const MID_GAP := 12.0  # mezera mezi spritem a jeho siluetou ve stejné bunce

	var _size := Vector2(sheet_w, 600.0)

	func _ready() -> void:
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_layout()
		queue_redraw()

	func computed_size() -> Vector2i:
		return Vector2i(_size)

	## Šířka BUŇKY (pro layout/wrap), ne spritu — u nejmenších spritů (32px)
	## je popisek širší než obrázek, a bez týhle kontroly by přetekl do
	## sousední buňky (přesně to se stalo v prvním běhu u broccoli_knight/art).
	func _cell_w(font: Font, it: Dictionary) -> float:
		var sprite_w := float(it["w"]) * draw_scale
		var label_w: float = font.get_string_size(
			it["label"], HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT_SIZE).x
		return maxf(sprite_w, label_w)

	## Spočítá layout (pozice + celkovou výšku) BEZ vykreslení — volá se z
	## _ready(), aby computed_size() měla co vrátit dřív, než se SubViewport
	## zvětší na potřebnou velikost.
	func _layout() -> void:
		var font := ThemeDB.fallback_font
		var y := MARGIN
		for g: Dictionary in groups:
			y += LABEL_H + 10.0
			var items: Array = g["items"]
			var x := MARGIN
			var row_h := 0.0
			for it: Dictionary in items:
				var cell_w := _cell_w(font, it)
				var h := float(it["h"]) * draw_scale
				var cell_h := LABEL_H + h + MID_GAP + LABEL_H + h
				if x > MARGIN and x + cell_w > MARGIN + sheet_w - MARGIN:
					x = MARGIN
					y += row_h + ROW_GAP
					row_h = 0.0
				x += cell_w + CELL_GAP
				row_h = maxf(row_h, cell_h)
			y += row_h + SECTION_GAP
		_size = Vector2(sheet_w, y)

	func _draw() -> void:
		var font := ThemeDB.fallback_font
		draw_rect(Rect2(Vector2.ZERO, _size), Game.SQUARE_GROUND_COLOR)

		var y := MARGIN
		for g: Dictionary in groups:
			var eid: String = g["id"]
			draw_string(font, Vector2(MARGIN, y + 16.0), eid,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1, 1, 1))
			y += LABEL_H + 10.0

			var items: Array = g["items"]
			var x := MARGIN
			var row_h := 0.0
			var row_start_y := y
			for it: Dictionary in items:
				var cell_w := _cell_w(font, it)
				var h := float(it["h"]) * draw_scale
				var cell_h := LABEL_H + h + MID_GAP + LABEL_H + h
				if x > MARGIN and x + cell_w > MARGIN + sheet_w - MARGIN:
					x = MARGIN
					row_start_y += row_h + ROW_GAP
					row_h = 0.0
				_draw_cell(font, it, x, row_start_y, float(it["w"]) * draw_scale, h)
				x += cell_w + CELL_GAP
				row_h = maxf(row_h, cell_h)
			y = row_start_y + row_h + SECTION_GAP

	func _draw_cell(font: Font, it: Dictionary, x: float, y: float, w: float, h: float) -> void:
		var tex: Texture2D = it["tex"]
		var sil: Texture2D = it["sil_tex"]
		var label: String = it["label"]

		draw_string(font, Vector2(x, y + 14.0), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT_SIZE, Color(0.9, 0.92, 0.96))
		var sprite_y := y + LABEL_H
		draw_texture_rect(tex, Rect2(Vector2(x, sprite_y), Vector2(w, h)), false)

		var sil_label_y := sprite_y + h + MID_GAP
		draw_string(font, Vector2(x, sil_label_y + 14.0), "silueta",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.68, 0.72, 0.8))
		var sil_y := sil_label_y + LABEL_H
		draw_texture_rect(sil, Rect2(Vector2(x, sil_y), Vector2(w, h)), false)
