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

## Autoload `Data` se v editoru chovat nemusí; `preload` na tentýž skript ano.
## GRID, BUILD_BLOCK i převodníky jsou const/static, takže je to plnohodnotná náhrada.
const D = preload("res://scripts/data.gd")
## Jen kvůli SQUARE_GROUND_COLOR/SQUARE_TOP_COLOR — viz `_draw_square()` níž. Ty samé
## konstanty, ne vlastní kopie, aby se barvy nemohly rozejít s tím, co skutečně kreslí
## `Game._build_square_terrain()`.
const G = preload("res://scripts/game.gd")

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

# ---------------------------------------------------------------- izometrický náhled
#
# Kreslí TOUTÉŽ logikou jako `Game._build_path_layer()` a `Game._build_terrace_blocks()`,
# včetně masek pruhu a losování variant ze stejného seedu — jinak by náhled ukazoval jiné
# dlaždice než hra a byl by k ničemu právě v tom, kvůli čemu existuje.
#
# Čte PLÁTNO, ne soubor levelu, takže ukazuje i nevypálené tahy.

const ISO_GROUND_DIR := "res://assets/terrain/iso/ground/"
const ISO_LANE_DIR := "res://assets/terrain/iso/lane/"
const ISO_TERRACE_BLOCK := "res://assets/terrain/iso/terrace/block.png"
const ISO_TERRACE_CAP := "res://assets/terrain/iso/terrace/cap.png"
const ISO_CORE := "res://assets/terrain/iso/props/core.png"

var _iso_high := {}                 ## Vector2i -> true
var _iso_lane := {}                 ## Vector2i -> true
var _iso_ground: Array[Texture2D] = []
var _iso_accent: Array[Texture2D] = []
var _iso_lane_tex := {}             ## maska -> Array[Texture2D]
var _iso_lane_fill: Texture2D = null
var _iso_block: Texture2D = null
var _iso_core: Texture2D = null
var _iso_anchor := Vector2.ZERO
var _iso_ready := false

func _load_iso_art() -> void:
	if _iso_ready:
		return
	_iso_ready = true
	for i in range(64):
		var p := ISO_GROUND_DIR + "ground_%02d.png" % i
		if not ResourceLoader.exists(p):
			break
		_iso_ground.append(load(p))
	for i in range(64):
		var p := ISO_GROUND_DIR + "ground_accent_%02d.png" % i
		if not ResourceLoader.exists(p):
			break
		_iso_accent.append(load(p))
	for mask in range(16):
		var pool: Array[Texture2D] = []
		for suffix in ["", "a", "b"]:
			var p := ISO_LANE_DIR + "lane_%02d%s.png" % [mask, suffix]
			if ResourceLoader.exists(p):
				pool.append(load(p))
		if not pool.is_empty():
			_iso_lane_tex[mask] = pool
	if ResourceLoader.exists(ISO_LANE_DIR + "lane_fill.png"):
		_iso_lane_fill = load(ISO_LANE_DIR + "lane_fill.png")
	if ResourceLoader.exists(ISO_TERRACE_BLOCK):
		_iso_block = load(ISO_TERRACE_BLOCK)
	if ResourceLoader.exists(ISO_CORE):
		_iso_core = load(ISO_CORE)
	# Kotva terasy se ČTE Z ARTU, ne zadrátuje — přesně jako `_build_terrace_blocks()`,
	# aby výměna artu náhled tiše nerozhodila.
	if ResourceLoader.exists(ISO_TERRACE_CAP):
		var cap: Texture2D = load(ISO_TERRACE_CAP)
		var used := cap.get_image().get_used_rect()
		var th: float = float(D.GRID.get("tile_h", 32))
		_iso_anchor = Vector2(float(used.position.x) + float(used.size.x) * 0.5,
			float(used.position.y + used.size.y - 1) - th * 0.5)

func _iso_pick(pool: Array, key: Vector2i, salt: int) -> Texture2D:
	if pool.is_empty():
		return null
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key) ^ salt
	return pool[rng.randi() % pool.size()]

func _draw_iso() -> void:
	var g: Dictionary = D.GRID
	var cols: int = int(g.cols)
	var rows: int = int(g.rows)
	var seed_val: int = hash(_level_id) ^ 0x9a71

	draw_rect(Rect2(Vector2(-1200, -200), Vector2(3000, 1600)), Color("0d1017"))

	# STAVOVÝ ŘÁDEK SE KRESLÍ VŽDY A UKOTVENÝ K POHLEDU, NE K POČÁTKU SVĚTA.
	#
	# První verze psala hlášku na (24, 40) ve světových souřadnicích. Kamera panelu je
	# ale synchronizovaná s levým 2D pohledem, takže hláška padla mimo obraz a uživatel
	# viděl černou plochu bez vysvětlení. Panel, který mlčí, je k nerozeznání od
	# rozbitého — a hádání, proč mlčí, stálo několik kol.
	#
	# Proto se čísla ukazují i když je všechno v pořádku: kdykoli je náhled prázdný, je
	# z nich hned vidět, jestli chybí art, data z plátna, nebo se jen kamera dívá jinam.
	var cam := get_viewport().get_camera_2d()
	var at := Vector2(24, 40)
	if cam != null:
		at = cam.get_screen_center_position() \
			- get_viewport().get_visible_rect().size * 0.5 / maxf(cam.zoom.x, 0.01) \
			+ Vector2(16, 26)
	var font := ThemeDB.fallback_font
	var status := "terén %d · lane sad %d · cesta %d bun. · terasa %d bun. · kamera %s" \
		% [_iso_ground.size(), _iso_lane_tex.size(), _iso_lane.size(), _iso_high.size(),
			("%.0f,%.0f" % [cam.get_screen_center_position().x,
				cam.get_screen_center_position().y]) if cam != null else "?"]
	draw_string(font, at, status, HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
		Color(0.55, 0.65, 0.8) if not _iso_ground.is_empty() else Color(1.0, 0.6, 0.4))

	if _iso_ground.is_empty():
		draw_string(font, at + Vector2(0, 26),
			"Chybí assets/terrain/iso/ground/ground_00.png — zmáčkni ⟳ nad panelem.",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1.0, 0.6, 0.4))
		return

	# Akcenty ve stejných pramíncích jako hra.
	var accent := {}
	if not _iso_accent.is_empty():
		var arng := RandomNumberGenerator.new()
		arng.seed = seed_val ^ 0x5A17
		var strands: int = maxi(1, int(float(rows * cols) * ACCENT_SHARE / float(ACCENT_STRAND)))
		for _s in range(strands):
			var c := Vector2i(arng.randi_range(0, cols - 1), arng.randi_range(0, rows - 1))
			var step: Vector2i = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1),
				Vector2i(1, -1)][arng.randi() % 4]
			for _k in range(arng.randi_range(2, ACCENT_STRAND)):
				if D.in_bounds(c) and not _iso_lane.has(c):
					accent[c] = true
				c += step

	# Podlaha. Pořadí x+y je pro 2:1 projekci totéž co y-sort.
	for s in range(cols + rows - 1):
		for x in range(maxi(0, s - rows + 1), mini(cols - 1, s) + 1):
			var cell := Vector2i(x, s - x)
			var tex: Texture2D = null
			if _iso_lane.has(cell) and not _iso_lane_tex.is_empty():
				var mask := 0
				if _iso_lane.has(cell + Vector2i(0, -1)): mask |= 1
				if _iso_lane.has(cell + Vector2i(1, 0)): mask |= 2
				if _iso_lane.has(cell + Vector2i(0, 1)): mask |= 4
				if _iso_lane.has(cell + Vector2i(-1, 0)): mask |= 8
				var interior: bool = mask == 15 and _iso_lane_fill != null \
					and _iso_lane.has(cell + Vector2i(1, 1)) \
					and _iso_lane.has(cell + Vector2i(-1, -1)) \
					and _iso_lane.has(cell + Vector2i(1, -1)) \
					and _iso_lane.has(cell + Vector2i(-1, 1))
				if interior:
					tex = _iso_lane_fill
				else:
					tex = _iso_pick(_iso_lane_tex.get(mask, _iso_lane_tex.get(0, [])),
						cell, seed_val)
			if tex == null and accent.has(cell):
				tex = _iso_pick(_iso_accent, cell, seed_val ^ 0x5A17)
			if tex == null:
				var blk: int = D.BUILD_BLOCK
				tex = _iso_pick(_iso_ground, Vector2i(int(floorf(float(x) / blk)),
					int(floorf(float(cell.y) / blk))), seed_val)
			if tex != null:
				draw_texture(tex, D.cell_center(cell) - tex.get_size() * 0.5)

	# Terasa přes podlahu, taky odzadu dopředu.
	if _iso_block != null:
		var hs: Array[Vector2i] = []
		hs.assign(_iso_high.keys())
		hs.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			return a.x + a.y < b.x + b.y)
		for c in hs:
			if c == _objective:
				continue
			draw_texture(_iso_block, D.cell_center(c) - _iso_anchor)

	if _iso_core != null and D.in_bounds(_objective):
		draw_texture(_iso_core, D.cell_center(_objective)
			- _iso_core.get_size() * Vector2(0.5, 0.75))

	for z in _zones:
		var r := PackedVector2Array()
		for corner in [Vector2i(0, 0), Vector2i(z.size.x, 0),
				Vector2i(z.size.x, z.size.y), Vector2i(0, z.size.y)]:
			r.append(D.cell_center(z.position + corner) - Vector2(0, 16))
		r.append(r[0])
		draw_polyline(r, Color(1.0, 0.35, 0.4, 0.9), 2.0)

## Náhled hraje přesně to, co dnes kreslí Game._build_square_terrain(): plochá barva
## podlahy, plochá barva zdí, žádný atlas. Sdílené konstanty (G.SQUARE_GROUND_COLOR/
## SQUARE_TOP_COLOR), ne vlastní kopie, takže barvy nemůžou s hrou rozejít. Cesta se
## nekreslí jinou barvou, protože to nedělá ani hra — až bude mít top-down terén
## skutečný art, přibude sem stejná logika jako u _draw_iso() výš.
func _draw_square() -> void:
	var g: Dictionary = D.GRID
	var t: float = float(g.tile)
	var ox := _origin.x
	var oy := _origin.y
	draw_rect(Rect2(ox, oy, float(g.cols) * t, float(g.rows) * t), G.SQUARE_GROUND_COLOR)
	# Lane BEFORE high ground — same order and same color as Game.SquareTerrain._draw()
	# (scripts/game.gd, "draw the lane as a surface", 2026-09-05): a lane is floor and
	# a wall stands on floor, so if the two ever disagreed the wall must win. Until this
	# fix _draw_square() drew no lane at all — the square panel's biggest gap, since a
	# maze TD's whole point is where the wave walks.
	for c: Vector2i in _paths:
		draw_rect(Rect2(ox + float(c.x) * t, oy + float(c.y) * t, t, t), G.SQUARE_LANE_COLOR)
	for c: Vector2i in _walls.keys():
		draw_rect(Rect2(ox + float(c.x) * t, oy + float(c.y) * t, t, t), G.SQUARE_TOP_COLOR)

	for z in _zones:
		var r := PackedVector2Array()
		for corner in [Vector2i(0, 0), Vector2i(z.size.x, 0),
				Vector2i(z.size.x, z.size.y), Vector2i(0, z.size.y)]:
			var cc: Vector2i = z.position + corner
			r.append(Vector2(ox + float(cc.x) * t, oy + float(cc.y) * t))
		r.append(r[0])
		draw_polyline(r, Color(1.0, 0.35, 0.4, 0.9), 2.0)
		if _spawn_marker != null:
			var zc := Vector2(ox + (float(z.position.x) + float(z.size.x) * 0.5) * t,
				oy + (float(z.position.y) + float(z.size.y) * 0.5) * t)
			var msz := Vector2(_spawn_marker.get_size()) \
				* maxf(1.0, floorf(t / _spawn_marker.get_width()))
			draw_texture_rect(_spawn_marker, Rect2(zc - msz / 2.0, msz), false)

	# Rekvizity, seřazené podle y (malíř) — stejný úryvek jako ve staré top-down větvi
	# níž, protože rekvizita žádnou projekci neřeší, jen kreslí sprite na svojí pozici.
	for p in _props:
		var tex: Texture2D = p.tex
		var sz: Vector2 = Vector2(tex.get_size()) * D.pixel_scale()
		var at: Vector2 = p.pos
		if bool(p.flip):
			draw_set_transform(at, 0.0, Vector2(-1.0, 1.0))
			draw_texture_rect(tex, Rect2(-sz * 0.5, sz), false, DecorLayer.TINT)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		else:
			draw_texture_rect(tex, Rect2(at - sz * 0.5, sz), false, DecorLayer.TINT)

	if D.in_bounds(_objective):
		var oc := D.cell_center(_objective)
		if _goal_marker != null:
			var gsz := Vector2(_goal_marker.get_size()) \
				* maxf(1.0, floorf(t / _goal_marker.get_width()))
			draw_texture_rect(_goal_marker, Rect2(oc - gsz / 2.0, gsz), false)
		draw_circle(oc, t * 0.35, Color("2bd6c0"))
		draw_circle(oc, t * 0.14, Color.WHITE)

## Stáhne aktuální stav plátna z MapEditoru. Volá plugin při každé změně otisku.
func rebuild(ed) -> void:
	if GridProjection.active_mode != GridProjection.MODE_SQUARE:
		_load_iso_art()
	_iso_high.clear()
	_iso_lane.clear()
	for c in ed._high_cells():
		_iso_high[c] = true
	for c in ed._lane_cells():
		_iso_lane[c] = true

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

	# _high_cells()/_lane_cells(), NOT the raw TileMapLayer nodes: those two merge the
	# BLOCK layers (BlockTiles/BlockPath — the default one-click-per-block way of
	# painting) with the per-cell layers, which is exactly what MODE_ISO already reads
	# two lines up (_iso_high/_iso_lane). Reading only HighGroundTiles/PathTiles here
	# left MODE_SQUARE blind to anything painted in blocks — a canvas built entirely
	# from BlockTiles/BlockPath (like MapEditor.tscn ships) drew NO walls and no lane
	# at all on the square panel.
	for c: Vector2i in ed._high_cells():
		if c != _objective:
			_walls[c] = true
	# Already sorted (y, x) by _lane_cells() — the same order Bake writes path_cells
	# in, so the square panel matches what a playtest would actually show.
	_paths.assign(ed._lane_cells())

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
	# Izo sadu taky — načítá se jednou a hlídá se `_iso_ready`. Kdyby se sem nevešla,
	# tlačítko ⟳ by po přegenerování artu nic neudělalo a jediná cesta zpět by bylo
	# restartovat editor.
	_iso_ready = false
	_iso_ground.clear()
	_iso_accent.clear()
	_iso_lane_tex.clear()
	_iso_lane_fill = null
	_iso_block = null
	_iso_core = null
	_atlas_tex = null
	_bg_tex = null
	_path_tex.clear()
	_accent_tex.clear()
	_face_tex.clear()
	_spawn_marker = null
	_goal_marker = null

## Náhled dole kreslil TOP-DOWN desku: `CELL = 48`, atlas `high_ground_atlas.png`,
## dlaždice z `terrain/path` a `terrain/face`. Ten kód je z DOBY PŘED izometrií — hra
## od přechodu na izometrii (21. 8. 2026) nic z toho nekreslila, takže tenhle panel
## ukazoval barevný šum, který s výsledkem nesouvisel. `ISO_NOTICE` to tehdy nahradilo
## `_draw_iso()`.
##
## 2026-08-29: hra je zase top-down (T5), ale NE ta samá deska — `CELL=48` a
## `terrain/path`/`terrain/face` jsou z jiné éry (jiná velikost dlaždice, jiný atlas) a
## dnešní čtvercový terén nemá žádný z těch assetů, jen ploché barvy
## (`Game._build_square_terrain()`). Ta stará větev proto zůstává mrtvá i teď — přibyla
## `_draw_square()` jako TŘETÍ, aktuální větev, ne oživení téhle.
const ISO_NOTICE := true

func _draw() -> void:
	if GridProjection.active_mode == GridProjection.MODE_SQUARE:
		_draw_square()
		return
	if ISO_NOTICE:
		_draw_iso()
		return
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
		var sz: Vector2 = Vector2(tex.get_size()) * D.pixel_scale()
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
