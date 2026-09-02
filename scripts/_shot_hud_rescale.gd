extends Node
## One-shot visual check for the P-task "game.gd HUD container sizes never got the /4
## treatment the font sizes got when the canvas moved from 1920x1080 to 480x270". Loads a
## real level via Game.tscn (same pattern as _shot_defender_pivot.gd), lets the HUD build
## (_build_top_bar / _build_bottom_bar run synchronously from Game._ready()), then grabs
## the internal 480x270 viewport image and upscales it 4x nearest — because
## stretch/mode="viewport" means get_viewport().get_texture() only ever returns the
## internal buffer, never the 1920x1080 window-scaled picture a player actually sees.
##
## Not a pass/fail test (see CLAUDE.md: _shot_* does snapshots, not assertions) — the
## human looks at the PNGs. Single-use, deleted after the screenshots are captured.
##
## Run (needs a real renderer, so NOT --headless; --main-scene, not --script, for the
## Data/GameState autoloads):
##   godot --path <proj> --main-scene res://scenes/_shot_hud_rescale.tscn

const OUT_DIR := ".dev/screenshots"


func _ready() -> void:
	call_deferred("_run")


func _save(img: Image, path: String) -> void:
	var dir := path.get_base_dir()
	if dir != "" and not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	if img.save_png(path) != OK:
		printerr("_shot_hud_rescale: save failed: ", path)
		return
	print("_shot_hud_rescale: %s  %dx%d" % [path, img.get_width(), img.get_height()])


func _upscale4x(img: Image) -> Image:
	var out: Image = img.duplicate()
	out.resize(out.get_width() * 4, out.get_height() * 4, Image.INTERPOLATE_NEAREST)
	return out


func _run() -> void:
	var game: Game = load("res://scenes/Game.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	# Guard against a stray _game_over() scene-swap wiping this harness out from under
	# itself mid-capture (same reasoning as _shot_defender_pivot.gd).
	GameState.max_focus = 999999
	GameState.focus = 999999
	game.fog_enabled = false
	await get_tree().process_frame

	# A couple more frames so every HUD element (top bar, bottom build bar, wave preview,
	# hover tooltip) has settled its layout pass.
	for _f in range(6):
		await get_tree().process_frame

	var full := get_viewport().get_texture().get_image()
	print("_shot_hud_rescale: internal viewport %dx%d" % [full.get_width(), full.get_height()])
	_save(_upscale4x(full), "%s/p_hudrescale_gameplay.png" % OUT_DIR)

	# Zoomed crop of just the bottom build panel row — the row with the most fixed-width
	# buttons packed side by side (8 habit + 5 intervention + pause/speed/skip/quick-hit/
	# start-wave), so the one most likely to still show overflow if a literal was missed.
	# Hardcoded 24/17 rather than reading Game's private consts (mirrors the values at
	# scripts/game.gd _HUD_BOTTOM_H / _HUD_TOP_H — this harness is disposable, not worth
	# a public accessor on Game just to avoid the duplication).
	const BOTTOM_H := 24
	const TOP_H := 17
	var bh := full.get_height()
	var bar_rect := Rect2i(0, bh - BOTTOM_H, full.get_width(), BOTTOM_H)
	var bottom_crop := full.get_region(bar_rect)
	_save(_upscale4x(bottom_crop), "%s/p_hudrescale_buildpanel.png" % OUT_DIR)

	# Zoomed crop of just the top bar row (Focus/Burnout/Tolerance meters + combo label).
	var top_rect := Rect2i(0, 0, full.get_width(), TOP_H)
	var top_crop := full.get_region(top_rect)
	_save(_upscale4x(top_crop), "%s/p_hudrescale_topbar.png" % OUT_DIR)

	# --- extra: the upgrade/sell panel (_open_panel — the panel/stats-width fix) ---
	var cell: Vector2i = game.build_spots.keys()[0]
	var bs: BuildSpot = game.build_spots[cell]
	bs.build_habit("focus_timer")
	game._try_open_panel(cell)
	for _f in range(4):
		await get_tree().process_frame
	var panel_img := get_viewport().get_texture().get_image()
	_save(_upscale4x(panel_img), "%s/p_hudrescale_openpanel.png" % OUT_DIR)
	game._close_panel()

	# --- extra: the draft overlay (_CARD_W / _CARD_BODY_W fix) ---
	GameState.run_insight = 999
	game._show_draft_screen()
	for _f in range(4):
		await get_tree().process_frame
	var draft_img := get_viewport().get_texture().get_image()
	_save(_upscale4x(draft_img), "%s/p_hudrescale_draft.png" % OUT_DIR)

	print("HOTOVO")
	get_tree().quit(0)
