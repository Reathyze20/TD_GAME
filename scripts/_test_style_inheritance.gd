extends Node
## Dědičnost stylu: je opravdu v OBJEDNÁVCE, a dá se vůbec změřit, že funguje?
##
## Proč tenhle harness vznikl (G0, 4. 9. 2026). `tools/gen_art_prompts.py` psal
## dědičnost stylu jako VĚTU do sloupce „závislost" — „style_images = hotové PNG
## entity X" — zatímco `params` toho záznamu žádné `style_images` neměly. Dokument
## tedy tvrdil, že se dědí, objednávka nic takového neposílala, a rozdíl by se poznal
## až na staženém výsledku, po utracených generacích. Je to přesně ta třída chyby,
## kterou už jednou v tomhle repu zaplatila fáze 0 (A0b: plán psaný proti jinému
## nástroji, 3-4 validation errors na volání), jen o patro tišší: tohle by se
## neodmítlo, tohle by se vyrobilo — jen špatně.
##
## Harness proto stojí na dvou nohách a obě musí držet:
##
##   SMLOUVA (body 1-4) — plán skutečně nese referenci v parametrech, ne v próze,
##   posílá ji nástrojem, který ji umí, neposílá dvojici polí, kterou živé schéma
##   vylučuje, a jedno volání nese jedinou referenci.
##
##   MĚŘENÍ (body 5-6) — obě metriky, kterými se dědičnost posuzuje, na skutečných
##   souborech opravdu rozlišují „ze stejného zdroje" od „odjinud". Bez toho by
##   smlouva hlídala formu a nikdo by nevěděl, jestli má obsah.
##
## Žádný práh se sem neopisuje. Práh soudržnosti rodiny se čte z STYLE_BIBLE.md
## (`gen:failure_modes`, řádek „styl, soudržnost rodiny"), práh průhlednosti z
## `tools/check_style_failure_modes.py` (`ALPHA_THRESH`, jediné místo v repu, kde to
## číslo doopravdy je — bible slovo „alpha" neobsahuje) a vylučující se dvojice polí
## z `tools/pixellab_schema.json`. Stejná stavba jako `check_terrain_contrast.py`
## vůči `flat_terrain.py`.
##
## Pouštět přes --main-scene (scenes/_test_style_inheritance.tscn), NIKDY přes
## --script: v --script režimu nejsou autoloady zaregistrované.

const PLAN_PATH := "res://docs/art/GENERATION_PLAN.md"
const BIBLE_PATH := "res://docs/art/STYLE_BIBLE.md"
const SCHEMA_PATH := "res://tools/pixellab_schema.json"
const FAILURE_MODES_PATH := "res://tools/check_style_failure_modes.py"
const RAW_ROOT := "res://assets/raw"

## Skupina kandidátů = jeden adresář v assets/raw/, tedy JEDNO volání, tedy jeden
## zdroj stylu. Měří se stav PO paletě (`*_pal48.png`), protože v něm se art
## nasazuje do hry — surová generace má rozptyl barev, který paleta stejně srovná,
## a gate na barvy by na ní měřil něco, co se nikdy nikam nedostane.
const GROUP_SUFFIX := "_pal48.png"

## Kruh vykreslený do rastru vyjde touhle definicí kompaktnosti kolem 0.74-0.77
## (naměřeno sourozeneckou implementací v tools/check_style_failure_modes.py pro
## poloměry 8, 12, 16 a 24 px). Není to 1.0, protože obvod se počítá po čtyřech
## sousedech a diagonální krok tím podhodnotí. Pásmo je kolem naměřeného, ne kolem
## teoretického: hlídá, že se vzorec v tomhle souboru chová jako ten v Pythonu.
const DISC_MIN := 0.60
const DISC_MAX := 0.90

var completed := false
var fails := 0


func _ready() -> void:
	var wd := Timer.new()
	wd.wait_time = 60.0
	wd.one_shot = true
	add_child(wd)
	wd.timeout.connect(func():
		if not completed:
			print("FAILED: watchdog fired")
			get_tree().quit(1))
	wd.start()
	call_deferred("_run")


func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("  ok   %s %s" % [label, detail])
	else:
		fails += 1
		print("  FAIL %s %s" % [label, detail])


func _read(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path)


## Řádky markdown tabulky z bloku <!-- gen:klic --> jako pole slovníků podle záhlaví.
func _bible_table(bible: String, key: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var re := RegEx.create_from_string("(?s)<!--\\s*gen:%s\\s*-->(.*?)<!--\\s*/gen:%s\\s*-->" % [key, key])
	var m := re.search(bible)
	if m == null:
		return out
	var head: PackedStringArray = []
	for raw in m.get_string(1).split("\n"):
		var line := raw.strip_edges()
		if not line.begins_with("|"):
			continue
		var cells: PackedStringArray = []
		for c in line.trim_prefix("|").trim_suffix("|").split("|"):
			cells.append(c.strip_edges())
		var is_sep := true
		for c in cells:
			if c.replace("-", "").replace(":", "") != "":
				is_sep = false
				break
		if is_sep:
			continue
		if head.is_empty():
			head = cells
			continue
		var row := {}
		for i in range(mini(head.size(), cells.size())):
			row[head[i]] = cells[i]
		out.append(row)
	return out


## Jeden záznam plánu. Kromě parametrů se čte i dávka — style_images je parametr
## VOLÁNÍ, takže „kdo s kým sdílí volání" je součást toho, co se dá porušit.
func _parse_plan(plan: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var head_re := RegEx.create_from_string("^\\d+\\.\\s+`([a-z0-9_]+)`\\s+—\\s+([a-z_]+),\\s+(\\d+)\\s+px")
	var order_re := RegEx.create_from_string("^(\\d+)\\.")
	var json_re := RegEx.create_from_string("(?s)```json\\n(.*?)\\n```")
	var tool_re := RegEx.create_from_string("\\|\\s*nástroj\\s*\\|\\s*`mcp__pixellab__(\\w+)`\\s*\\|")
	var batch_re := RegEx.create_from_string("\\|\\s*dávka\\s*\\|\\s*(?:`([a-z0-9_]+)`|([^|]+))\\s*\\|")
	for chunk in plan.split("\n### "):
		var head := head_re.search(chunk)
		if head == null:
			continue
		var jm := json_re.search(chunk)
		var toolm := tool_re.search(chunk)
		var bm := batch_re.search(chunk)
		var om := order_re.search(chunk)
		out.append({
			"id": head.get_string(1),
			"kind": head.get_string(2),
			"order": 0 if om == null else int(om.get_string(1)),
			"tool": "" if toolm == null else toolm.get_string(1),
			"batch": "" if bm == null else bm.get_string(1),
			"params": {} if jm == null else (JSON.parse_string(jm.get_string(1)) as Dictionary),
		})
	return out


# --------------------------------------------------------------------- měření

## Neprůhledná maska: 1 pro pixel s alfou >= prahu. Práh přichází z
## tools/check_style_failure_modes.py, aby obě implementace měřily týž tvar.
func _mask_of(img: Image, alpha_min: int) -> PackedByteArray:
	var w := img.get_width()
	var h := img.get_height()
	var data := img.get_data()
	var mask := PackedByteArray()
	mask.resize(w * h)
	for i in range(w * h):
		mask[i] = 1 if data[i * 4 + 3] >= alpha_min else 0
	return mask


## Kompaktnost = obvod^2 / (4*pi*plocha). Obvodový pixel je neprůhledný pixel,
## který má aspoň jednoho ze čtyř sousedů průhledného nebo mimo plátno. Kruh vyjde
## kolem 0.75, roztřepený tvar roste. Tatáž definice jako
## tools/check_style_failure_modes.py's compactness() — STYLE_BIBLE.md §12d.
func _compactness(mask: PackedByteArray, w: int, h: int) -> float:
	var area := 0
	var perimeter := 0
	for y in range(h):
		for x in range(w):
			if mask[y * w + x] == 0:
				continue
			area += 1
			var edge := false
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx := x + d.x
				var ny := y + d.y
				if nx < 0 or ny < 0 or nx >= w or ny >= h or mask[ny * w + nx] == 0:
					edge = true
					break
			if edge:
				perimeter += 1
	if area == 0:
		return 0.0
	return float(perimeter * perimeter) / (4.0 * PI * float(area))


## Počet unikátních RGB trojic mezi neprůhlednými pixely („pět stylů", §12d).
func _unique_colors(img: Image, mask: PackedByteArray) -> int:
	var w := img.get_width()
	var h := img.get_height()
	var data := img.get_data()
	var seen := {}
	for i in range(w * h):
		if mask[i] == 0:
			continue
		seen[(int(data[i * 4]) << 16) | (int(data[i * 4 + 1]) << 8) | int(data[i * 4 + 2])] = true
	return seen.size()


## PNG ze surových bajtů, ne přes load(): měří se soubor na disku, ne to, co z něj
## udělal importér (komprese a případný resize by z počtu barev udělaly fikci).
func _load_png(path: String) -> Image:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return null
	var img := Image.new()
	if img.load_png_from_buffer(bytes) != OK:
		return null
	img.convert(Image.FORMAT_RGBA8)
	return img


func _mean(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var s := 0.0
	for v in values:
		s += float(v)
	return s / float(values.size())


func _run() -> void:
	var plan := _read(PLAN_PATH)
	var bible := _read(BIBLE_PATH)
	var schema_text := _read(SCHEMA_PATH)
	var fm_text := _read(FAILURE_MODES_PATH)
	_check("GENERATION_PLAN.md se načetl", plan.length() > 0, "%d znaků" % plan.length())
	_check("STYLE_BIBLE.md se načetl", bible.length() > 0, "%d znaků" % bible.length())
	_check("tools/pixellab_schema.json se načetl", schema_text.length() > 0)
	_check("tools/check_style_failure_modes.py se načetl", fm_text.length() > 0)
	if plan.is_empty() or bible.is_empty() or schema_text.is_empty() or fm_text.is_empty():
		completed = true
		print("\nFAILED (%d failures) — bez zdrojů nemá smysl pokračovat" % fails)
		get_tree().quit(1)
		return

	var schema: Dictionary = JSON.parse_string(schema_text) as Dictionary
	_check("schéma se rozparsovalo", schema != null and not schema.is_empty())

	## Práh průhlednosti ze sourozenecké implementace, ne opsaný.
	var alpha_re := RegEx.create_from_string("(?m)^ALPHA_THRESH\\s*=\\s*(\\d+)")
	var alpha_m := alpha_re.search(fm_text)
	_check("ALPHA_THRESH se vyčetl z check_style_failure_modes.py", alpha_m != null)
	var alpha_min: int = 128 if alpha_m == null else int(alpha_m.get_string(1))
	print("  (ALPHA_THRESH = %d)" % alpha_min)

	## Práh soudržnosti rodiny z bible, ne opsaný.
	var cohesion := -1.0
	for row in _bible_table(bible, "failure_modes"):
		if row.get("brána", "") == "styl, soudržnost rodiny":
			var num := RegEx.create_from_string("(<=|>=|=)\\s*([\\d.]+)").search(row.get("prah", ""))
			if num != null:
				cohesion = float(num.get_string(2))
	_check("práh „styl, soudržnost rodiny" + "\" se vyčetl z bible", cohesion > 0.0,
		"<= %.0f" % cohesion)

	var base_of := {}
	var family_of := {}
	var kind_of := {}
	for row in _bible_table(bible, "forms"):
		base_of[row.get("id", "")] = row.get("base", "-")
		family_of[row.get("id", "")] = row.get("family", "-")
		kind_of[row.get("id", "")] = row.get("kind", "")
	var anchors := {}
	for row in _bible_table(bible, "anchors"):
		anchors[row.get("rodina", "")] = row.get("style_character_id", "")
	_check("bible: tabulka forem se načetla", base_of.size() > 5, "%d entit" % base_of.size())

	var records := _parse_plan(plan)
	_check("plán se rozparsoval", records.size() > 0, "%d záznamů" % records.size())
	var order_of := {}
	for r in records:
		order_of[r["id"]] = r["order"]

	print("\n-- 1. kdo podle bible dědí, nese referenci v PARAMETRECH volání --")
	var inheriting := 0
	for r in records:
		var base: String = str(base_of.get(r["id"], "-"))
		if base == "-" or base == "":
			continue
		if r["kind"] == "terrain":
			continue   # terén dědí druhým terénem v témž volání, ne referencí
		inheriting += 1
		var p: Dictionary = r["params"]
		var has_images: bool = p.has("style_images") and not (p["style_images"] as Array).is_empty()
		var has_anchor: bool = str(p.get("style_character_id", "")) != ""
		_check("%s dědí po %s a má to v parametrech" % [r["id"], base],
			has_images or has_anchor,
			"params nesou jen: " + ", ".join(PackedStringArray(p.keys())))
		if has_images:
			var first: Dictionary = (p["style_images"] as Array)[0]
			_check("%s: style_images míří na %s" % [r["id"], base],
				str(first.get("entity", "")) == base,
				"míří na '%s'" % str(first.get("entity", "")))
			_check("%s: reference je existující entita" % r["id"],
				base_of.has(str(first.get("entity", ""))))
		elif has_anchor:
			## Postava `style_images` v živém schématu nemá; rodinu jí drží kotva.
			## Musí to být kotva SPRÁVNÉ rodiny, jinak by „dědí" znamenalo „dědí po
			## někom jiném" a nikdo by to nepoznal.
			var want: String = str(anchors.get(str(family_of.get(r["id"], "-")), ""))
			_check("%s: kotva je z rodiny %s" % [r["id"], family_of.get(r["id"], "-")],
				want != "" and str(p["style_character_id"]) == want,
				str(p.get("style_character_id", "")))
	_check("plán vůbec nějakou dědičnost obsahuje", inheriting > 0,
		"%d dědících záznamů" % inheriting)

	print("\n-- 2. žádné volání neposílá dvojici, kterou živé schéma vylučuje --")
	## `create_1_direction_object` říká doslova „Cannot be set together with
	## style_images" u `size`. Dvojice se sem neopisují, čtou se ze zamrazeného
	## schématu (tools/fetch_pixellab_schema.py je vytáhne z prose descriptionů).
	var conflict_checks := 0
	for r in records:
		var spec: Dictionary = schema.get(r["tool"], {}) as Dictionary
		for pair in (spec.get("conflicts", []) as Array):
			var both := true
			for key in (pair as Array):
				if not (r["params"] as Dictionary).has(key):
					both = false
			conflict_checks += 1
			_check("%s (%s): neposílá %s současně" % [r["id"], r["tool"],
				" + ".join(PackedStringArray(pair as Array))], not both)
	_check("aspoň jedna vylučující dvojice se opravdu kontrolovala", conflict_checks > 0,
		"%d kontrol" % conflict_checks)

	print("\n-- 3. jedno volání = jedna stylová reference --")
	## style_images je parametr volání, ne položky: čtyři objekty v jednom
	## `item_descriptions` sdílí JEDNU referenci. Dávka, která by mísila zdroje, je
	## objednávka, kterou API splnit neumí.
	var refs_by_batch := {}
	for r in records:
		var p: Dictionary = r["params"]
		if str(r["batch"]) == "" or not p.has("style_images"):
			continue
		var arr: Array = p["style_images"] as Array
		if arr.is_empty():
			continue
		var ent: String = str((arr[0] as Dictionary).get("entity", ""))
		if not refs_by_batch.has(r["batch"]):
			refs_by_batch[r["batch"]] = {}
		(refs_by_batch[r["batch"]] as Dictionary)[ent] = true
	for batch in refs_by_batch:
		var found: Dictionary = refs_by_batch[batch]
		_check("dávka %s nese jedinou referenci" % batch, found.size() == 1,
			"nese: " + ", ".join(PackedStringArray(found.keys())))
	_check("nějaká dávka se stylovou referencí v plánu je", refs_by_batch.size() > 0,
		"%d dávek" % refs_by_batch.size())

	print("\n-- 4. zdroj stylu je v plánu dřív než ten, kdo z něj dědí --")
	## Dědit z něčeho, co se teprve bude generovat, znamená poslat referenci na
	## soubor, který neexistuje. Pořadí v plánu je jediná obrana.
	for r in records:
		var p: Dictionary = r["params"]
		if not p.has("style_images") or (p["style_images"] as Array).is_empty():
			continue
		var ent: String = str(((p["style_images"] as Array)[0] as Dictionary).get("entity", ""))
		_check("%s (#%d) jde až za %s (#%d)" % [r["id"], r["order"], ent,
			int(order_of.get(ent, -1))],
			order_of.has(ent) and int(order_of[ent]) < int(r["order"]))

	print("\n-- 5. metriky opravdu rozlišují „ze stejného zdroje" + "\" od „odjinud" + "\" --")
	## Skupina = adresář v assets/raw/, tedy jedno volání, tedy jeden zdroj stylu.
	var groups := {}
	for dir_name in DirAccess.get_directories_at(RAW_ROOT):
		var files: Array[String] = []
		for f in DirAccess.get_files_at("%s/%s" % [RAW_ROOT, dir_name]):
			if f.ends_with(GROUP_SUFFIX):
				files.append("%s/%s/%s" % [RAW_ROOT, dir_name, f])
		files.sort()
		if files.size() >= 2:
			groups[dir_name] = files
	_check("skupin kandidátů po paletě je aspoň dvojice", groups.size() >= 2,
		"%d skupin: %s" % [groups.size(), ", ".join(PackedStringArray(groups.keys()))])

	var comp := {}          # skupina -> pole kompaktností
	var colors := {}        # skupina -> pole počtů barev
	for g in groups:
		var cs: Array[float] = []
		var us: Array[int] = []
		for path in (groups[g] as Array[String]):
			var img := _load_png(path)
			if img == null:
				_check("%s: PNG se načetlo" % path, false)
				continue
			var mask := _mask_of(img, alpha_min)
			cs.append(_compactness(mask, img.get_width(), img.get_height()))
			us.append(_unique_colors(img, mask))
		comp[g] = cs
		colors[g] = us

	## a) barvy: uvnitř jednoho zdroje stylu drží rodina pohromadě (bible, §12d).
	for g in groups:
		var us: Array[int] = colors[g]
		if us.is_empty():
			continue
		var lo: int = us.min()
		var hi: int = us.max()
		_check("%s: rozptyl barev %d (<= %.0f)" % [g, hi - lo, cohesion],
			float(hi - lo) <= cohesion, "%d..%d barev, %d kandidátů" % [lo, hi, us.size()])

	## b) kompaktnost: dvojice z téhož zdroje si je bližší než dvě náhodné.
	var within: Array[float] = []
	var cross: Array[float] = []
	var keys: Array = groups.keys()
	keys.sort()
	for i in range(keys.size()):
		var a: Array[float] = comp[keys[i]]
		for x in range(a.size()):
			for y in range(x + 1, a.size()):
				within.append(absf(a[x] - a[y]))
		for j in range(i + 1, keys.size()):
			var b: Array[float] = comp[keys[j]]
			for x2 in a:
				for y2 in b:
					cross.append(absf(x2 - y2))
	var mean_within := _mean(within)
	var mean_cross := _mean(cross)
	_check("dvojice mají co porovnávat", within.size() > 0 and cross.size() > 0,
		"%d uvnitř, %d napříč" % [within.size(), cross.size()])
	_check("kompaktnost: uvnitř zdroje blíž než napříč zdroji",
		within.size() > 0 and cross.size() > 0 and mean_within < mean_cross,
		"uvnitř %.4f, napříč %.4f (%.2fx)" % [mean_within, mean_cross,
			mean_cross / maxf(mean_within, 0.0001)])

	print("\n-- 6. kalibrace vzorce: kruh musí vyjít jako kruh --")
	## Bez tohohle by bod 5 mohl projít i s rozbitým vzorcem — dvě čísla ze stejné
	## chybné funkce si jsou pořád bližší než dvě z různých skupin.
	var side := 64
	var disc := PackedByteArray()
	disc.resize(side * side)
	for y in range(side):
		for x in range(side):
			var dx := float(x) - 31.5
			var dy := float(y) - 31.5
			disc[y * side + x] = 1 if dx * dx + dy * dy <= 16.0 * 16.0 else 0
	var disc_c := _compactness(disc, side, side)
	_check("kruh r=16 má kompaktnost v pásmu %.2f-%.2f" % [DISC_MIN, DISC_MAX],
		disc_c >= DISC_MIN and disc_c <= DISC_MAX, "%.4f" % disc_c)

	completed = true
	print("\n%s (%d failures, %d záznamů plánu, %d skupin kandidátů)"
		% ["PASSED" if fails == 0 else "FAILED", fails, records.size(), groups.size()])
	get_tree().quit(1 if fails > 0 else 0)
