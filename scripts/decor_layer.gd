class_name DecorLayer
extends Node2D
## Scenery scattered over the empty floor: dropped phones, spilled coffee, dead bulbs,
## sticky notes. None of it is interactive.
##
## It exists because the field read as dead. The walkable area was bare background with a
## few circuit traces, so a wave crossing it looked like sprites sliding over a desktop
## wallpaper rather than creatures moving through a place. Kingdom Rush fills the same
## space with signs and bones for exactly this reason — clutter is what makes ground read
## as ground.
##
## Art: assets/decor/*.png, 16px, drawn at x3 — the terrain is 16px art at x3 (48px cell),
## so props on the same raster share the same grain. Adding a file is all it takes to
## widen the pool.

const DECOR_DIR := "res://assets/decor"
const ZOOM := 3

## Share of eligible floor cells that get something.
##
## Started at 0.17 at full brightness and the field looked like confetti — bright little
## objects every few cells, competing with the enemies instead of supporting them. Scenery
## has to sit UNDER the action: sparse, and dimmed into the floor by TINT below.
const DENSITY := 0.06

## Multiplikativní ztlumení do podlahy — NE průhlednost.
##
## Propy jsou kreslené v původní broskvové paletě, kdy byla světlá i podlaha. Po přechodu
## na Deep Focus je podlaha tmavá a tytéž propy z ní svítí jako nejjasnější věc v poli
## (nejsvětlejší pixel 642 proti 181 u zdí) — přesně obrácená hierarchie, kterou scenérie
## mít nesmí. Násobení tmavou barvou zachová kresbu i vzájemné odstíny a jen je celé
## posadí pod akci; průhlednost by je na tmavém pozadí naopak vypláchla do šeda.
const TINT := Color(0.42, 0.40, 0.55)

var _items: Array = []          ## [{tex, pos, flip}]

## Deterministic per level: the same level always lays out the same way, so a restart
## does not reshuffle the scenery under the player. Seeded from the level id rather than
## left to global randomness.
func build(game, level_seed: int) -> void:
	_items.clear()
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	var pool := _load_pool()
	if pool.is_empty():
		return

	# Authored scenery wins outright. Once a designer has placed things by hand, adding a
	# random scatter on top would fight the composition they just made.
	if game.level != null and not game.level.decor.is_empty():
		for entry in game.level.decor:
			var tex := _texture_named(String(entry.get("id", "")))
			if tex != null:
				_items.append({"tex": tex, "pos": entry.get("pos", Vector2.ZERO),
					"flip": bool(entry.get("flip", false))})
		_items.sort_custom(func(a, b): return a["pos"].y < b["pos"].y)
		queue_redraw()
		return

	var g = Data.GRID
	var tile: int = int(g.tile)
	var rng := RandomNumberGenerator.new()
	rng.seed = level_seed

	# Spawn zones are excluded: enemies pour out of them in clumps, and a prop under that
	# is never seen and only adds noise where the eye is already busy.
	var blocked := {}
	for zone: Array in game.spawn_zone_cells:
		for c: Vector2i in zone:
			blocked[c] = true

	# CLUSTERS, not an even sprinkle. Spreading props uniformly is what made the field
	# look like confetti: evenly spaced litter reads as noise, because nothing in a real
	# place is evenly spaced. A few seeded piles with bare floor between them reads as
	# somewhere things happened.
	var free: Array[Vector2i] = []
	for cy in range(g.rows):
		for cx in range(g.cols):
			var cell := Vector2i(cx, cy)
			if game.high_ground.has(cell) or cell == game.objective_cell or blocked.has(cell):
				continue
			free.append(cell)
	if free.is_empty():
		return

	var clusters: int = maxi(1, int(free.size() * DENSITY / 3.0))
	for _c in range(clusters):
		var origin: Vector2i = free[rng.randi() % free.size()]
		# Two to four pieces per pile, dropped within about a cell of each other, so they
		# touch and overlap the way dropped things do.
		var count: int = rng.randi_range(2, 4)
		for _i in range(count):
			var spread := Vector2(rng.randf_range(-30.0, 30.0), rng.randf_range(-22.0, 22.0))
			var centre := Vector2(g.origin_x + origin.x * tile + tile * 0.5,
				g.origin_y + origin.y * tile + tile * 0.5) + spread
			var at_cell := Vector2i(int((centre.x - g.origin_x) / tile),
				int((centre.y - g.origin_y) / tile))
			# The spread can push a piece onto a wall or off the board; drop those rather
			# than clamping, which would pile them against the edge.
			if game.high_ground.has(at_cell) or blocked.has(at_cell) \
					or at_cell.x < 0 or at_cell.y < 0 \
					or at_cell.x >= g.cols or at_cell.y >= g.rows:
				continue
			_items.append({"tex": pool[rng.randi() % pool.size()], "pos": centre,
				"flip": rng.randf() < 0.5})
	# Painter order by Y so a piece further down overlaps one behind it.
	_items.sort_custom(func(a, b): return a["pos"].y < b["pos"].y)
	queue_redraw()

## Looks a prop up by its file stem ("mug"), which is what authored entries store — a
## path would break the moment the folder moves, and an index would break the moment a
## file is added.
static func _texture_named(id: String) -> Texture2D:
	if id == "":
		return null
	var p := "%s/%s.png" % [DECOR_DIR, id]
	if not ResourceLoader.exists(p):
		return null
	var tex = load(p)
	return tex if tex is Texture2D else null

## Every prop id available to place, sorted — the editor palette reads this.
static func available_ids() -> Array:
	var out: Array = []
	var dir := DirAccess.open(DECOR_DIR)
	if dir == null:
		return out
	for f in dir.get_files():
		var base := f.trim_suffix(".remap").trim_suffix(".import")
		if base.ends_with(".png"):
			var id := base.get_basename()
			if not out.has(id):
				out.append(id)
	out.sort()
	return out

func _load_pool() -> Array[Texture2D]:
	var out: Array[Texture2D] = []
	var dir := DirAccess.open(DECOR_DIR)
	if dir == null:
		return out
	var names := dir.get_files()
	names.sort()   # stable order, or the seeded layout would differ per platform
	for f in names:
		var base := f.trim_suffix(".remap").trim_suffix(".import")
		if not base.ends_with(".png"):
			continue
		var p := "%s/%s" % [DECOR_DIR, base]
		if ResourceLoader.exists(p):
			var tex = load(p)
			if tex is Texture2D and not out.has(tex):
				out.append(tex)
	return out

func _draw() -> void:
	for item in _items:
		var tex: Texture2D = item["tex"]
		var size := Vector2(tex.get_size()) * ZOOM
		var at: Vector2 = item["pos"] - size * 0.5
		if item["flip"]:
			# Mirroring doubles the apparent variety for free. Nothing here carries text
			# or a handed shape, so a flipped copy never reads as wrong.
			draw_set_transform(item["pos"], 0.0, Vector2(-1.0, 1.0))
			draw_texture_rect(tex, Rect2(-size * 0.5, size), false, TINT)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		else:
			draw_texture_rect(tex, Rect2(at, size), false, TINT)
