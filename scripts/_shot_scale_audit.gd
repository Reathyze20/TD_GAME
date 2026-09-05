extends Node
## Scale audit: measures the board, the objective prop, the HUD and the units IN PIXELS
## on the real 480x270 canvas, and saves the picture next to the numbers.
##
## Why numbers and not just a picture: this project has hit the same class of bug three
## times now -- art authored for a different canvas, drawn at pixel_scale() with no
## adjustment (Data.UNIT_ART_SCALE's header and Game.CORE_PROP_ART_SCALE's header each
## describe their own instance of it). Every time it was argued from a screenshot, and
## every time the argument was "looks too big", which cannot be checked, shared, or
## regressed. This prints px and tiles, so "the core overflows" becomes a number that is
## either true or false.
##
## NOT a pass/fail test (CLAUDE.md: _shot_* takes snapshots, assertions live in _test_*).
## It prints a report and saves PNGs; the human reads both. Kept rather than deleted
## because it answers a recurring question -- rerun it after any art or HUD change.
##
## Run (needs a real renderer, so NOT --headless; --main-scene, not --script, because
## the Data/GameState autoloads have to exist):
##   godot --path <proj> --main-scene res://scenes/_shot_scale_audit.tscn -- --level 0

const OUT_DIR := ".dev/screenshots"


func _ready() -> void:
	call_deferred("_run")


func _arg(n: String, fallback: String) -> String:
	var args := OS.get_cmdline_user_args()
	for i in range(args.size()):
		if args[i] == n and i + 1 < args.size():
			return args[i + 1]
	return fallback


func _save(img: Image, path: String) -> void:
	var dir := path.get_base_dir()
	if dir != "" and not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	if img.save_png(path) != OK:
		printerr("_shot_scale_audit: save failed: ", path)


## Brings a grab up to 4x CANVAS size whatever resolution it arrived at. The blind `* 4`
## this replaced was written when the readback WAS the 480x270 canvas; since the stretch
## mode became "canvas_items" (2026-09-05) it arrives at 1920x1080 already, and this
## harness was writing a 7680x4320 PNG into .dev/screenshots on every run.
func _up4(img: Image) -> Image:
	var factor := maxi(1, int(round(4.0 / UI.readback_scale(get_viewport(), img))))
	if factor == 1:
		return img
	var out: Image = img.duplicate()
	out.resize(out.get_width() * factor, out.get_height() * factor, Image.INTERPOLATE_NEAREST)
	return out


## Every Control under the HUD layer, depth-first, with its rect in canvas space and how
## far that rect leaves the canvas. Controls only -- the Node2D overlays live in world
## space, not screen space, so they are measured separately above.
func _walk(n: Node, canvas: Vector2, depth: int, rows: Array) -> void:
	for c in n.get_children():
		if c is Control:
			var ctl := c as Control
			var r := Rect2(ctl.global_position, ctl.size)
			rows.append({
				"depth": depth,
				"name": String(ctl.name),
				"cls": ctl.get_class(),
				"rect": r,
				"visible": ctl.is_visible_in_tree(),
				"over": Vector4(
					maxf(0.0, -r.position.x),
					maxf(0.0, -r.position.y),
					maxf(0.0, r.end.x - canvas.x),
					maxf(0.0, r.end.y - canvas.y)),
			})
		_walk(c, canvas, depth + 1, rows)


## Distractions this level actually spawns, in wave order, deduplicated. Reads the wave
## data rather than the whole roster, because "what is on screen" is the question and
## docs/ROSTER.md says most distractions are used nowhere.
func _level_distraction_ids(lvl) -> Array:
	var seen := {}
	var out: Array = []
	if lvl == null:
		return out
	for w in lvl.waves:
		for b in w.groups:
			if b.distraction == null:
				continue
			if not seen.has(b.distraction.id):
				seen[b.distraction.id] = true
				out.append(b.distraction.id)
	return out


func _run() -> void:
	var want := int(_arg("--level", "0"))
	GameState.current_level_index = clampi(want, 0, Data.get_level_count() - 1)
	var lvl = Data.get_level(GameState.current_level_index)

	var game: Game = load("res://scenes/Game.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	# The guard every _shot_ harness needs: without it Focus reaches 0, _game_over() calls
	# change_scene_to_file() and the whole harness is freed out from under itself.
	GameState.max_focus = 999999
	GameState.focus = 999999
	GameState.dopamine = 100000
	await get_tree().process_frame
	for _f in range(8):
		await get_tree().process_frame

	var vp := get_viewport().get_visible_rect().size
	var g = Data.GRID
	var tile: float = float(g.tile)
	var board := Rect2(float(g.origin_x), float(g.origin_y),
		float(g.cols) * tile, float(g.rows) * tile)

	print("")
	print("======== SCALE AUDIT  level[%d] %s ========" % [
		GameState.current_level_index, str(lvl.id) if lvl != null else "?"])
	print("canvas        : %.0f x %.0f" % [vp.x, vp.y])
	print("board         : x %.0f..%.0f  y %.0f..%.0f  (%d x %d cells of %.0f px)" % [
		board.position.x, board.end.x, board.position.y, board.end.y,
		int(g.cols), int(g.rows), tile])
	print("pixel_scale   : %.2f    fog=%s  routine_gates=%s" % [
		Data.pixel_scale(), str(game.fog_enabled), str(game.routine_gates_enabled)])

	# ---- objective prop -----------------------------------------------------------
	print("")
	print("---- objective prop (Game.CORE_PROP_ART_SCALE) ----")
	var tex: Texture2D = game._core_prop_tex
	if tex == null:
		print("  core prop texture NOT LOADED - falls back to the drawn circles")
	else:
		var raw := Vector2(tex.get_size())
		# Recomputed with game.gd's own formula from _draw(), reading game.gd's OWN
		# constant. It used to say `* 0.3` -- a hand-copied literal, because the constant
		# was function-local and unnameable from here (fixed 2026-09-05 by promoting it).
		var csz := raw * Data.pixel_scale() * Game.CORE_PROP_ART_SCALE
		var r := Rect2(game.objective_pos + Vector2(-csz.x * 0.5, -csz.y + tile * 0.5), csz)
		print("  core.png raw  : %.0f x %.0f px" % [raw.x, raw.y])
		print("  drawn size    : %.1f x %.1f px = %.2f x %.2f tiles" % [
			csz.x, csz.y, csz.x / tile, csz.y / tile])
		print("  objective_pos : (%.1f, %.1f)  cell %s" % [
			game.objective_pos.x, game.objective_pos.y, str(lvl.objective)])
		print("  drawn rect    : x %.1f..%.1f  y %.1f..%.1f" % [
			r.position.x, r.end.x, r.position.y, r.end.y])
		print("  OVER canvas   : L%.1f T%.1f R%.1f B%.1f" % [
			maxf(0.0, -r.position.x), maxf(0.0, -r.position.y),
			maxf(0.0, r.end.x - vp.x), maxf(0.0, r.end.y - vp.y)])
		print("  OVER board    : L%.1f T%.1f R%.1f B%.1f" % [
			maxf(0.0, board.position.x - r.position.x),
			maxf(0.0, board.position.y - r.position.y),
			maxf(0.0, r.end.x - board.end.x), maxf(0.0, r.end.y - board.end.y)])
		var free_r := board.end.x - game.objective_pos.x
		print("  room right    : %.1f px = %.2f tiles from objective to board edge" % [
			free_r, free_r / tile])
		# Same omission as the unit section had: the sprite is not the only thing drawn at
		# the objective. game.gd::_draw() also paints the Focus arc ring and two pulse
		# waves there every frame, and on a 16px tile the ring's `+ 7.0` is nearly half a
		# tile of pure addition -- a pre-T5 absolute constant (initial commit, 2026-08-13)
		# that the canvas /4 never reached. Printed so it is a number, not a surprise.
		var ring_d := (tile * 0.45 + 7.0) * 2.0
		var wave_d := tile * 0.45 * 1.9 * 2.0
		print("  ring / waves  : ring %.1f px = %.2f tiles, widest pulse %.1f px = %.2f tiles" % [
			ring_d, ring_d / tile, wave_d, wave_d / tile])

	# ---- unit art -----------------------------------------------------------------
	print("")
	print("---- unit art (Data.UNIT_ART_SCALE = %.2f) ----" % Data.UNIT_ART_SCALE)
	# BODY vs FOOTPRINT, and the difference is the whole reason this section was wrong.
	#
	# Until 2026-09-05 this printed only the body rect and called it the unit's size. It
	# is not: distraction_animator.gd::_draw_type_glow (and horde_renderer.gd's batched
	# quad) paints a ground pool of the creature's colour AROUND that body every single
	# frame, sized off visual_radius(). So this harness reported a comfortable 1.20 tiles
	# for `notification` while a frame diff of the actual render measured 1.72 -- and the
	# oversized enemies stayed invisible to the one tool built to catch them. Reporting
	# the body alone is exactly as useful as measuring a person and omitting their coat.
	var glow_mult: float = DistractionAnimator.TYPE_GLOW_DIAMETER_SCALE
	print("  (footprint = the type-glow pool, visual_radius * %.2f, which is what the" % glow_mult)
	print("   player sees as the creature's extent -- the body rect is only its middle)")
	for did in _level_distraction_ids(lvl):
		var path := "res://assets/distractions/%s_frame_1.png" % String(did)
		if not ResourceLoader.exists(path):
			print("  %s : no sprite on disk - DistractionAnimator draws it procedurally"
				% String(did))
			continue
		var t: Texture2D = load(path)
		var s := Vector2(t.get_size()) * Data.pixel_scale() * Data.UNIT_ART_SCALE
		# visual_radius() is half the body WIDTH (animator's own definition), so the pool
		# is derived from s.x here rather than from a second copy of the sprite formula.
		var pool: float = (s.x * 0.5) * glow_mult
		print("  %s : raw %s -> body %.1f x %.1f px = %.2f tiles | footprint %.1f px = %.2f tiles" % [
			String(did), str(t.get_size()), s.x, s.y, s.x / tile, pool, pool / tile])


	# ---- habit head art ------------------------------------------------------------
	# Towers are the one family Data.UNIT_ART_SCALE does NOT cover: its header scopes
	# itself to "a moving combat unit's sprite (enemy Distraction and DefenderUnit)", and
	# tower.gd draws its head at get_size() * pixel_scale() with no further factor. So the
	# same 64px sheet that becomes a 1.6-tile distraction becomes a 4-tile tower. Measured
	# here rather than reasoned about, because that is this harness's whole point.
	print("")
	print("---- habit head art (tower.gd: get_size() * pixel_scale(), no UNIT_ART_SCALE) ----")
	for hid in Data.HABIT_ORDER:
		var hd = Data.get_habit(String(hid))
		var found := ""
		for suffix in ["", "_frame_1", "_east"]:
			var hp := "res://assets/towers/head_%s%s.png" % [String(hid), suffix]
			if ResourceLoader.exists(hp):
				found = hp
				break
		if found == "":
			print("  %s : no head art on disk" % String(hid))
			continue
		var ht: Texture2D = load(found)
		var hs := Vector2(ht.get_size()) * Data.pixel_scale()
		print("  %s : raw %s -> %.1f x %.1f px = %.2f tiles" % [
			String(hid), str(ht.get_size()), hs.x, hs.y, hs.x / tile])

	# The direction-A master candidates, if they are on disk, measured through BOTH
	# formulas -- the number the approval decision actually turns on.
	print("")
	print("---- direction A master candidates at game scale ----")
	for pair in [["assets/raw/master_distraction_a/cand_00.png", "as a distraction",
			Data.UNIT_ART_SCALE],
			["assets/raw/master_habit_a/cand_00.png", "as a habit head", 1.0]]:
		var cp: String = "res://" + str(pair[0])
		if not ResourceLoader.exists(cp):
			print("  %s : not on disk" % str(pair[0]))
			continue
		var ct: Texture2D = load(cp)
		var cs := Vector2(ct.get_size()) * Data.pixel_scale() * float(pair[2])
		print("  %s %s: raw %s -> %.1f px = %.2f tiles" % [
			str(pair[0]).get_file(), str(pair[1]), str(ct.get_size()), cs.x, cs.x / tile])
	# ---- HUD ----------------------------------------------------------------------
	print("")
	print("---- HUD controls leaving the %.0f x %.0f canvas ----" % [vp.x, vp.y])
	var rows: Array = []
	if game._hud_layer != null:
		_walk(game._hud_layer, vp, 0, rows)
	var bad := 0
	for row in rows:
		var o: Vector4 = row["over"]
		if o.x + o.y + o.z + o.w <= 0.01:
			continue
		bad += 1
		var r: Rect2 = row["rect"]
		print("  %s%s [%s] rect x %.0f..%.0f y %.0f..%.0f  OUT L%.0f T%.0f R%.0f B%.0f%s" % [
			"  ".repeat(int(row["depth"])), str(row["name"]), str(row["cls"]),
			r.position.x, r.end.x, r.position.y, r.end.y,
			o.x, o.y, o.z, o.w, "" if bool(row["visible"]) else "  (hidden)"])
	print("  -> %d of %d HUD controls leave the canvas" % [bad, rows.size()])

	# Fitting inside the canvas is only half of "the HUD is not broken": two panels can
	# both be on screen and still sit on top of each other. That is what a bar whose
	# content is taller than the _HUD_*_H it declares does to whatever was positioned
	# just below it, and no bounds check can see it.
	print("")
	print("---- top-level HUD panels: declared bar heights, and overlaps ----")
	print("  _HUD_TOP_H = %d   _HUD_BOTTOM_H = %d" % [Game._HUD_TOP_H, Game._HUD_BOTTOM_H])
	var tops: Array = []
	if game._hud_root != null:
		for c in game._hud_root.get_children():
			if c is Control and (c as Control).is_visible_in_tree():
				var ctl := c as Control
				if ctl.size.x <= 0.0 or ctl.size.y <= 0.0:
					continue
				tops.append({"name": str(ctl.name), "cls": ctl.get_class(),
					"rect": Rect2(ctl.global_position, ctl.size)})
	for t in tops:
		var r: Rect2 = t["rect"]
		var tag := ""
		if absf(r.position.y) < 0.5 and r.size.y > float(Game._HUD_TOP_H):
			tag = "   <-- TALLER than _HUD_TOP_H by %.0f px" % (r.size.y - Game._HUD_TOP_H)
		if r.end.y > 269.5 and r.size.y > float(Game._HUD_BOTTOM_H):
			tag = "   <-- TALLER than _HUD_BOTTOM_H by %.0f px" % (r.size.y - Game._HUD_BOTTOM_H)
		print("  %s [%s] x %.0f..%.0f y %.0f..%.0f%s" % [
			t["name"], t["cls"], r.position.x, r.end.x, r.position.y, r.end.y, tag])
	var clashes := 0
	for i in range(tops.size()):
		for j in range(i + 1, tops.size()):
			var a: Rect2 = tops[i]["rect"]
			var b: Rect2 = tops[j]["rect"]
			var hit := a.intersection(b)
			if hit.size.x > 0.5 and hit.size.y > 0.5:
				clashes += 1
				print("  OVERLAP %s x %s -> %.0f x %.0f px at (%.0f, %.0f)" % [
					tops[i]["name"], tops[j]["name"],
					hit.size.x, hit.size.y, hit.position.x, hit.position.y])
	print("  -> %d overlapping pairs among %d visible top-level panels" % [clashes, tops.size()])

	# ---- pictures -----------------------------------------------------------------
	var img := get_viewport().get_texture().get_image()
	var stem := "%s/p_scale_l%d" % [OUT_DIR, GameState.current_level_index]
	_save(img, "%s_native.png" % stem)
	_save(_up4(img), "%s_4x.png" % stem)
	print("")
	print("saved %s_native.png (%d x %d) and %s_4x.png" % [
		stem, img.get_width(), img.get_height(), stem])
	print("======== end audit ========")
	get_tree().quit(0)
