extends Node
## T5 (docs/refactor/MIGRATION.MD): a first concrete image for the visual call T5 stops
## on — "what does high_ground look like in a top-down square view with no visible side
## faces?" (see BLOCKED.md's T5 entry, GridProjection.gd's diamond_corners() doc comment).
## NOT a proposal to ship, just something real to look at instead of an idea.
##
## Colors are not invented for this: GROUND/LANE/TOP below are the exact RGB values
## `tools/flat_terrain.py` already paints onto the LIVE iso terrain's TOP FACE
## (docs/art/iso_bible.md §2b, "PLOCHÝ STYL", user-approved 21.8.2026). A top-down view
## only ever shows a "top face" — no left/right terrace sides exist to shade — so reusing
## those exact values keeps continuity with art already shipped instead of guessing fresh.
##
## Renders the level whose data already fits Data.GRID's current 24x24 bounds ("First
## Light", the iso vertical slice's own level) rather than level_1/level_2, which are
## still sized for the pre-iso 120x57 grid (T6, separately blocked, not this task).
##
## Pure Image pixel-buffer output, no viewport capture needed — unlike every other
## _shot_*.gd this can in principle run --headless, but still needs --main-scene (never
## --script) so the Data autoload is actually registered:
##   godot --headless --path <proj> --main-scene res://scenes/_shot_topdown_mockup.tscn

const OUT_DIR := ".dev/screenshots"
const GROUND := Color8(20, 17, 41)      ## tools/flat_terrain.py GROUND
const LANE := Color8(78, 52, 16)        ## tools/flat_terrain.py LANE (path_cells)
const TOP := Color8(184, 165, 135)      ## tools/flat_terrain.py TOP (high_ground)
const SPAWN_TINT := Color8(0xC7, 0x0D, 0x53)     ## palette_48.hex C70D53
const OBJECTIVE_TINT := Color8(0x7D, 0xEF, 0x39) ## palette_48.hex 7DEF39

## Mirrors _test_levels.gd's KNOWN_BROKEN: level_1/level_2's objective sits outside the
## current 24x24 grid (T6, blocked separately) — skip them, this task is about the LOOK,
## not the migration.
const KNOWN_BROKEN := {1: true, 2: true}

func _ready() -> void:
	call_deferred("_run")

func _pick_level() -> LevelData:
	for i in range(Data.get_level_count()):
		var lv: LevelData = Data.get_level(i)
		if not KNOWN_BROKEN.has(lv.id):
			return lv
	return null

func _render(lv: LevelData) -> Image:
	var cols: int = Data.GRID.cols
	var rows: int = Data.GRID.rows
	var tile: int = Data.GRID.get("tile", 32)
	var img := Image.create(cols * tile, rows * tile, false, Image.FORMAT_RGB8)
	img.fill(GROUND)

	for cell: Vector2i in lv.path_cells:
		img.fill_rect(Rect2i(cell.x * tile, cell.y * tile, tile, tile), LANE)
	for cell: Vector2i in lv.high_ground:
		img.fill_rect(Rect2i(cell.x * tile, cell.y * tile, tile, tile), TOP)
	for rect: Rect2i in lv.spawn_zones:
		for y in range(rect.position.y, rect.position.y + rect.size.y):
			for x in range(rect.position.x, rect.position.x + rect.size.x):
				img.fill_rect(Rect2i(x * tile, y * tile, tile, tile), SPAWN_TINT)
	img.fill_rect(Rect2i(lv.objective.x * tile, lv.objective.y * tile, tile, tile), OBJECTIVE_TINT)
	return img

func _save(img: Image, path: String) -> void:
	var dir := path.get_base_dir()
	if dir != "" and not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	if img.save_png(path) != OK:
		printerr("_shot_topdown_mockup: save failed: ", path)
		return
	print("_shot_topdown_mockup: %s  %dx%d" % [path, img.get_width(), img.get_height()])

func _run() -> void:
	var lv := _pick_level()
	if lv == null:
		printerr("_shot_topdown_mockup: no usable level found (all KNOWN_BROKEN?)")
		get_tree().quit(1)
		return
	print("-- level %d (%s) --" % [lv.id, lv.display_name])

	var full := _render(lv)
	_save(full, "%s/topdown_mockup_native.png" % OUT_DIR)

	## A gameplay-scale sanity check: how this reads much smaller, not just up close.
	## A quarter of the image's CANVAS-space size: divide out the readback scale first, so
	## this squints by the same real factor whether the source arrived at canvas resolution
	## (a SubViewport render, as here) or at window resolution (a root readback, since the
	## stretch mode changed on 2026-09-05). A blind `/ 4` squints correctly only in the
	## first case; dividing by the canvas instead would break the aspect ratio in it.
	var div: float = 4.0 * UI.readback_scale(get_viewport(), full)
	var squint: Image = full.duplicate()
	squint.resize(maxi(1, int(full.get_width() / div)), maxi(1, int(full.get_height() / div)),
		Image.INTERPOLATE_NEAREST)
	_save(squint, "%s/topdown_mockup_squint.png" % OUT_DIR)

	print("\ndone")
	get_tree().quit(0)
