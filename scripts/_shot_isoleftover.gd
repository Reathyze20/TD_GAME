extends Node
## Single-use verification shot for the iso-leftover-diamond fix (game.gd's
## _draw_static_field spawn-zone/trod-telegraph tint and _draw_placement_preview hover
## block): before the fix, all three drew via GridProjection.cell_diamond()/
## diamond_corners() -- hardcoded 2:1 iso diamond math -- on a board whose live
## projection is GridProjection.MODE_SQUARE. That mismatch is the "red diamond floating
## over the top-right of the board" the original bug report screenshot caught: the hover
## preview specifically, since it is the one of the three that is live per-frame
## (PlacementOverlay._process() calls queue_redraw() every frame) and mouse-driven.
##
## ONE state per process run (--mode board|valid|invalid).
##
## level_1 is loaded automatically by Game._ready() (Data.get_level(
## GameState.current_level_index)); "exercise" (data/habits/exercise.tres) is the habit
## selected for the two hover shots.
##
## THIS DOES NOT TRY TO STEER THE HOVER CELL. Earlier drafts fought Game._process()'s
## unconditional _update_hover() call, which re-derives _hover_cell from
## get_global_mouse_position() every real frame -- the actual desktop cursor, which this
## run does not control and which was observed both drifting and resting at different
## positions across attempts (this is a real windowed process on a live desktop, not an
## isolated headless one; even Input.warp_mouse()/injected motion events got overridden
## or landed somewhere unexpected). Rather than win that race, this makes the OUTCOME
## independent of which cell ends up hovered:
##   "valid"   -- every in-bounds block gets pointed at a shared, already-EMPTY BuildSpot
##                in game.build_spots, so _can_build() is true no matter where the mouse
##                organically lands.
##   "invalid" -- game.build_spots is cleared outright, so _can_build() is false
##                everywhere.
## Whatever cell _update_hover() lands on, the hover preview it draws is still a genuine
## exercise of _draw_placement_preview() end to end -- same function, same tint logic,
## same shape code -- just no longer dependent on hitting one specific cell.
##
## Run (NOT --headless -- drawing needs a real renderer; --main-scene, not --script, so
## autoloads are registered):
##   godot --path <proj> --main-scene res://scenes/_shot_isoleftover.tscn -- --mode board
##   godot --path <proj> --main-scene res://scenes/_shot_isoleftover.tscn -- --mode valid
##   godot --path <proj> --main-scene res://scenes/_shot_isoleftover.tscn -- --mode invalid

const OUT_DIR := ".dev/screenshots"
const SETTLE_FRAMES := 20
const MAX_ATTEMPTS := 10

## Full-opacity outline colors _draw_placement_preview() draws (Color(0.35,1.0,0.55) /
## Color(1.0,0.4,0.4), alpha 1.0) -- used only to confirm SOMETHING drew (i.e.
## _hover_cell moved off its Vector2i(-999,-999) boot sentinel by capture time), not to
## pin down where.
const GREEN_OUTLINE := Color8(89, 255, 140)
const RED_OUTLINE := Color8(255, 102, 102)
const COLOR_TOL := 30.0 / 255.0


func _ready() -> void:
	call_deferred("_run")


func _arg(name: String, fallback: String) -> String:
	var args := OS.get_cmdline_user_args()
	for i in range(args.size()):
		if args[i] == name and i + 1 < args.size():
			return args[i + 1]
	return fallback


func _save(img: Image, path: String) -> void:
	var dir := path.get_base_dir()
	if dir != "" and not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	# 4x the CANVAS, derived rather than a blind *4: since the stretch mode became
	# "canvas_items" (2026-09-05) a viewport grab already arrives at window resolution.
	var big := img.duplicate()
	var up := maxi(1, int(round(4.0 / UI.readback_scale(get_viewport(), img))))
	if up > 1:
		big.resize(big.get_width() * up, big.get_height() * up, Image.INTERPOLATE_NEAREST)
	if big.save_png(path) != OK:
		printerr("_shot_isoleftover: uložení selhalo: ", path)
		return
	print("_shot_isoleftover: %s  %dx%d" % [path, big.get_width(), big.get_height()])


## Internal viewport texture at native resolution (480x270-ish) -- upscaling 4x nearest
## happens only in _save(), same technique _shot_unitscale.gd uses since stretch/
## mode="viewport" (project.godot) means the upscaled version is what actually shows.
func _capture_raw() -> Image:
	return get_viewport().get_texture().get_image()


## True if `outline_color` appears ANYWHERE in `img` -- confirms _draw_placement_preview
## actually drew a hover block this frame (i.e. _hover_cell was in-bounds), regardless of
## which cell it landed on.
func _outline_present_anywhere(img: Image, outline_color: Color) -> bool:
	var w := img.get_width()
	var h := img.get_height()
	# Coarse stride: this only needs to catch a ~48x48-native-px block, not every pixel.
	var stride := 3
	for y in range(0, h, stride):
		for x in range(0, w, stride):
			var c := img.get_pixel(x, y)
			if absf(c.r - outline_color.r) < COLOR_TOL and absf(c.g - outline_color.g) < COLOR_TOL \
				and absf(c.b - outline_color.b) < COLOR_TOL:
				return true
	return false


func _run() -> void:
	var mode := _arg("--mode", "board")

	var game: Game = load("res://scenes/Game.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	# Same harness bypasses as every other _test_/_shot_ fixture that instantiates
	# Game.tscn directly (see reference-godot-binary / _test_phase2.gd etc.): without
	# these, a stray distraction or the Routine gate could interfere with what this shot
	# is actually trying to isolate (shape, not balance).
	GameState.max_focus = 999999
	GameState.focus = 999999
	GameState.dopamine = 9999
	game.fog_enabled = false
	game.routine_gates_enabled = false
	for _f in range(4):
		await get_tree().process_frame

	if game.build_spots.is_empty():
		printerr("_shot_isoleftover: level has no build_spots -- cannot demo hover preview")
		get_tree().quit(1)
		return

	var out_path := ""
	var want_color := Color.WHITE
	var check_outline := false
	match mode:
		"board":
			out_path = "%s/p_isoleftover_before.png" % OUT_DIR
			print("_shot_isoleftover[board]: %d build spots, %d spawn zone groups" %
				[game.build_spots.size(), game.spawn_zone_cells.size()])
		"valid":
			# Point EVERY in-bounds block at a shared, already-EMPTY BuildSpot so
			# _can_build() is true wherever the mouse actually ends up hovering --
			# see the file header for why this sidesteps steering the hover cell.
			var any_spot = game.build_spots.values()[0]
			var g := Data.GRID
			for y in range(int(g.rows)):
				for x in range(int(g.cols)):
					var c := Data.build_block(Vector2i(x, y))
					if game._in_bounds(c):
						game.build_spots[c] = any_spot
			GameState.select_habit("exercise")
			out_path = "%s/p_isoleftover_hover_valid.png" % OUT_DIR
			want_color = GREEN_OUTLINE
			check_outline = true
			print("_shot_isoleftover[valid]: every in-bounds block forced EMPTY (%d spots)" %
				game.build_spots.size())
		"invalid":
			# No BuildSpot anywhere -- _can_build() is false wherever the mouse ends up.
			game.build_spots.clear()
			GameState.select_habit("exercise")
			out_path = "%s/p_isoleftover_hover_invalid.png" % OUT_DIR
			want_color = RED_OUTLINE
			check_outline = true
			print("_shot_isoleftover[invalid]: build_spots cleared")
		_:
			printerr("_shot_isoleftover: unknown --mode %s (want board|valid|invalid)" % mode)
			get_tree().quit(1)
			return

	var img: Image = null
	var attempt := 0
	while attempt < MAX_ATTEMPTS:
		attempt += 1
		for _f in range(SETTLE_FRAMES):
			await get_tree().process_frame
		var candidate := _capture_raw()
		if not check_outline or _outline_present_anywhere(candidate, want_color):
			img = candidate
			print("_shot_isoleftover[%s]: captured on attempt %d (hover_cell=%s)" %
				[mode, attempt, game._hover_cell])
			break
		print("_shot_isoleftover[%s]: attempt %d showed no hover block yet (hover_cell=%s still out of bounds?), retrying" %
			[mode, attempt, game._hover_cell])
	if img == null:
		printerr("_shot_isoleftover[%s]: gave up after %d attempts -- saving last capture anyway" %
			[mode, MAX_ATTEMPTS])
		img = _capture_raw()

	_save(img, out_path)
	print("HOTOVO")
	get_tree().quit(0)
