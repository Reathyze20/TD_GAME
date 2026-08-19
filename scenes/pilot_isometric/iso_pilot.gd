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

const Z_FLOOR := -10   ## flat plane, never y-sorted — see 01_rendering_and_depth.md
const Z_ENTITIES := 0  ## walls + tower + enemy, y-sorted against each other

const FLOOR_TEX := "res://assets/iso_pilot/floor_tile.png"
const PILLAR_TEX := "res://assets/iso_pilot/wall.png"  ## round-1 leftover, kept as an optional corner accent
const TOWER_TEX := "res://assets/iso_pilot/tower_focus_pillar.png"
const ENEMY_TEX := "res://assets/iso_pilot/enemy_energy_drink.png"
## Flat material swatch for the code-drawn wall faces — no iso shape, just surface
## texture (stone/tissue, same palette as the tower and floor). Falls back to a
## placeholder swatch if art-direction's real one isn't on disk yet.
const WALL_MATERIAL_TEX := "res://assets/iso_pilot/wall_material.png"
const WALL_MATERIAL_FALLBACK := "res://assets/iso_pilot/wall_material_placeholder.png"

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
	_build_entities()
	_build_camera()


func _build_floor() -> void:
	var ts := TileSet.new()
	ts.tile_shape = TileSet.TILE_SHAPE_ISOMETRIC
	ts.tile_layout = TileSet.TILE_LAYOUT_DIAMOND_DOWN
	ts.tile_size = TILE_SIZE

	var tex := load(FLOOR_TEX) as Texture2D
	var source := TileSetAtlasSource.new()
	source.texture = tex
	source.texture_region_size = TILE_SIZE
	source.create_tile(Vector2i(0, 0))
	ts.add_source(source, 0)

	floor_layer = TileMapLayer.new()
	floor_layer.name = "Floor"
	floor_layer.tile_set = ts
	floor_layer.z_index = Z_FLOOR
	floor_layer.y_sort_enabled = false  # flat plane — depth comes from the entities layer
	floor_layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(floor_layer)

	for x in range(GRID_W):
		for y in range(GRID_H):
			floor_layer.set_cell(Vector2i(x, y), 0, Vector2i(0, 0))


func _build_entities() -> void:
	entities = Node2D.new()
	entities.name = "Entities"
	entities.y_sort_enabled = true  # 01_rendering_and_depth.md: sort by node origin Y
	entities.z_index = Z_ENTITIES
	add_child(entities)

	_build_walls()

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
func _build_walls() -> void:
	var path := WALL_MATERIAL_TEX if ResourceLoader.exists(WALL_MATERIAL_TEX) else WALL_MATERIAL_FALLBACK
	var tex := load(path) as Texture2D
	for x in range(GRID_W):
		_spawn_wall_segment(Vector2i(x, 0), "N", "E", tex, 1.0)   # back-right wall, catches the light
	for y in range(GRID_H):
		_spawn_wall_segment(Vector2i(0, y), "N", "W", tex, 0.72)  # back-left wall, in shadow — one consistent light source from the right


func _corner_offset(corner: String) -> Vector2:
	match corner:
		"N": return Vector2(0, -TILE_SIZE.y / 2.0)
		"E": return Vector2(TILE_SIZE.x / 2.0, 0)
		"S": return Vector2(0, TILE_SIZE.y / 2.0)
		"W": return Vector2(-TILE_SIZE.x / 2.0, 0)
	return Vector2.ZERO


func _spawn_wall_segment(cell: Vector2i, corner_a: String, corner_b: String, tex: Texture2D, shade: float) -> void:
	var oa := _corner_offset(corner_a)
	var ob := _corner_offset(corner_b)
	var seg := IsoWallSegment.new()
	seg.pts = PackedVector2Array([oa, ob, ob - Vector2(0, WALL_HEIGHT), oa - Vector2(0, WALL_HEIGHT)])
	seg.tex = tex
	seg.shade = shade
	seg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# Tile CENTER, same anchor convention as every entity here — keeps this segment's
	# y-sort key consistent with what a unit standing on the same tile would use.
	seg.position = floor_layer.map_to_local(cell)
	entities.add_child(seg)


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
