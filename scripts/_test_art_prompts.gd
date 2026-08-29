extends Node
## Smlouva mezi docs/art/STYLE_BIBLE.md, data/ a docs/art/GENERATION_PLAN.md.
##
## Plán generování artu je GENEROVANÝ soubor (tools/gen_art_prompts.py) a jako každý
## generovaný soubor v tomhle repu zvětrá v tichosti — ROSTER.md to udělal třikrát, viz
## varování v jeho hlavičce. Tenhle harness je proto to samé, co dělá verify.sh pro
## ROSTER.md, jen o vrstvu výš: nekontroluje, že plán je čerstvý (to dělá
## `python tools/gen_art_prompts.py --check`, který verify.sh pouští vedle), ale že je
## VNITŘNĚ SPRÁVNÝ — že žádný prompt neztratil povinný suffix, nesáhl po opuštěné kotvě
## ani si nevymyslel vlastní paletu, a že plán a data/ pokrývají přesně tytéž entity.
##
## Proč to čte markdown a ne nějaký JSON: plán je to, co člověk reálně čte a podle čeho
## objednává. Kdyby se testoval mezistupeň, mohl by projít test a přesto by v dokumentu,
## ze kterého se objednává, chyběl suffix.
##
## Pouštět přes --main-scene (scenes/_test_art_prompts.tscn), NIKDY přes --script:
## v --script režimu nejsou autoloady zaregistrované. Tenhle harness sice žádný autoload
## nepotřebuje, ale platí to pro celou rodinu a odchylka by mátla.

const PLAN_PATH := "res://docs/art/GENERATION_PLAN.md"
const BIBLE_PATH := "res://docs/art/STYLE_BIBLE.md"

## Které složky v data/ mají mít vizuální protějšek a pod jakými `kind` se v plánu
## objevují. Musí souhlasit s DATA_KINDS v tools/gen_art_prompts.py — schválně to je
## napsané dvakrát: kdyby to test importoval z generátoru, ověřoval by generátor sám
## proti sobě.
const DATA_KINDS := {
	"distractions": ["distraction", "distraction_boss"],
	"habits": ["habit"],
	"defenders": ["defender"],
}

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


func _bible_fence(bible: String, key: String, lang: String) -> String:
	var re := RegEx.create_from_string(
		"(?s)<!--\\s*gen:%s\\s*-->.*?```%s\\n(.*?)\\n```" % [key, lang])
	var m := re.search(bible)
	return "" if m == null else m.get_string(1).strip_edges()


## Jeden záznam plánu: id, kind, deklarovaná velikost, parametry (JSON) a prompt.
func _parse_plan(plan: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var head_re := RegEx.create_from_string("^\\d+\\.\\s+`([a-z0-9_]+)`\\s+—\\s+([a-z_]+),\\s+(\\d+)\\s+px")
	var json_re := RegEx.create_from_string("(?s)```json\\n(.*?)\\n```")
	var text_re := RegEx.create_from_string("(?s)```text\\n(.*?)\\n```")
	for chunk in plan.split("\n### "):
		var head := head_re.search(chunk)
		if head == null:
			continue
		var jm := json_re.search(chunk)
		var tm := text_re.search(chunk)
		out.append({
			"id": head.get_string(1),
			"kind": head.get_string(2),
			"size": int(head.get_string(3)),
			"params": {} if jm == null else (JSON.parse_string(jm.get_string(1)) as Dictionary),
			"prompt": "" if tm == null else tm.get_string(1),
			"raw": chunk,
		})
	return out


## Živá id z data/<folder>/*.tres. Fallback na jméno souboru je nutný: Godot vynechává
## vlastnost rovnou defaultu ve skriptu, takže notification.tres nemá řádek `id` vůbec.
func _data_ids(folder: String) -> PackedStringArray:
	var ids: PackedStringArray = []
	var id_re := RegEx.create_from_string("(?m)^id\\s*=\\s*&?\"([^\"]+)\"")
	for f in DirAccess.get_files_at("res://data/%s" % folder):
		if not f.ends_with(".tres"):
			continue
		var text := _read("res://data/%s/%s" % [folder, f])
		var m := id_re.search(text)
		ids.append(m.get_string(1) if m != null else f.trim_suffix(".tres"))
	ids.sort()
	return ids


func _run() -> void:
	var plan := _read(PLAN_PATH)
	var bible := _read(BIBLE_PATH)
	_check("GENERATION_PLAN.md existuje a není prázdný", plan.length() > 0,
		"%d znaků" % plan.length())
	_check("STYLE_BIBLE.md existuje a není prázdný", bible.length() > 0,
		"%d znaků" % bible.length())
	if plan.is_empty() or bible.is_empty():
		completed = true
		print("\nFAILED (%d failures) — bez obou souborů nemá smysl pokračovat" % fails)
		get_tree().quit(1)
		return

	var suffix := _bible_fence(bible, "suffix", "suffix")
	var sizes := {}
	var gen_sizes := {}
	for row in _bible_table(bible, "sizes"):
		sizes[row.get("kind", "")] = int(row.get("art_px", "0"))
		gen_sizes[row.get("kind", "")] = int(row.get("gen_px", "0"))
	var anchors := {}
	## Zakázané kotvy se nevyjmenovávají tady — poznají se podle `plati_pro = nic`
	## v bibli. Kdyby byl v testu pevný seznam, přibyla by jednou čtvrtá odpískaná
	## kotva do bible a test by o ní nevěděl.
	var forbidden: PackedStringArray = []
	for row in _bible_table(bible, "anchors"):
		var id: String = row.get("style_character_id", "")
		anchors[row.get("rodina", "")] = id
		if row.get("plati_pro", "") == "nic":
			forbidden.append(id)
	var family_of := {}
	var kind_of := {}
	for row in _bible_table(bible, "forms"):
		family_of[row.get("id", "")] = row.get("family", "-")
		kind_of[row.get("id", "")] = row.get("kind", "")
	## Které kindy jsou POSTAVY — odvozeno z bible, ne z ručního seznamu, aby přidání
	## dalšího druhu postavy nezpůsobilo tiše neotestovaný prompt.
	var character_kinds := {}
	for row in _bible_table(bible, "tools"):
		if row.get("mcp_tool", "").ends_with("create_character"):
			character_kinds[row.get("kind", "")] = true

	_check("bible: povinný suffix se načetl", suffix.length() > 40, "%d znaků" % suffix.length())
	_check("bible: tabulka velikostí se načetla", sizes.size() >= 5, "%d tříd" % sizes.size())
	_check("bible: tabulka kotev se načetla", anchors.size() >= 2, "%d řádků" % anchors.size())
	_check("bible: aspoň jedna kotva je označená jako odpískaná", forbidden.size() >= 1,
		"%d zakázaných" % forbidden.size())
	_check("bible: aspoň jeden kind je postava", character_kinds.size() > 0,
		", ".join(PackedStringArray(character_kinds.keys())))

	var records := _parse_plan(plan)
	_check("plán se rozparsoval na záznamy", records.size() > 0, "%d záznamů" % records.size())

	print("\n-- 1. každý prompt pro postavu má style_character_id ze správné rodiny --")
	var char_count := 0
	for r in records:
		if not character_kinds.has(r["kind"]):
			continue
		char_count += 1
		var want_family: String = family_of.get(r["id"], "-")
		var want_id: String = anchors.get(want_family, "")
		var got: String = str(r["params"].get("style_character_id", ""))
		_check("%s (%s) má kotvu rodiny '%s'" % [r["id"], r["kind"], want_family],
			want_id != "" and got == want_id, got if got != "" else "CHYBÍ")
	_check("nějaké postavy vůbec v plánu jsou", char_count > 0, "%d postav" % char_count)

	print("\n-- 2. žádná odpískaná kotva se v plánu neobjevuje --")
	for bad in forbidden:
		_check("kotva %s má tvar uuid" % bad, bad.length() == 36)
		## Celý soubor, ne jen prompty: kotva se do volání dostane PARAMETREM, takže
		## kontrola omezená na text promptu by ji minula přesně tam, kde škodí.
		_check("celý GENERATION_PLAN.md neobsahuje %s" % bad, not plan.contains(bad))

	print("\n-- 3. každý prompt obsahuje povinný suffix --")
	for r in records:
		_check("%s má suffix" % r["id"], String(r["prompt"]).contains(suffix))

	print("\n-- 4. žádný prompt si nedefinuje vlastní paletu --")
	var hex_re := RegEx.create_from_string("#[0-9a-fA-F]{6}")
	for r in records:
		var body := String(r["prompt"])
		_check("%s neobsahuje hex barvu" % r["id"], hex_re.search(body) == null,
			"" if hex_re.search(body) == null else hex_re.search(body).get_string(0))
		_check("%s nezmiňuje palette_32" % r["id"], not body.to_lower().contains("palette_32"))
	_check("palette_32 se neobjevuje nikde v celém plánu",
		not plan.to_lower().contains("palette_32"))

	print("\n-- 5. velikosti odpovídají tabulce ze STYLE_BIBLE.md --")
	for r in records:
		var want: int = int(sizes.get(r["kind"], -1))
		_check("%s (%s) má %d px" % [r["id"], r["kind"], want], r["size"] == want,
			"plán říká %d" % r["size"])
		## Deklarace v nadpisu je jedna věc; to, co se reálně pošle do MCP, druhá — a
		## u postav se ta dvě čísla LIŠÍ schválně (objednává se na dvojnásobku a půlí
		## se přesně jednou, STYLE_BIBLE.md §5). Kdyby test kontroloval jen jedno,
		## půlicí krok by mohl tiše zmizet a distrakce by se objednaly na 32 px, což
		## kotva `62772f73-…` (64px postava) odmítne.
		var want_gen: int = int(gen_sizes.get(r["kind"], -1))
		var p: Dictionary = r["params"]
		for key in ["size", "tile_size"]:
			if p.has(key):
				_check("%s posílá %s=%d (objednávka)" % [r["id"], key, want_gen],
					int(p[key]) == want_gen, "parametr je %s" % str(p[key]))
		_check("%s: objednávka je buď rovná cíli, nebo přesně dvojnásobek" % r["id"],
			want_gen == want or want_gen == want * 2, "%d -> %d" % [want_gen, want])

	print("\n-- 6. entity z data/ a záznamy v plánu se kryjí 1:1 --")
	var by_id := {}
	var dupes: PackedStringArray = []
	for r in records:
		if by_id.has(r["id"]):
			dupes.append(r["id"])
		by_id[r["id"]] = r
	_check("žádné id není v plánu dvakrát", dupes.is_empty(), ", ".join(dupes))

	for folder in DATA_KINDS:
		var kinds: Array = DATA_KINDS[folder]
		var on_disk := _data_ids(folder)
		var in_plan: PackedStringArray = []
		for r in records:
			if r["kind"] in kinds:
				in_plan.append(r["id"])
		in_plan.sort()
		var missing: PackedStringArray = []
		for id in on_disk:
			if not in_plan.has(id):
				missing.append(id)
		var extra: PackedStringArray = []
		for id in in_plan:
			if not on_disk.has(id):
				extra.append(id)
		_check("data/%s: každé .tres má záznam v plánu (%d)" % [folder, on_disk.size()],
			missing.is_empty(), "chybí: " + ", ".join(missing))
		_check("data/%s: každý záznam v plánu má své .tres (%d)" % [folder, in_plan.size()],
			extra.is_empty(), "navíc: " + ", ".join(extra))

	print("\n-- navíc: kind v plánu souhlasí s tabulkou forem v bibli --")
	for r in records:
		_check("%s má kind podle bible" % r["id"], kind_of.get(r["id"], "") == r["kind"],
			"bible: %s, plán: %s" % [kind_of.get(r["id"], "?"), r["kind"]])

	completed = true
	print("\n%s (%d failures, %d záznamů)"
		% ["PASSED" if fails == 0 else "FAILED", fails, records.size()])
	get_tree().quit(1 if fails > 0 else 0)
