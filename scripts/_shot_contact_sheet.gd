extends Node
## Kontaktní list pro bránu fáze 0 (docs/art/STYLE_BIBLE.md `<!-- gen:gate0 -->`,
## vygenerovaný do docs/art/GENERATION_PLAN.md). Brána žádá doslova tohle: každý kus
## fáze 0 ve dvou verzích vedle sebe — jak přišel z generátoru (`gen_px`) a po
## downsamplu na `art_px` — v herním měřítku, na plochém terénu z `flat_terrain.py`
## (ne na bílém pozadí), snímek v 1920×1080.
##
##   godot --path <proj> --main-scene res://scenes/_shot_contact_sheet.tscn
##
## NENÍ `--headless` — jako každý jiný `_shot_*.gd` v repu potřebuje skutečnou
## viewport texturu.
##
## PROČ TO EXISTUJE DŘÍV NEŽ ART. Downsample 64→32 je brána pro celý zbytek rejstříku
## (520 generací): dokud se neschválí, negeneruje se ani jeden další kus. Měřidlo
## postavené až po dodání vzorku by znamenalo další kolo stavění nástrojů uprostřed
## odpočítávání do 13. 9. Harness proto běží i teď, bez artu — chybějící kus vykreslí
## jako čitelný placeholder s cestou, kam se soubor čeká, takže je vidět rozvržení
## a je co opravit dřív, než na tom bude záležet.
##
## MĚŘÍTKO. `Data.pixel_scale()` je dnes 1.0 (`ISO_PIXEL_SCALE`), ale hra se renderuje
## v 480×270 a okno je 1920×1080 (`window_width_override`), tedy celočíselný upscale
## 4×. Na 1080p monitoru je proto jeden art pixel čtyři fyzické. Aby snímek ukazoval,
## co hráč doopravdy vidí, kreslí se `pixel_scale() * WINDOW_UPSCALE`.

const OUT_PATH := "res://build/contact_sheet_phase0.png"
const SHEET := Vector2i(1920, 1080)

## 480×270 logická plocha vs. 1920×1080 okno (project.godot `window_width_override`).
const WINDOW_UPSCALE := 4.0

## Práh z brány: tělo nesmí ležet do ±60 součtu jasu od podkladu, na kterém stojí.
const SUBSTRATE_SUM := 484.0  # Game.SQUARE_TOP_COLOR (184+165+135) == flat_terrain.py TOP
const BRIGHTNESS_MARGIN := 60.0

## Fáze 0 přesně jak ji vyjmenovává GENERATION_PLAN.md (3 kusy, 80 generací).
## `sources` jsou kandidátní cesty v pořadí, v jakém se hledá — první existující vyhraje.
## Pipeline dnes stahuje přes `tools/pixellab.py pull --out build/pixellab/<id>`;
## instalované cesty jsou tam jako druhá možnost, aby list fungoval i po instalaci.
## AŽ DORAZÍ PRVNÍ DÁVKA: když se soubor jmenuje jinak, uprav jen tenhle seznam.
const ENTITIES: Array[Dictionary] = [
	{
		"id": "prop_focus_core", "gen_px": 96, "art_px": 96,
		"sources": ["res://build/pixellab/prop_focus_core.png",
			"res://assets/props/focus_core.png"],
	},
	{
		"id": "focus_timer", "gen_px": 64, "art_px": 64,
		"sources": ["res://build/pixellab/focus_timer.png",
			"res://assets/towers/head_focus_timer.png"],
	},
	{
		"id": "broccoli_knight", "gen_px": 64, "art_px": 32,
		"sources": ["res://build/pixellab/broccoli_knight.png",
			"res://assets/defenders/broccoli_knight_walk_frame_1.png",
			"res://assets/defenders/broccoli_knight_frame_1.png"],
	},
]


## Vrátí první existující cestu ze seznamu, jinak "".
static func _first_existing(paths: Array) -> String:
	for p: String in paths:
		if FileAccess.file_exists(p):
			return p
	return ""


## Načte PNG bajtově, ne přes load() — soubory pod build/ nejsou importované jako
## Godot resources, takže load() by na nich selhal.
static func _load_png(path: String) -> Image:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var bytes := f.get_buffer(f.get_length())
	f.close()
	var img := Image.new()
	if img.load_png_from_buffer(bytes) != OK:
		return null
	return img


## Průměrný součet kanálů přes NEPRŮHLEDNÉ pixely — tělo, ne okolní průhledno.
## Vrací -1.0, když je obrázek celý průhledný (nemá co měřit).
static func _body_sum(img: Image) -> float:
	var total := 0.0
	var n := 0
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var c := img.get_pixel(x, y)
			if c.a < 0.5:
				continue
			total += (c.r + c.g + c.b) * 255.0
			n += 1
	return -1.0 if n == 0 else total / float(n)


## Půlení PŘESNĚ JEDNOU, NEAREST — plán §8: dvakrát půlený obrázek se rozpadne.
static func _downsample(src: Image, art_px: int) -> Image:
	var out := src.duplicate() as Image
	if out.get_width() != art_px:
		out.resize(art_px, art_px, Image.INTERPOLATE_NEAREST)
	return out


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var scale := Data.pixel_scale() * WINDOW_UPSCALE

	# Data pro kreslení + měření na stdout (brána má i strojově ověřitelnou půlku).
	var rows: Array[Dictionary] = []
	print("== kontaktní list fáze 0 ==  pixel_scale=%.2f × upscale=%.0f → %.0f×" % [
		Data.pixel_scale(), WINDOW_UPSCALE, scale])

	for e: Dictionary in ENTITIES:
		var id: String = e["id"]
		var gen_px: int = e["gen_px"]
		var art_px: int = e["art_px"]
		var path := _first_existing(e["sources"])

		var row := {"id": id, "gen_px": gen_px, "art_px": art_px, "path": path,
			"gen_tex": null, "art_tex": null, "note": "",
			"gen_used": Rect2i(), "art_used": Rect2i()}

		if path == "":
			row["note"] = "CHYBÍ — čeká se na %s" % String(e["sources"][0])
			print("  %-18s CHYBÍ (%d→%d)  hledáno: %s" % [
				id, gen_px, art_px, ", ".join(PackedStringArray(e["sources"]))])
			rows.append(row)
			continue

		var src := _load_png(path)
		if src == null:
			row["note"] = "NELZE NAČÍST %s" % path
			print("  %-18s NELZE NAČÍST %s" % [id, path])
			rows.append(row)
			continue

		var art := _downsample(src, art_px)
		row["gen_tex"] = ImageTexture.create_from_image(src)
		row["art_tex"] = ImageTexture.create_from_image(art)
		# Obálka NEPRŮHLEDNÝCH pixelů. Bez ní by se kus zarovnal podle okraje PNG, a
		# protože generátor kolem obsahu nechává průhledný lem, "stál" by ve vzduchu —
		# přesně ten dotyk podkladu, který brána měří, by snímek ukazoval falešně.
		row["gen_used"] = src.get_used_rect()
		row["art_used"] = art.get_used_rect()

		# Brána, strojová půlka: jas těla proti podkladu, na kterém to stojí.
		var bs := _body_sum(art)
		var delta: float = absf(bs - SUBSTRATE_SUM)
		var verdict := "?"
		if bs >= 0.0:
			verdict = "OK" if delta > BRIGHTNESS_MARGIN else "POD PRAHEM"
		row["note"] = "%dpx zdroj %dx%d · jas těla %.0f (podklad %.0f, Δ%.0f) %s" % [
			src.get_width(), src.get_width(), src.get_height(),
			bs, SUBSTRATE_SUM, delta, verdict]
		print("  %-18s %d→%d  jas %.0f  Δ%.0f vs %.0f  %s   %s" % [
			id, gen_px, art_px, bs, delta, SUBSTRATE_SUM, verdict, path])
		rows.append(row)

	# 1920×1080 napevno přes SubViewport — brána to výslovně žádá a nechceme být
	# závislí na tom, jakou velikost okna zrovna dá OS.
	var sv := SubViewport.new()
	sv.size = SHEET
	sv.transparent_bg = false
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(sv)

	var painter := Sheet.new()
	painter.rows = rows
	painter.draw_scale = scale
	sv.add_child(painter)

	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw

	var img := sv.get_texture().get_image()
	var dir := OUT_PATH.get_base_dir()
	if dir != "" and not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	if img.save_png(OUT_PATH) != OK:
		printerr("_shot_contact_sheet: zápis selhal: ", OUT_PATH)
		get_tree().quit(1)
		return
	print("_shot_contact_sheet: %s  %dx%d" % [OUT_PATH, img.get_width(), img.get_height()])
	get_tree().quit(0)


## Vlastní kreslení listu. Oddělené do Node2D, protože _draw() existuje jen na
## CanvasItem a kořen harnessu je prostý Node (konvence ostatních _test_/_shot_).
class Sheet extends Node2D:
	var rows: Array[Dictionary] = []
	var draw_scale := 4.0

	const MARGIN := 48.0
	const TITLE_H := 46.0   # titulek + poznámka nad skupinou
	const WALL_H := 28.0    # pás podkladu; nižší než dlaždice, aby se tři kusy vešly
	const CELL_GAP := 40.0
	const GROUP_GAP := 96.0
	const LINE_GAP := 28.0
	const SHEET := Vector2(1920, 1080)

	func _ready() -> void:
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	## Buňky jedné entity: [texture, scale, label]. Šířky/výšky se počítají z OBÁLKY
	## obsahu, ne z rozměru PNG — proto se tu obálka vrací s sebou.
	func _cells_of(r: Dictionary) -> Array:
		var out: Array = []
		var gen_tex: Texture2D = r["gen_tex"]
		var art_tex: Texture2D = r["art_tex"]
		if gen_tex == null or art_tex == null:
			return out
		var gen_px: int = r["gen_px"]
		var art_px: int = r["art_px"]
		out.append([gen_tex, r["gen_used"], draw_scale, "gen %dpx" % gen_px])
		out.append([art_tex, r["art_used"], draw_scale, "art %dpx (shipuje)" % art_px])
		# Třetí buňka jen když downsample vůbec nastává — u 96→96 a 64→64 by to byla
		# tatáž kresba potřetí. Zvětšená na stopu gen verze: jediný poctivý pohled na
		# to, co půlení sebralo, protože obě pak měří na obrazovce totéž.
		if art_px != gen_px:
			out.append([art_tex, r["art_used"],
				draw_scale * float(gen_px) / float(art_px),
				"art %dpx @ stopa gen" % art_px])
		return out

	func _group_size(cells: Array) -> Vector2:
		var w := 0.0
		var h := 0.0
		for c: Array in cells:
			var used: Rect2i = c[1]
			var s: float = c[2]
			w += float(used.size.x) * s + CELL_GAP
			h = maxf(h, float(used.size.y) * s)
		return Vector2(maxf(w - CELL_GAP, 0.0), h)

	func _draw() -> void:
		var font := ThemeDB.fallback_font
		# Podklad: plochý terén přesně barvami, které kreslí sama hra (Game.SQUARE_*),
		# tedy i tytéž, co zapisuje tools/flat_terrain.py.
		draw_rect(Rect2(Vector2.ZERO, SHEET), Game.SQUARE_GROUND_COLOR)

		var avail := SHEET.x - MARGIN * 2.0
		var x := MARGIN
		var y := MARGIN
		var line_h := 0.0

		for r: Dictionary in rows:
			var cells := _cells_of(r)
			# Chybějící kus dostane nenulovou výšku, jinak by se placeholder tiskl
			# přes poznámku nad ním.
			var gs := _group_size(cells) if not cells.is_empty() else Vector2(420.0, 96.0)
			var group_w: float = maxf(gs.x, 420.0)
			var group_h := TITLE_H + gs.y + WALL_H

			# Zabalení na nový řádek, když se skupina nevejde. Tři kusy fáze 0 se ve 4×
			# měřítku pod sebe do 1080 px nevejdou (96px prop je 384 px vysoký), takže
			# stohovat řádky natvrdo nelze — tohle je skládá vedle sebe, dokud je místo.
			if x > MARGIN and x + group_w > MARGIN + avail:
				x = MARGIN
				y += line_h + LINE_GAP
				line_h = 0.0

			_draw_group(font, r, cells, x, y, group_w, gs.y)
			line_h = maxf(line_h, group_h)
			x += group_w + GROUP_GAP

		var used_h := y + line_h + MARGIN
		if used_h > SHEET.y:
			draw_string(font, Vector2(MARGIN, SHEET.y - 16.0),
				"POZOR: obsah přetéká (%.0f > %.0f px) — uber entitu nebo měřítko" % [
					used_h, SHEET.y],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1.0, 0.45, 0.4))

	func _draw_group(font: Font, r: Dictionary, cells: Array, x: float, y: float,
			group_w: float, sprites_h: float) -> void:
		var id: String = r["id"]
		var note: String = r["note"]
		var base_y := y + TITLE_H + sprites_h

		# Pás podkladu pod celou skupinou — to je ta "plochá zeď", které se má kus dotýkat.
		draw_rect(Rect2(x, base_y, group_w, WALL_H), Game.SQUARE_TOP_COLOR)

		draw_string(font, Vector2(x, y + 20.0), id,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 23, Color(1, 1, 1))
		draw_string(font, Vector2(x, y + 40.0), note,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.72, 0.76, 0.82))

		if cells.is_empty():
			draw_string(font, Vector2(x, base_y - 10.0), "[ bez artu — placeholder ]",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Color(0.95, 0.55, 0.45))
			return

		var cx := x
		for c: Array in cells:
			var tex: Texture2D = c[0]
			var used: Rect2i = c[1]
			var s: float = c[2]
			var label: String = c[3]
			# Posun tak, aby OBSAH (ne okraj PNG) seděl levým spodním rohem na (cx, base_y).
			var dst := Rect2(
				cx - float(used.position.x) * s,
				base_y - float(used.end.y) * s,
				float(tex.get_width()) * s,
				float(tex.get_height()) * s)
			draw_texture_rect(tex, dst, false)
			draw_string(font, Vector2(cx, base_y + 20.0), label,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.16, 0.14, 0.10))
			cx += float(used.size.x) * s + CELL_GAP
