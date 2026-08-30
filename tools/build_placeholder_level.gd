extends SceneTree
## Rough placeholder LevelData for the new MODE_SQUARE grid (30x14 @ tile=16, see
## Data.GRID's own comment). Builds TWO levels:
##
##   id=1  — a simple smoke-test maze, no special mechanics.
##   id=98 — "First Light", rebuilt from the original (git show 5bfa33e:data/levels/
##           level_iso_1.tres) with every NON-spatial field copied verbatim (streak,
##           fog/shadows/routine_gates, cue_phase, path_off_lane_cost, wave_curve,
##           trods' announce/open_at_wave, ads) since those are proven game-design
##           values unrelated to the grid migration. Only the SPATIAL fields
##           (objective/spawn_zones/high_ground/path_cells/trod.cells) are redesigned
##           for the smaller 30x14 board — id=98 exists because a chunk of the test
##           suite (_test_trod, _test_streak, _test_level_simulator, _test_mapeditor)
##           hardcodes it as the one level with a working trod + streak setup, per
##           _test_attention.gd's own comment: "the entire reason level 98 exists".
##
## NOT a substitute for real level authoring — see this file's header before this
## session's edit for the full disclaimer (scenes/MapEditor.tscn + Bake is where real
## levels belong). This exists ONLY to prove the new grid/resolution/projection boots
## end to end and to satisfy tests that hardcode id 98's mechanics, not its layout.
##
## Usage: godot --headless --script tools/build_placeholder_level.gd

func _cells_range(x0: int, x1: int, y0: int, y1: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for x in range(x0, x1 + 1):
		for y in range(y0, y1 + 1):
			out.append(Vector2i(x, y))
	return out

func _build_level_1() -> LevelData:
	var lv := LevelData.new()
	lv.id = 1
	lv.display_name = "Placeholder — square grid smoke test"
	lv.start_dopamine = 300
	lv.focus = 30
	lv.objective = Vector2i(28, 7)  # must sit on a BUILD_BLOCK center: x%3==1, y%3==1
	lv.spawn_zones = [Rect2i(0, 5, 1, 4)]

	# Three BUILD_BLOCK(3)-aligned obstacles (middle cell = 3x+1, 3y+1 on both axes —
	# a block off that alignment still "works" but its middle cell no longer lines up
	# with Data.build_block()'s own convention, which starved _test_effort/_test_taxonomy
	# of the second buildable spot they expect). Row 6-8 stays a clear lane through the
	# first pair; the third sits across row 7 on purpose, so the open-maze pathfinder has
	# to route around it rather than the board being trivially a straight corridor.
	var high_ground: Array[Vector2i] = []
	high_ground.append_array(_cells_range(9, 11, 3, 5))
	high_ground.append_array(_cells_range(9, 11, 9, 11))
	high_ground.append_array(_cells_range(18, 20, 6, 8))
	lv.high_ground = high_ground

	lv.wave_count = 3
	var entry := WaveCurveEntryData.new()
	entry.distraction = load("res://data/distractions/doomscroll.tres")
	entry.from_wave = 1
	entry.base_count = 5
	entry.growth_per_wave = 2.0
	entry.spacing = 0.5
	lv.wave_curve = [entry]
	return lv

func _build_level_98() -> LevelData:
	var lv := LevelData.new()
	# --- non-spatial fields, copied verbatim from the original First Light ---
	lv.id = 98
	lv.display_name = "First Light"
	lv.start_dopamine = 300
	lv.focus = 25
	lv.cue_phase = 1
	lv.fog = false
	lv.shadows = false
	lv.routine_gates = false
	lv.streak = true
	lv.path_off_lane_cost = 8.0
	lv.wave_count = 5
	var ad: AdData = load("res://data/ads/brain_defense.tres")
	lv.ads = [ad]
	var e1 := WaveCurveEntryData.new()
	e1.distraction = load("res://data/distractions/notification.tres")
	e1.base_count = 6
	e1.growth_per_wave = 2.5
	e1.spacing = 0.8
	var e2 := WaveCurveEntryData.new()
	e2.distraction = load("res://data/distractions/doomscroll.tres")
	e2.from_wave = 3
	e2.base_count = 2
	e2.growth_per_wave = 1.5
	e2.spacing = 1.4
	lv.wave_curve = [e1, e2]

	# --- spatial fields, redesigned for the 30x14 grid ---
	# Two obstacle blocks off to the side (buildable spots, out of every path below).
	lv.spawn_zones = [Rect2i(0, 6, 1, 2)]
	lv.objective = Vector2i(28, 7)
	var high_ground: Array[Vector2i] = []
	high_ground.append_array(_cells_range(9, 11, 9, 11))
	high_ground.append_array(_cells_range(15, 17, 9, 11))
	lv.high_ground = high_ground

	# "Official" lane: up col 0, across row 2, down col 25, into the objective — long
	# way around. Weight 1.0 (path_cells), so the pathfinder prefers it pre-trod even
	# though it is a longer walk than the direct row-7 line below (8.0x off-lane cost
	# on that direct line makes 27 open cells cost more than this ~38-cell detour).
	#
	# EACH SEGMENT STARTS ONE PAST THE CORNER THE PREVIOUS ONE ENDED ON. _cells_range()
	# is inclusive at both ends, so a segment that begins ON the shared corner emits it a
	# second time and path_cells gets a duplicate. Two of the three corners below were
	# already written that way; the col-25 descent was not, and shipped level_98 with
	# Vector2i(25, 2) listed twice (found by the P0b side-car, fixed as P0c). Nothing in
	# the game reads that duplicate today -- lane_cells is a Dictionary and tile variants
	# are seeded from hash(cell), not from the array index -- which is exactly why it
	# survived: it could not show up as a visible defect. _test_levels checks for it now.
	var path_cells: Array[Vector2i] = []
	path_cells.append_array(_cells_range(0, 0, 2, 7))
	path_cells.append_array(_cells_range(1, 25, 2, 2))
	path_cells.append_array(_cells_range(25, 25, 3, 7))
	path_cells.append_array(_cells_range(26, 27, 7, 7))
	lv.path_cells = path_cells

	# Trod: the direct row-7 shortcut, closed until wave 3. Stops at col 24, one short of
	# where path_cells' own col-25 descent already sits at row 7 — trod.cells and
	# path_cells must be disjoint, or lane_cells (a Dictionary) grows by fewer than
	# trod.cells.size() when the overlap gets set twice. Still converges: the route this
	# produces shares the literal tail (25,7)-(26,7)-(27,7) with the old route into the
	# objective, satisfying the "new route stays in the old defense's reach" rule
	# trod_data.gd documents.
	var trod := TrodData.new()
	trod.open_at_wave = 3
	trod.cells = _cells_range(1, 24, 7, 7)
	trod.announce = "A new trod has opened to the west"
	lv.trods = [trod]
	return lv

func _initialize() -> void:
	for lv in [_build_level_1(), _build_level_98()]:
		var path := "res://data/levels/level_%d.tres" % lv.id
		var err := ResourceSaver.save(lv, path)
		if err != OK:
			push_error("save failed (%s): %s" % [path, err])
			quit(1)
			return
		print("wrote %s" % path)
	quit(0)
