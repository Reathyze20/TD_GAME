extends SceneTree
## One-shot generator for the shared high-ground TileSet.
##
## Run:  godot --headless --path <proj> --script res://tools/build_terrain_tileset.gd
##
## Produces two files that both the map editor and the game reference:
##   res://assets/terrain/high_ground_atlas.png   — placeholder art, 4x4 tiles
##   res://data/terrain/high_ground_tileset.tres  — TileSet with a side-matching terrain
##
## WHY A GENERATOR RATHER THAN A HAND-WRITTEN .tres
## The peering bits have to agree with the atlas layout exactly, and getting one of the
## sixteen wrong produces a wall with a hole in it that only shows up when you paint that
## specific shape. Deriving both from the same bitmask table makes that impossible.
##
## SWAPPING IN REAL ART
## Replace high_ground_atlas.png with the same 4x4 grid at the same tile size and keep
## the slot meaning below. Nothing else changes — the .tres references the texture by
## path, and the peering bits live on the TileSet, not on the image.
##
## SLOT LAYOUT (index = which SIDES this piece connects to)
##   bit 1 = connects up, 2 = right, 4 = down, 8 = left
##   atlas x = index % 4, atlas y = index / 4
##   so slot 0 is an isolated pillar, slot 5 (up+down) is a vertical straight,
##   slot 10 (right+left) is a horizontal straight, slot 15 is a full cross.

const OUT_TEXTURE := "res://assets/terrain/high_ground_atlas.png"
const OUT_TILESET := "res://data/terrain/high_ground_tileset.tres"

const BIT_UP := 1
const BIT_RIGHT := 2
const BIT_DOWN := 4
const BIT_LEFT := 8

func _init() -> void:
	var grid: Dictionary = preload("res://scripts/data.gd").GRID
	var tile: int = int(grid.tile)

	DirAccess.make_dir_recursive_absolute("res://assets/terrain")
	DirAccess.make_dir_recursive_absolute("res://data/terrain")

	_write_placeholder_atlas(tile)

	# The TileSet must REFERENCE the png, not embed it. An ImageTexture built at runtime
	# serialises its pixels into the .tres (half a megabyte of PackedByteArray) and, worse,
	# makes the art unswappable — the whole point is that real tiles replace the
	# placeholder by overwriting the file. Referencing requires the png to be imported
	# first, so this script must be run twice on a clean checkout, or once after --import.
	if not ResourceLoader.exists(OUT_TEXTURE):
		print("Atlas written but not yet imported.")
		print("Run --import, then run this script again to link the TileSet to it.")
		quit(0)
		return

	_write_tileset(tile)

	print("Terrain tileset generated.")
	print("  atlas:   ", OUT_TEXTURE)
	print("  tileset: ", OUT_TILESET)
	print("  tile size: %dpx (from Data.GRID)" % tile)
	quit(0)

## Draws a legible stand-in for each of the sixteen connection shapes: a slab with arms
## reaching toward every side it connects to, so autotiling can be verified visually
## before any real art exists.
func _write_placeholder_atlas(tile: int) -> void:
	var img := Image.create_empty(tile * 4, tile * 4, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var body := Color("2d334a")
	var edge := Color("454f73")
	var arm_w: int = int(tile * 0.42)
	var core: int = int(tile * 0.56)

	for mask in range(16):
		var ox: int = (mask % 4) * tile
		var oy: int = int(mask / 4.0) * tile
		var half: int = tile / 2

		# Centre block, present on every slot.
		var c0: int = half - core / 2
		_fill_rect(img, ox + c0, oy + c0, core, core, body)

		# Arms toward each connected side, so two adjacent tiles visually meet.
		if mask & BIT_UP:
			_fill_rect(img, ox + half - arm_w / 2, oy, arm_w, half, body)
		if mask & BIT_DOWN:
			_fill_rect(img, ox + half - arm_w / 2, oy + half, arm_w, half, body)
		if mask & BIT_LEFT:
			_fill_rect(img, ox, oy + half - arm_w / 2, half, arm_w, body)
		if mask & BIT_RIGHT:
			_fill_rect(img, ox + half, oy + half - arm_w / 2, half, arm_w, body)

		# A highlight rim on the centre so slots stay distinguishable at a glance.
		_stroke_rect(img, ox + c0, oy + c0, core, core, edge)

	img.save_png(OUT_TEXTURE)

func _fill_rect(img: Image, x: int, y: int, w: int, h: int, col: Color) -> void:
	for px in range(x, mini(x + w, img.get_width())):
		for py in range(y, mini(y + h, img.get_height())):
			if px >= 0 and py >= 0:
				img.set_pixel(px, py, col)

func _stroke_rect(img: Image, x: int, y: int, w: int, h: int, col: Color) -> void:
	for px in range(x, mini(x + w, img.get_width())):
		if px >= 0:
			if y >= 0: img.set_pixel(px, y, col)
			if y + h - 1 < img.get_height(): img.set_pixel(px, y + h - 1, col)
	for py in range(y, mini(y + h, img.get_height())):
		if py >= 0:
			if x >= 0: img.set_pixel(x, py, col)
			if x + w - 1 < img.get_width(): img.set_pixel(x + w - 1, py, col)

func _write_tileset(tile: int) -> void:
	# load(), not Image.load_from_file() — this yields the imported CompressedTexture2D,
	# which ResourceSaver writes as an ext_resource path.
	var tex: Texture2D = load(OUT_TEXTURE)

	var ts := TileSet.new()
	ts.tile_size = Vector2i(tile, tile)

	# One terrain set in "match sides" mode: connections are orthogonal only, which is
	# what the level geometry actually is (the old vector renderer connected right and
	# down and nothing else), and it needs 16 pieces instead of the 47 a corner-matching
	# blob would demand.
	ts.add_terrain_set()
	ts.set_terrain_set_mode(0, TileSet.TERRAIN_MODE_MATCH_SIDES)
	ts.add_terrain(0)
	ts.set_terrain_name(0, 0, "High Ground")
	ts.set_terrain_color(0, 0, Color("454f73"))

	var src := TileSetAtlasSource.new()
	src.texture = tex
	src.texture_region_size = Vector2i(tile, tile)
	ts.add_source(src, 0)

	for mask in range(16):
		var coords := Vector2i(mask % 4, int(mask / 4.0))
		src.create_tile(coords)
		var td: TileData = src.get_tile_data(coords, 0)
		td.terrain_set = 0
		td.terrain = 0
		# Peering bits are what let Godot pick the right piece while you drag. They must
		# mirror the arms drawn above, or painting produces visually broken joins.
		td.set_terrain_peering_bit(TileSet.CELL_NEIGHBOR_TOP_SIDE,
			0 if (mask & BIT_UP) else -1)
		td.set_terrain_peering_bit(TileSet.CELL_NEIGHBOR_RIGHT_SIDE,
			0 if (mask & BIT_RIGHT) else -1)
		td.set_terrain_peering_bit(TileSet.CELL_NEIGHBOR_BOTTOM_SIDE,
			0 if (mask & BIT_DOWN) else -1)
		td.set_terrain_peering_bit(TileSet.CELL_NEIGHBOR_LEFT_SIDE,
			0 if (mask & BIT_LEFT) else -1)

	var err := ResourceSaver.save(ts, OUT_TILESET)
	if err != OK:
		push_error("Failed to save TileSet: %d" % err)
