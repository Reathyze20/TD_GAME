extends Node2D
## Isometric rendering pilot — a small, ISOLATED experiment, not a migration.
##
## Nothing here touches scripts/game.gd, tower.gd, terrain_tiles.gd or any real scene.
## Whole point: can Godot's native isometric TileSet + y_sort_enabled carry a 2.5D iso
## look with genuinely-drawn iso art, well enough that a full migration is worth weeks
## of work? This scene answers "does it look right", nothing else.
##
## Deliberately mirrors the real game's conventions where they transfer:
## - depth is a hard Z_* layer split (background plane vs y-sorted entities), never
##   move_child() — see docs/core/01_rendering_and_depth.md and the game.gd Z_* consts.
## - y-sort origin sits at the FEET/BASE of every entity (01 "golden rule of pivots").
## - texture_filter = NEAREST per node, so this stays crisp at any window scale.
## - wall SHAPE is code, wall MATERIAL is a texture — same split as `class WallFace` in
##   game.gd (docs/PIXELLAB.md §5c). Round 1 of this pilot asked PixelLab to draw a
##   whole iso wall parallelogram baked against a diamond footprint, and it landed
##   3px off the floor tile's own footprint — two independently-generated pieces of art
##   that were never going to agree on a shared edge to the pixel. Round 2 fixes that
##   structurally instead of asking a third time and hoping: the wall's four corners are
##   computed from the SAME TILE_SIZE constant the floor uses, so a gap is not possible
##   by construction, and the art's only job is to supply what the stretched surface
##   looks like (see IsoWallSegment below).
##
## Everything is built in code, same pattern as Game._build_background_layer(): the
## scene file only holds the root + camera, _ready() does the rest. That means opening
## this scene in the editor shows nothing until you press Play — expected, matches how
## the real game's procedural layers work too.

const TILE_SIZE := Vector2i(64, 32)  ## art px, matches floor_tile.png exactly (2:1 diamond)
const GRID_W := 8
const GRID_H := 8
const WALL_HEIGHT := 48.0  ## 1.5x tile height — tall enough to read as a wall, not a curb
const STEP_HEIGHT := 16.0  ## one terrace step — half the wall, reads as a rise you could still see over

const Z_FLOOR := -10   ## flat plane, never y-sorted — see 01_rendering_and_depth.md
const Z_FOG := -9      ## ground fog: above the floor, below everything that stands in it
const Z_ENTITIES := 0  ## walls + tower + enemy, y-sorted against each other

const PILLAR_TEX := "res://assets/iso_pilot/wall.png"  ## round-1 leftover, kept as an optional corner accent
const TOWER_TEX := "res://assets/iso_pilot/tower_focus_pillar.png"
const ENEMY_TEX := "res://assets/iso_pilot/enemy_energy_drink.png"
## Flat material swatches for the code-drawn wall faces — no iso shape, just surface
## texture (stone/tissue, same palette as the tower and floor). Three variants, same
## reasoning as FLOOR_VARIANTS below: one swatch stretched over every segment in a
## wall run repeats the exact same diagonal grain pattern at a perfectly regular
## interval, which reads as a mechanical sawtooth rather than hand-painted strata.
## Falls back to a placeholder swatch if none of these are on disk yet.
const WALL_MATERIAL_VARIANTS := [
	"res://assets/iso_pilot/wall_material_1.png",
	"res://assets/iso_pilot/wall_material_2.png",
	"res://assets/iso_pilot/wall_material_3.png",
]
const WALL_MATERIAL_TEX := "res://assets/iso_pilot/wall_material.png"
const WALL_MATERIAL_FALLBACK := "res://assets/iso_pilot/wall_material_placeholder.png"

## Round 2: three MidJourney-sourced (--tile, then diamond-cut per tools/iso_diamond_cut.py)
## floor variants instead of one repeated tile — round 1 exposed a visible wallpaper grid
## on an 8x8 field with a single tile (see docs/core/16_isometric_slice.md §2). Falls back
## to the single original tile if the variants aren't on disk (older checkout).
const FLOOR_VARIANTS := [
	"res://assets/iso_pilot/floor_organic_1.png",
	"res://assets/iso_pilot/floor_organic_2.png",
	"res://assets/iso_pilot/floor_organic_3.png",
]
const FLOOR_FALLBACK := "res://assets/iso_pilot/floor_tile.png"

## A raised terrace, purely to demonstrate the thing top-down literally cannot show at
## all: a height change. Kept well clear of the tower/enemy/pillar cells below.
const RAISED_RECT := Rect2i(5, 4, 3, 4)

var floor_layer: TileMapLayer
var entities: Node2D
var camera: Camera2D


## A single flat-shaded, textured iso wall face. Godot has no built-in "extruded tile
## edge" primitive, so this draws one by hand: draw_polygon() with UVs mapped to the
## polygon's own bounding box, which is exactly what WallFace._draw() in game.gd does
## via draw_texture_rect (stretch, not tile) — same technique, generalized from an
## axis-aligned rect to an arbitrary iso parallelogram.
class IsoWallSegment extends Node2D:
	var pts: PackedVector2Array
	var tex: Texture2D
	var shade: float = 1.0  ## one consistent light source: the two wall orientations get different flat shades, not two textures

	func _draw() -> void:
		var min_pt := pts[0]
		var max_pt := pts[0]
		for p in pts:
			min_pt = min_pt.min(p)
			max_pt = max_pt.max(p)
		var span := max_pt - min_pt
		if span.x == 0.0:
			span.x = 1.0
		if span.y == 0.0:
			span.y = 1.0
		var uvs := PackedVector2Array()
		for p in pts:
			uvs.append((p - min_pt) / span)
		draw_polygon(pts, PackedColorArray([Color(shade, shade, shade, 1.0)]), uvs, tex)


func _ready() -> void:
	_build_floor()
	_build_ground_fog()
	_build_entities()
	_build_camera()


func _build_floor() -> void:
	var ts := TileSet.new()
	ts.tile_shape = TileSet.TILE_SHAPE_ISOMETRIC
	ts.tile_layout = TileSet.TILE_LAYOUT_DIAMOND_DOWN
	ts.tile_size = TILE_SIZE

	var paths: Array = FLOOR_VARIANTS.filter(func(p): return ResourceLoader.exists(p))
	if paths.is_empty():
		paths = [FLOOR_FALLBACK]
	for i in range(paths.size()):
		var source := TileSetAtlasSource.new()
		source.texture = load(paths[i]) as Texture2D
		source.texture_region_size = TILE_SIZE
		source.create_tile(Vector2i(0, 0))
		ts.add_source(source, i)

	floor_layer = TileMapLayer.new()
	floor_layer.name = "Floor"
	floor_layer.tile_set = ts
	floor_layer.z_index = Z_FLOOR
	floor_layer.y_sort_enabled = false  # flat plane — depth comes from the entities layer
	floor_layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(floor_layer)

	# Same convention as the real game's corner terrain / wall-face variant pick
	# (game.gd: rng.seed = hash(block) ^ seed_val) — deterministic per cell, not a
	# fresh dice roll every load.
	var rng := RandomNumberGenerator.new()
	for x in range(GRID_W):
		for y in range(GRID_H):
			rng.seed = hash(Vector2i(x, y))
			floor_layer.set_cell(Vector2i(x, y), rng.randi() % paths.size(), Vector2i(0, 0))


## Fog that pools on the ground and recedes near raised terrain — a small proof-of-concept
## for what "world of the brain, alive" could mean once terrain has actual elevation
## (the user's question this round). Not the real Brain Fog system (docs/core/14) — that
## stays a full-screen gameplay-visibility overlay. This is purely atmospheric set
## dressing: soft cool-tinted blobs sitting low, generated the same way the real game
## generates its light cookies (game.gd:_shadow_light_tex) rather than shipping a PNG.
func _build_ground_fog() -> void:
	var fog_tex := _fog_blob_tex()
	var layer := Node2D.new()
	layer.name = "GroundFog"
	layer.z_index = Z_FOG
	add_child(layer)

	var rng := RandomNumberGenerator.new()
	for x in range(GRID_W):
		for y in range(GRID_H):
			var cell := Vector2i(x, y)
			# Thin out near/over raised ground — fog is a low-lying gas, it doesn't
			# climb the terrace. Skip the raised cells themselves and their immediate
			# rim so the recession reads clearly instead of stopping exactly on the edge.
			var dist_to_raised := _dist_to_rect(cell, RAISED_RECT)
			if dist_to_raised <= 0:
				continue
			rng.seed = hash(cell) ^ 0x5A17
			if rng.randf() > 0.55:
				continue
			var fog := Sprite2D.new()
			fog.texture = fog_tex
			fog.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			fog.modulate = Color(0.55, 0.85, 0.95, clampf(0.30 - dist_to_raised * 0.04, 0.06, 0.30))
			fog.position = floor_layer.map_to_local(cell) + Vector2(rng.randf_range(-6, 6), rng.randf_range(-3, 3))
			fog.scale = Vector2.ONE * rng.randf_range(0.85, 1.25)
			layer.add_child(fog)


func _dist_to_rect(cell: Vector2i, r: Rect2i) -> int:
	var dx := maxi(maxi(r.position.x - cell.x, cell.x - (r.position.x + r.size.x - 1)), 0)
	var dy := maxi(maxi(r.position.y - cell.y, cell.y - (r.position.y + r.size.y - 1)), 0)
	return maxi(dx, dy)


## Soft radial falloff, same shape family as game.gd's light cookies: bright core,
## smoothstep falloff to transparent. Squashed 2:1 so it pools like a flat gas layer on
## the iso ground plane instead of reading as a sphere.
func _fog_blob_tex() -> ImageTexture:
	var w := 56
	var h := 28
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var center := Vector2(w / 2.0, h / 2.0)
	for y in range(h):
		for x in range(w):
			var d := Vector2(x, y) - center
			var n := (d / center).length()
			var v: float = 1.0 - smoothstep(0.35, 1.0, n)
			img.set_pixel(x, y, Color(1, 1, 1, v))
	return ImageTexture.create_from_image(img)


func _build_entities() -> void:
	entities = Node2D.new()
	entities.name = "Entities"
	entities.y_sort_enabled = true  # 01_rendering_and_depth.md: sort by node origin Y
	entities.z_index = Z_ENTITIES
	add_child(entities)

	_build_walls()
	_build_terrace()

	# Two round-1 pillars kept as optional decoration at the room's outer corners —
	# the user explicitly said this stepped-totem look can stay ALONGSIDE a real wall,
	# it just can't BE the wall on its own.
	_spawn_at(PILLAR_TEX, Vector2i(GRID_W - 1, 0))
	_spawn_at(PILLAR_TEX, Vector2i(0, GRID_H - 1))

	# Tower near the corner where both wall rows meet, close enough to the back-right
	# wall to prove a standing entity can sit right up against a real wall segment
	# without fighting it in the sort.
	_spawn_at(TOWER_TEX, Vector2i(2, 1))

	# Enemy one diagonal step further (higher x+y => further "south", drawn in front in
	# a diamond-down iso grid) so its sprite overlaps the tower's base and the y-sort
	# has something real to prove: enemy must render OVER the tower's feet, not under.
	_spawn_at(ENEMY_TEX, Vector2i(3, 2))


## Builds the room's two back walls — the edges a diamond-down grid can actually show
## the player (the two facing the camera; the near two are traditionally left open so
## the camera can see inside, same convention every iso room game uses). Cell (x,y)'s
## neighbor at (x,y-1) shares its N-E edge, and its neighbor at (x-1,y) shares its N-W
## edge — cells at y=0 / x=0 have no such neighbor, so THAT edge is the true outer
## boundary. Both rows share the (0,0) tile's north vertex, so the two walls meet with
## zero gap, by construction, not by matching two separately-generated pieces of art.
## Loads whichever wall material variants exist on disk, falling back to the single
## WALL_MATERIAL_TEX / WALL_MATERIAL_FALLBACK path for an older checkout.
func _wall_textures() -> Array:
	var paths: Array = WALL_MATERIAL_VARIANTS.filter(func(p): return ResourceLoader.exists(p))
	if paths.is_empty():
		paths = [WALL_MATERIAL_TEX if ResourceLoader.exists(WALL_MATERIAL_TEX) else WALL_MATERIAL_FALLBACK]
	var textures: Array = []
	for p in paths:
		textures.append(load(p) as Texture2D)
	return textures


## Deterministic per-cell pick, same convention as the floor's variant pick — a fresh
## dice roll every load would make the wall look different on every playtest for no
## reason and make bug reports about "that one ugly seam" unreproducible.
func _pick_wall_tex(cell: Vector2i, salt: int, textures: Array) -> Texture2D:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(cell) ^ salt
	return textures[rng.randi() % textures.size()]


func _build_walls() -> void:
	var textures := _wall_textures()
	for x in range(GRID_W):
		var cell := Vector2i(x, 0)
		_spawn_wall_segment(cell, "N", "E", _pick_wall_tex(cell, 0x9A11, textures), 1.0)   # back-right wall, catches the light
	for y in range(GRID_H):
		var cell := Vector2i(0, y)
		_spawn_wall_segment(cell, "N", "W", _pick_wall_tex(cell, 0x9A11, textures), 0.72)  # back-left wall, in shadow — one consistent light source from the right


func _corner_offset(corner: String) -> Vector2:
	match corner:
		"N": return Vector2(0, -TILE_SIZE.y / 2.0)
		"E": return Vector2(TILE_SIZE.x / 2.0, 0)
		"S": return Vector2(0, TILE_SIZE.y / 2.0)
		"W": return Vector2(-TILE_SIZE.x / 2.0, 0)
	return Vector2.ZERO


func _spawn_wall_segment(cell: Vector2i, corner_a: String, corner_b: String, tex: Texture2D, shade: float, height: float = WALL_HEIGHT) -> void:
	var oa := _corner_offset(corner_a)
	var ob := _corner_offset(corner_b)
	var seg := IsoWallSegment.new()
	seg.pts = PackedVector2Array([oa, ob, ob - Vector2(0, height), oa - Vector2(0, height)])
	seg.tex = tex
	seg.shade = shade
	seg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# Tile CENTER, same anchor convention as every entity here — keeps this segment's
	# y-sort key consistent with what a unit standing on the same tile would use.
	seg.position = floor_layer.map_to_local(cell)
	entities.add_child(seg)


## The one thing top-down literally cannot show: a height change. A short riser (half the
## wall height, so it reads as a step you could see over, not a room boundary) plus the
## raised cells' own floor sprites redrawn STEP_HEIGHT higher. Risers only go on the two
## edges that face the camera — same corner-pair logic as _build_walls, mirrored: a wall's
## N-E/N-W edges face AWAY from the viewer (the room's back), so a terrace's visible front
## edges are the opposite pair, E-S and S-W (see the edge/neighbor mapping comment above
## _build_walls). Only drawn where the neighbor in that direction is NOT part of the
## raised block, i.e. only where the drop is real.
const STONE_TOP_TEX := "res://assets/iso_pilot/floor_stone_top.png"  ## wall_material.png, diamond-cut via tools/iso_diamond_cut.py — a flat SQUARE material swatch would draw as a square blob here, not a diamond, so it must go through the same cut as the organic floor tiles.


func _build_terrace() -> void:
	var textures := _wall_textures()
	# Deliberately the STONE material, not another organic floor variant: the height
	# change alone reads as subtle at this zoom (one 16px step), but a material change on
	# top of it — built stone vs. the organic ground below — makes "this ground was
	# raised and built on" unmistakable at a glance, not just on close inspection.
	var top_tex := load(STONE_TOP_TEX if ResourceLoader.exists(STONE_TOP_TEX) else FLOOR_FALLBACK) as Texture2D

	for x in range(RAISED_RECT.position.x, RAISED_RECT.position.x + RAISED_RECT.size.x):
		for y in range(RAISED_RECT.position.y, RAISED_RECT.position.y + RAISED_RECT.size.y):
			var cell := Vector2i(x, y)
			if not RAISED_RECT.has_point(Vector2i(x + 1, y)):
				_spawn_wall_segment(cell, "E", "S", _pick_wall_tex(cell, 0x7EEC, textures), 0.85, STEP_HEIGHT)
			if not RAISED_RECT.has_point(Vector2i(x, y + 1)):
				_spawn_wall_segment(cell, "S", "W", _pick_wall_tex(cell, 0x7EEC, textures), 0.62, STEP_HEIGHT)

			var top := Sprite2D.new()
			top.texture = top_tex
			top.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			top.centered = true
			top.position = floor_layer.map_to_local(cell) + Vector2(0, -STEP_HEIGHT)
			entities.add_child(top)


## Places a sprite so the LOWEST non-transparent pixel of its own art (the actual
## ground-contact point — feet, plinth, or a baked shadow, whichever a given piece
## draws) lands exactly on the tile's center (what map_to_local gives for an isometric
## diamond tileset). This is the "golden rule of pivots" from 01 — origin at the feet,
## never the middle — computed from the texture's real content via get_used_rect()
## instead of a hand-measured pixel constant. Hardcoding that constant is exactly what
## broke the first placeholder wall (see git history on this file): the number was
## right for one draft of the art and silently wrong for the next. Reading it from the
## pixels themselves means a future art swap can't desync from the code that places it.
func _spawn_at(tex_path: String, cell: Vector2i) -> void:
	var tex := load(tex_path) as Texture2D
	var sprite := Sprite2D.new()
	sprite.texture = tex
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.centered = true
	var used := tex.get_image().get_used_rect()
	var h := float(tex.get_height())
	var anchor_from_bottom := h - float(used.position.y + used.size.y)
	sprite.offset = Vector2(0, anchor_from_bottom - h / 2.0)
	sprite.position = floor_layer.map_to_local(cell)
	entities.add_child(sprite)


func _build_camera() -> void:
	camera = Camera2D.new()
	camera.name = "PilotCamera"
	# Fit the whole 8x8 room (plus the wall height rising above it) in frame. Center on
	# the grid's midpoint, nudged up so the back walls aren't clipped off the top.
	var center := floor_layer.map_to_local(Vector2i(GRID_W / 2, GRID_H / 2))
	camera.position = center + Vector2(0, -WALL_HEIGHT * 0.6)
	camera.zoom = Vector2(2.2, 2.2)
	add_child(camera)  # make_current() must be called AFTER it's inside the tree
	camera.make_current()  # Godot 4 renamed Camera2D.current -> the "enabled" property; make_current() works either way
