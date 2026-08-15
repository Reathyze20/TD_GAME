extends SceneTree
## Recomputes `terrain_tiles` for every level from its `high_ground` layout.
##
## Run:  godot --headless --path <proj> --script res://tools/retile_levels.gd
##
## WHY THIS EXISTS
## `terrain_tiles` is authored art and `high_ground` is gameplay truth, kept separate on
## purpose (see level_data.gd). But a level can end up with art that contradicts the
## layout — level 1 shipped with all 170 cells stored as atlas (0,0), the isolated-pillar
## slot, so every wall rendered as a row of loose blocks with a bevel on all four sides.
## That is invisible while the tiles are mostly transparent and glaring once they are not.
##
## This regenerates the straightforward answer: each cell gets the slot matching which of
## its four neighbours are also high ground. Hand-authored variation is overwritten, which
## is the point — run it when the art has drifted out of sync with the layout, not as part
## of a build.
##
## SLOT LAYOUT — must stay identical to tools/build_terrain_tileset.gd
##   bit 1 = up, 2 = right, 4 = down, 8 = left
##   atlas x = mask % 4, atlas y = mask / 4

const LEVEL_DIR := "res://data/levels"
const SOURCE_ID := 0

const BIT_UP := 1
const BIT_RIGHT := 2
const BIT_DOWN := 4
const BIT_LEFT := 8

func _init() -> void:
	var dir := DirAccess.open(LEVEL_DIR)
	if dir == null:
		push_error("Cannot open %s" % LEVEL_DIR)
		quit(1)
		return

	var changed := 0
	for file in dir.get_files():
		if not file.ends_with(".tres"):
			continue
		var path := "%s/%s" % [LEVEL_DIR, file]
		var level: Resource = load(path)
		if level == null or not ("high_ground" in level):
			continue

		var cells: Array = level.high_ground
		if cells.is_empty():
			print("%s: zadny high ground, preskoceno" % file)
			continue

		# Mirror game.gd: the objective cell is never part of the walkable-blocking set,
		# so it must not be drawn as terrain either.
		var solid := {}
		for c: Vector2i in cells:
			if c != level.objective:
				solid[c] = true

		var tiles := {}
		for c: Vector2i in solid:
			var mask := 0
			if solid.has(c + Vector2i(0, -1)): mask |= BIT_UP
			if solid.has(c + Vector2i(1, 0)):  mask |= BIT_RIGHT
			if solid.has(c + Vector2i(0, 1)):  mask |= BIT_DOWN
			if solid.has(c + Vector2i(-1, 0)): mask |= BIT_LEFT
			tiles[c] = Vector3i(SOURCE_ID, mask % 4, mask / 4)

		var before: int = level.terrain_tiles.size()
		level.terrain_tiles = tiles
		var err := ResourceSaver.save(level, path)
		if err != OK:
			push_error("%s: ulozeni selhalo (%d)" % [file, err])
			continue

		var isolated := 0
		for v: Vector3i in tiles.values():
			if v.y == 0 and v.z == 0:
				isolated += 1
		print("%s: %d -> %d dlazdic, z toho %d osamocenych"
			% [file, before, tiles.size(), isolated])
		changed += 1

	print("Hotovo, prepsano levelu: %d" % changed)
	quit(0)
