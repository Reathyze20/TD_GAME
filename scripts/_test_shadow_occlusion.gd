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


## Luma of the pixel at a world position. NOT assumed 1:1 with the readback image, and
## NOT hardcoded to a canvas size either — the ratio is read from the live viewport every
## call. World coordinates are logical-canvas coordinates; `img` is whatever size the
## readback happened to come back at.
##
## THIS LINE IS THE ENTIRE "KNOWN-BROKEN" STORY, so it gets the long version. It used to
## read `Vector2(sz.x / 1920.0, sz.y / 1080.0)`, with a comment explaining that
## window/stretch/mode was "canvas_items" over a 1920x1080 LOGICAL canvas measured back
## as 1895x1066. Both halves of that stopped being true: `project.godot` now declares a
## 480x270 viewport with stretch mode "viewport" and integer scaling (the T5 square
## migration and the 480x270 UI rescale), and the readback comes back at exactly 480x270.
## The constant did not follow, so every sample was taken at 480/1920 = 0.25 of its
## intended position — a point meant to sit 56 px left of the core was read 342 px away
## from it, off the board entirely and nowhere near any light.
##
## That one stale constant is why docs/KNOWN_BROKEN.md recorded a "Defect 2 — real
## regression in rendering: the lamp adds nothing to the rendered image at all", quoting
## `blocked point (272.0, 137.0) off=0.0967 on=0.0967 (delta +0.0000)`. Those coordinates
## give it away: y=137 is this 480x270 board's own core row, not a 1920x1080 one, so that
## measurement was already taken after the rescale and read pixels at (68, 34) and
## (160, 34) — the top edge of the screen, outside the field. Re-measured with the ratio
## derived instead of assumed, the core lamp contributes +0.15 luma at r=10 and stays
## above this test's own 0.003 threshold out to r~100. The lamp was never broken; the
## ruler was.
func _sample(img: Image, world_pos: Vector2) -> float:
	var sz := img.get_size()
	var canvas := get_viewport().get_visible_rect().size
	var scale := Vector2(sz.x / canvas.x, sz.y / canvas.y)
	var p := world_pos * scale
	var x: int = clampi(int(p.x), 0, sz.x - 1)
	var y: int = clampi(int(p.y), 0, sz.y - 1)
	var c := img.get_pixel(x, y)
	return (c.r + c.g + c.b) / 3.0


func _run() -> void:
	var game: Game = load("res://scenes/Game.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	# Bez obrany jádro vyhoří a _game_over() přepne scénu ještě před měřením (harness je
	# RODIČ Game — viz reference-godot-binary).
	GameState.max_focus = 999999
	GameState.focus = 999999
	await get_tree().process_frame

	var core_pos: Vector2 = game.objective_pos
	var r: float = Game.CORE_ROUTINE_RADIUS
	var g = Data.GRID
	var tile := float(g.tile)
	# Shrunk by a tile on every side, deliberately. A sample landing on the outermost pixel
	# column reads a border pixel where the field art ends, and the whole measurement below
	# is a luma difference of ~0.018 -- small enough that an edge artefact would swamp it.
	# The unshrunk rect first picked (479.7, 187.8) on a 480-wide board: passing, but one
	# pixel from the edge and passing for no reason anyone could rely on.
	var board := Rect2(
		Vector2(float(g.origin_x), float(g.origin_y)),
		Vector2(float(g.cols) * tile, float(g.rows) * tile)).grow(-tile)

	# WHY THIS TEST NOW PLANTS ITS OWN WALL INSTEAD OF HUNTING FOR ONE.
	#
	# The original search walked level.high_ground for a wall cell in the ring
	# (24 px, 0.80 * r] around the core and sampled a point just past its far side. That
	# worked while CORE_ROUTINE_RADIUS was 330: the ring reached out to 264 px and level
	# 1's wall mass sat inside it. P8b halved every light radius to fit the real 480x224
	# board (330 -> 165), which pulled the ring in to (24, 132] -- and on the shipped level
	# the NEAREST wall cell is 128 px from the core, with every other one past 132.
	# Measured: of 27 wall cells, 24 fell outside the ring and the remaining 3 were
	# rejected because the point "just past" them landed inside the same wall mass. Zero
	# candidates, which is the `blocked=(inf, inf) r=0` this fixture had been failing with.
	#
	# Widening the ring does not fix it, and it is worth writing down why so nobody tries:
	# the core lamp's contribution, re-measured along five angles with the sampler above
	# fixed, is +0.1190 at r=10, +0.0183 at r=55, +0.0078 at r=85, +0.0026 at r=100 and
	# indistinguishable from zero from r=115 outward -- 1/255 is 0.0039, so past ~r=100 the
	# signal is under the 8-bit floor of the readback itself. Every wall on this level is
	# at r>=128, i.e. in the dead zone. A ring wide enough to include one would only ever
	# produce a "clear point gained no brightness" failure that says nothing about
	# occlusion -- exactly the false failure this file's own comments already warn about
	# twice ("once picked a point near 90% of r under that pre-fix curve and failed for a
	# similar reason -- neither failure meant shadows were broken").
	#
	# So the geometry is now BUILT rather than found. That also removes a dependency this
	# test never declared and nobody could see: it silently required the shipped level to
	# carry a wall in a particular annulus around its objective, and level authoring broke
	# it from a distance. What the test ASSERTS is unchanged -- the three checks at the
	# bottom of this function are the same three, on the same thresholds.
	var sample_r: float = clampf(r * 0.34, tile * 2.5, r * 0.5)

	var wall_cell := Vector2i(-9999, -9999)
	var blocked_point := Vector2.INF
	var clear_point := Vector2.INF
	for deg in range(0, 360, 5):
		var dir := Vector2.RIGHT.rotated(deg_to_rad(float(deg)))
		var candidate := core_pos + dir * sample_r
		if not board.has_point(candidate):
			continue
		if game.high_ground.has(game.world_to_cell(candidate)):
			continue
		# The wall goes 1.5 tiles short of the sample, so the sample sits just past its far
		# face -- the same "a bit past the far side of the wall cell" the search-based
		# version used, now expressed in tiles instead of a 24 px literal that happened to
		# be 1.5 tiles only while a tile was 16 px.
		var cell := game.world_to_cell(core_pos + dir * (sample_r - tile * 1.5))
		if cell == game.objective_cell or game.high_ground.has(cell):
			continue
		if not board.has_point(game.cell_center(cell)):
			continue
		# A clear point at the SAME radius, at least 60 degrees away so the wall about to be
		# planted cannot shadow it too, and ON THE BOARD -- the old scan checked neither, and
		# would happily return a point off the right-hand edge that _sample() then clamped
		# back to the border pixel, silently reading a different radius than it reported.
		var found_clear := Vector2.INF
		for deg2 in range(0, 360, 5):
			var sep: int = absi(((deg2 - deg + 180) % 360) - 180)
			if sep < 60:
				continue
			var cp := core_pos + Vector2.RIGHT.rotated(deg_to_rad(float(deg2))) * sample_r
			if not board.has_point(cp):
				continue
			if game.high_ground.has(game.world_to_cell(cp)):
				continue
			if not game.has_line_of_sight(core_pos, cp):
				continue
			found_clear = cp
			break
		if found_clear == Vector2.INF:
			continue
		wall_cell = cell
		blocked_point = candidate
		clear_point = found_clear
		break

	_check("found a blocked+clear sample pair at the same radius from the core",
		blocked_point != Vector2.INF and clear_point != Vector2.INF,
		"blocked=%s clear=%s r=%.0f (core lamp r=%.0f)" % [blocked_point, clear_point, sample_r, r])
	if blocked_point == Vector2.INF or clear_point == Vector2.INF:
		completed = true
		print("\n%d FAIL(S)" % fails if fails > 0 else "\nALL PASS")
		get_tree().quit(1 if fails > 0 else 0)
		return

	# Plant the occluder. Same order _set_sunk() uses when Tolerance re-solidifies a sunk
	# block -- the game's own "a cell just became a wall" recipe -- plus the occluder rebuild
	# _set_sunk() does NOT do (noted in PROGRESS.md; sinking walls and cast shadows drifting
	# apart is a real game-side question, not this test's to answer).
	game.high_ground[wall_cell] = true
	if not game.level.high_ground.has(wall_cell):
		game.level.high_ground.append(wall_cell)
	if game.astar.is_in_bounds(wall_cell.x, wall_cell.y):
		game.astar.set_point_solid(wall_cell, true)
	game._build_platforms()
	game._rebuild_walls()
	game._build_shadow_occluders()
	await get_tree().process_frame

	# Preconditions, not the thing under test: if the planted cell does not read as
	# occluding to the game's OWN raycast, every brightness number below is meaningless and
	# would otherwise fail the real checks with a misleading story.
	_check("the planted wall cell occludes the blocked point",
		not game.has_line_of_sight(core_pos, blocked_point),
		"wall_cell=%s blocked=%s" % [wall_cell, blocked_point])
	_check("the clear point is still clear after planting the wall",
		game.has_line_of_sight(core_pos, clear_point), "clear=%s" % clear_point)
	if fails > 0:
		completed = true
		print("\n%d FAIL(S)" % fails)
		get_tree().quit(1)
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
