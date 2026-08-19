extends Node
## Correctness check for the cast-shadow system: does a LightOccluder2D actually block a
## Light2D's contribution, or is this just a glow with no real occlusion behind it?
##
## Needs a real renderer (--main-scene, NOT --headless: shadows are computed on the GPU
## and this reads pixels back from the viewport) — same requirement as _shot_fog.gd /
## _perf_probe.gd, see the reference-godot-binary note on why.
##
## CONFOUND NOTE, because it shaped this test's design: a first attempt at verifying this
## visually compared two whole-screen SCREENSHOTS taken a couple dozen frames apart
## (shadow_enabled false, then true) and pixel-diffed them. That diff was real (~27% of
## pixels changed) but noisy, because time-driven animation (dashed Routine tethers,
## Habit idle motion, ...) differs between two moments regardless of shadow_enabled —
## the diff could not by itself prove the CAUSE was shadows and not just time passing.
##
## This test instead samples two points at the SAME radius from the core's lamp — one the
## game's own has_line_of_sight() (the exact raycast combat already trusts, walking the
## same `high_ground` dictionary the occluders are built from) says is blocked by a wall,
## one it says is clear — and compares what EACH point gains from toggling
## shadow_enabled, not their absolute brightness. A same-radius same-frame ABSOLUTE
## comparison looks confound-free but silently assumes the floor/wall art under both
## points starts equally bright, which real level geometry does not guarantee (measured:
## a blocked point sitting on a brighter wall-face highlight beat a clear point on plain
## floor even with the light fully off). The delta each point gains from the toggle
## isolates the light's own contribution from whatever the art underneath already looked
## like — see the longer note next to the check itself.
##
## Spuštění:
##   godot --path <proj> --main-scene res://scenes/_test_shadow_occlusion.tscn

var completed := false
var fails := 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("  ok   %s %s" % [label, detail])
	else:
		fails += 1
		print("  FAIL %s %s" % [label, detail])


func _ready() -> void:
	var wd := Timer.new()
	wd.wait_time = 90.0
	wd.one_shot = true
	add_child(wd)
	wd.timeout.connect(func():
		if not completed:
			print("FAILED: watchdog fired")
			get_tree().quit(1))
	wd.start()
	call_deferred("_run")


## Luma of the pixel at a world position. NOT direct 1:1 with viewport pixels, even
## though there is no Camera2D anywhere in this project (ruled out as the cause first):
## window/stretch/mode is "canvas_items", which scales the 1920x1080 LOGICAL canvas to
## fit whatever the actual window turned out to be — measured here as 1895x1066, not
## 1920x1080, presumably this environment's window/DPI, not something the shipped game
## controls. brain_fog.gdshader's own SCREEN_UV lookups do not care (0..1 is resolution-
## independent by construction) but a raw pixel readback from a CPU-side Image does. A
## first pass at this test skipped this and got confusing near-zero deltas at points that
## should have been brightly lit — off by ~1.3%, i.e. ~26px at this map's scale, plenty to
## land a sample meant to be "just past a 16px-thick wall" on the wrong side of it.
func _sample(img: Image, world_pos: Vector2) -> float:
	var sz := img.get_size()
	var scale := Vector2(sz.x / 1920.0, sz.y / 1080.0)
	var p := world_pos * scale
	var x: int = clampi(int(p.x), 0, sz.x - 1)
	var y: int = clampi(int(p.y), 0, sz.y - 1)
	var c := img.get_pixel(x, y)
	return (c.r + c.g + c.b) / 3.0


func _run() -> void:
	var game = load("res://scenes/Game.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	# Bez obrany jádro vyhoří a _game_over() přepne scénu ještě před měřením (harness je
	# RODIČ Game — viz reference-godot-binary).
	GameState.max_focus = 999999
	GameState.focus = 999999
	await get_tree().process_frame

	var core_pos: Vector2 = game.objective_pos
	var r: float = Game.CORE_ROUTINE_RADIUS

	# Search level.high_ground for a wall cell close enough to the core that a point just
	# past its far side is still within the core's own lamp radius, confirm has_line_of_
	# sight calls that point blocked, then scan for a point at the SAME radius the same
	# check calls clear.
	var blocked_point := Vector2.INF
	var clear_point := Vector2.INF
	var sample_r := 0.0
	for cell: Vector2i in game.high_ground.keys():
		if cell == game.objective_cell:
			continue
		var wc: Vector2 = game.cell_center(cell)
		var d := wc.distance_to(core_pos)
		# The comparison this test makes (clear point brighter than blocked point, same
		# radius from the same light) only needs both points to sit where the light's
		# falloff is not ALREADY zero for reasons that have nothing to do with occlusion —
		# it does not need the flat, no-falloff zone specifically. That zone is now small
		# for the core (Game.SHADOW_CURVE_WIDE.x = 0.17 of r, since the 2026-08-18 playtest
		# fix made the core/Anchor curve more gradual — SHADOW_CURVE_TIGHT (0.55) is the
		# tower lamp's curve only, no longer the core's), so pinning the search to inside
		# it made level 1 too sparse to find a candidate at all. 0.80 stays comfortably
		# under SHADOW_CURVE_WIDE.y (0.90, where the curve goes hard to zero) while giving
		# the search a much wider ring to find real geometry in. A first pass at this test
		# used 0.55 (the core's pre-fix curve) and, separately, once picked a point near
		# 90% of r under that pre-fix curve and failed for a similar reason — neither
		# failure meant shadows were broken.
		if d < 24.0 or d > r * 0.80:
			continue
		var dir := (wc - core_pos).normalized()
		var candidate := wc + dir * 24.0   # a bit past the far side of the wall cell
		if game.high_ground.has(game.world_to_cell(candidate)):
			continue   # still inside a thick wall mass — try a different cell
		if game.has_line_of_sight(core_pos, candidate):
			continue   # not actually occluded (e.g. grazed a 1-cell-deep wall)
		var r_try := core_pos.distance_to(candidate)
		if r_try > r:
			continue
		var found_clear := Vector2.INF
		for deg in range(0, 360, 5):
			var a := deg_to_rad(float(deg))
			var cp := core_pos + Vector2.RIGHT.rotated(a) * r_try
			if game.has_line_of_sight(core_pos, cp):
				found_clear = cp
				break
		# Keep the CLOSEST-to-core candidate found, not the first: closer means more of
		# the light's falloff still remains (stronger signal), which matters more now
		# that the search ring is wide (0.80 * r) and its far edge sits close to
		# SHADOW_CURVE_WIDE.y (0.90), where the curve is nearly zero regardless of
		# occlusion. Do not break early — keep scanning every candidate cell so a closer
		# one later in iteration order still wins.
		if found_clear != Vector2.INF and (blocked_point == Vector2.INF or r_try < sample_r):
			blocked_point = candidate
			clear_point = found_clear
			sample_r = r_try

	_check("found a blocked+clear sample pair at the same radius from the core",
		blocked_point != Vector2.INF and clear_point != Vector2.INF,
		"blocked=%s clear=%s r=%.0f (core lamp r=%.0f)" % [blocked_point, clear_point, sample_r, r])
	if blocked_point == Vector2.INF or clear_point == Vector2.INF:
		completed = true
		print("\n%d FAIL(S)" % fails if fails > 0 else "\nALL PASS")
		get_tree().quit(1 if fails > 0 else 0)
		return

	# The core's own always-on lamp (built unconditionally in _build_shadow_light_layer)
	# is exactly the light source this geometry was chosen against — no extra build needed.
	game.shadow_enabled = false
	for _f in range(6):
		await get_tree().process_frame
	var img_off := get_viewport().get_texture().get_image()
	var off_blocked := _sample(img_off, blocked_point)
	var off_clear := _sample(img_off, clear_point)

	game.shadow_enabled = true
	for _f in range(6):
		await get_tree().process_frame
	var img_on := get_viewport().get_texture().get_image()
	var on_blocked := _sample(img_on, blocked_point)
	var on_clear := _sample(img_on, clear_point)

	var blocked_delta := on_blocked - off_blocked
	var clear_delta := on_clear - off_clear
	print("  blocked point %s: off=%.4f on=%.4f (delta %+.4f)" \
		% [blocked_point, off_blocked, on_blocked, blocked_delta])
	print("  clear   point %s: off=%.4f on=%.4f (delta %+.4f)" \
		% [clear_point, off_clear, on_clear, clear_delta])

	# THE actual check, on DELTAS rather than absolute brightness. An earlier version of
	# this test compared on_clear vs on_blocked directly ("same frame, same radius, so
	# the wall is the only difference") — sound in theory, but it silently assumed the
	# floor/wall ART under the two points was equally bright to begin with, which real
	# level geometry does not guarantee: two points at the same radius but different
	# ANGLES can land on a plain floor tile and a bright wall-face highlight respectively,
	# and that baseline gap can be bigger than anything the light adds. Measured directly:
	# a blocked point that happened to sit on brighter art read 0.2471 with the light
	# fully OFF, comfortably beating a clear point's 0.1085 WITH the light on — a false
	# fail that had nothing to do with occlusion. The delta each point gained from
	# shadow_enabled toggling isolates the light's own contribution from whatever the art
	# underneath already looked like, which is the thing actually under test.
	_check("clear point gained more brightness from the light than the blocked point did",
		clear_delta > blocked_delta + 0.003,
		"clear_delta=%.4f blocked_delta=%.4f" % [clear_delta, blocked_delta])
	_check("clear point gained brightness off->on at all", clear_delta > 0.003,
		"delta=%.4f" % clear_delta)
	_check("blocked point did not brighten anywhere near as much off->on",
		blocked_delta < 0.003, "delta=%.4f" % blocked_delta)

	completed = true
	print("\n%d FAIL(S)" % fails if fails > 0 else "\nALL PASS")
	get_tree().quit(1 if fails > 0 else 0)
