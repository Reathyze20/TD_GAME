@tool
extends VBoxContainer
## Animation Lab: přehrává všechny sady jedné příšery vedle sebe, v té velikosti, v jaké
## je kreslí hra, a ladí dvě věci, které dělají sadu rozbitou.
##
## CO SE TU LADÍ
##
##   Rychlost  Snímky za sekundu, pro každou sadu zvlášť. Než tohle vzniklo, běžela celá
##             hra na jedné natvrdo zadané dvanáctce, takže osmiframová chůze a
##             šestnáctiframový útok byly nuceny do stejné kadence.
##
##   Posun     Posun jednotlivého framu v ARTOVÝCH pixelech. Tohle je lék na kmitání:
##             generátor centruje každý frame na jeho vlastní obálku, takže příšera, která
##             při chůzi rozpaží, ujíždí do strany, i když každý jednotlivý frame je v
##             pořádku. Posun to vrací zpátky na osu.
##
## CO SE TU JEN UKAZUJE
##
## Tabulka měr je detektor „pohledy k sobě nesedí". South, north a east vznikají odděleně
## a vracejí se v různých velikostech — příšera, jejíž východní pohled je o tři pixely
## nižší, se při zatáčení viditelně scvrkne. Ve hře to nikde nevidíš; tady je to sloupec.
##
## Vodicí linka jde přes všechny sloupce v jedné výšce, spočítaná z pohledu south. Kterýkoli
## pohled, co na ní nestojí nohama, je špatně zarovnaný.
##
## Zapisuje se JEN do AnimTuning (data/anim_tuning.tres). Na PNG tenhle panel nesahá.

const ART_DIR := "res://assets/distractions/"
const DEF_DIR := "res://data/distractions/"

## Sady v pořadí, v jakém se kreslí zleva doprava. Prázdný řetězec je south — tak se
## jmenuje sada, se kterou hra začínala, a proto nemá příponu.
const SETS := ["", "_north", "_east", "_west", "_attack", "_death"]
const SET_LABELS := {
	"": "south", "_north": "north", "_east": "east",
	"_west": "west", "_attack": "attack", "_death": "death",
}

## Musí sedět s DistractionAnimator.SPRITE_FPS / DEATH_FPS — obojí je tam 12.
const DEFAULT_FPS := 12.0
const MAX_FRAMES := 32

var _tuning: AnimTuning = null
var _dirty := false

var _ids: Array[String] = []
var _id := ""
var _sets: Dictionary = {}          ## suffix -> Array[Texture2D]
var _stats: Dictionary = {}         ## suffix -> Dictionary (viz _measure)
var _scale := 2.0                   ## celočíselné zvětšení, jaké použije hra
var _zoom := 2                      ## násobek navíc, jen pro čitelnost panelu

var _time := 0.0
var _playing := true
var _frame := 0                     ## krokování při pauze
var _sel := ""                      ## laděná sada

var _id_opt: OptionButton
var _stage: Control
var _grid: GridContainer
var _sel_opt: OptionButton
var _fps_slider: HSlider
var _fps_label: Label
var _frame_label: Label
var _off_x: SpinBox
var _off_y: SpinBox
var _save_btn: Button
var _status: Label


func _ready() -> void:
	name = "Animation Lab"
	_load_tuning()
	_build_ui()
	_ids = _scan_ids()
	for id in _ids:
		_id_opt.add_item(id)
	if not _ids.is_empty():
		_select_id(_ids[0])
	set_process(true)


func _process(delta: float) -> void:
	if not _playing or _sets.is_empty():
		return
	_time += delta
	_stage.queue_redraw()


# ---------------------------------------------------------------- data

func _load_tuning() -> void:
	if ResourceLoader.exists(AnimTuning.PATH):
		_tuning = load(AnimTuning.PATH) as AnimTuning
	if _tuning == null:
		_tuning = AnimTuning.new()
	_dirty = false


## Jména příšer se čtou ze SOUBORŮ, ne z data/distractions/*.tres. Tenhle panel je o
## artu — varianta `_b`, která ještě nemá vlastní .tres, se musí dát ladit taky, a sada
## bez framů nemá v seznamu co dělat, i kdyby .tres existoval.
func _scan_ids() -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(ART_DIR)
	if d == null:
		return out
	for f in d.get_files():
		if not f.ends_with("_frame_1.png"):
			continue
		var stem := f.substr(0, f.length() - "_frame_1.png".length())
		for s in SETS:
			if s != "" and stem.ends_with(s):
				stem = stem.substr(0, stem.length() - s.length())
				break
		if not out.has(stem):
			out.append(stem)
	out.sort()
	return out


## Načte jeden frame, i když ho Godot ještě nenaimportoval.
##
## Tenhle dvojí pokus není opatrnost navíc, je to hlavní scénář: hned po tom, co
## tools/sprite_cleanup.py přepíše PNG, ukazuje .import soubor na starý výřez v .godot/
## a `load()` selže, i když `ResourceLoader.exists()` hlásí ano. Bez čtení z disku by
## panel po každém přegenerování artu ukazoval prázdno až do restartu editoru.
func _load_tex(path: String) -> Texture2D:
	if not FileAccess.file_exists(path):
		return null
	if ResourceLoader.exists(path):
		var t := load(path)
		if t is Texture2D:
			return t
	var img := Image.new()
	if img.load(path) != OK:
		return null
	return ImageTexture.create_from_image(img)


func _load_frames(stem: String, suffix: String) -> Array[Texture2D]:
	var out: Array[Texture2D] = []
	for i in range(1, MAX_FRAMES + 1):
		var t := _load_tex(ART_DIR + "%s%s_frame_%d.png" % [stem, suffix, i])
		if t == null:
			break
		out.append(t)
	return out


## Herní zvětšení: DistractionAnimator._sprite_size() dělá `max(2, round(r * 2 / šířka))`.
## Kopíruje se to sem, aby panel ukazoval sprite v té velikosti, v jaké ho uvidí hráč —
## ladit zarovnání na jiném zoomu, než na jakém se to kreslí, nemá cenu.
func _game_scale(stem: String, tex: Texture2D) -> float:
	if tex == null or tex.get_width() <= 0:
		return 2.0
	var r := 9.0
	var p := DEF_DIR + stem + ".tres"
	if ResourceLoader.exists(p):
		var def := load(p) as DistractionData
		if def != null:
			r = def.radius
	return maxf(2.0, roundf(r * 2.0 / float(tex.get_width())))


func _image_of(tex: Texture2D) -> Image:
	var img := tex.get_image()
	if img != null and img.is_compressed():
		img.decompress()
	return img


## Míry jedné sady. Všechno se počítá ze siluety (alfa), protože právě silueta je to, co
## oko čte jako „velikost" a „kde ta příšera stojí".
func _measure(frames: Array[Texture2D], key: String) -> Dictionary:
	var out := {
		"n": frames.size(), "w": 0, "h": 0,
		"base_min": 0, "base_max": 0, "cx_min": 0.0, "cx_max": 0.0, "base_ref": 0,
		"per_frame": [],
	}
	if frames.is_empty():
		return out
	var offs := _tuning.offsets_for(key, frames.size())
	var first := true
	for i in range(frames.size()):
		var img := _image_of(frames[i])
		if img == null:
			continue
		var x0 := img.get_width()
		var x1 := -1
		var y0 := img.get_height()
		var y1 := -1
		var sx := 0.0
		var n := 0
		for y in range(img.get_height()):
			for x in range(img.get_width()):
				if img.get_pixel(x, y).a <= 0.125:
					continue
				x0 = mini(x0, x); x1 = maxi(x1, x)
				y0 = mini(y0, y); y1 = maxi(y1, y)
				sx += float(x); n += 1
		if n == 0:
			out["per_frame"].append({"base": 0, "cx": 0.0, "w": 0, "h": 0})
			continue
		# Naladěný posun se do měr započítá, jinak by tabulka pořád hlásila kmitání,
		# které jsi před chvílí srovnal.
		var off: Vector2i = offs[i]
		var base := y1 + off.y
		var cx := sx / float(n) + float(off.x)
		out["per_frame"].append({"base": base, "cx": cx, "w": x1 - x0 + 1, "h": y1 - y0 + 1})
		out["w"] = maxi(out["w"], x1 - x0 + 1)
		out["h"] = maxi(out["h"], y1 - y0 + 1)
		if first:
			out["base_min"] = base; out["base_max"] = base
			out["cx_min"] = cx; out["cx_max"] = cx
			first = false
		else:
			out["base_min"] = mini(out["base_min"], base)
			out["base_max"] = maxi(out["base_max"], base)
			out["cx_min"] = minf(out["cx_min"], cx)
			out["cx_max"] = maxf(out["cx_max"], cx)

	# Referencni vyska sady je MEDIAN spodnich hran, ne hodnota prvniho framu.
	#
	# Prvni frame je libovolny okamzik cyklu. U notification, ktery se pri chuzi houpe o
	# ctyri pixely, muze byt frame 1 v horni nebo dolni uvrati — a pak by se ostatni
	# pohledy srovnaly na nahodny bod houpani misto na to, kde prisera stoji. Median je
	# proti jednomu vybocujicimu framu odolny a u sady, ktera nekmita, je to tataz
	# hodnota jako drive. Prazdne framy se do nej nepocitaji — jejich nulova spodni
	# hrana neni misto, kde prisera stoji.
	var bases: Array[int] = []
	for pf in out["per_frame"]:
		if int(pf["h"]) > 0:
			bases.append(int(pf["base"]))
	if not bases.is_empty():
		bases.sort()
		out["base_ref"] = bases[bases.size() / 2]
	return out


func _select_id(id: String) -> void:
	_id = id
	_sets.clear()
	_stats.clear()
	for s in SETS:
		var fr := _load_frames(id, s)
		if not fr.is_empty():
			_sets[s] = fr
	if _sets.is_empty():
		_refresh_all()
		return
	var firstsuf: String = _sets.keys()[0]
	_scale = _game_scale(id, (_sets[firstsuf] as Array[Texture2D])[0])
	for s in _sets.keys():
		_stats[s] = _measure(_sets[s], _key(s))
	_sel = "" if _sets.has("") else String(_sets.keys()[0])
	_frame = 0
	_time = 0.0
	_refresh_all()


func _key(suffix: String) -> String:
	return _id + suffix


## Míry jedné sady, vždycky kompletní. Kdyby měření z jakéhokoli důvodu neproběhlo,
## vrátí nuly — volající tak dostane „0 px" místo pádu na chybějícím klíči. Bez tohohle
## se z jedné chyby v _measure() stala kaskáda chyb v tabulce i v kreslení.
func _stat(suffix: String) -> Dictionary:
	var d: Variant = _stats.get(suffix)
	if d is Dictionary and (d as Dictionary).has("base_ref"):
		return d
	return {
		"n": 0, "w": 0, "h": 0, "base_min": 0, "base_max": 0,
		"cx_min": 0.0, "cx_max": 0.0, "base_ref": 0, "per_frame": [],
	}


func _frames_of(suffix: String) -> Array[Texture2D]:
	var a: Array[Texture2D] = _sets.get(suffix, [] as Array[Texture2D])
	return a


## Který frame sady je zrovna vidět. Při přehrávání každá sada běží svou vlastní
## rychlostí (o to tu jde), při pauze drží všechny stejný index, aby se daly porovnat.
func _frame_index(suffix: String) -> int:
	var fr := _frames_of(suffix)
	if fr.is_empty():
		return 0
	if not _playing:
		return _frame % fr.size()
	return int(_time * _tuning.fps_for(_key(suffix), DEFAULT_FPS)) % fr.size()


# ---------------------------------------------------------------- UI

## Panel se skládá ze dvou částí: lišta, která je vidět vždycky, a pod ní VŠECHNO OSTATNÍ
## uvnitř ScrollContaineru.
##
## Ten scroll tam není z opatrnosti. Dock sedí ve spodním pravém slotu, který je v Godotu
## defaultně vysoký kolem 250 px — bez scrollu se pod přehrávač nevejde tabulka ani jedno
## tlačítko a panel vypadá, že umí jen přehrávat. Vodorovný scroll je tam ze stejného
## důvodu: při zoomu 3 je pět sloupců širších než jakýkoliv dock.
func _build_ui() -> void:
	var top := HBoxContainer.new()
	add_child(top)
	_id_opt = OptionButton.new()
	_id_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_id_opt.item_selected.connect(func(i: int): _select_id(_id_opt.get_item_text(i)))
	top.add_child(_id_opt)
	var reload := Button.new()
	reload.text = "⟳"
	reload.tooltip_text = "Znovu načíst PNG a ladění z disku (po sprite_cleanup.py nebo novém exportu)"
	reload.pressed.connect(func():
		_load_tuning()
		_ids = _scan_ids()
		_id_opt.clear()
		for id in _ids:
			_id_opt.add_item(id)
		if _ids.has(_id):
			_id_opt.select(_ids.find(_id))
			_select_id(_id)
		elif not _ids.is_empty():
			_select_id(_ids[0]))
	top.add_child(reload)
	var play := CheckBox.new()
	play.text = "hrát"
	play.button_pressed = true
	play.toggled.connect(func(on: bool):
		_playing = on
		_refresh_tuner()
		_stage.queue_redraw())
	top.add_child(play)
	top.add_child(_lbl("lupa"))
	var zoom := SpinBox.new()
	zoom.min_value = 1
	zoom.max_value = 6
	zoom.step = 1
	zoom.value = _zoom
	zoom.tooltip_text = "Násobek herní velikosti. 1 = přesně jak to uvidí hráč,\n" \
		+ "vyšší = na pixelové zarovnání."
	zoom.value_changed.connect(func(v: float):
		_zoom = int(v)
		_fit_stage()
		_stage.queue_redraw())
	top.add_child(zoom)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)

	_stage = Control.new()
	_stage.custom_minimum_size = Vector2(0, 150)
	_stage.draw.connect(_draw_stage)
	body.add_child(_stage)

	_grid = GridContainer.new()
	_grid.columns = 7
	body.add_child(_grid)

	body.add_child(HSeparator.new())

	var row1 := HBoxContainer.new()
	body.add_child(row1)
	row1.add_child(_lbl("Ladím:"))
	_sel_opt = OptionButton.new()
	_sel_opt.item_selected.connect(func(i: int):
		_sel = String(_sel_opt.get_item_metadata(i))
		_frame = 0
		_refresh_tuner()
		_stage.queue_redraw())
	row1.add_child(_sel_opt)
	_fps_label = _lbl("12 fps")
	_fps_slider = HSlider.new()
	_fps_slider.min_value = 1.0
	_fps_slider.max_value = 30.0
	_fps_slider.step = 1.0
	_fps_slider.custom_minimum_size.x = 130
	_fps_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fps_slider.value_changed.connect(func(v: float):
		_tuning.set_fps(_key(_sel), v, DEFAULT_FPS)
		_mark_dirty()
		_fps_label.text = "%d fps" % int(v))
	row1.add_child(_fps_slider)
	row1.add_child(_fps_label)

	var row2 := HBoxContainer.new()
	body.add_child(row2)
	var prev := Button.new()
	prev.text = "◀"
	prev.pressed.connect(func(): _step(-1))
	row2.add_child(prev)
	_frame_label = _lbl("1/8")
	row2.add_child(_frame_label)
	var next := Button.new()
	next.text = "▶"
	next.pressed.connect(func(): _step(1))
	row2.add_child(next)
	row2.add_child(_lbl("   posun X"))
	_off_x = _spin()
	_off_x.value_changed.connect(func(v: float): _set_offset(int(v), int(_off_y.value)))
	row2.add_child(_off_x)
	row2.add_child(_lbl("Y"))
	_off_y = _spin()
	_off_y.value_changed.connect(func(v: float): _set_offset(int(_off_x.value), int(v)))
	row2.add_child(_off_y)

	var row3 := HBoxContainer.new()
	body.add_child(row3)
	_btn(row3, "Srovnat nohy", "Posune framy TÉTO sady tak, aby všechny stály na stejné\n"
		+ "spodní hraně jako frame 1. Lék na poskakování při chůzi.", _align_baseline)
	_btn(row3, "Srovnat střed", "Posune framy TÉTO sady tak, aby jim seděla vodorovná\n"
		+ "poloha těžiště. Lék na ujíždění do strany.", _align_centroid)
	_btn(row3, "Pohledy na south", "Posune KAŽDÝ pohled jako celek tak, aby stál na stejné\n"
		+ "lince jako south. Lék na 'při zatáčení se scvrkne'.", _align_views)
	_btn(row3, "Vynulovat", "Zahodí posuny této sady.", _clear_offsets)

	var row4 := HBoxContainer.new()
	body.add_child(row4)
	_save_btn = Button.new()
	_save_btn.text = "Uložit"
	_save_btn.disabled = true
	_save_btn.pressed.connect(_save)
	row4.add_child(_save_btn)
	var revert := Button.new()
	revert.text = "Vrátit"
	revert.tooltip_text = "Zahodí neuložené změny a načte ladění z disku"
	revert.pressed.connect(func():
		_load_tuning()
		_select_id(_id))
	row4.add_child(revert)
	_status = _lbl("")
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row4.add_child(_status)


func _lbl(t: String) -> Label:
	var l := Label.new()
	l.text = t
	return l


func _spin() -> SpinBox:
	var s := SpinBox.new()
	s.min_value = -16
	s.max_value = 16
	s.step = 1
	s.custom_minimum_size.x = 60
	return s


func _btn(parent: Control, text: String, tip: String, fn: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.pressed.connect(fn)
	parent.add_child(b)


# ---------------------------------------------------------------- kreslení

## Zvětšení, ve kterém panel kreslí: herní velikost krát lupa. Obojí celé číslo, takže
## pixel zůstane čtverec i tady — na kontrolu zarovnání by rozmazaný náhled byl k ničemu.
func _view_scale() -> float:
	return _scale * float(_zoom)


## Nastaví minimální rozměr plátna podle toho, co se na něj má vejít. Bez tohohle by
## ScrollContainer neměl co scrollovat a při vyšší lupě by sprity přetekly mimo panel.
func _fit_stage() -> void:
	if _stage == null:
		return
	if _sets.is_empty():
		_stage.custom_minimum_size = Vector2(0, 60)
		return
	var z := _view_scale()
	var col_w := 0.0
	var max_h := 0.0
	for s in _sets.keys():
		var t: Texture2D = _frames_of(s)[0]
		col_w = maxf(col_w, float(t.get_width()) * z)
		max_h = maxf(max_h, float(t.get_height()) * z)
	col_w += 20.0
	_stage.custom_minimum_size = Vector2(col_w * float(_sets.size()) + 20.0, max_h + 46.0)


func _draw_stage() -> void:
	if _sets.is_empty():
		_stage.draw_string(_font(), Vector2(4, 20), "Žádné framy pro tuhle příšeru.",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.7, 0.7, 0.75))
		return

	var font := _font()
	var pad := 10.0
	var scale := _view_scale()
	var col_w := 0.0
	for s in _sets.keys():
		var t: Texture2D = _frames_of(s)[0]
		col_w = maxf(col_w, float(t.get_width()) * scale)
	col_w += pad * 2.0

	var cy := 24.0 + (_stage.size.y - 24.0) * 0.5

	# Vodicí linka: spodní hrana pohledu south, protažená přes všechny sloupce. Sprite se
	# kreslí na střed, takže řádek `b` textury vysoké H sedí na cy + (b + 0.5 - H/2) * scale.
	var guide := -1.0
	if _stat("")["n"] > 0:
		var h0: float = float(_frames_of("")[0].get_height())
		var b0: float = float(_stat("")["base_ref"])
		guide = cy + (b0 + 0.5 - h0 * 0.5) * scale
		_stage.draw_line(Vector2(0, guide), Vector2(_stage.size.x, guide),
			Color(0.35, 0.85, 1.0, 0.35), 1.0)

	var i := 0
	for s in _sets.keys():
		var x := pad + float(i) * col_w
		var fr := _frames_of(s)
		var idx := _frame_index(s)
		var tex: Texture2D = fr[idx]
		var w := float(tex.get_width()) * scale
		var h := float(tex.get_height()) * scale
		var cx := x + col_w * 0.5 - pad

		var is_sel: bool = s == _sel
		_stage.draw_string(font, Vector2(x, 15),
			"%s  %d/%d" % [SET_LABELS.get(s, s), idx + 1, fr.size()],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
			Color(1, 0.85, 0.4) if is_sel else Color(0.72, 0.74, 0.8))

		# Svislá osa sloupce — proti ní se čte ujíždění do strany.
		_stage.draw_line(Vector2(cx, 22), Vector2(cx, _stage.size.y),
			Color(1, 1, 1, 0.10), 1.0)

		var off := _tuning.offset_for(_key(s), idx)
		var pos := Vector2(cx - w * 0.5, cy - h * 0.5) + Vector2(off) * scale
		_stage.draw_texture_rect(tex, Rect2(pos, Vector2(w, h)), false)
		if is_sel:
			_stage.draw_rect(Rect2(pos, Vector2(w, h)), Color(1, 0.85, 0.4, 0.35), false, 1.0)
		i += 1


func _font() -> Font:
	var f := get_theme_font("font", "Label")
	return f if f != null else ThemeDB.fallback_font


# ---------------------------------------------------------------- akce

func _step(d: int) -> void:
	var fr := _frames_of(_sel)
	if fr.is_empty():
		return
	_playing = false
	_frame = posmod(_frame + d, fr.size())
	_refresh_tuner()
	_stage.queue_redraw()


func _set_offset(x: int, y: int) -> void:
	var fr := _frames_of(_sel)
	if fr.is_empty():
		return
	var key := _key(_sel)
	var arr := _tuning.offsets_for(key, fr.size())
	var idx := _frame % fr.size()
	if arr[idx] == Vector2i(x, y):
		return
	arr[idx] = Vector2i(x, y)
	_tuning.set_offsets(key, arr)
	_after_offset_change()


## Srovná spodní hranu siluety každého framu na hranu framu 1 — nohy pak drží linku
## místo poskakování. Svislý bob, který je v chůzi ZÁMĚRNÝ, tím zmizí taky, takže je to
## nástroj na sady, kde poskakování ruší, ne paušální úklid.
func _align_baseline() -> void:
	_align(func(pf: Dictionary, ref: Dictionary, cur: Vector2i) -> Vector2i:
		return Vector2i(cur.x, cur.y + int(ref["base"]) - int(pf["base"])))


func _align_centroid() -> void:
	_align(func(pf: Dictionary, ref: Dictionary, cur: Vector2i) -> Vector2i:
		return Vector2i(cur.x + int(roundf(float(ref["cx"]) - float(pf["cx"]))), cur.y))


func _align(fn: Callable) -> void:
	var fr := _frames_of(_sel)
	if fr.is_empty():
		return
	var st: Dictionary = _stat(_sel)
	var pfs: Array = st.get("per_frame", [])
	if pfs.size() < fr.size():
		return
	var key := _key(_sel)
	var arr := _tuning.offsets_for(key, fr.size())
	for i in range(fr.size()):
		arr[i] = fn.call(pfs[i], pfs[0], arr[i] as Vector2i)
	_tuning.set_offsets(key, arr)
	_after_offset_change()


## Posune každý pohled JAKO CELEK tak, aby stál na stejné lince jako south. Nesahá na
## rozdíly uvnitř sady — ty řeší „Srovnat nohy". Tohle je čistě o tom, že se příšera při
## otočení nesmí propadnout nebo vyskočit.
func _align_views() -> void:
	if not _stats.has(""):
		_note("Chybí pohled south, není na co srovnávat.")
		return
	var ref: int = int(_stat("")["base_ref"])
	var moved := 0
	for s in _sets.keys():
		if s == "":
			continue
		var st: Dictionary = _stat(s)
		if int(st["n"]) == 0:
			continue
		var d: int = ref - int(st["base_ref"])
		if d == 0:
			continue
		var fr := _frames_of(s)
		var key := _key(s)
		var arr := _tuning.offsets_for(key, fr.size())
		for i in range(fr.size()):
			arr[i] = (arr[i] as Vector2i) + Vector2i(0, d)
		_tuning.set_offsets(key, arr)
		moved += 1
	_after_offset_change()
	_note("Srovnáno pohledů: %d" % moved)


func _clear_offsets() -> void:
	_tuning.offsets.erase(_key(_sel))
	_after_offset_change()


func _after_offset_change() -> void:
	_mark_dirty()
	for s in _sets.keys():
		_stats[s] = _measure(_sets[s], _key(s))
	_refresh_metrics()
	_refresh_tuner()
	_stage.queue_redraw()


func _mark_dirty() -> void:
	_dirty = true
	_save_btn.disabled = false
	_save_btn.text = "Uložit *"


func _save() -> void:
	var err := ResourceSaver.save(_tuning, AnimTuning.PATH)
	if err != OK:
		_note("Uložení selhalo (chyba %d)" % err)
		return
	_dirty = false
	_save_btn.disabled = true
	_save_btn.text = "Uložit"
	# Běžící náhled i rozehraná hra si drží statickou kopii; tohle ji zahodí.
	DistractionAnimator.drop_tuning_cache()
	_note("Uloženo do %s" % AnimTuning.PATH)


func _note(t: String) -> void:
	if _status != null:
		_status.text = t


# ---------------------------------------------------------------- refresh

func _refresh_all() -> void:
	_fit_stage()
	_refresh_metrics()
	_refresh_sel_options()
	_refresh_tuner()
	_stage.queue_redraw()


func _refresh_sel_options() -> void:
	_sel_opt.clear()
	var i := 0
	for s in _sets.keys():
		_sel_opt.add_item(String(SET_LABELS.get(s, s)))
		_sel_opt.set_item_metadata(i, s)
		if s == _sel:
			_sel_opt.select(i)
		i += 1


func _refresh_tuner() -> void:
	var fr := _frames_of(_sel)
	if fr.is_empty():
		_frame_label.text = "-"
		return
	var idx := _frame % fr.size()
	_frame_label.text = "%d/%d" % [idx + 1, fr.size()]
	_fps_slider.set_block_signals(true)
	_fps_slider.value = _tuning.fps_for(_key(_sel), DEFAULT_FPS)
	_fps_slider.set_block_signals(false)
	_fps_label.text = "%d fps" % int(_fps_slider.value)
	var off := _tuning.offset_for(_key(_sel), idx)
	_off_x.set_block_signals(true)
	_off_y.set_block_signals(true)
	_off_x.value = off.x
	_off_y.value = off.y
	_off_x.set_block_signals(false)
	_off_y.set_block_signals(false)
	# Krokovat framy a nudgovat jde jen na stojící animaci — jinak ladíš frame, který
	# už dávno není na obrazovce.
	_off_x.editable = not _playing
	_off_y.editable = not _playing


func _refresh_metrics() -> void:
	for c in _grid.get_children():
		c.queue_free()
	for h in ["sada", "framů", "š×v", "nohy", "kmit Y", "drift X", "fps"]:
		var l := _lbl(h)
		l.modulate = Color(0.62, 0.65, 0.72)
		_grid.add_child(l)
	if _sets.is_empty():
		return
	var ref_base: int = int(_stat("")["base_ref"]) if _stats.has("") else -999
	for s in _sets.keys():
		var st: Dictionary = _stat(s)
		var wob: int = int(st["base_max"]) - int(st["base_min"])
		var drift: float = float(st["cx_max"]) - float(st["cx_min"])
		_grid.add_child(_lbl(String(SET_LABELS.get(s, s))))
		_grid.add_child(_lbl(str(st["n"])))
		_grid.add_child(_lbl("%d×%d" % [int(st["w"]), int(st["h"])]))
		# Nohy: o kolik tahle sada stojí jinde než south. To je ta „scvrkne se při
		# zatáčení" veličina, a je jediná mezisadová — proto se zvýrazňuje.
		var d: int = int(st["base_ref"]) - ref_base
		var dl := _lbl("—" if (s == "" or ref_base == -999) else "%+d" % d)
		if s != "" and ref_base != -999 and absi(d) >= 2:
			dl.modulate = Color(1.0, 0.55, 0.45)
		_grid.add_child(dl)
		var wl := _lbl(str(wob))
		if wob >= 3:
			wl.modulate = Color(1.0, 0.75, 0.35)
		_grid.add_child(wl)
		var fl := _lbl("%.1f" % drift)
		if drift >= 2.0:
			fl.modulate = Color(1.0, 0.75, 0.35)
		_grid.add_child(fl)
		_grid.add_child(_lbl("%d" % int(_tuning.fps_for(_key(s), DEFAULT_FPS))))
