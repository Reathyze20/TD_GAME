extends Node
## Brána fáze 0: obě postavy NA JEDNOM boardu vedle sebe, v herním měřítku.
##
##   godot --path <proj> --main-scene res://scenes/_shot_phase0.tscn
##
## NENÍ `--headless` — potřebuje skutečnou viewport texturu, jako každý `_shot_*`.
##
## PROČ VEDLE SEBE A NE JEDNOTLIVĚ. Konzistence rodiny se nedá posoudit na
## samostatných náhledech — dva sprity, každý sám o sobě přijatelný, můžou vedle sebe
## vypadat jako z jiné hry (jiná tloušťka obrysu, jiná výška očí, jiné pásmo jasu).
## Proto je `broccoli_knight` a `focus_timer` na jedné desce, na stejném podkladu,
## ve stejném měřítku, se společnou linií země.
##
## MĚŘÍTKO. `Data.pixel_scale()` je 1.0, ale hra renderuje 480×270 do okna 1920×1080,
## tedy celočíselný upscale 4×; na 1080p je jeden art pixel čtyři fyzické. Kreslí se
## proto `pixel_scale() * 4`, jinak by se posuzovala čtvrtinová velikost.
##
## Varianty (rozostřená/odbarvená/siluetová) používají tytéž tři funkce jako
## `_shot_readability.gd` — schválně stejné, aby byly snímky mezi sebou srovnatelné.

const OUT_DIR := "res://.dev/screenshots"
const SHEET := Vector2i(1920, 1080)
const WINDOW_UPSCALE := 4.0

## Dvojice, kterou brána posuzuje. `prop_focus_core` se kreslí taky, ale stranou —
## není to postava a do srovnání siluet rodiny nepatří.
const PAIR := ["broccoli_knight", "focus_timer"]
const EXTRA := ["prop_focus_core"]

## art_px podle STYLE_BIBLE.md §5 (kind). gen_px je to, co reálně přišlo z generátoru.
const ART_PX := {"broccoli_knight": 32, "focus_timer": 64, "prop_focus_core": 96}

var completed := false


static func _load_png(path: String) -> Image:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var bytes := f.get_buffer(f.get_length())
	f.close()
	var img := Image.new()
	return img if img.load_png_from_buffer(bytes) == OK else null


## Preferuje verzi po reduce_colors (paleta 48), jinak syrový kandidát.
static func _source_for(eid: String) -> String:
	var pal := "res://assets/raw/%s/cand_00_pal48.png" % eid
	var raw := "res://assets/raw/%s/cand_00.png" % eid
	if FileAccess.file_exists(pal):
		return pal
	return raw if FileAccess.file_exists(raw) else ""


# --- varianty: shodné s _shot_readability.gd, aby šly snímky srovnávat ---

func _blur(img: Image, factor: int = 10) -> Image:
	var out: Image = img.duplicate()
	var w := out.get_width()
	var h := out.get_height()
	out.resize(maxi(1, w / factor), maxi(1, h / factor), Image.INTERPOLATE_BILINEAR)
	out.resize(w, h, Image.INTERPOLATE_BILINEAR)
	return out


func _desaturate(img: Image) -> Image:
	var out: Image = img.duplicate()
	out.convert(Image.FORMAT_RGBA8)
	for y in range(out.get_height()):
		for x in range(out.get_width()):
			var c := out.get_pixel(x, y)
			var lum := c.r * 0.299 + c.g * 0.587 + c.b * 0.114
			out.set_pixel(x, y, Color(lum, lum, lum, c.a))
	return out


func _silhouette(img: Image, threshold: float = 0.45) -> Image:
	var out: Image = img.duplicate()
	out.convert(Image.FORMAT_RGBA8)
	for y in range(out.get_height()):
		for x in range(out.get_width()):
			var c := out.get_pixel(x, y)
			var lum := c.r * 0.299 + c.g * 0.587 + c.b * 0.114
			var v := 0.0 if lum < threshold else 1.0
			out.set_pixel(x, y, Color(v, v, v, c.a))
	return out


func _save(img: Image, path: String) -> void:
	var dir := path.get_base_dir()
	if dir != "" and not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	if img.save_png(path) != OK:
		printerr("_shot_phase0: zapis selhal: ", path)
		return
	print("  ulozeno %s" % path)


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var scale := Data.pixel_scale() * WINDOW_UPSCALE
	var rows: Array[Dictionary] = []
	print("== faze 0: dvojice na jednom boardu ==  meritko %.0fx" % scale)

	for eid: String in PAIR + EXTRA:
		var path := _source_for(eid)
		if path == "":
			print("  %-18s CHYBI zdroj" % eid)
			continue
		var src := _load_png(path)
		if src == null:
			print("  %-18s nelze nacist %s" % [eid, path])
			continue
		var art_px: int = ART_PX[eid]
		var art: Image = src.duplicate()
		if art.get_width() != art_px:
			art.resize(art_px, art_px, Image.INTERPOLATE_NEAREST)
		rows.append({
			"id": eid, "gen_px": src.get_width(), "art_px": art_px,
			"gen_tex": ImageTexture.create_from_image(src),
			"art_tex": ImageTexture.create_from_image(art),
			"gen_used": src.get_used_rect(), "art_used": art.get_used_rect(),
			"pal": path.ends_with("_pal48.png"),
			"in_pair": eid in PAIR,
		})
		print("  %-18s gen %dpx -> art %dpx   %s" % [
			eid, src.get_width(), art_px,
			"paleta48" if path.ends_with("_pal48.png") else "SYROVY"])

	var sv := SubViewport.new()
	sv.size = SHEET
	sv.transparent_bg = false
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(sv)
	var painter := Board.new()
	painter.rows = rows
	painter.draw_scale = scale
	sv.add_child(painter)

	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw

	var full := sv.get_texture().get_image()
	var prefix := OUT_DIR + "/phase0"
	_save(full, prefix + ".png")
	_save(_blur(full), prefix + "_blur.png")
	_save(_desaturate(full), prefix + "_gray.png")
	_save(_silhouette(full), prefix + "_silhouette.png")

	completed = true
	get_tree().quit(0)


## Deska: společná linie země, oba kusy na stejném podkladu, u každého gen i art.
class Board extends Node2D:
	var rows: Array[Dictionary] = []
	var draw_scale := 4.0

	const MARGIN := 56.0
	const TILE := 16.0
	const CELL_GAP := 44.0
	const GROUP_GAP := 110.0

	func _ready() -> void:
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	func _draw() -> void:
		var font := ThemeDB.fallback_font
		var sheet := Vector2(1920, 1080)
		draw_rect(Rect2(Vector2.ZERO, sheet), Game.SQUARE_GROUND_COLOR)

		# Jedna společná linie země pro celou dvojici — to je ta věc, kterou samostatné
		# náhledy neumí: stejná podlaha pod oběma, takže jde srovnat výška i posazení.
		var pair_rows: Array[Dictionary] = []
		var extra_rows: Array[Dictionary] = []
		for r: Dictionary in rows:
			if bool(r["in_pair"]):
				pair_rows.append(r)
			else:
				extra_rows.append(r)

		var tallest := 0.0
		for r: Dictionary in pair_rows:
			var u: Rect2i = r["gen_used"]
			tallest = maxf(tallest, float(u.size.y) * draw_scale)

		var base_y := MARGIN + 40.0 + tallest
		var wall_w := sheet.x - MARGIN * 2.0
		draw_rect(Rect2(MARGIN, base_y, wall_w, TILE * draw_scale),
			Game.SQUARE_TOP_COLOR)

		draw_string(font, Vector2(MARGIN, MARGIN - 14.0),
			"faze 0 — dvojice na jednom boardu, herni meritko %.0fx" % draw_scale,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.92, 0.94, 0.97))

		var x := MARGIN + 30.0
		for r: Dictionary in pair_rows:
			x = _draw_entity(font, r, x, base_y) + GROUP_GAP

		# prop_focus_core stranou, pod dvojicí — kreslí se, ale do srovnání siluet
		# rodiny nepatří (není to postava).
		if not extra_rows.is_empty():
			var y2 := base_y + TILE * draw_scale + 90.0
			var tall2 := 0.0
			for r: Dictionary in extra_rows:
				var u2: Rect2i = r["gen_used"]
				tall2 = maxf(tall2, float(u2.size.y) * draw_scale)
			var base2 := y2 + tall2
			draw_rect(Rect2(MARGIN, base2, wall_w, TILE * draw_scale),
				Game.SQUARE_TOP_COLOR)
			var x2 := MARGIN + 30.0
			for r: Dictionary in extra_rows:
				x2 = _draw_entity(font, r, x2, base2) + GROUP_GAP

	## gen i art vedle sebe, obojí spodkem OBSAHU na linii země. Vrací koncové x.
	func _draw_entity(font: Font, r: Dictionary, x: float, base_y: float) -> float:
		var id: String = r["id"]
		var gen_px: int = r["gen_px"]
		var art_px: int = r["art_px"]
		var cells: Array = [
			[r["gen_tex"], r["gen_used"], draw_scale, "gen %dpx" % gen_px],
			[r["art_tex"], r["art_used"], draw_scale, "art %dpx" % art_px],
		]
		# Třetí buňka jen když downsample vážně nastává — jinak by to byla tatáž kresba.
		if art_px != gen_px:
			cells.append([r["art_tex"], r["art_used"],
				draw_scale * float(gen_px) / float(art_px),
				"art %dpx @ stopa gen" % art_px])

		var start := x
		var cx := x
		for c: Array in cells:
			var tex: Texture2D = c[0]
			var used: Rect2i = c[1]
			var s: float = c[2]
			var label: String = c[3]
			# Zarovnat podle OBSAHU, ne podle okraje PNG — generátor kolem nechává
			# průhledný lem a kus by jinak "stál ve vzduchu".
			draw_texture_rect(tex, Rect2(
				cx - float(used.position.x) * s,
				base_y - float(used.end.y) * s,
				float(tex.get_width()) * s, float(tex.get_height()) * s), false)
			draw_string(font, Vector2(cx, base_y + 20.0), label,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.16, 0.14, 0.10))
			cx += float(used.size.x) * s + CELL_GAP

		var head := "%s%s" % [id, "" if bool(r["pal"]) else "  (SYROVY, bez palety)"]
		draw_string(font, Vector2(start, base_y + TILE * draw_scale + 26.0), head,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 1, 1))
		return cx - CELL_GAP
