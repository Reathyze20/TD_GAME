@tool
class_name StylizedMapRenderer
extends Node2D
## Živý stylizovaný náhled mapy — pravá půlka „samsfacee" workflow.
##
## Vlevo se maluje abstraktně (plné barevné dlaždice, vestavěný TileMap editor); tenhle
## uzel žije v SubViewportu spodního panelu a při každé změně plátna se překreslí tak,
## jak level vykreslí hra: rohový terén s variantami, dlaždice cest se stejným losováním,
## rekvizity, brány spawnů i podstavec jádra. Nečte level ze souboru — čte PLÁTNO, takže
## ukazuje i nevypálené tahy.
##
## Vše je nakešované v lokálních polích: rebuild() sesbírá data z editoru, _draw() jen
## kreslí. Kdyby _draw sahal na uzly scény, panel by se rozbil při každém přejmenování.

const CELL := 48
const ATLAS := "res://assets/terrain/high_ground_atlas.png"
const PATH_DIR := "res://assets/terrain/path"
const FACE_DIR := "res://assets/terrain/face"
const BACKGROUND := "res://assets/background.png"
## Musí sedět s Game.ACCENT_SHARE / ACCENT_STRAND.
const ACCENT_SHARE := 0.06
const ACCENT_STRAND := 4
## Musí sedět s Game.WALL_FACE_H — přední stěna zdi ve 3/4 pohledu.
const FACE_H := 24

var _walls := {}                          ## Vector2i -> true
var _paths: Array[Vector2i] = []          ## seřazené (y,x) — stejně je řadí Bake
var _props: Array[Dictionary] = []        ## {tex, pos, flip}
var _zones: Array[Rect2i] = []
var _objective := Vector2i.ZERO
var _level_id: int = 1
var _origin := Vector2.ZERO

var _atlas_tex: Texture2D = null
var _variants: int = 1
var _path_tex: Array[Texture2D] = []
var _accent_tex: Array[Texture2D] = []
var _face_tex: Array[Texture2D] = []
var _bg_tex: Texture2D = null
var _field := Vector2.ZERO
var _spawn_marker: Texture2D = null
var _goal_marker: Texture2D = null

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

## Stáhne aktuální stav plátna z MapEditoru. Volá plugin při každé změně otisku.
func rebuild(ed) -> void:
	_load_art()
	_walls.clear()
	_paths.clear()
	_props.clear()
	_zones.clear()

	var g: Dictionary = ed._grid()
	_origin = Vector2(float(g.origin_x), float(g.origin_y))
	_field = Vector2(float(g.cols) * CELL, float(g.rows) * CELL)
	_level_id = int(ed.target_level.id) if ed.target_level != null else 1
	_objective = ed._read_objective()
	_zones = ed._read_zones()

	var tm: TileMapLayer = ed.get_node_or_null("HighGroundTiles")
	if tm != null:
		for c: Vector2i in tm.get_used_cells():
			if c != _objective:
				_walls[c] = true

	var pt: TileMapLayer = ed.get_node_or_null("PathTiles")
	if pt != null:
		for c: Vector2i in pt.get_used_cells():
			_paths.append(c)
		# Stejné řazení používá Bake — díky tomu editor i hra vylosují buňkám tytéž
		# varianty a náhled je playtestu věrný do posledního pixelu.
		_paths.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			return a.y < b.y or (a.y == b.y and a.x < b.x))

	var props: Node2D = ed.get_node_or_null("Props")
	if props != null:
		for child in props.get_children():
			var s := child as Sprite2D
			if s != null and s.texture != null:
				_props.append({"tex": s.texture, "pos": s.position, "flip": s.flip_h})
		_props.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return (a.pos as Vector2).y < (b.pos as Vector2).y)

	queue_redraw()

func _load_art() -> void:
	if _atlas_tex == null and ResourceLoader.exists(ATLAS):
		_atlas_tex = load(ATLAS)
	if _atlas_tex != null:
		_variants = maxi(1, int(_atlas_tex.get_height() / float(CELL * 4)))
	if _bg_tex == null and ResourceLoader.exists(BACKGROUND):
		_bg_tex = load(BACKGROUND)
	if _path_tex.is_empty():
		var dir := DirAccess.open(PATH_DIR)
		if dir != null:
			var files := dir.get_files()
			files.sort()
			for f in files:
				var base := f.trim_suffix(".remap").trim_suffix(".import")
				if base.ends_with(".png") and ResourceLoader.exists("%s/%s" % [PATH_DIR, base]):
					# Předškálovat na buňku, přesně jako Game._build_path_layer — dlaždice
					# kreslená v 16 px se jinak vykreslí malá, ne roztažená.
					var t: Texture2D = load("%s/%s" % [PATH_DIR, base])
					var im: Image = t.get_image()
					im.resize(CELL, CELL, Image.INTERPOLATE_NEAREST)
					var tex := ImageTexture.create_from_image(im)
					if base.begins_with("accent_"):
						_accent_tex.append(tex)
					else:
						_path_tex.append(tex)
	if _face_tex.is_empty():
		var fdir := DirAccess.open(FACE_DIR)
		if fdir != null:
			var ffiles := fdir.get_files()
			ffiles.sort()
			for f in ffiles:
				var fbase := f.trim_suffix(".remap").trim_suffix(".import")
				if fbase.ends_with(".png") and ResourceLoader.exists("%s/%s" % [FACE_DIR, fbase]):
					_face_tex.append(load("%s/%s" % [FACE_DIR, fbase]))
	if _spawn_marker == null and ResourceLoader.exists("res://assets/markers/spawn_portal.png"):
		_spawn_marker = load("res://assets/markers/spawn_portal.png")
	if _goal_marker == null and ResourceLoader.exists("res://assets/markers/goal_core.png"):
		_goal_marker = load("res://assets/markers/goal_core.png")

## Po výměně atlasu (tiles.py instaluj) zavolá plugin, ať se art načte znovu.
func drop_art_cache() -> void:
	_atlas_tex = null
	_bg_tex = null
	_path_tex.clear()
	_accent_tex.clear()
	_face_tex.clear()
	_spawn_marker = null
	_goal_marker = null

func _draw() -> void:
	var ox := _origin.x
	var oy := _origin.y

	# Pozadí přesně jako Game._build_background_layer: jeden obraz roztažený na pole,
	# ne dlaždicovaný. Dřív se sem bralo políčko masky 0 z atlasu — to je od přechodu
	# na Deep Focus vyklíčované na alfu, takže náhled nekreslil pozadí vůbec.
	draw_rect(Rect2(_origin, _field), Color("11141f"))
	if _bg_tex != null:
		draw_texture_rect(_bg_tex, Rect2(_origin, _field), false)

	# Cesty pod terénem. Musí kopírovat Game._build_path_layer i v tom, že akcenty jsou
	# ve shlucích, ne posypané — jinak náhled vypadá rušivěji než hra.
	if not _path_tex.is_empty():
		var prng := RandomNumberGenerator.new()
		prng.seed = hash(_level_id) ^ 0x9a71
		var chosen := {}
		for c in _paths:
			chosen[c] = _path_tex[prng.randi() % _path_tex.size()]
		if not _accent_tex.is_empty() and not _paths.is_empty():
			var strands: int = maxi(1, int(_paths.size() * ACCENT_SHARE / float(ACCENT_STRAND)))
			var steps := [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]
			for _s in range(strands):
				var head: Vector2i = _paths[prng.randi() % _paths.size()]
				var pick: Texture2D = _accent_tex[prng.randi() % _accent_tex.size()]
				for _i in range(prng.randi_range(2, ACCENT_STRAND)):
					if not chosen.has(head):
						break
					chosen[head] = pick
					head += steps[prng.randi() % 4]
		for c in _paths:
			draw_texture(chosen[c], Vector2(ox + c.x * CELL, oy + c.y * CELL))

	# Kontaktní stín zdí — musí sedět s Game.WallShadow, jinak náhled lže o hloubce.
	# Stín začíná až pod přední stěnou, stejně jako ve hře.
	var face_drop: int = FACE_H if not _face_tex.is_empty() else 0
	var near := Color(0.016, 0.027, 0.063, 0.62)
	var far := Color(0.016, 0.027, 0.063, 0.30)
	for cell: Vector2i in _walls.keys():
		if not _walls.has(cell + Vector2i.DOWN):
			var sx := ox + cell.x * CELL
			var sy := oy + (cell.y + 1) * CELL + face_drop
			draw_rect(Rect2(sx, sy, CELL, 6), near)
			draw_rect(Rect2(sx, sy + 6, CELL, 6), far)
		for dx in [-1, 1]:
			var side := cell + Vector2i(dx, 0)
			if _walls.has(side):
				continue
			var inset := CELL - 4 if dx < 0 else 0
			draw_rect(Rect2(ox + side.x * CELL + inset, oy + side.y * CELL, 4, CELL), far)

	# Přední stěna zdi (3/4 pohled) — musí kopírovat Game.WallFace včetně volby varianty
	# podle buňky, jinak náhled ukáže jiný rozpis stěn než hra.
	if not _face_tex.is_empty():
		var frng := RandomNumberGenerator.new()
		var wkeys: Array = _walls.keys()
		wkeys.sort()
		for cell: Vector2i in wkeys:
			if _walls.has(cell + Vector2i.DOWN):
				continue
			frng.seed = hash(Vector2i(cell.x, cell.y)) ^ hash(_level_id)
			var ftex: Texture2D = _face_tex[frng.randi() % _face_tex.size()]
			draw_texture_rect(ftex, Rect2(ox + cell.x * CELL,
				oy + (cell.y + 1) * CELL, CELL, FACE_H), false)

	# Rohový terén s variantami — stejný seed jako Game._build_corner_terrain.
	if _atlas_tex != null:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(_level_id) ^ 0x7e44a1
		var bounds := _cell_bounds()
		for i in range(bounds.position.y, bounds.end.y + 2):
			for j in range(bounds.position.x, bounds.end.x + 2):
				var m := ((1 if _walls.has(Vector2i(j - 1, i - 1)) else 0)
					| (2 if _walls.has(Vector2i(j, i - 1)) else 0)
					| (4 if _walls.has(Vector2i(j - 1, i)) else 0)
					| (8 if _walls.has(Vector2i(j, i)) else 0))
				if m == 0:
					continue
				var v := rng.randi() % _variants
				draw_texture_rect_region(_atlas_tex,
					Rect2(ox + j * CELL - CELL / 2.0, oy + i * CELL - CELL / 2.0, CELL, CELL),
					Rect2((m % 4) * CELL, (v * 4 + m / 4) * CELL, CELL, CELL))

	# Rekvizity, seřazené podle y (malíř), ×3 jako DecorLayer.
	for p in _props:
		var tex: Texture2D = p.tex
		var sz := Vector2(tex.get_size()) * DecorLayer.ZOOM
		var at: Vector2 = p.pos
		if bool(p.flip):
			draw_set_transform(at, 0.0, Vector2(-1.0, 1.0))
			draw_texture_rect(tex, Rect2(-sz * 0.5, sz), false, DecorLayer.TINT)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		else:
			draw_texture_rect(tex, Rect2(at - sz * 0.5, sz), false, DecorLayer.TINT)

	# Brány spawnů a podstavec jádra — jako ve hře.
	if _spawn_marker != null:
		for z in _zones:
			var zc := Vector2(ox + (z.position.x + z.size.x * 0.5) * CELL,
				oy + (z.position.y + z.size.y * 0.5) * CELL)
			var msz := Vector2(_spawn_marker.get_size()) \
				* maxf(1.0, floorf(float(CELL) / _spawn_marker.get_width()))
			draw_texture_rect(_spawn_marker, Rect2(zc - msz / 2.0, msz), false)
	var opos := Vector2(ox + (_objective.x + 0.5) * CELL, oy + (_objective.y + 0.5) * CELL)
	if _goal_marker != null:
		var gsz := Vector2(_goal_marker.get_size()) \
			* maxf(1.0, floorf(float(CELL) / _goal_marker.get_width()))
		draw_texture_rect(_goal_marker, Rect2(opos - gsz / 2.0, gsz), false)
	draw_circle(opos, 9.0, Color("2bd6c0"))
	draw_circle(opos, 4.0, Color.WHITE)

func _cell_bounds() -> Rect2i:
	if _walls.is_empty():
		return Rect2i(0, 0, 40, 22)
	var lo := Vector2i(9999, 9999)
	var hi := Vector2i(-9999, -9999)
	for c: Vector2i in _walls:
		lo = Vector2i(mini(lo.x, c.x), mini(lo.y, c.y))
		hi = Vector2i(maxi(hi.x, c.x), maxi(hi.y, c.y))
	return Rect2i(lo, hi - lo)
