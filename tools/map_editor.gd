@tool
class_name MapEditor
extends Node2D
## In-editor level designer. Paint high ground on the TileMapLayer, drag the Objective,
## drop ReferenceRects for spawn zones, then Bake.
##
## Three things this tool now does that it did not before, each of which corresponds to a
## defect that actually shipped:
##
##  1. VALIDATES. Level 1 carries 20 high-ground cells at y=21 on a 19-row grid — build
##     spots that exist, cost memory, and can never be clicked — and a spawn zone of
##     height 23. Both were baked from here without complaint.
##  2. USES THE GAME'S GRID. It read a hardcoded TILE_SIZE and ignored origin_y entirely,
##     so the picture in the editor sat 60px above what the game rendered.
##  3. MEASURES. Nothing here told a designer whether a map was any good, which is why
##     both shipped maps have a detour factor of ~1.0 (enemies walk almost straight) and
##     leave all but 8 and 2 build spots outside Routine. Analyze reports those numbers
##     against explicit targets before you bake.

const D = preload("res://scripts/data.gd")   ## GRID is a const, so no autoload needed here.
const G = preload("res://scripts/game.gd")   ## CORE/ANCHOR_ROUTINE_RADIUS live here.

## Fired at the end of every _analyze(). The designer dock listens and refreshes its
## panel from _report_lines/_last_summary, instead of polling this node.
signal analysis_updated

@export var target_level: LevelData

@export_group("Actions")
@export var load_from_level: bool = false:
	set(v):
		if v: _load_from_level()
		load_from_level = false

@export var analyze: bool = false:
	set(v):
		if v: _analyze()
		analyze = false

@export var bake_to_level: bool = false:
	set(v):
		if v: _bake_to_level()
		bake_to_level = false

## Bake, then launch the game straight into this level — paint→playtest in one click.
## Writes a one-shot marker the game consumes at boot (Game.read_playtest_marker);
## a marker older than 60s is ignored, so a failed launch can't hijack a later run.
@export var playtest: bool = false:
	set(v):
		if v: _playtest()
		playtest = false

## Playtests launch with designer cheats: F1 +500 Dopamine, F2 +10 Insight, F3 turbo 5×,
## F4 clear wave — and NO telemetry, so runlog.csv stays honest. Turn off to playtest
## under real economy rules.
@export var playtest_designer_mode: bool = true

## Saves the target level WITHOUT touching geometry: waves, economy, boss, drafts —
## everything you edit by clicking Target Level above and expanding it. Separate from
## Bake so tuning numbers never requires the painted map to be valid. Backs up first.
@export var save_level_settings: bool = false:
	set(v):
		if v: _save_level_settings()
		save_level_settings = false

## Creates data/levels/level_<N>.tres as a copy of the current target level — geometry,
## waves, everything (a working template beats a blank file) — with the next free id,
## and points Target Level at it. The game picks it up automatically: Data scans
## data/levels/ at startup and sorts by id.
@export var create_new_level: bool = false:
	set(v):
		if v: _create_new_level()
		create_new_level = false

@export var add_spawn_zone: bool = false:
	set(v):
		if v: _add_spawn_zone()
		add_spawn_zone = false

# ---------------------------------------------------------------- native editing
#
# Maluje se VESTAVĚNÝM editorem dlaždic — žádné razítkovací režimy, žádné přebírání
# kliků. Vyber vrstvu (HighGroundTiles = zdi, PathTiles = cesty), maluj; spawny, cíl
# a rekvizity jsou obyčejné uzly a hýbe se s nimi nástrojem výběru. Vlastní razítkovací
# nástroj s pěti režimy tu byl a byl to omyl: reimplementoval půlku Godotu, hůř.
#
# Tenhle skript už jen: staví abstraktní dlaždice vrstev, drží split-view náhled
# (SubViewport se StylizedRenderer — „samsfacee" workflow), validuje, měří a peče.

## Kosočtverečná dlaždice pro abstraktní malování. Levá strana split-view má být čitelná
## jako plán, ne hezká — hezká je pravá strana.
##
## KOSOČTVEREC, NE ČTVEREC. Do 21. 8. 2026 se tu kreslil čtverec a vrstvy byly
## TILE_SHAPE_SQUARE, zatímco hra kreslí 2:1 izometrii. Designér tedy maloval do jiné
## projekce, než jakou dostal — a co hůř, editor si odporoval i sám v sobě: mřížka, cíl,
## zóny a teplotní mapa se kreslily čtvercově, ale kruh Routine a trasy nepřátel
## izometricky (přes `D.cell_center()`). Půlka obrazu ukazovala něco jiného než druhá.
static func _abstract_tile(fill: Color, edge: Color, w: int, h: int) -> ImageTexture:
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	# Řádek po řádku: v 2:1 kosočtverci je polovina šířky lineární funkcí vzdálenosti
	# od svislého středu. Kreslí se přímo do rastru, aby hrana seděla na pixel a dvě
	# sousední dlaždice se nepřekrývaly ani nenechávaly škvíru.
	# VÝPLŇ JE PRŮSVITNÁ, OKRAJ PEVNÝ. Plná výplň vypadá logicky ("blok je vyplněný"),
	# ale na desce z ní je jednolitý koberec: nepoznáš, kde jeden blok končí a druhý
	# začíná, ani neuvidíš mřížku a překryvy pod ním. Průsvitná výplň s ostrým okrajem
	# čte obojí — kolik toho je i kde jsou švy.
	var body := Color(fill.r, fill.g, fill.b, 0.30)
	var rim := Color(edge.r, edge.g, edge.b, 0.95)
	var hw := float(w) * 0.5
	var hh := float(h) * 0.5
	var thick: int = 2 if w <= 96 else 3
	for y in range(h):
		var dy: float = absf(float(y) + 0.5 - hh) / hh
		var half: float = hw * (1.0 - dy)
		var x0 := int(round(hw - half))
		var x1 := int(round(hw + half)) - 1
		for x in range(maxi(x0, 0), mini(x1, w - 1) + 1):
			var on_edge: bool = (x < x0 + thick or x > x1 - thick
				or y < thick - 1 or y > h - thick)
			img.set_pixel(x, y, rim if on_edge else body)
	return ImageTexture.create_from_image(img)

## `span` = kolik BUNĚK má dlaždice na stranu. 1 = jedna buňka, 3 = celý stavební blok.
func _abstract_tileset(fill: Color, edge: Color, span: int = 1) -> TileSet:
	var g := _grid()
	var w: int = int(g.get("tile_w", 64)) * span
	var h: int = int(g.get("tile_h", 32)) * span
	var ts := TileSet.new()
	ts.tile_shape = TileSet.TILE_SHAPE_ISOMETRIC
	ts.tile_layout = TileSet.TILE_LAYOUT_DIAMOND_DOWN
	ts.tile_size = Vector2i(w, h)
	var src := TileSetAtlasSource.new()
	src.texture = _abstract_tile(fill, edge, w, h)
	src.texture_region_size = Vector2i(w, h)
	src.create_tile(Vector2i.ZERO)
	# Bez jména hlásí paleta „Zdroj neznámého typu" — zdroj je postavený za běhu, takže
	# nemá soubor, ze kterého by si Godot jméno vzal.
	src.resource_name = "Blok 3×3" if span > 1 else "Buňka"
	ts.add_source(src, 0)
	return ts

# ---------------------------------------------------------------- bloky

## Malování po BLOCÍCH je výchozí způsob, a je to jediná věc, která tenhle editor dělá
## pochopitelným pro někoho, kdo nezná pravidla hry.
##
## Hra staví na bloky 3x3 (`Data.BUILD_BLOCK`) a stavební místo vznikne JEN tam, kde je
## celý blok vysokou zemí. Když se maluje po buňkách, drtivá většina namalované terasy
## je proto zeď bez užitku — a nikde to není vidět. Když je jednotka malby rovnou blok,
## tohle pravidlo přestane být skrytá past a stane se tvarem štětce.
##
## Geometrie sedí PŘESNĚ, není to aproximace: střed buňky (3bx+1, 3by+1) je
## ((bx-by)*3*tile_w/2, (bx+by+1)*3*tile_h/2) od počátku, což je totéž co střed buňky
## (bx,by) v izometrické mřížce s dlaždicí (3*tile_w, 3*tile_h). Blokové vrstvy proto
## mají stejný `position` jako buňkové a nepotřebují žádný posun.
const BLOCK_LAYERS := {
	"BlockTiles": "high",
	"BlockPath": "path",
	"BlockSpawn": "spawn",
	"BlockGoal": "goal",
}

# ---------------------------------------------------------------- výběr dlaždic artem

## Adresáře, ze kterých se skládá paleta „vyber podle obrázku".
## Paleta se staví ZE SOUBORŮ NA DISKU, ne z ručního seznamu — nový art se v ní objeví
## sám, jakmile ho vygenerujeme, a nemusí se nikde dopisovat.
const ART_DIRS := ["ground", "lane", "props"]
const ART_ROOT := "res://assets/terrain/iso/"

## Pořadí souborů určuje id zdroje v TileSetu, takže musí být STABILNÍ napříč spuštěními
## — jinak by se po přidání jedné textury přeházely všechny už namalované dlaždice.
## Proto setříděné podle cesty, ne podle pořadí ze souborového systému.
func art_tile_paths() -> Array[String]:
	var out: Array[String] = []
	for sub in ART_DIRS:
		var dir := DirAccess.open(ART_ROOT + sub)
		if dir == null:
			continue
		var names: Array[String] = []
		for f in dir.get_files():
			if f.ends_with(".png"):
				names.append(f.get_basename())
		names.sort()
		for n in names:
			out.append("%s/%s" % [sub, n])
	return out

func _art_tileset() -> TileSet:
	var g := _grid()
	var ts := TileSet.new()
	ts.tile_shape = TileSet.TILE_SHAPE_ISOMETRIC
	ts.tile_layout = TileSet.TILE_LAYOUT_DIAMOND_DOWN
	ts.tile_size = Vector2i(int(g.get("tile_w", 64)), int(g.get("tile_h", 32)))
	var paths := art_tile_paths()
	for i in range(paths.size()):
		var p := "%s%s.png" % [ART_ROOT, paths[i]]
		if not ResourceLoader.exists(p):
			continue
		var tex: Texture2D = load(p)
		var src := TileSetAtlasSource.new()
		src.texture = tex
		src.texture_region_size = tex.get_size()
		src.create_tile(Vector2i.ZERO)
		src.resource_name = paths[i]
		ts.add_source(src, i)
	return ts

## Rozseje seznam buněk na blokovou vrstvu (celé bloky) a buňkovou vrstvu (zbytek).
func _fill_layers(cells: Array[Vector2i], block_layer: String, cell_layer: TileMapLayer) -> void:
	var bl: TileMapLayer = get_node_or_null(block_layer)
	if bl != null:
		bl.clear()
	if cell_layer != null:
		cell_layer.clear()
	var want := {}
	for c: Vector2i in cells:
		if D.in_bounds(c):
			want[c] = true
	var n := D.BUILD_BLOCK
	var covered := {}
	if bl != null:
		var blocks := {}
		for c: Vector2i in want:
			blocks[Vector2i(int(floorf(float(c.x) / n)), int(floorf(float(c.y) / n)))] = true
		for b: Vector2i in blocks:
			var full := true
			for bc in block_cells(b):
				if not want.has(bc):
					full = false
					break
			if not full or block_cells(b).size() < n * n:
				continue
			bl.set_cell(b, 0, Vector2i.ZERO)
			for bc in block_cells(b):
				covered[bc] = true
	if cell_layer != null:
		for c: Vector2i in want:
			if not covered.has(c):
				cell_layer.set_cell(c, 0, Vector2i.ZERO)

## Vyrobí na plátně PLATNÝ začátek mapy: cíl uprostřed, prstenec terasy kolem něj,
## spawn v rohu a cesta mezi tím.
##
## PROČ TO EXISTUJE. Prázdné plátno je pro tuhle hru horší než pro jinou, protože
## „platná mapa" tu má netriviální podmínky: cíl musí být na středu bloku, kolem něj
## musí být 12–20 stavebních míst V DOSAHU SVĚTLA, ze spawnu musí vést cesta a nesmí
## být kratší než 25 buněk. Kdo je nezná, nakreslí něco, co Bake odmítne — a nedozví se
## proč dřív, než to zkusí. Tohle dá do ruky funkční mapu, kterou stačí ohýbat.
##
## Rozvržení není náhodné: prstenec o poloměru 1 bloku kolem cíle dá přesně tolik
## stavebních míst, aby se vešla do počátečního Routine, a cesta vede od rohu obloukem,
## takže detour vyjde nad 1.35 bez další práce.
func scaffold_starter_map() -> void:
	build_layers()
	var g := _grid()
	var blocks_x := int(g.cols) / D.BUILD_BLOCK
	var blocks_y := int(g.rows) / D.BUILD_BLOCK
	var mid := Vector2i(blocks_x / 2, blocks_y / 2)

	for layer_name in ["BlockTiles", "BlockPath", "BlockSpawn", "BlockGoal"]:
		var l: TileMapLayer = get_node_or_null(layer_name)
		if l != null:
			l.clear()
	var hg: TileMapLayer = get_node_or_null("HighGroundTiles")
	if hg != null:
		hg.clear()
	var pl: TileMapLayer = get_node_or_null("PathTiles")
	if pl != null:
		pl.clear()

	var goal: TileMapLayer = get_node_or_null("BlockGoal")
	if goal != null:
		goal.set_cell(mid, 0, Vector2i.ZERO)

	var spawn_b := Vector2i(0, 0)
	var spawn: TileMapLayer = get_node_or_null("BlockSpawn")
	if spawn != null:
		spawn.set_cell(spawn_b, 0, Vector2i.ZERO)

	# Terasa kolem cíle, ale s JEDNÍMI dveřmi — a to je celý trik téhle mapy.
	#
	# Detour se počítá jako délka cesty děleno vzdušnou (Manhattanovou) vzdáleností.
	# Lomená cesta ho tedy NEZVEDNE: Manhattan tu zatáčku už započítal. Zvednout ho umí
	# jedině skutečná překážka, kterou musí nepřítel obejít. Terasa je zeď, takže
	# kompaktní blok kolem jádra s jediným vstupem z odvrácené strany donutí hordu
	# obejít celý shluk — a detour vyleze nad cíl sám od sebe.
	# Dveře nejsou jeden volný blok, ale CHODBA až k okraji desky. Jeden volný blok
	# nestačí — shluk bere nejbližší bloky dokola, takže by za dveřmi vznikla kapsa
	# obklopená terasou a jádro by zůstalo zazděné. (Vyzkoušeno; test to chytil.)
	var corridor := {}
	for bx in range(mid.x + 1, blocks_x):
		corridor[Vector2i(bx, mid.y)] = true
	var door := mid + Vector2i(1, 0)
	var tiles: TileMapLayer = get_node_or_null("BlockTiles")
	var core := D.cell_center(block_center_cell(mid))
	if tiles != null:
		var cand: Array[Vector2i] = []
		for by in range(blocks_y):
			for bx in range(blocks_x):
				var cb := Vector2i(bx, by)
				if cb == mid or cb == spawn_b or corridor.has(cb):
					continue
				# Jen to, co je v dosahu světla — dál od jádra je tma a tam se stejně
				# stavět nedá, takže by to byla jen zeď navíc.
				if core.distance_to(D.cell_center(block_center_cell(cb))) \
						> G.CORE_ROUTINE_RADIUS:
					continue
				cand.append(cb)
		cand.sort_custom(func(p: Vector2i, q: Vector2i) -> bool:
			return core.distance_squared_to(D.cell_center(block_center_cell(p))) \
				< core.distance_squared_to(D.cell_center(block_center_cell(q))))
		var want: int = (TARGET_CORE_SPOTS_MIN + TARGET_CORE_SPOTS_MAX) / 2
		for i in range(mini(want, cand.size())):
			tiles.set_cell(cand[i], 0, Vector2i.ZERO)

	# Malovaný pruh se NEODHADUJE — spočítá se tou samou cestou, kterou skutečně půjde
	# horda. Kdyby se kreslil ručně, ukazoval by hráči jinudy, než kudy nepřátelé jdou,
	# a to je horší než žádný pruh.
	var path: TileMapLayer = get_node_or_null("BlockPath")
	if path != null:
		var solid := {}
		for c: Vector2i in _high_cells():
			solid[c] = true
		var objective := block_center_cell(mid)
		var start := block_center_cell(spawn_b)
		var route := _path_cells(start, objective, solid)
		var b := D.BUILD_BLOCK
		for c: Vector2i in route:
			var cb := Vector2i(int(floorf(float(c.x) / b)), int(floorf(float(c.y) / b)))
			if cb == mid or cb == spawn_b:
				continue
			path.set_cell(cb, 0, Vector2i.ZERO)
		if route.is_empty():
			push_warning("MapEditor: startovní mapa nemá cestu — to je vada scaffoldu")
	# `door` drží chodbu otevřenou; proměnná je tu kvůli čitelnosti záměru.
	assert(not corridor.is_empty() and corridor.has(door))

	last_action = "Nová mapa připravena · %s" % _clock()
	canvas_changed.emit()
	queue_redraw()
	_analyze()

## Pozice malovací vrstvy tak, aby `map_to_local()` vracelo TENTÝŽ bod jako
## `Data.cell_center()`.
##
## ZMĚŘENO 21. 8. 2026, ne odvozeno z dokumentace. Godot pro izometrický DIAMOND_DOWN
## vrací střed dlaždice jako `((x-y+1)*w/2, (x+y+1)*h/2)`, kdežto kanonický převod hry
## je `((x-y)*w/2, (x+y+1)*h/2)`. V ose y se shodují, v ose x se liší o **půl dlaždice**
## — obojí je samo o sobě konzistentní, ale dohromady ne, a používá se obojí najednou.
##
## Posun se proto sráží tady, jednou a měřitelně, místo aby se s ním počítalo v každém
## překryvu zvlášť.
##
## Pozn.: `scripts/game.gd` má tentýž rozdíl neopravený — podlaha tam leží o 32 px
## vpravo od věží, jádra a tras, které se kreslí přes `Data.cell_center()`. Viz
## `scripts/_probe_align.gd`.
func _layer_origin(span: int) -> Vector2:
	var g := _grid()
	return Vector2(float(g.origin_x) - float(g.get("tile_w", 64)) * 0.5 * span,
		float(g.origin_y))

## Buňky, které blok pokrývá.
static func block_cells(b: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var n := D.BUILD_BLOCK
	for dy in range(n):
		for dx in range(n):
			out.append(Vector2i(b.x * n + dx, b.y * n + dy))
	return out

## Prostřední buňka bloku — klíč do `Game.build_spots` a jediné platné místo pro cíl.
static func block_center_cell(b: Vector2i) -> Vector2i:
	var n := D.BUILD_BLOCK
	return Vector2i(b.x * n + n / 2, b.y * n + n / 2)

## Všechny buňky namalované na blokové vrstvě.
func _cells_from_blocks(layer_name: String) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var tm: TileMapLayer = get_node_or_null(layer_name)
	if tm == null:
		return out
	for b: Vector2i in tm.get_used_cells():
		out.append_array(block_cells(b))
	return out

## Přemaluje cizí/staré dlaždice vrstvy na (0, (0,0)) — po výměně tilesetů by jinak
## buňky odkazovaly na neexistující zdroje a kreslily se prázdné.
static func _normalize_layer(tm: TileMapLayer) -> void:
	for c: Vector2i in tm.get_used_cells():
		if tm.get_cell_source_id(c) != 0 or tm.get_cell_atlas_coords(c) != Vector2i.ZERO:
			tm.set_cell(c, 0, Vector2i.ZERO)

# ---------------------------------------------------------------- split-view nahled
#
# "Samsfacee" workflow: vlevo abstraktni plan, vpravo zive vykresleny level. Pravou
# pulku (SubViewport + StylizedRenderer, kamera synchronizovana s 2D pohledem) vlastni
# PLUGIN - pripina ji k pravemu okraji canvas editoru. Tenhle skript jen hlida otisk
# platna a pri kazde zmene vystreli canvas_changed; plugin na nej prekresli.

signal canvas_changed

var _preview_fp: int = 0

@export_group("Overlays")
## Draws the playable bounds, the Focus core's Routine reach, and every spawn zone, so
## the constraints are visible while painting instead of discovered after baking.
@export var show_overlays: bool = true:
	set(v):
		show_overlays = v
		queue_redraw()

## Re-runs Analyze automatically ~0.8s after the last edit (terrain, zones, objective),
## so the drawn paths and the metrics panel stay current while painting. Fingerprint
## polling, no signals — cheap, and version-proof. Turn off on a pathological map.
@export var live_analyze: bool = true

## Tints every cell by how many spawn cells route through it — the maze's killzones and
## dead corridors, visible before a single enemy walks. Refreshed by Analyze.
@export var show_traffic: bool = true:
	set(v):
		show_traffic = v
		queue_redraw()

## The "what am I looking at?" box below the field: one line per color/shape on this
## canvas. Costs nothing when you know the tool; turn it off then.
@export var show_legend: bool = true:
	set(v):
		show_legend = v
		queue_redraw()

# ---------------------------------------------------------------- live-analysis state

## Sampled enemy routes from the last analysis, in editor world space — what _draw()
## renders so the designer SEES where the maze sends enemies, not just a detour number.
var _preview_paths: Array[PackedVector2Array] = []
## Headline report rows for the on-canvas panel: {text: String, ok: int} with
## ok 1 = target met, 0 = MISS, -1 = neutral/informational.
var _report_lines: Array = []
## Vector2i cell -> how many spawn cells' shortest routes pass through it. The heat
## overlay's data; _traffic_max normalizes the colors.
var _traffic: Dictionary = {}
var _traffic_max: int = 0
## _wave_summary() output cached at analysis time, so _draw() can render the difficulty
## bar chart without recomputing the curve every frame.
var _last_summary: Dictionary = {}

## Strukturovaný stav mapy z poslední analýzy. Syrová čísla; větu z nich dělá
## `map_health()`.
var _health: Dictionary = {}

# ---------------------------------------------------------------- semafor

## Jedna věta, která říká, jestli se mapa dá hrát — a když ne, co s tím.
##
## PROČ TO NENÍ JEN DALŠÍ ŘÁDEK METRIK. Metrika „detour factor 1.02, cíl >= 1.35" je
## užitečná až pro toho, kdo ví, co detour factor je. Pro každého jiného je to šum,
## ve kterém se nepozná, jestli je mapa rozbitá, nebo jen průměrná. Čísla proto
## zůstávají, ale až POD odpovědí na otázku „můžu to hrát?".
##
## Vrací {"level": "ok"|"warn"|"broken"|"none", "headline": String, "advice": Array}.
func map_health() -> Dictionary:
	if target_level == null:
		return {"level": "none", "headline": "Vyber level v poli Target Level.",
			"advice": []}
	if _health.is_empty():
		return {"level": "none", "headline": "Zatím nezměřeno — dej Analyze.",
			"advice": []}

	var advice: Array[String] = []

	# 1. Blokující vady. Bake je stejně odmítne, takže nemá smysl řešit nic jiného.
	var problems: Array = _health.get("problems", [])
	if not problems.is_empty():
		return {"level": "broken",
			"headline": "Mapa se nedá uložit — %d vada(y)." % problems.size(),
			"advice": _czech_problems(problems)}

	# 2. Průchodnost. Mapa, ze které se nedá dojít k cíli, není těžká, je rozbitá.
	if not bool(_health.get("any_route", false)):
		return {"level": "broken",
			"headline": "Nepřátelé se vůbec nedostanou k cíli.",
			"advice": ["Někde jsi terasou přehradil celou cestu. Smaž pár bloků mezi "
				+ "spawnem a cílem — terasa je zeď, nepřátelé přes ni neprojdou."]}
	var unreach := int(_health.get("unreachable_spawn", 0))
	if unreach > 0:
		return {"level": "broken",
			"headline": "%d spawn buněk nemá cestu k cíli." % unreach,
			"advice": ["Část spawnu je zazděná. Buď ji odkryj, nebo spawn přesuň jinam."]}

	# 3. Varování: hratelné, ale mapa zatím nic zajímavého nedělá.
	var detour := float(_health.get("detour", 0.0))
	if detour > 0.0 and detour < TARGET_DETOUR:
		advice.append("Nepřátelé jdou skoro rovně (%.2f, chce to aspoň %.2f). Přidej "
			% [detour, TARGET_DETOUR]
			+ "bloky doprostřed trasy, ať ji musí obejít — z toho vzniká bludiště.")
	var shortest := int(_health.get("shortest", 999))
	if shortest < TARGET_MIN_SPAWN_PATH:
		advice.append("Spawn je moc blízko cíli (%d buněk, chce to aspoň %d). "
			% [shortest, TARGET_MIN_SPAWN_PATH]
			+ "Odsuň spawn dál, nebo trasu prodluž zatáčkou.")
	var core := int(_health.get("spots_core", 0))
	if core < TARGET_CORE_SPOTS_MIN:
		advice.append("Kolem cíle je málo místa na stavbu (%d, chce to %d–%d). "
			% [core, TARGET_CORE_SPOTS_MIN, TARGET_CORE_SPOTS_MAX]
			+ "Přimaluj bloky terasy blíž k cíli — dál od něj je tma a tam se nestaví.")
	elif core > TARGET_CORE_SPOTS_MAX:
		advice.append("Kolem cíle je stavebních míst moc (%d, chce to %d–%d). "
			% [core, TARGET_CORE_SPOTS_MIN, TARGET_CORE_SPOTS_MAX]
			+ "Uber bloky, ať si hráč musí vybírat.")
	var total := int(_health.get("spots_total", 0))
	var reach := int(_health.get("spots_reachable", 0))
	if total > 0 and reach < total:
		advice.append("%d stavebních míst je mimo dosah světla — hráč se tam nikdy "
			% (total - reach) + "nedostane. Buď je smaž, nebo k nim veď cestu blíž.")

	if advice.is_empty():
		return {"level": "ok", "headline": "Mapa je hratelná a měří se dobře.",
			"advice": []}
	return {"level": "warn", "headline": "Hratelné, ale dá se to zlepšit:",
		"advice": advice}

## Blokující vady jsou psané anglicky pro log; tady se z nich dělá věta pro člověka.
func _czech_problems(problems: Array) -> Array[String]:
	var out: Array[String] = []
	for p in problems:
		var s := String(p)
		if s.contains("No spawn zones"):
			out.append("Chybí spawn. Namaluj aspoň jeden blok na vrstvu BlockSpawn.")
		elif s.contains("Objective") and s.contains("outside the grid"):
			out.append("Cíl je mimo mřížku. Namaluj blok na vrstvu BlockGoal uvnitř desky.")
		elif s.contains("Objective") and s.contains("high ground"):
			out.append("Cíl stojí na terase. Smaž tam blok terasy — jádro potřebuje "
				+ "vlastní buňku.")
		elif s.contains("outside the") and s.contains("grid"):
			out.append("Něco jsi namaloval mimo desku. Ty bloky se do hry nedostanou "
				+ "— smaž je.")
		else:
			out.append(s)
		if out.size() >= 3:
			break
	return out
## One-line record of the last write/launch ("Baked → level_1.tres · 14:32"), surfaced
## by the dock so success is never something you go check in the Output console.
var last_action := ""
## The on-canvas info boxes (metrics panel, legend, difficulty chart) below the field.
## The designer dock flips this off when it takes over their job. Deliberately NOT an
## export: the plugin toggling it must never mark the scene as modified.
var draw_info_boxes := true

func _clock() -> String:
	return Time.get_time_string_from_system().substr(0, 5)
var _fingerprint: int = 0
var _recheck_accum: float = 0.0
var _analyze_delay: float = 0.0

# ---------------------------------------------------------------- design targets
#
# Measured against the shipped maps, which fail most of them. Analyze flags each miss.

const TARGET_DETOUR := 1.35        ## path length vs straight-line; 1.0 means "no maze"
const TARGET_CORE_SPOTS_MIN := 12  ## build spots inside the core's Routine reach
const TARGET_CORE_SPOTS_MAX := 20
const TARGET_MIN_SPAWN_PATH := 25  ## cells; stops a spawn opening next to the objective

func _grid() -> Dictionary:
	return D.GRID

func _tile() -> int:
	return int(_grid().tile)

# ---------------------------------------------------------------- live loop (editor only)

func _process(delta: float) -> void:
	if not Engine.is_editor_hint():
		return
	_snap_children()

	# Náhled má VLASTNÍ, levnější otisk a NENÍ debouncovaný — překreslit pravou stranu
	# nestojí nic vedle pathfindingu, a náhled o 0,8 s za štětcem je horší než žádný.
	# Otisk pokrývá všechno, co pravá strana kreslí: zdi, cesty, rekvizity, zóny, cíl.
	var tmp: TileMapLayer = get_node_or_null("HighGroundTiles")
	var ptl: TileMapLayer = get_node_or_null("PathTiles")
	var props_sig: Array = []
	var props_node: Node2D = get_node_or_null("Props")
	if props_node != null:
		for ch in props_node.get_children():
			var s := ch as Sprite2D
			if s != null:
				props_sig.append([s.texture, s.position, s.flip_h])
	var pfp: int = hash([
		tmp.get_used_cells() if tmp != null else [],
		ptl.get_used_cells() if ptl != null else [],
		props_sig, _read_zones(), _read_objective()])
	if pfp != _preview_fp:
		_preview_fp = pfp
		canvas_changed.emit()

	if not live_analyze or target_level == null:
		return
	_recheck_accum += delta
	if _recheck_accum >= 0.3:
		_recheck_accum = 0.0
		var fp := _current_fingerprint()
		if fp != _fingerprint:
			_fingerprint = fp
			_analyze_delay = 0.8   # debounce: analyze once the strokes stop
	if _analyze_delay > 0.0:
		_analyze_delay -= delta
		if _analyze_delay <= 0.0:
			_analyze()

## Cheap identity of everything analysis depends on. When it changes, an edit happened.
func _current_fingerprint() -> int:
	var tm: TileMapLayer = get_node_or_null("HighGroundTiles")
	var parts := []
	if tm != null:
		parts.append(tm.get_used_cells())
	parts.append(_read_objective())
	parts.append(_read_zones())
	parts.append(_settings_fingerprint())
	return hash(parts)

## The FUNCTION half folded into the edit fingerprint: tuning waves, economy or the boss
## in the Inspector refreshes the analysis exactly like painting terrain does.
func _settings_fingerprint() -> int:
	if target_level == null:
		return 0
	var tl := target_level
	var parts := [tl.id, tl.display_name, tl.start_dopamine, tl.focus, tl.quick_hit,
		tl.wave_count, tl.draft_interval, tl.lean_waves,
		tl.boss.resource_path if tl.boss != null else ""]
	for e in tl.wave_curve:
		if e == null:
			parts.append("null")
			continue
		parts.append([String(e.distraction.id) if e.distraction != null else "",
			e.from_wave, e.base_count, e.growth_per_wave, e.spacing])
	return hash(parts)

## Grid snap while dragging the Objective or a zone rect. Assigns ONLY when the rounded
## value differs — an idle scene must not be re-dirtied frame after frame, and undo is
## not fought (a restored value just gets re-rounded once, idempotently).
func _snap_children() -> void:
	var t := float(_tile())
	var obj: Node2D = get_node_or_null("Objective")
	if obj != null:
		var sp := Vector2(_snap_px(obj.position.x, t), _snap_px(obj.position.y, t))
		if not obj.position.is_equal_approx(sp):
			obj.position = sp
	var sz: Node2D = get_node_or_null("SpawnZones")
	if sz != null:
		for child in sz.get_children():
			if child is ReferenceRect or child is ColorRect:
				var p := Vector2(_snap_px(child.position.x, t), _snap_px(child.position.y, t))
				var s := Vector2(maxf(t, _snap_px(child.size.x, t)),
					maxf(t, _snap_px(child.size.y, t)))
				if not child.position.is_equal_approx(p):
					child.position = p
				if not child.size.is_equal_approx(s):
					child.size = s

func _snap_px(v: float, t: float) -> float:
	return roundf(v / t) * t

# ---------------------------------------------------------------- scene scaffolding

func _get_or_create(node_name: String, type_name: String) -> Node:
	var n = get_node_or_null(node_name)
	if n == null:
		match type_name:
			"TileMapLayer": n = TileMapLayer.new()
			"Sprite2D": n = Sprite2D.new()
			"Node2D": n = Node2D.new()
			_: n = Node.new()
		n.name = node_name
		add_child(n)
	if Engine.is_editor_hint() and get_tree().edited_scene_root != null and n.owner == null:
		n.owner = owner if owner != null else get_tree().edited_scene_root
	return n

func _enter_tree() -> void:
	if not Engine.is_editor_hint():
		return
	build_layers()

## Postaví (nebo opraví) všechny malovací vrstvy. Oddělené od `_enter_tree()` schválně:
## v běžícím projektu `_enter_tree` skončí hned na `is_editor_hint()`, takže bez tohohle
## vstupního bodu se geometrie bloků nedá ověřit headless harnessem — a přesně u ní se
## chyba o půl dlaždice pozná až očima, pozdě.
func build_layers() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	var tm := _get_or_create("HighGroundTiles", "TileMapLayer") as TileMapLayer
	var pt := _get_or_create("PathTiles", "TileMapLayer") as TileMapLayer
	var obj := _get_or_create("Objective", "Sprite2D") as Sprite2D
	_get_or_create("SpawnZones", "Node2D")
	_get_or_create("Props", "Node2D")

	# Pozůstatky starých verzí: náhled býval TileMapLayer ve scéně, pak SubViewport ve
	# scéně. Teď ho vlastní plugin — kdyby tu uzly zůstaly, kreslily by zastaralý obraz.
	for stale_name in ["TerrainPreview", "PreviewPane"]:
		var stale := get_node_or_null(stale_name)
		if stale != null:
			stale.queue_free()

	# Everything the game renders is offset by origin_y. Applying the same offset here is
	# what makes the editor's picture and the running game agree.
	var oy: int = int(_grid().origin_y)
	tm.position = Vector2(int(_grid().origin_x), oy)
	pt.position = tm.position
	# Stará verze tlumila malovací vrstvu pod náhledem na 22 % — teď je náhled vedle,
	# takže se maluje v plné síle. Bez resetu by hodnota přežila v .tscn.
	tm.modulate = Color.WHITE

	# Abstraktní dlaždice: levá strana je PLÁN, ne umění — barvy volené jako legenda
	# (sytá fialová = zeď, sytá oranžová = cesta), ať se čtou i přes overlay a mřížku.
	# Herní paletu nese pravá strana náhledu. Cesty pod zdmi, ať malování zdí přes
	# cestu nechá cestu vidět jen tam, kde zeď není.
	tm.tile_set = _abstract_tileset(Color("8b3fd6"), Color("4e1f66"))
	pt.tile_set = _abstract_tileset(Color("f08c28"), Color("a85a10"))
	move_child(pt, mini(tm.get_index(), pt.get_index()))
	_normalize_layer(tm)
	_normalize_layer(pt)
	for layer in [tm, pt]:
		layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	# Blokové vrstvy — výchozí způsob malování. Jedno kliknutí = jedno stavební místo.
	# Barvy jsou legenda, ne herní paleta: fialová zeď, oranžová cesta, červený spawn,
	# zelený cíl. Pořadí dětí určuje překryv, proto se vrství odspodu: cesta, terasa,
	# spawn, cíl — cíl a spawny musí být vidět i přes terasu pod nimi.
	var block_style := {
		"BlockPath": [Color("f08c28"), Color("a85a10")],
		"BlockTiles": [Color("8b3fd6"), Color("4e1f66")],
		"BlockSpawn": [Color("e0433f"), Color("7a1d1b")],
		"BlockGoal": [Color("3fd67a"), Color("176b3a")],
	}
	for layer_name in ["BlockPath", "BlockTiles", "BlockSpawn", "BlockGoal"]:
		var bl := _get_or_create(layer_name, "TileMapLayer") as TileMapLayer
		var style: Array = block_style[layer_name]
		bl.tile_set = _abstract_tileset(style[0], style[1], D.BUILD_BLOCK)
		bl.position = _layer_origin(D.BUILD_BLOCK)
		bl.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		bl.modulate = Color(1, 1, 1, 0.85)
		_normalize_layer(bl)
		move_child(bl, get_child_count() - 1)

	# Buňkové vrstvy na stejnou kanonickou mřížku jako blokové.
	tm.position = _layer_origin(1)
	pt.position = tm.position

	# Vrstva pro ruční výběr dlaždic. Leží NEJNÍŽ ze všech, protože je to podlaha —
	# abstraktní bloky se kreslí přes ni, aby zůstalo vidět, kde je zeď a kde cesta.
	var art := _get_or_create("ArtTiles", "TileMapLayer") as TileMapLayer
	art.tile_set = _art_tileset()
	art.position = _layer_origin(1)
	art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	move_child(art, 0)

	if obj.texture == null:
		var t: int = _tile()
		var img := Image.create_empty(t, t, false, Image.FORMAT_RGBA8)
		img.fill(Color(0.2, 1.0, 0.2, 0.8))
		obj.texture = ImageTexture.create_from_image(img)
		obj.centered = false
	canvas_changed.emit()
	queue_redraw()

# ---------------------------------------------------------------- validation

## Returns a list of human-readable problems. Bake refuses while this is non-empty,
## because every entry here is something that silently corrupts a level.
func _validate(cells: Array[Vector2i], objective: Vector2i,
		zones: Array[Rect2i]) -> Array[String]:
	var g := _grid()
	var cols: int = int(g.cols)
	var rows: int = int(g.rows)
	var problems: Array[String] = []

	var off_grid: Array[Vector2i] = []
	for c in cells:
		if c.x < 0 or c.y < 0 or c.x >= cols or c.y >= rows:
			off_grid.append(c)
	if not off_grid.is_empty():
		problems.append("%d high-ground cells are outside the %dx%d grid (e.g. %s). They would become build spots that can never be clicked."
			% [off_grid.size(), cols, rows, str(off_grid.slice(0, 4))])

	if objective.x < 0 or objective.y < 0 or objective.x >= cols or objective.y >= rows:
		problems.append("Objective %s is outside the grid." % str(objective))
	elif cells.has(objective):
		problems.append("Objective %s sits on high ground — the core cell is skipped when build spots are created, so that tile would be lost."
			% str(objective))

	if zones.is_empty():
		problems.append("No spawn zones. Nothing would ever spawn.")
	for i in range(zones.size()):
		var z := zones[i]
		if z.size.x <= 0 or z.size.y <= 0:
			problems.append("Spawn zone %d has zero size." % i)
			continue
		if z.position.x < 0 or z.position.y < 0 \
				or z.position.x + z.size.x > cols or z.position.y + z.size.y > rows:
			problems.append("Spawn zone %d %s extends past the grid; the clipped part spawns nothing."
				% [i, str(z)])

	return problems

const LEVELS_DIR := "res://data/levels/"

## Problems in the level's FUNCTION half — waves, economy, drafts, boss. Same contract
## as _validate(): every entry is a reason to refuse writing the file, because each one
## either crashes wave building or ships a level that cannot be played.
func _validate_settings() -> Array[String]:
	var problems: Array[String] = []
	if target_level == null:
		return problems
	var tl := target_level

	if tl.wave_count < 1:
		problems.append("wave_count is %d — the level would end instantly." % tl.wave_count)
	if tl.wave_curve.is_empty():
		problems.append("wave_curve is empty — nothing would ever spawn.")
	var wave1_total := 0
	for i in range(tl.wave_curve.size()):
		var e: WaveCurveEntryData = tl.wave_curve[i]
		if e == null:
			problems.append("curve entry %d is empty (null) — delete it or fill it in." % i)
			continue
		if e.distraction == null:
			problems.append("curve entry %d has no distraction assigned." % i)
		if e.from_wave < 1 or e.from_wave > tl.wave_count:
			problems.append("curve entry %d: from_wave %d is outside 1..%d."
				% [i, e.from_wave, tl.wave_count])
		if e.base_count < 0:
			problems.append("curve entry %d: base_count is negative." % i)
		if e.base_count == 0 and e.growth_per_wave <= 0.0:
			problems.append("curve entry %d would never spawn anything (base 0, growth %s)."
				% [i, String.num(e.growth_per_wave, 1)])
		if e.spacing <= 0.0:
			problems.append("curve entry %d: spacing must be > 0 seconds." % i)
		if e.from_wave <= 1:
			wave1_total += e.base_count
	if not tl.wave_curve.is_empty() and wave1_total <= 0:
		problems.append("wave 1 has no spawns — the level opens with dead air.")

	var seen_lean := {}
	for lw in tl.lean_waves:
		if lw < 1 or lw > tl.wave_count:
			problems.append("lean wave %d is outside 1..%d." % [lw, tl.wave_count])
		if seen_lean.has(lw):
			problems.append("lean wave %d is listed twice." % lw)
		seen_lean[lw] = true

	if tl.draft_interval < 0:
		problems.append("draft_interval must be >= 0 (0 = only the guaranteed pre-final draft).")
	if tl.start_dopamine < 0:
		problems.append("start_dopamine is negative.")
	if tl.focus < 1:
		problems.append("focus is %d — the level would be lost before it starts." % tl.focus)

	# Two campaign files with the same id sort ambiguously in Data's level list. Only
	# checked for files that actually live in the campaign folder — a scratch copy
	# elsewhere cannot collide because Data never scans it.
	if tl.resource_path.begins_with(LEVELS_DIR):
		var dir := DirAccess.open(LEVELS_DIR)
		if dir != null:
			dir.list_dir_begin()
			var fn := dir.get_next()
			while fn != "":
				if not dir.current_is_dir() and fn.ends_with(".tres"):
					var p := LEVELS_DIR + fn
					if p != tl.resource_path:
						var other := load(p) as LevelData
						if other != null and other.id == tl.id:
							problems.append("id %d collides with %s — the campaign order becomes a coin flip." % [tl.id, fn])
				fn = dir.get_next()
			dir.list_dir_end()

	return problems

# ---------------------------------------------------------------- metrics

func _collect_cells(tm: TileMapLayer) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if tm != null:
		out.assign(tm.get_used_cells())
	return out

## Vysoká zem = namalované BLOKY plus případné doladění po buňkách.
##
## Obojí dohromady na JEDNOM místě schválně: kdyby to každý volající slučoval sám,
## analýza a Bake by se mohly rozejít — a rozdíl mezi „co mi editor naměřil" a „co se
## zapsalo do levelu" je přesně ten druh tiché neshody, který tenhle projekt už jednou
## stál měsíc.
## POZOR: buňky mimo mřížku se tu SCHVÁLNĚ nefiltrují. `_validate()` na ně hlásí vadu
## („namaloval jsi mimo desku") a když se odsud tiše zahodí, ta kontrola je mrtvá —
## což se 21. 8. 2026 na hodinu stalo a projevilo se to tak, že starý top-down level_1
## prošel jako „hratelný, jen průměrný", místo aby řekl, že do téhle mřížky nepatří.
func _high_cells() -> Array[Vector2i]:
	var seen := {}
	for c in _cells_from_blocks("BlockTiles"):
		seen[c] = true
	for c in _collect_cells(get_node_or_null("HighGroundTiles")):
		seen[c] = true
	var out: Array[Vector2i] = []
	out.assign(seen.keys())
	return out

## Cesta: totéž pro malovaný pruh. Cesta nikdy neleží pod terasou — terasa je zeď,
## takže by to byl pruh, kudy se nedá jít. Průnik se proto odečítá tady, ne až ve hře.
func _lane_cells() -> Array[Vector2i]:
	var high := {}
	for c in _high_cells():
		high[c] = true
	var seen := {}
	for c in _cells_from_blocks("BlockPath"):
		if not high.has(c):
			seen[c] = true
	for c in _collect_cells(get_node_or_null("PathTiles")):
		if not high.has(c):
			seen[c] = true
	var out: Array[Vector2i] = []
	out.assign(seen.keys())
	out.sort_custom(func(a: Vector2i, b: Vector2i):
		return a.y < b.y if a.y != b.y else a.x < b.x)
	return out

func _cell_center(cell: Vector2i) -> Vector2:
	return D.cell_center(cell)

## Kosočtverec jedné buňky pro překryvy. Čtverec by v 2:1 izometrii ukazoval jinam,
## než kam hra buňku kreslí — a překryv, který lže, je horší než žádný.
func _cell_diamond(cell: Vector2i, span: int = 1) -> PackedVector2Array:
	var g := _grid()
	var hw: float = float(g.get("tile_w", 64)) * 0.5 * span
	var hh: float = float(g.get("tile_h", 32)) * 0.5 * span
	var c := D.cell_center(cell)
	if span > 1:
		c = D.cell_center(cell) + Vector2(0.0, hh - float(g.get("tile_h", 32)) * 0.5)
	return PackedVector2Array([
		c + Vector2(0.0, -hh), c + Vector2(hw, 0.0),
		c + Vector2(0.0, hh), c + Vector2(-hw, 0.0)])

## Shortest path length in cells from `from` to `to`, routing around `solid`.
## Mirrors the game's AStarGrid2D setup: 4-way movement, high ground is solid.
func _path_len(from: Vector2i, to: Vector2i, solid: Dictionary) -> int:
	var g := _grid()
	var cols: int = int(g.cols)
	var rows: int = int(g.rows)
	if from == to:
		return 0
	var seen := {from: true}
	var queue: Array[Vector2i] = [from]
	var dist := {from: 0}
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_front()
		for d in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP, Vector2i.DOWN]:
			var nxt: Vector2i = cur + d
			if nxt.x < 0 or nxt.y < 0 or nxt.x >= cols or nxt.y >= rows:
				continue
			if seen.has(nxt) or (solid.has(nxt) and nxt != to):
				continue
			seen[nxt] = true
			dist[nxt] = int(dist[cur]) + 1
			if nxt == to:
				return int(dist[nxt])
			queue.append(nxt)
	return -1

## Full cell chain from `from` to `to` — same BFS rules as _path_len() (4-way, high
## ground solid except the target), plus parent pointers for reconstruction. Kept
## separate on purpose: _path_len() runs once per spawn CELL for the metrics (hundreds
## of calls), while this runs only for the ~3 drawn samples per zone.
func _path_cells(from: Vector2i, to: Vector2i, solid: Dictionary) -> Array[Vector2i]:
	var g := _grid()
	var cols: int = int(g.cols)
	var rows: int = int(g.rows)
	var out: Array[Vector2i] = []
	if from == to:
		return out
	var came := {from: from}
	var queue: Array[Vector2i] = [from]
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_front()
		for d in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP, Vector2i.DOWN]:
			var nxt: Vector2i = cur + d
			if nxt.x < 0 or nxt.y < 0 or nxt.x >= cols or nxt.y >= rows:
				continue
			if came.has(nxt) or (solid.has(nxt) and nxt != to):
				continue
			came[nxt] = cur
			if nxt == to:
				var walk: Vector2i = to
				while walk != from:
					out.push_front(walk)
					walk = came[walk]
				out.push_front(from)
				return out
			queue.append(nxt)
	return out

## Per-cell route load. One BFS from the objective builds the whole shortest-path tree
## over open cells; each spawn cell's route then just follows parent pointers home, so
## the total cost stays ~one _path_len() no matter how many spawn cells there are.
## Tie-breaking can differ from _path_cells()' spawn-side BFS — irrelevant for a heat
## overlay, both are shortest routes.
func _compute_traffic(solid: Dictionary, objective: Vector2i, zones: Array[Rect2i]) -> void:
	_traffic = {}
	_traffic_max = 0
	var g := _grid()
	var cols: int = int(g.cols)
	var rows: int = int(g.rows)
	if objective.x < 0 or objective.y < 0 or objective.x >= cols or objective.y >= rows \
			or solid.has(objective):
		return
	var came := {objective: objective}
	var queue: Array[Vector2i] = [objective]
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_front()
		for d in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP, Vector2i.DOWN]:
			var nxt: Vector2i = cur + d
			if nxt.x < 0 or nxt.y < 0 or nxt.x >= cols or nxt.y >= rows:
				continue
			if came.has(nxt) or solid.has(nxt):
				continue
			came[nxt] = cur
			queue.append(nxt)
	for z in zones:
		for x in range(maxi(0, z.position.x), mini(z.position.x + z.size.x, cols)):
			for y in range(maxi(0, z.position.y), mini(z.position.y + z.size.y, rows)):
				var c := Vector2i(x, y)
				if solid.has(c) or c == objective or not came.has(c):
					continue
				var walk := c
				while true:
					_traffic[walk] = int(_traffic.get(walk, 0)) + 1
					if walk == objective:
						break
					walk = came[walk]
	for v in _traffic.values():
		_traffic_max = maxi(_traffic_max, int(v))

## Greedy minimum-Anchor estimate under the chaining rule the game now enforces
## (Game.compute_routine_sources): an Anchor only projects Routine once it is itself
## inside Routine. Reports both how many spots are reachable at all and roughly what
## that coverage costs, which is the number that decides whether a map is affordable.
## POZOR NA HISTORII: do 21. 8. 2026 se tu za stavební místo považovala KAŽDÁ buňka
## vysoké země. Hra ale staví na bloky 3x3 (`game.gd`: buňka musí být střed bloku a
## celý blok musí být vysoká zem), takže analyzátor hlásil **devětkrát víc míst, než
## kolik jich ve hře existuje** — level 98 měl „63 spots" a ve skutečnosti sedm.
##
## Cíl 12–20 míst v Routine se tedy celou dobu porovnával proti nafouknutému číslu a
## každá mapa vypadala, že má stavění dost. Tady se počítá to samé co ve hře.
static func _build_spot_cells(cells: Array[Vector2i]) -> Array[Vector2i]:
	var solid := {}
	for c in cells:
		solid[c] = true
	var b := D.BUILD_BLOCK
	var out: Array[Vector2i] = []
	for cell: Vector2i in solid:
		if cell.x % b != b / 2 or cell.y % b != b / 2:
			continue
		var whole := true
		for dy in range(-(b / 2), b / 2 + 1):
			for dx in range(-(b / 2), b / 2 + 1):
				if not solid.has(cell + Vector2i(dx, dy)):
					whole = false
					break
			if not whole:
				break
		if whole:
			out.append(cell)
	return out

func _routine_report(cells: Array[Vector2i], objective: Vector2i) -> Dictionary:
	var core := _cell_center(objective)
	var pts: Array[Vector2] = []
	for c in _build_spot_cells(cells):
		pts.append(_cell_center(c))

	var in_core := 0
	for p in pts:
		if p.distance_to(core) <= G.CORE_ROUTINE_RADIUS:
			in_core += 1

	# Reachability: repeatedly absorb every spot the current sources cover.
	var sources: Array[Vector2] = [core]
	var remaining := pts.duplicate()
	var reachable := 0
	var grew := true
	while grew:
		grew = false
		var still: Array[Vector2] = []
		for p in remaining:
			if _covered(p, sources, core):
				sources.append(p)
				reachable += 1
				grew = true
			else:
				still.append(p)
		remaining = still

	# Cost: greedily pick, among currently covered spots, the Anchor that newly covers
	# the most. An approximation of set cover, which is enough to compare two layouts.
	var anchors := 0
	var covered_src: Array[Vector2] = [core]
	var uncovered := pts.duplicate()
	while true:
		var newly: Array[Vector2] = []
		for p in uncovered:
			if _covered(p, covered_src, core):
				newly.append(p)
		for p in newly:
			uncovered.erase(p)
		if uncovered.is_empty():
			break
		var best: Vector2 = Vector2.INF
		var best_gain := 0
		for cand in pts:
			if not _covered(cand, covered_src, core):
				continue
			var gain := 0
			for p in uncovered:
				if p.distance_to(cand) <= G.ANCHOR_ROUTINE_RADIUS:
					gain += 1
			if gain > best_gain:
				best_gain = gain
				best = cand
		if best_gain == 0:
			break
		covered_src.append(best)
		anchors += 1

	return {"in_core": in_core, "reachable": reachable, "total": pts.size(),
		"anchors": anchors, "unreachable": uncovered.size()}

func _covered(p: Vector2, sources: Array[Vector2], core: Vector2) -> bool:
	for s in sources:
		var r: float = G.CORE_ROUTINE_RADIUS if s == core else G.ANCHOR_ROUTINE_RADIUS
		if p.distance_to(s) <= r:
			return true
	return false

func _analyze() -> void:
	if target_level == null:
		print("MapEditor: assign a Target Level first.")
		return
	var tm: TileMapLayer = get_node_or_null("HighGroundTiles")
	var cells := _high_cells()
	var objective := _read_objective()
	var zones := _read_zones()

	_report_lines = []
	_preview_paths = []
	_health = {}

	print("\n========== MAP ANALYSIS: %s ==========" % target_level.resource_path)

	var problems := _validate(cells, objective, zones)
	var sproblems := _validate_settings()
	if problems.is_empty() and sproblems.is_empty():
		print("  validation: OK (map + settings)")
		_report_lines.append({"text": "validation: OK (map + settings)", "ok": 1})
	else:
		for p in problems:
			print("  BLOCKER: ", p)
		for p in sproblems:
			print("  BLOCKER (settings): ", p)
		_report_lines.append({"text": "%d BLOCKER(s) — bake/save will refuse:"
			% (problems.size() + sproblems.size()), "ok": 0})
		# Every blocker in full, right here — the fix happens on this canvas or in the
		# Inspector next to it, so a trip to the Output console must never be required.
		for p in problems + sproblems:
			var txt: String = p
			if txt.length() > 78:
				txt = txt.substr(0, 78) + "…"
			_report_lines.append({"text": "  " + txt, "ok": 0})

	var solid := {}
	for c in cells:
		solid[c] = true

	_compute_traffic(solid, objective, zones)

	# Path metrics per spawn zone — and the sampled routes the overlay draws.
	var g := _grid()
	var all_lens: Array[int] = []
	var shortest := 1 << 30
	var unreachable := 0
	for zi in range(zones.size()):
		var z := zones[zi]
		var open_cells: Array[Vector2i] = []
		for x in range(z.position.x, mini(z.position.x + z.size.x, int(g.cols))):
			for y in range(z.position.y, mini(z.position.y + z.size.y, int(g.rows))):
				var c := Vector2i(x, y)
				if solid.has(c) or c == objective:
					continue
				open_cells.append(c)
		var lens: Array[int] = []
		for c in open_cells:
			var l := _path_len(c, objective, solid)
			if l < 0:
				unreachable += 1
			else:
				lens.append(l)
				all_lens.append(l)
				shortest = mini(shortest, l)
		# Drawn routes: first / middle / last open cell — the same sampling the game's
		# own build-phase preview uses (game.gd _compute_path_previews).
		var samples: Array[int] = []
		if open_cells.size() >= 3:
			samples = [0, open_cells.size() / 2, open_cells.size() - 1]
		elif open_cells.size() == 2:
			samples = [0, 1]
		elif open_cells.size() == 1:
			samples = [0]
		for si: int in samples:
			var chain := _path_cells(open_cells[si], objective, solid)
			if chain.size() >= 2:
				var line := PackedVector2Array()
				for cc in chain:
					line.append(_cell_center(cc))
				_preview_paths.append(line)
		if lens.is_empty():
			print("  zone %d: no reachable spawn cells" % zi)
			continue
		var sum := 0
		for l in lens:
			sum += l
		print("  zone %d: %d cells · path min %d / avg %.1f / max %d"
			% [zi, lens.size(), lens.min(), float(sum) / lens.size(), lens.max()])

	if all_lens.is_empty():
		print("  no reachable spawn cells at all — enemies would idle forever")
		_report_lines.append({"text": "no reachable spawn cells — enemies would idle forever", "ok": 0})
	else:
		var sum := 0
		var manh := 0
		for l in all_lens:
			sum += l
		# Straight-line reference: Manhattan distance from each spawn cell.
		for zi2 in range(zones.size()):
			var z2 := zones[zi2]
			for x in range(z2.position.x, mini(z2.position.x + z2.size.x, int(g.cols))):
				for y in range(z2.position.y, mini(z2.position.y + z2.size.y, int(g.rows))):
					var c2 := Vector2i(x, y)
					if solid.has(c2) or c2 == objective:
						continue
					manh += absi(c2.x - objective.x) + absi(c2.y - objective.y)
		var detour: float = float(sum) / maxf(1.0, float(manh))
		_health["detour"] = detour
		_health["shortest"] = shortest
		_report("detour factor", "%.2f" % detour, detour >= TARGET_DETOUR,
			"target >= %.2f (1.00 means enemies walk straight; no maze)" % TARGET_DETOUR)
		_report("shortest spawn path", "%d cells" % shortest, shortest >= TARGET_MIN_SPAWN_PATH,
			"target >= %d" % TARGET_MIN_SPAWN_PATH)
	_health["unreachable_spawn"] = unreachable
	_health["any_route"] = not all_lens.is_empty()
	if unreachable > 0:
		print("  BLOCKER: %d spawn cells have no path to the objective" % unreachable)
		_report_lines.append({"text": "%d spawn cells have NO path to the objective"
			% unreachable, "ok": 0})

	var rr := _routine_report(cells, objective)
	_health["spots_total"] = int(rr.total)
	_health["spots_core"] = int(rr.in_core)
	_health["spots_reachable"] = int(rr.reachable)
	_health["problems"] = problems + sproblems
	_report("build spots", "%d" % rr.total, rr.total > 0, "")
	_report("spots in core Routine", "%d" % rr.in_core,
		rr.in_core >= TARGET_CORE_SPOTS_MIN and rr.in_core <= TARGET_CORE_SPOTS_MAX,
		"target %d-%d (this is where you can build before any Anchor)"
			% [TARGET_CORE_SPOTS_MIN, TARGET_CORE_SPOTS_MAX])
	_report("reachable by Anchor chain", "%d of %d (%.0f%%)"
		% [rr.reachable, rr.total, 100.0 * float(rr.reachable) / maxf(1.0, float(rr.total))],
		rr.reachable == rr.total, "spots left out can never be used")
	print("  Anchor cost to cover the map: ~%d Anchors (%d Dopamine)"
		% [rr.anchors, rr.anchors * 20])
	_report_lines.append({"text": "Anchor cost to cover: ~%d Anchors (%d ◆)"
		% [rr.anchors, rr.anchors * 20], "ok": -1})

	# What the level DOES, not only where its walls are. The full function readout lives
	# here on purpose: everything below is editable by clicking Target Level in the
	# Inspector, and seeing the current values next to the map is what makes that flow work.
	var ws := _wave_summary()
	_last_summary = ws
	if not ws.is_empty():
		print("  waves: ", ws.totals_text)
		print("  %s" % ws.line)
		_report_lines.append({"text": ws.line, "ok": -1})
	_report_lines.append({"text": "economy: start %d ◆ · focus %d · quick hit %s"
		% [target_level.start_dopamine, target_level.focus,
			"on" if target_level.quick_hit else "off"], "ok": -1})
	for e in target_level.wave_curve:
		if e == null or e.distraction == null:
			continue   # already flagged red by the validation rows above
		_report_lines.append({"text": "  curve: %s — from w%d · %d %s/w · every %ss"
			% [String(e.distraction.id), e.from_wave, e.base_count,
				("+" + String.num(e.growth_per_wave, 1)), String.num(e.spacing, 2)], "ok": -1})
	_report_lines.append({"text": "▶ edit ALL of this: click Target Level in the Inspector, then Save Level Settings",
		"ok": -1})

	print("=======================================\n")
	# Swallow the fingerprint change this analysis itself observed, so a Load or a
	# self-triggered run doesn't immediately schedule another one.
	_fingerprint = _current_fingerprint()
	queue_redraw()
	analysis_updated.emit()

## Per-wave spawn totals + the one-line function summary. MIRRORS Data.build_waves()
## (scripts/data.gd) — Data is an autoload and does not exist in the editor context,
## so the count formula is duplicated here. If build_waves() ever changes, change this.
func _wave_summary() -> Dictionary:
	return _wave_summary_for(target_level)

func _wave_summary_for(level: LevelData) -> Dictionary:
	if level == null or level.wave_curve.is_empty():
		return {}
	var totals: Array[int] = []
	for w in range(1, level.wave_count + 1):
		var total := 0
		for curve in level.wave_curve:
			if curve == null or w < curve.from_wave:
				continue
			total += roundi(curve.base_count + curve.growth_per_wave * (w - curve.from_wave))
		totals.append(total)
	var peak := 0
	var peak_wave := 0
	var sum := 0
	for i in range(totals.size()):
		sum += totals[i]
		if totals[i] > peak:
			peak = totals[i]
			peak_wave = i + 1
	var parts: Array[String] = []
	for i in range(totals.size()):
		parts.append(str(totals[i]))
	var lean_text := "none"
	if not level.lean_waves.is_empty():
		var lp: Array[String] = []
		for lw in level.lean_waves:
			lp.append(str(lw))
		lean_text = ",".join(lp)
	var line := "%d waves · %d spawns total · peak wave %d (%d) · lean %s · boss %s · draft every %d" \
		% [level.wave_count, sum, peak_wave, peak, lean_text,
			"yes" if level.boss != null else "no", level.draft_interval]
	return {"totals": totals, "peak": peak, "peak_wave": peak_wave, "sum": sum,
		"totals_text": " ".join(parts), "line": line}

## Everything the campaign overview needs about one level, computed straight from the
## RESOURCE — no scene, no Load. Reuses the same helpers Analyze runs on the canvas, so
## the two views cannot disagree about a map. Note: detour here averages over reachable
## spawn cells only, so it can differ slightly from Analyze on maps with cut-off cells.
func level_stats(level: LevelData) -> Dictionary:
	if level == null:
		return {}
	var g := _grid()
	var solid := {}
	for c in level.high_ground:
		solid[c] = true
	var rr := _routine_report(level.high_ground, level.objective)
	var shortest := -1
	var len_sum := 0
	var manh := 0
	for z: Rect2i in level.spawn_zones:
		for x in range(maxi(0, z.position.x), mini(z.position.x + z.size.x, int(g.cols))):
			for y in range(maxi(0, z.position.y), mini(z.position.y + z.size.y, int(g.rows))):
				var c2 := Vector2i(x, y)
				if solid.has(c2) or c2 == level.objective:
					continue
				var l := _path_len(c2, level.objective, solid)
				if l < 0:
					continue
				len_sum += l
				manh += absi(c2.x - level.objective.x) + absi(c2.y - level.objective.y)
				shortest = l if shortest < 0 else mini(shortest, l)
	var detour := 0.0
	if manh > 0:
		detour = float(len_sum) / float(manh)
	var ws := _wave_summary_for(level)
	return {
		"id": level.id, "name": level.display_name,
		"spots": rr.total, "core_spots": rr.in_core, "reachable": rr.reachable,
		"shortest": shortest, "detour": detour,
		"waves": level.wave_count, "spawns": int(ws.get("sum", 0)),
		"peak": int(ws.get("peak", 0)), "lean": level.lean_waves.size(),
		"boss": level.boss != null,
	}

func _report(label: String, value: String, ok: bool, note: String) -> void:
	print("  %s %-26s %-18s %s" % ["ok  " if ok else "MISS", label, value, note])
	# Panel copy: compact, with the target note only when it fits on one panel line.
	var text := "%s: %s" % [label, value]
	if not ok and note != "":
		var short := note
		if short.length() > 46:
			short = short.substr(0, 46) + "…"
		text += "  — MISS (%s)" % short
	_report_lines.append({"text": text, "ok": 1 if ok else 0})

# ---------------------------------------------------------------- bake / load

## Cíl: přednost má namalovaný blok na `BlockGoal`, teprve pak starý tahaný sprite.
##
## Namalovaný cíl je vždycky na středu bloku, což je jediné platné místo — validace to
## vyžaduje a hráč tam staví. Tahaný sprite to zaručit nemohl a byl navíc čtený
## ČTVERCOVĚ (`position / tile`), zatímco hra je izometrická; sprite tedy hlásil jinou
## buňku, než na které ležel. Fallback je proto opravený na kanonický převod.
func _read_objective() -> Vector2i:
	var goal: TileMapLayer = get_node_or_null("BlockGoal")
	if goal != null:
		var used := goal.get_used_cells()
		if not used.is_empty():
			return block_center_cell(used[0])
	var obj: Node2D = get_node_or_null("Objective")
	if obj == null:
		return Vector2i.ZERO
	return D.world_to_cell(obj.position)

## Spawny: přednost mají namalované bloky na `BlockSpawn`.
##
## Obdélník `ReferenceRect` byl v izometrii principiálně špatně — obdélník BUNĚK je na
## obrazovce kosočtverec, takže tažené rohy nikdy neodpovídaly tomu, co se zapeklo.
## Namalovaný blok je 3x3 buňky a převod je přesný.
func _read_zones() -> Array[Rect2i]:
	var out: Array[Rect2i] = []
	var sp: TileMapLayer = get_node_or_null("BlockSpawn")
	if sp != null and not sp.get_used_cells().is_empty():
		var n := D.BUILD_BLOCK
		for b: Vector2i in sp.get_used_cells():
			out.append(Rect2i(b.x * n, b.y * n, n, n))
		return out
	var sz: Node2D = get_node_or_null("SpawnZones")
	if sz == null:
		return out
	for child in sz.get_children():
		if child is ReferenceRect or child is ColorRect:
			var tl := D.world_to_cell(child.position)
			var br := D.world_to_cell(child.position + child.size)
			out.append(Rect2i(tl, Vector2i(maxi(1, br.x - tl.x), maxi(1, br.y - tl.y))))
	return out

## Returns true only when the level file was actually written — Playtest launches on
## that answer, and launching a game on a refused bake would test yesterday's map.
func _bake_to_level() -> bool:
	if target_level == null:
		push_warning("MapEditor: Assign a Target Level resource first!")
		print("MapEditor: ERROR — assign a Target Level resource first.")
		return false

	var tm: TileMapLayer = get_node_or_null("HighGroundTiles")
	var cells := _high_cells()
	var objective := _read_objective()
	var zones := _read_zones()

	# Bake saves the WHOLE resource, so broken settings would ride along with a clean
	# map into the file — both halves have to pass.
	var problems := _validate(cells, objective, zones)
	problems.append_array(_validate_settings())

	# Wipe guard. Bake replaces geometry outright, so opening the editor on an EMPTY
	# canvas and baking silently throws the target level's map away — which is exactly
	# what happened to level 1: one stamped 5x5 chamber overwrote 170 cells, because
	# Load had never been pressed. The .bak saved it, but a backup you have to know about
	# is not a safety net. Refuse instead, and say which button fixes it.
	var had: int = target_level.high_ground.size()
	if had >= 20 and cells.size() < had / 4:
		var wipe_msg := "canvas has %d cells but %s already holds %d — baking would delete most of the map. Press Load first to bring it onto the canvas, or clear Target Level's high_ground by hand if wiping is what you want."
		problems.append(wipe_msg % [cells.size(), target_level.resource_path.get_file(), had])
	if not problems.is_empty():
		print("\nMapEditor: BAKE REFUSED — %d problem(s):" % problems.size())
		for p in problems:
			print("  - ", p)
		print("Fix these, or run Analyze for the full report. Nothing was written.\n")
		return false

	var level_path := target_level.resource_path
	if not _secure_backup(level_path):
		print("MapEditor: BAKE REFUSED — backup copy failed. Nothing was written.")
		return false

	target_level.high_ground = cells
	target_level.objective = objective
	target_level.spawn_zones = zones

	# Cesty z vlastní vrstvy, seřazené (y, x). Na pořadí záleží: hra losuje variantu
	# dlaždice po prvcích pole, takže deterministické pořadí = stejná mapa v editoru,
	# ve hře i po každém dalším Bake.
	var lanes: Array[Vector2i] = []
	lanes.assign(_lane_cells())
	target_level.path_cells = lanes

	# Ruční přepisy dlaždic. Klíč je jméno souboru, ne id zdroje — id se posune,
	# jakmile do adresáře přibude textura, a level by se tiše přemaloval.
	var overrides := {}
	var art_layer: TileMapLayer = get_node_or_null("ArtTiles")
	if art_layer != null:
		var names := art_tile_paths()
		for c: Vector2i in art_layer.get_used_cells():
			var sid := art_layer.get_cell_source_id(c)
			if sid >= 0 and sid < names.size():
				overrides[c] = names[sid]
	target_level.tile_overrides = overrides

	# Rekvizity z uzlů: id = jméno souboru textury. Duplikuj sprite (Ctrl+D), přesuň,
	# hotovo — Bake si je posbírá.
	var dec: Array[Dictionary] = []
	var props_node: Node2D = get_node_or_null("Props")
	if props_node != null:
		for ch in props_node.get_children():
			var s := ch as Sprite2D
			if s == null or s.texture == null or s.texture.resource_path == "":
				continue
			dec.append({"id": s.texture.resource_path.get_file().get_basename(),
				"pos": s.position, "flip": s.flip_h})
	target_level.decor = dec

	# Abstraktní vrstva už nenese art identitu — tvar dělá rohové vykreslení ve hře.
	target_level.terrain_tiles = {}

	var err := ResourceSaver.save(target_level, target_level.resource_path)
	if err != OK:
		print("MapEditor: SAVE FAILED (%d)" % err)
		return false
	# Named loudly: the scene ships pointing at level_1, and overwriting the wrong level
	# is silent and unrecoverable without VCS.
	print("MapEditor: baked %d cells, %d lane cells, %d props, %d zones → %s"
		% [cells.size(), lanes.size(), dec.size(), zones.size(), target_level.resource_path])
	last_action = "Baked → %s · %s" % [target_level.resource_path.get_file(), _clock()]
	_analyze()
	return true

# ---------------------------------------------------------------- settings save / new level

## Copies the level file to <path>.bak before any overwrite. Returns false when the copy
## failed — on a VCS-less project a write that cannot secure the previous version must
## not happen. A path with no existing file has nothing to lose, so that passes.
## Keeps TWO generations, not one.
##
## A single rolling .bak is no protection against the failure that actually happens: bake
## a wrecked map, notice nothing, bake again — and the second backup overwrites the good
## one with the wreck. That is exactly how level 1's 170-cell backup became a 15-cell
## backup within half an hour, leaving git as the only surviving copy.
##
## So .bak holds the previous version and .bak2 the one before it, and .bak2 is only
## refreshed when .bak is about to be replaced.
func _secure_backup(level_path: String) -> bool:
	if level_path == "" or not FileAccess.file_exists(level_path):
		return true
	var abs_src := ProjectSettings.globalize_path(level_path)
	if FileAccess.file_exists(level_path + ".bak"):
		DirAccess.copy_absolute(abs_src + ".bak", abs_src + ".bak2")
	if DirAccess.copy_absolute(abs_src, abs_src + ".bak") != OK:
		return false
	print("MapEditor: previous version secured at %s.bak (older one at .bak2)" % level_path)
	return true

## Persists Inspector edits to the level's function half (waves, economy, boss, drafts)
## without re-baking geometry — the resource's stored layout fields are written back
## unchanged, so an unfinished paint job on screen can't leak into the file.
func _save_level_settings() -> bool:
	if target_level == null:
		print("MapEditor: assign a Target Level first.")
		return false
	var problems := _validate_settings()
	if not problems.is_empty():
		print("\nMapEditor: SETTINGS SAVE REFUSED — %d problem(s):" % problems.size())
		for p in problems:
			print("  - ", p)
		print("Nothing was written.\n")
		return false
	var level_path := target_level.resource_path
	if level_path == "":
		print("MapEditor: this level has no file yet — use Create New Level first.")
		return false
	if not _secure_backup(level_path):
		print("MapEditor: SETTINGS SAVE REFUSED — backup copy failed. Nothing was written.")
		return false
	var err := ResourceSaver.save(target_level, level_path)
	if err != OK:
		print("MapEditor: SETTINGS SAVE FAILED (%d)" % err)
		return false
	print("MapEditor: settings saved → %s" % level_path)
	var ws := _wave_summary()
	if not ws.is_empty():
		print("  %s" % ws.line)
	last_action = "Settings saved → %s · %s" % [level_path.get_file(), _clock()]
	_analyze()
	return true

func _create_new_level() -> void:
	if target_level == null:
		print("MapEditor: assign a Target Level to copy from first.")
		return
	var slot := _next_level_slot()
	var nl := _create_new_level_at(String(slot.path), int(slot.number))
	if nl == null:
		return
	target_level = nl
	print("MapEditor: created %s (id %d, \"%s\") and made it the Target Level — Load, paint, Bake."
		% [nl.resource_path, nl.id, nl.display_name])
	last_action = "Created %s · %s" % [nl.resource_path.get_file(), _clock()]
	_analyze()

## Next free file name AND id in one decision, so they can't drift apart: the id grows
## past the current maximum and the file number matches it.
func _next_level_slot() -> Dictionary:
	var max_id := 0
	var dir := DirAccess.open(LEVELS_DIR)
	if dir != null:
		dir.list_dir_begin()
		var fn := dir.get_next()
		while fn != "":
			if not dir.current_is_dir() and fn.ends_with(".tres"):
				var res := load(LEVELS_DIR + fn) as LevelData
				if res != null:
					max_id = maxi(max_id, res.id)
			fn = dir.get_next()
		dir.list_dir_end()
	var n := max_id + 1
	while FileAccess.file_exists(LEVELS_DIR + "level_%d.tres" % n):
		n += 1
	return {"path": LEVELS_DIR + "level_%d.tres" % n, "number": n}

## The copy discipline matters more than the copying: per-level data (curve entries,
## geometry arrays, painted tiles) must be OWN instances so editing the new level never
## mutates the template — while the shared defs (distractions, boss) must stay REFERENCES
## so the new level keeps tracking data/distractions instead of forking it.
func _create_new_level_at(path: String, number: int) -> LevelData:
	var nl := target_level.duplicate(true) as LevelData
	nl.id = number
	nl.display_name = "Level %d" % number
	nl.high_ground = target_level.high_ground.duplicate()
	nl.spawn_zones = target_level.spawn_zones.duplicate()
	nl.lean_waves = target_level.lean_waves.duplicate()
	nl.terrain_tiles = target_level.terrain_tiles.duplicate(true)
	var new_curve: Array[WaveCurveEntryData] = []
	for e in target_level.wave_curve:
		if e == null:
			continue
		var ne := e.duplicate() as WaveCurveEntryData
		ne.distraction = e.distraction
		new_curve.append(ne)
	nl.wave_curve = new_curve
	nl.boss = target_level.boss
	var err := ResourceSaver.save(nl, path)
	if err != OK:
		print("MapEditor: CREATE FAILED (%d) — nothing was written." % err)
		return null
	nl.take_over_path(path)
	return nl

# ---------------------------------------------------------------- playtest launch

const PLAYTEST_SCENE := "res://scenes/Game.tscn"

## Bake → marker → run. The whole point is closing the paint→playtest loop: what you
## see in the viewport is what the launched game loads, or nothing launches at all.
func _playtest() -> void:
	if target_level == null:
		print("MapEditor: assign a Target Level first.")
		return
	if not _bake_to_level():
		print("MapEditor: PLAYTEST ABORTED — bake refused, see above. Nothing was launched.")
		return
	_write_playtest_marker(target_level.resource_path, playtest_designer_mode)
	last_action = "Playtest %s · %s" % [target_level.resource_path.get_file(), _clock()]
	# EditorInterface only exists inside a running editor; resolved by name so this
	# script still parses and runs in game-only contexts (headless checks, exports).
	if Engine.is_editor_hint() and Engine.has_singleton("EditorInterface"):
		Engine.get_singleton("EditorInterface").call("play_custom_scene", PLAYTEST_SCENE)
	else:
		print("MapEditor: playtest marker written — launch the game within 60s to use it.")

## Format contract lives in Game.read_playtest_marker (scripts/game.gd) — keep in sync.
func _write_playtest_marker(level_path: String, designer: bool) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("playtest", "level_path", level_path)
	cfg.set_value("playtest", "designer", designer)
	cfg.set_value("playtest", "stamp", int(Time.get_unix_time_from_system()))
	var err := cfg.save(G.PLAYTEST_MARKER)
	if err != OK:
		print("MapEditor: could not write the playtest marker (error %d)." % err)

func _load_from_level() -> void:
	if target_level == null:
		push_warning("MapEditor: Assign a Target Level resource first!")
		return

	var tm: TileMapLayer = get_node_or_null("HighGroundTiles")
	var pt: TileMapLayer = get_node_or_null("PathTiles")
	var obj: Node2D = get_node_or_null("Objective")
	var sz: Node2D = get_node_or_null("SpawnZones")
	var props: Node2D = get_node_or_null("Props")
	var t: float = float(_tile())

	# Abstraktní vrstvy: jedna plná dlaždice na buňku, žádné autotilování — tvar dělá
	# až pravá strana split-view a hra.
	#
	# Rozdělení na bloky a zbytek: co je celý blok 3x3, jde na blokovou vrstvu (a dá se
	# tedy dál upravovat jedním klikem), co zbude, jde po buňkách. Nikdy ne obojí, jinak
	# by se stejná buňka počítala dvakrát a mazání by ji nechalo naživu na druhé vrstvě.
	_fill_layers(target_level.high_ground, "BlockTiles", tm)
	_fill_layers(target_level.path_cells, "BlockPath", pt)

	var art_layer: TileMapLayer = get_node_or_null("ArtTiles")
	if art_layer != null:
		art_layer.clear()
		var names := art_tile_paths()
		for key in target_level.tile_overrides:
			var idx := names.find(String(target_level.tile_overrides[key]))
			if idx >= 0:
				art_layer.set_cell(key, idx, Vector2i.ZERO)

	if props != null:
		for child in props.get_children():
			child.queue_free()
		for entry in target_level.decor:
			var tex := DecorLayer._texture_named(String(entry.get("id", "")))
			if tex == null:
				continue
			var s := Sprite2D.new()
			s.name = String(entry.get("id", "prop")).capitalize()
			s.texture = tex
			s.position = entry.get("pos", Vector2.ZERO)
			s.flip_h = bool(entry.get("flip", false))
			s.scale = Vector2.ONE * Data.pixel_scale()
			s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			props.add_child(s)
			_adopt(s)

	# Cíl a spawny se nově MALUJÍ, ne tahají. Staré uzly se proto vyprázdní — kdyby
	# zůstaly, `_read_objective()` by sice dalo přednost namalovanému, ale v pohledu by
	# ležely dvě značky na různých místech a nikdo by nevěděl, která platí.
	var n := D.BUILD_BLOCK
	var goal: TileMapLayer = get_node_or_null("BlockGoal")
	if goal != null:
		goal.clear()
		var oc := target_level.objective
		if D.in_bounds(oc):
			goal.set_cell(Vector2i(int(floorf(float(oc.x) / n)), int(floorf(float(oc.y) / n))),
				0, Vector2i.ZERO)
	if obj != null:
		obj.position = D.cell_center(target_level.objective)
		obj.visible = false

	var spawn: TileMapLayer = get_node_or_null("BlockSpawn")
	if spawn != null:
		spawn.clear()
		for rect: Rect2i in target_level.spawn_zones:
			# Obdélník buněk se pokryje bloky, které protíná. Zaokrouhluje se nahoru:
			# spawn menší než blok je pořád spawn a nesmí se ztratit.
			var b0 := Vector2i(int(floorf(float(rect.position.x) / n)),
				int(floorf(float(rect.position.y) / n)))
			var b1 := Vector2i(int(floorf(float(rect.position.x + maxi(rect.size.x, 1) - 1) / n)),
				int(floorf(float(rect.position.y + maxi(rect.size.y, 1) - 1) / n)))
			for by in range(b0.y, b1.y + 1):
				for bx in range(b0.x, b1.x + 1):
					spawn.set_cell(Vector2i(bx, by), 0, Vector2i.ZERO)
	if sz != null:
		for child in sz.get_children():
			child.queue_free()

	print("MapEditor: loaded %s" % target_level.resource_path)
	last_action = "Loaded %s · %s" % [target_level.resource_path.get_file(), _clock()]
	canvas_changed.emit()
	queue_redraw()
	_analyze()

func _add_spawn_zone() -> void:
	var sz: Node2D = get_node_or_null("SpawnZones")
	if sz == null:
		return
	var t: float = float(_tile())
	var rr := ReferenceRect.new()
	rr.name = "NewZone"
	rr.border_color = Color(1.0, 0.2, 0.2, 0.8)
	rr.border_width = 4.0
	rr.editor_only = false
	rr.position = Vector2.ZERO
	rr.size = Vector2(t * 2, t * 2)
	sz.add_child(rr)
	_adopt(rr)
	print("MapEditor: added a spawn zone.")

func _adopt(n: Node) -> void:
	if Engine.is_editor_hint() and get_tree().edited_scene_root != null:
		n.owner = owner if owner != null else get_tree().edited_scene_root

# ---------------------------------------------------------------- overlays

func _draw() -> void:
	if not Engine.is_editor_hint() or not show_overlays:
		return
	var g := _grid()
	var t: float = float(g.tile)
	var ox: float = float(g.origin_x)
	var oy: float = float(g.origin_y)
	var w: float = float(g.cols) * t
	var h: float = float(g.rows) * t

	# Hrací plocha. Izometricky — dřív se tu kreslil ČTVEREC, zatímco hra i kruh Routine
	# o pár řádků níž pracují v 2:1 kosočtverci, takže mřížka lhala o tom, kde buňka je.
	var cols := int(g.cols)
	var rows := int(g.rows)
	# Rohy desky: buňka (0,0) horní, (cols,0) pravá, (cols,rows) dolní, (0,rows) levá.
	var corner := func(cx: int, cy: int) -> Vector2:
		return Vector2(ox + (cx - cy) * (float(g.tile_w) * 0.5),
			oy + (cx + cy) * (float(g.tile_h) * 0.5))
	draw_polyline(PackedVector2Array([
		corner.call(0, 0), corner.call(cols, 0), corner.call(cols, rows),
		corner.call(0, rows), corner.call(0, 0)]), Color(0.4, 0.6, 1.0, 0.5), 3.0)

	# Mřížka buněk slabě, hranice BLOKŮ výrazněji — blok je jednotka, ve které se staví
	# i maluje, takže musí být vidět na první pohled, kde jeden končí.
	var blk := D.BUILD_BLOCK
	for c in range(cols + 1):
		var strong: bool = (c % blk == 0)
		draw_line(corner.call(c, 0), corner.call(c, rows),
			Color(1, 1, 1, 0.16 if strong else 0.05), 1.0)
	for r in range(rows + 1):
		var strong_r: bool = (r % blk == 0)
		draw_line(corner.call(0, r), corner.call(cols, r),
			Color(1, 1, 1, 0.16 if strong_r else 0.05), 1.0)

	# The Focus core's Routine reach — the only area buildable without an Anchor chain.
	var core := _cell_center(_read_objective())
	draw_arc(core, G.CORE_ROUTINE_RADIUS, 0.0, TAU, 64, Color(0.49, 1.0, 0.7, 0.9), 2.0)
	draw_circle(core, G.CORE_ROUTINE_RADIUS, Color(0.49, 1.0, 0.7, 0.06))
	draw_arc(core, G.ANCHOR_ROUTINE_RADIUS, 0.0, TAU, 64, Color(0.12, 0.9, 0.95, 0.35), 1.5)

	var font := ThemeDB.fallback_font

	# Traffic heat: how much of the horde funnels through each cell. Under the sampled
	# routes; sqrt lifts single-digit corridors into visibility next to the
	# everything-merges-here cells around the core.
	if show_traffic and _traffic_max > 0:
		for cell: Vector2i in _traffic:
			var f := sqrt(float(_traffic[cell]) / float(_traffic_max))
			draw_colored_polygon(_cell_diamond(cell),
				Color(1.0, 0.85 - 0.6 * f, 0.15, 0.06 + 0.3 * f))

	# Enemy routes from the last analysis — the maze made visible. Spawn end dotted,
	# small direction arrows along the way.
	var path_col := Color(1.0, 0.35, 0.4, 0.55)
	for path: PackedVector2Array in _preview_paths:
		if path.size() < 2:
			continue
		draw_polyline(path, path_col, 3.0)
		draw_circle(path[0], 6.0, Color(1.0, 0.35, 0.4, 0.85))
		for i in range(3, path.size() - 1, 6):
			var dir := (path[i + 1] - path[i]).normalized()
			var perp := dir.orthogonal()
			draw_colored_polygon(PackedVector2Array([
				path[i] + dir * 9.0, path[i] - dir * 4.0 + perp * 6.0,
				path[i] - dir * 4.0 - perp * 6.0]), path_col)

	# Popisky spawnů a cíle. Čtou se z toho, co je NAMALOVANÉ, takže ukazují přesně to,
	# co se zapeče — ne pozici uzlu, který už nikdo nepoužívá.
	var zi := 0
	for rect: Rect2i in _read_zones():
		draw_string(font, _cell_center(rect.position) + Vector2(-24, -10),
			"Spawn %d" % zi, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1.0, 0.35, 0.4, 0.95))
		zi += 1
	var ocell := _read_objective()
	if D.in_bounds(ocell):
		draw_string(font, _cell_center(ocell) + Vector2(-28, -14),
			"Cíl (%d, %d)" % [ocell.x, ocell.y],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.49, 1.0, 0.7, 0.95))

	# On-canvas metrics panel, below the play field (the grid spans the full width, so
	# below is the free space). The numbers that decide whether the map is good, without
	# a trip to the Output console. Skipped entirely when the designer dock is mounted —
	# it shows the same data as real UI, and duplicating it here would just be noise.
	if not draw_info_boxes:
		return
	var px := ox
	var py := oy + h + 16.0
	var line_h := 22.0
	var rows_n: int = maxi(1, _report_lines.size())
	var panel_h := line_h * float(rows_n) + 34.0
	draw_rect(Rect2(px, py, 720.0, panel_h), Color(0.04, 0.06, 0.11, 0.94))
	draw_rect(Rect2(px, py, 720.0, panel_h), Color(0.3, 0.4, 0.6, 0.8), false, 1.5)
	if _report_lines.is_empty():
		draw_string(font, Vector2(px + 12, py + 26),
			"Assign a Target Level, then Load or Analyze to measure this map.",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.7, 0.75, 0.85))
	else:
		for i in range(_report_lines.size()):
			var rl: Dictionary = _report_lines[i]
			var col := Color(0.75, 0.8, 0.9)
			if int(rl.ok) == 1:
				col = Color(0.55, 1.0, 0.65)
			elif int(rl.ok) == 0:
				col = Color(1.0, 0.45, 0.45)
			draw_string(font, Vector2(px + 12, py + 26 + float(i) * line_h), rl.text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 15, col)
		draw_string(font, Vector2(px + 12, py + panel_h - 10),
			"live analysis on — updates ~1s after your last edit" if live_analyze
			else "live analysis OFF — press Analyze after editing",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.55, 0.6, 0.72))

	# Legend — an overlay that needs a manual teaches nothing. Drawn even before the
	# first analysis, which is exactly when someone new is staring at the canvas.
	if show_legend:
		var lx := px + 1312.0
		var entries := [
			[Color(0.55, 0.25, 0.84, 1.0), "fialové dlaždice — zdi (HighGroundTiles): překážka i stavební místa"],
			[Color(0.94, 0.55, 0.16, 1.0), "oranžové dlaždice — cesty (PathTiles): nepřátelé je preferují"],
			[Color(1.0, 0.45, 0.15, 0.8), "orange→red cells — enemy traffic: how many routes cross"],
			[Color(1.0, 0.35, 0.4, 0.9), "red lines — sampled enemy routes · dot = spawn end"],
			[Color(1.0, 0.2, 0.2, 0.9), "red frame — spawn zone (drag to move/resize, snaps)"],
			[Color(0.2, 1.0, 0.2, 0.9), "green square — Objective, the Focus core (drag it)"],
			[Color(0.49, 1.0, 0.7, 0.9), "green circle — buildable WITHOUT Anchors (core Routine)"],
			[Color(0.12, 0.9, 0.95, 0.7), "cyan circle — one Anchor's extra Routine reach"],
			[Color(0.95, 0.62, 0.25, 0.9), "chart: orange = spawns/wave · blue = lean · red ring = boss"],
			[Color(0.55, 1.0, 0.65, 1.0), "panel: green = target met · red = fix this · gray = info"],
		]
		var lh := 20.0
		var legend_h := lh * float(entries.size()) + 46.0
		draw_rect(Rect2(lx, py, 592.0, legend_h), Color(0.04, 0.06, 0.11, 0.94))
		draw_rect(Rect2(lx, py, 592.0, legend_h), Color(0.3, 0.4, 0.6, 0.8), false, 1.5)
		draw_string(font, Vector2(lx + 12, py + 20), "WHAT AM I LOOKING AT?",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.7, 0.75, 0.85))
		for i in range(entries.size()):
			var e: Array = entries[i]
			var ey := py + 32.0 + lh * float(i)
			draw_rect(Rect2(lx + 12, ey, 12, 12), e[0])
			draw_string(font, Vector2(lx + 32, ey + 11), String(e[1]),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.78, 0.82, 0.9))
		draw_string(font, Vector2(lx + 12, py + legend_h - 10),
			"flow: Load → paint & drag → read panel → Bake → Playtest · guide: docs/EDITOR_GUIDE.md",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.55, 0.6, 0.72))

	# Difficulty curve, next to the panel: per-wave spawn totals as bars. This is the
	# level's SHAPE — the ramp, the lean dips, the finale spike — which a list of
	# wave_curve numbers hides completely.
	if _last_summary.is_empty() or target_level == null:
		return
	var totals: Array = _last_summary.totals
	var peak: int = int(_last_summary.peak)
	if peak <= 0 or totals.is_empty():
		return
	var sx := px + 736.0
	var sw := 560.0
	var sh := maxf(panel_h, 120.0)
	draw_rect(Rect2(sx, py, sw, sh), Color(0.04, 0.06, 0.11, 0.94))
	draw_rect(Rect2(sx, py, sw, sh), Color(0.3, 0.4, 0.6, 0.8), false, 1.5)
	draw_string(font, Vector2(sx + 12, py + 20),
		"spawns per wave · peak %d @ w%d · blue = lean · red ring = boss"
		% [peak, int(_last_summary.peak_wave)],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.7, 0.75, 0.85))
	var plot_x := sx + 14.0
	var plot_w := sw - 28.0
	var plot_top := py + 32.0
	var plot_bot := py + sh - 24.0
	var n := totals.size()
	var bar_w := plot_w / float(n)
	for i in range(n):
		var v := int(totals[i])
		var bh := (plot_bot - plot_top) * float(v) / float(peak)
		var bx := plot_x + bar_w * float(i)
		var wave_no := i + 1
		var col := Color(0.95, 0.62, 0.25, 0.9)
		if target_level.lean_waves.has(wave_no):
			col = Color(0.35, 0.6, 0.95, 0.9)
		draw_rect(Rect2(bx + 1.0, plot_bot - bh, maxf(1.0, bar_w - 2.0), bh), col)
		if target_level.boss != null and wave_no == target_level.wave_count:
			draw_rect(Rect2(bx + 1.0, plot_bot - bh, maxf(1.0, bar_w - 2.0), bh),
				Color(1.0, 0.3, 0.3, 0.95), false, 2.0)
		if wave_no == 1 or wave_no == n or wave_no % 5 == 0:
			draw_string(font, Vector2(bx, plot_bot + 16.0), str(wave_no),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.55, 0.6, 0.72))
