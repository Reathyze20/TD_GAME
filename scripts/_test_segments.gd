extends Node
## P8 (docs/refactor/PATHFINDING.MD): proves map-segment composition — MapSegmentData +
## LevelData.base/segment + MapComposer — actually holds up, in eight checks.
##
## THE THREE THINGS P8'S OWN "hotovo když" DEMANDS, and where each one lives here:
##
##  2. EVERY COMBINATION of unlocked segments yields a completable map. Check 2 walks the
##     REAL power set of the fixture's four segments — all 2^4 = 16 subsets, exhaustive
##     rather than sampled — composes each, builds ONE FlowField (P1) from the composed
##     objective and high_ground exactly the way AntiBlockValidator (P2) does, and demands
##     a route for every spawn that is active on any wave of that board.
##  3. IT FITS ON ONE SCREEN. Check 1 re-derives the visible tile budget from
##     ProjectSettings + Data.GRID + Game's own HUD bar constants and fails if
##     MapComposer's answer drifts from it, so the limit is MEASURED and not asserted;
##     check 2 then applies it to every one of the 16 composed boards.
##  4. COMPOSITION IS DETERMINISTIC. Check 3 composes each of the 16 subsets four ways —
##     twice from one chain with the unlock set built in opposite insertion orders, and
##     twice more from a SECOND chain carrying the same four segments in reversed
##     positions — and demands a byte-identical fingerprint from all four. That is the
##     real claim: the composed board depends on WHICH segments are live and on nothing
##     else, neither the enumeration order of the unlock set nor the segments' positions
##     in the base chain.
##
## The other five checks are what make the three above worth trusting:
##
##  5. Check 4 gives check 2 TEETH. A fifth segment seals its own spawn into a one-cell
##     pocket; composing it must produce an active, genuinely UNREACHABLE spawn. Without
##     this, "every combination was reachable" could just mean the reachability test never
##     says no.
##  6. Check 5 is the hard limit's own negative control: two deliberately oversized
##     segments (one a row past the bottom of the board, one a column past the right edge)
##     must be REFUSED even while unlocked — dropped from active_segments, their spawns
##     dark, the board still fitting. A limit that is only ever tested on content that
##     obeys it is not a limit.
##  7. Check 6 wires unlock_condition to MetaProgression, the autoload the user chose for
##     it on 2026-08-30, and proves compose() reads it. SAFETY: it mutates
##     MetaProgression.current_save.unlocked_segments IN MEMORY ONLY and never calls
##     write_savegame() — the real user://savegame.tres is left untouched, and the check
##     confirms that by comparing the file's modification time before and after. That
##     rule is inherited from _test_save_round_trip.gd's own hard-learned header.
##  8. Check 7 runs the PRODUCTION path: it registers the UNCOMPOSED chain tip in Data and
##     lets a real instantiated Game do the composing itself, then calls the actual
##     Game._active_spawn_point_cells() rather than any reimplementation — the same shape
##     _test_multispawn.gd (P6) uses, and what proves requires_segment now means something.
##  9. Check 8 plays that composed level to victory through LevelSimulator, so composition
##     is shown not to break wave spawning for real.
##
## FIXTURE. Six links, entirely in memory (Resource.new() — NEVER a .tres in data/, the
## same precedent _test_multispawn.gd set and for the same CLAUDE.md reason):
##
##     root ── S1 ── S2 ── S3 ── S4 ── tip          (each link's `base` points left)
##      │       └── the four unlockable segments ──┘        │
##      │                                                   └── identity/economy/waves
##      └── the spine: level 1's real, known-good geometry + the base spawn points
##
## root and tip carry no MapSegmentData header, so their geometry is unconditional; S1..S4
## each carry one and only join the board while their id is in the unlock set. The tip is
## the level actually played, which is why it owns the objective, the Focus pool and the
## wave curve — see MapComposer's header for the full "what composes / what the played
## level wins" contract.
##
## Needs --fixed-fps 60 (verify.sh's FIXED_FPS_TESTS) for check 8's LevelSimulator run,
## same reason _test_multispawn.gd does.

var completed := false
var fails := 0

## Far outside the range real campaign levels use, and distinct from _test_multispawn's
## own 762034 so the two can never collide if anything ever runs them in one process.
const TEST_LEVEL_ID := 762035
const WAVE_COUNT := 4

# ---------------------------------------------------------------- fixture geometry
#
# Base spawn cells, on the spine and therefore present on every one of the 16 boards.
const CELL_BASE_A := Vector2i(0, 6)
const CELL_BASE_B := Vector2i(0, 7)
## Authored on the SPINE but gated on a segment — P6's own documented use of
# requires_segment ("a spawn point authored on the base map that stays dark until the
# segment that justifies it is in play"). It is what makes level.active_segments
# load-bearing rather than a by-product of which cells got composed.
const CELL_GATED := Vector2i(0, 0)

const SEG_NORTH := &"north_wing"
const SEG_SOUTH := &"south_spur"
const SEG_EAST := &"east_gate"
const SEG_BAFFLE := &"inner_baffle"
const SEG_SEALED := &"sealed_pocket"
const SEG_TOO_TALL := &"overflow_south"
const SEG_TOO_WIDE := &"overflow_east"

const COND_NORTH := &"p8_test_cond_north"
const COND_SOUTH := &"p8_test_cond_south"
const COND_EAST := &"p8_test_cond_east"
const COND_BAFFLE := &"p8_test_cond_baffle"

## Cells the four unlockable segments contribute once anchored. Written out here as the
## ABSOLUTE result so the test states its own expectation independently of anchor
## arithmetic — every one of them lands in a row or column both shipped levels leave
## empty (rows 0, 1, 12, 13 and column 29), which is exactly the room P8 was looking for.
const NORTH_SPAWN := Vector2i(24, 0)
const SOUTH_SPAWN := Vector2i(2, 13)
const EAST_SPAWN := Vector2i(29, 2)
const SEALED_SPAWN := Vector2i(26, 12)

func _ready() -> void:
	var wd := Timer.new()
	wd.wait_time = 240.0
	wd.one_shot = true
	add_child(wd)
	wd.timeout.connect(func():
		if not completed:
			print("FAILED: watchdog fired")
			get_tree().quit(1))
	wd.start()
	call_deferred("_run")

func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("  ok   %s %s" % [label, detail])
	else:
		fails += 1
		print("  FAIL %s %s" % [label, detail])

# ---------------------------------------------------------------- fixture builders

func _spawn(cell: Vector2i, wave: int, requires: StringName = &"") -> SpawnPointData:
	var sp := SpawnPointData.new()
	sp.cell = cell
	sp.active_from_wave = wave
	sp.requires_segment = requires
	return sp

func _cells(list: Array) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	out.assign(list)
	return out

func _shipped_level_1() -> LevelData:
	for i in range(Data.get_level_count()):
		if Data.get_level(i).id == 1:
			return Data.get_level(i)
	return null

## The unconditional spine: level 1's real high_ground (known-good geometry every other
## test in this repo already trusts) plus the three spawn points that live on the base
## map. No identity, no economy, no objective — the tip owns all of that.
func _make_root(src: LevelData) -> LevelData:
	var lv := LevelData.new()
	lv.display_name = "P8 fixture spine (test-only)"
	lv.high_ground = src.high_ground.duplicate()
	lv.spawn_zones = []
	lv.spawn_points = [
		_spawn(CELL_BASE_A, 0),
		_spawn(CELL_BASE_B, 0),
		_spawn(CELL_GATED, 0, SEG_NORTH),
	] as Array[SpawnPointData]
	lv.decor = [{"id": "spine_marker", "pos": Vector2(8.0, 8.0), "flip": false}] as Array[Dictionary]
	return lv

## The played level: identity, Focus, wave curve, objective. Carries no geometry of its
## own, which is the shape a campaign level built purely out of a base plus segments takes.
func _make_tip(src: LevelData) -> LevelData:
	var lv := LevelData.new()
	lv.id = TEST_LEVEL_ID
	lv.display_name = "P8 segment fixture (test-only, never a real campaign level)"
	lv.start_dopamine = src.start_dopamine
	# Deliberately huge, same reasoning as _test_multispawn's fixture: this test is about
	# COMPOSITION, so Focus must never be what ends the run before every wave (and every
	# segment-added spawn point) has had its turn. SimStrategyPassive builds nothing.
	lv.focus = 999
	lv.objective = src.objective
	lv.spawn_zones = []
	lv.wave_count = WAVE_COUNT
	lv.wave_curve = src.wave_curve.duplicate()
	return lv

## One unlockable link: a LevelData holding the segment's geometry in its OWN cell space,
## plus the MapSegmentData header that says where it lands and what opens it.
func _make_segment(id: StringName, condition: StringName, anchor: Vector2i,
		walls: Array, lanes: Array, adds: Array[SpawnPointData]) -> LevelData:
	var seg := MapSegmentData.new()
	seg.id = id
	seg.unlock_condition = condition
	seg.anchor_offset = anchor
	seg.adds_spawns = adds
	var lv := LevelData.new()
	lv.display_name = "P8 fixture segment %s" % String(id)
	lv.segment = seg
	lv.high_ground = _cells(walls)
	lv.path_cells = _cells(lanes)
	return lv

## The four in-budget segments, in their canonical (declaration) order. Each is returned
## FRESH so two chains can be built from the same recipe without sharing resources — a
## shared link would make the "different chain order" determinism check meaningless.
func _make_unlockable_segments() -> Array[LevelData]:
	# North wing: fills row 0/1 at the top right, and brings a spawn point of its own.
	var north := _make_segment(SEG_NORTH, COND_NORTH, Vector2i(24, 0),
		[Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1)], [],
		[_spawn(Vector2i(0, 0), 0, SEG_NORTH)] as Array[SpawnPointData])
	north.terrain_tiles = {Vector2i(0, 1): Vector3i(0, 2, 3)}

	# South spur: fills rows 12/13 at the bottom left. Its spawn opens on wave 2, so the
	# fixture exercises active_from_wave and requires_segment gating at once.
	var south := _make_segment(SEG_SOUTH, COND_SOUTH, Vector2i(2, 12),
		[Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)], [],
		[_spawn(Vector2i(0, 1), 2, SEG_SOUTH)] as Array[SpawnPointData])
	south.decor = [{"id": "spur_rock", "pos": Vector2(4.0, 2.0), "flip": true}] as Array[Dictionary]

	# East gate: the only content in column 29, the single free column the measured
	# horizontal budget leaves. Carries a trod, so trod cell shifting is exercised too.
	var east := _make_segment(SEG_EAST, COND_EAST, Vector2i(29, 2),
		[Vector2i(0, 2), Vector2i(0, 3)], [],
		[_spawn(Vector2i(0, 0), 3, SEG_EAST)] as Array[SpawnPointData])
	var trod := TrodData.new()
	trod.open_at_wave = 3
	trod.cells = _cells([Vector2i(0, 1)])
	east.trods = [trod] as Array[TrodData]
	east.tile_overrides = {Vector2i(0, 0): "ground/ground_03"}

	# Inner baffle: pure geometry in the open middle of the board — no spawn at all. It
	# changes WHERE the horde can go without adding anywhere for it to come from, which is
	# the segment shape a maze TD actually cares about.
	var baffle := _make_segment(SEG_BAFFLE, COND_BAFFLE, Vector2i(14, 3),
		[Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 0), Vector2i(1, 1)],
		[Vector2i(0, 2), Vector2i(1, 2)],
		[] as Array[SpawnPointData])

	return [north, south, east, baffle] as Array[LevelData]

## Links `parts` into one base chain, root first, and returns the tip.
func _link_chain(parts: Array[LevelData]) -> LevelData:
	for i in range(1, parts.size()):
		parts[i].base = parts[i - 1]
	return parts[parts.size() - 1]

## root -> the four segments in `order` -> tip. `order` is a permutation of 0..3 into
## _make_unlockable_segments()'s list, which is how check 3 builds two structurally
## different chains carrying the same four segments.
func _build_chain(order: Array) -> LevelData:
	var src := _shipped_level_1()
	var segs := _make_unlockable_segments()
	var parts: Array[LevelData] = [_make_root(src)]
	for i in order:
		parts.append(segs[int(i)])
	parts.append(_make_tip(src))
	return _link_chain(parts)

# ---------------------------------------------------------------- helpers

func _set_of(ids: Array) -> Dictionary:
	var d: Dictionary = {}
	for id in ids:
		d[id] = true
	return d

## The active-spawn filter Game._active_spawn_point_cells() applies, reimplemented from
## P6/P8's written spec rather than copied from game.gd — check 7 calls the REAL method,
## so a divergence between the two cannot hide. wave_elapsed is left at its INF default
## here (the telegraph gate is P7's subject and has its own fixture).
func _expected_active(lv: LevelData, wave: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for sp: SpawnPointData in lv.spawn_points:
		if sp.active_from_wave > wave:
			continue
		if sp.requires_segment != &"" and not lv.active_segments.has(sp.requires_segment):
			continue
		cells.append(sp.cell)
	return cells

func _flow_field_for(lv: LevelData) -> FlowField:
	var g := Data.GRID
	var blocked: Dictionary = {}
	for c: Vector2i in lv.high_ground:
		blocked[c] = true
	return FlowField.build(int(g.cols), int(g.rows), lv.objective, blocked)

## Everything composition is allowed to decide, rendered as one deterministic string.
## Compared for exact equality, so any difference at all — a cell, an order, a dictionary
## insertion order — shows up as a diff rather than as a silent pass.
func _fingerprint(lv: LevelData) -> String:
	var parts: Array[String] = []
	parts.append("segments=" + var_to_str(lv.active_segments))
	parts.append("objective=" + var_to_str(lv.objective))
	parts.append("high_ground=" + var_to_str(lv.high_ground))
	parts.append("path_cells=" + var_to_str(lv.path_cells))
	var spawns: Array[String] = []
	for sp: SpawnPointData in lv.spawn_points:
		spawns.append("%s|from=%d|seg=%s|dir=%s|lead=%.3f"
			% [str(sp.cell), sp.active_from_wave, String(sp.requires_segment),
				String(sp.direction_id), sp.telegraph_lead_time])
	parts.append("spawn_points=" + var_to_str(spawns))
	var trods: Array[String] = []
	for t: TrodData in lv.trods:
		trods.append("%d|%s" % [t.open_at_wave, var_to_str(t.cells)])
	parts.append("trods=" + var_to_str(trods))
	parts.append("decor=" + var_to_str(lv.decor))
	parts.append("terrain_tiles=" + var_to_str(lv.terrain_tiles))
	parts.append("tile_overrides=" + var_to_str(lv.tile_overrides))
	return "\n".join(parts)

func _subsets(ids: Array) -> Array:
	var out: Array = []
	for mask in range(1 << ids.size()):
		var subset: Array = []
		for i in range(ids.size()):
			if mask & (1 << i):
				subset.append(ids[i])
		out.append(subset)
	return out

# ---------------------------------------------------------------- 1: screen budget

func _run_screen_budget() -> void:
	print("== 1: the screen limit is MEASURED, not asserted ==")
	var g := Data.GRID
	var tile: int = int(g.tile)
	var vw: int = int(ProjectSettings.get_setting("display/window/size/viewport_width", 0))
	var vh: int = int(ProjectSettings.get_setting("display/window/size/viewport_height", 0))
	# Independent re-derivation. The top HUD bar is already paid for by origin_y (see
	# data.gd's own comment: it must clear Game._HUD_TOP_H or row 0 draws behind it), so
	# only the bottom bar is subtracted here.
	var want_cols: int = int(floor(float(vw - int(g.origin_x)) / float(tile)))
	var want_rows: int = int(floor(float(vh - Game._HUD_BOTTOM_H - int(g.origin_y)) / float(tile)))
	print("     viewport %dx%d, tile %d, origin (%d,%d), HUD bars %d/%d -> %d x %d tiles visible"
		% [vw, vh, tile, int(g.origin_x), int(g.origin_y),
			Game._HUD_TOP_H, Game._HUD_BOTTOM_H, want_cols, want_rows])

	var got := MapComposer.visible_tile_budget()
	_check("MapComposer.visible_tile_budget() matches an independent re-derivation",
		got == Vector2i(want_cols, want_rows), "got %s want %s" % [str(got), str(Vector2i(want_cols, want_rows))])
	_check("Data.GRID itself fits on screen (nothing composed can be asked to)",
		int(g.cols) <= want_cols and int(g.rows) <= want_rows,
		"grid %dx%d vs visible %dx%d" % [int(g.cols), int(g.rows), want_cols, want_rows])
	_check("board_budget() is the tighter of grid and screen on both axes",
		MapComposer.board_budget() == Vector2i(mini(int(g.cols), want_cols), mini(int(g.rows), want_rows)),
		str(MapComposer.board_budget()))
	# The trap the queue calls out by name: the objective sits on x = 28 in both shipped
	# levels, so a board narrower than 29 columns puts it out of bounds and kills
	# pathfinding outright (PROGRESS.md's T0 failure). Guarded here rather than trusted.
	var budget := MapComposer.board_budget()
	for i in range(Data.get_level_count()):
		var lv: LevelData = Data.get_level(i)
		_check("shipped level id %d: objective %s is inside the board budget %s"
			% [lv.id, str(lv.objective), str(budget)],
			lv.objective.x >= 0 and lv.objective.y >= 0
				and lv.objective.x < budget.x and lv.objective.y < budget.y)
		_check("shipped level id %d composes to itself and still fits" % lv.id,
			MapComposer.fits_on_screen(MapComposer.compose(lv)))

# ---------------------------------------------------------------- 2: every combination

func _run_every_combination() -> void:
	print("\n== 2: every combination of unlocked segments (exhaustive power set) ==")
	var ids: Array = [SEG_NORTH, SEG_SOUTH, SEG_EAST, SEG_BAFFLE]
	var subsets := _subsets(ids)
	_check("the power set really is exhaustive", subsets.size() == 16,
		"%d subsets of %d segments" % [subsets.size(), ids.size()])

	var budget := MapComposer.board_budget()
	var tip := _build_chain([0, 1, 2, 3])
	var bad_fit := 0
	var bad_segments := 0
	var bad_reach: Array[String] = []
	var bad_expectation := 0
	var checked_spawn_routes := 0

	for subset: Array in subsets:
		var composed := MapComposer.compose_with(tip, _set_of(subset))

		if not MapComposer.fits_on_screen(composed):
			bad_fit += 1
			print("     off screen: %s -> extent %s" % [str(subset), str(MapComposer.extent(composed))])
		var ext := MapComposer.extent(composed)
		if ext.position.x < 0 or ext.position.y < 0 \
				or ext.position.x + ext.size.x > budget.x or ext.position.y + ext.size.y > budget.y:
			bad_fit += 1

		var want_segments: Array = subset.duplicate()
		want_segments.sort()
		var got_segments: Array = []
		for s in composed.active_segments:
			got_segments.append(s)
		got_segments.sort()
		if want_segments != got_segments:
			bad_segments += 1
			print("     active_segments mismatch: want %s got %s" % [str(want_segments), str(got_segments)])

		# ONE field per board, read for every wave — the same "flow field se NEMĚNÍ"
		# discipline P6 established, and the same construction AntiBlockValidator uses.
		var field := _flow_field_for(composed)
		for wave in range(1, WAVE_COUNT + 1):
			var active := _expected_active(composed, wave)
			if not active.has(CELL_BASE_A) or not active.has(CELL_BASE_B):
				bad_expectation += 1
			# The spine's gated spawn is present on every board but only ELIGIBLE when the
			# segment that justifies it is live. This is the check that would fail if
			# active_segments were ignored.
			var gated_expected: bool = subset.has(SEG_NORTH)
			if active.has(CELL_GATED) != gated_expected:
				bad_expectation += 1
				print("     gated spawn %s eligibility wrong for %s wave %d"
					% [str(CELL_GATED), str(subset), wave])
			for cell: Vector2i in active:
				checked_spawn_routes += 1
				if not field.has_cell(cell):
					bad_reach.append("%s wave %d spawn %s" % [str(subset), wave, str(cell)])

	_check("all 16 composed boards fit inside the measured budget %s" % str(budget),
		bad_fit == 0, "%d violations" % bad_fit)
	_check("all 16 boards report exactly the segments they were composed with",
		bad_segments == 0, "%d mismatches" % bad_segments)
	_check("the base spawns and the segment-gated spawn are eligible exactly when they should be",
		bad_expectation == 0, "%d wrong" % bad_expectation)
	_check("every active spawn on every wave of all 16 boards reaches the objective (%d routes checked)"
		% checked_spawn_routes, bad_reach.is_empty(), str(bad_reach))

	# Segment-added spawns must really be showing up, or the sweep above proved nothing.
	var all_live := MapComposer.compose_with(tip, _set_of(ids))
	var full_cells := _expected_active(all_live, WAVE_COUNT)
	for cell in [CELL_BASE_A, CELL_BASE_B, CELL_GATED, NORTH_SPAWN, SOUTH_SPAWN, EAST_SPAWN]:
		_check("fully unlocked board: spawn %s is active on the last wave" % str(cell),
			full_cells.has(cell))
	var none_live := MapComposer.compose_with(tip, {})
	_check("empty unlock set: only the two spine spawns are active",
		_expected_active(none_live, WAVE_COUNT).size() == 2,
		str(_expected_active(none_live, WAVE_COUNT)))
	_check("empty unlock set: the board is exactly the spine's own high ground",
		none_live.high_ground.size() == _shipped_level_1().high_ground.size(),
		"%d cells" % none_live.high_ground.size())
	_check("fully unlocked board adds every segment's walls (%d -> %d cells)"
		% [none_live.high_ground.size(), all_live.high_ground.size()],
		all_live.high_ground.size() == none_live.high_ground.size() + 12)
	_check("segment lanes and trods composed at their anchors",
		all_live.path_cells.has(Vector2i(14, 5)) and all_live.path_cells.has(Vector2i(15, 5))
			and all_live.trods.size() == 1 and all_live.trods[0].cells.has(Vector2i(29, 3)),
		"lanes=%s trods=%s" % [str(all_live.path_cells), str(all_live.trods.size())])
	_check("segment decor shifted by anchor * tile, spine decor left where it was",
		all_live.decor.size() == 2
			and all_live.decor[0]["pos"] == Vector2(8.0, 8.0)
			and all_live.decor[1]["pos"] == Vector2(4.0 + 2 * 16, 2.0 + 12 * 16),
		str(all_live.decor))
	_check("segment terrain tiles and overrides re-keyed to their anchored cells",
		all_live.terrain_tiles.has(Vector2i(24, 1)) and all_live.tile_overrides.has(Vector2i(29, 2)),
		"%s / %s" % [str(all_live.terrain_tiles.keys()), str(all_live.tile_overrides.keys())])
	_check("the source chain was not mutated by any of the 16 compositions",
		tip.high_ground.is_empty() and tip.base != null and tip.segment == null
			and _shipped_level_1().high_ground.size() == 27)

# ---------------------------------------------------------------- 3: determinism

func _run_determinism() -> void:
	print("\n== 3: composition depends on the SET of live segments and nothing else ==")
	var ids: Array = [SEG_NORTH, SEG_SOUTH, SEG_EAST, SEG_BAFFLE]
	var forward := _build_chain([0, 1, 2, 3])
	# Same four segments, opposite positions in the base chain. Composition is defined to
	# order the spine root-first and the live segments by id (MapComposer's header), so a
	# reversed chain must produce the identical board — that is the property being proven,
	# not an accident of how the fixture happens to be linked.
	var reversed_chain := _build_chain([3, 2, 1, 0])

	var mismatches: Array[String] = []
	for subset: Array in _subsets(ids):
		var ascending := _set_of(subset)
		var descending: Dictionary = {}
		for i in range(subset.size() - 1, -1, -1):
			descending[subset[i]] = true

		var a := _fingerprint(MapComposer.compose_with(forward, ascending))
		var b := _fingerprint(MapComposer.compose_with(forward, descending))
		var c := _fingerprint(MapComposer.compose_with(reversed_chain, ascending))
		var d := _fingerprint(MapComposer.compose_with(reversed_chain, descending))
		if a != b:
			mismatches.append("%s: unlock-set insertion order changed the board" % str(subset))
		if a != c:
			mismatches.append("%s: chain order changed the board" % str(subset))
		if a != d:
			mismatches.append("%s: chain + set order changed the board" % str(subset))
	_check("all 16 subsets compose identically across 2 chain orders x 2 set orders (64 compositions)",
		mismatches.is_empty(), str(mismatches))

	# Repeating one composition must also be byte-identical — nothing in here may consult
	# a clock or an RNG.
	var repeat_a := _fingerprint(MapComposer.compose_with(forward, _set_of(ids)))
	var repeat_b := _fingerprint(MapComposer.compose_with(forward, _set_of(ids)))
	_check("composing the same board twice in a row is byte-identical", repeat_a == repeat_b)

	# ... and the composed result must be FLAT, so nothing downstream can compose it again.
	var once := MapComposer.compose_with(forward, _set_of(ids))
	var twice := MapComposer.compose_with(once, _set_of(ids))
	_check("a composed level is flat (no base, no segment header) and composing it again is a no-op",
		once.base == null and once.segment == null and _fingerprint(once) == _fingerprint(twice))

# ---------------------------------------------------------------- 4: teeth

func _run_reachability_has_teeth() -> void:
	print("\n== 4: negative control — the reachability check can actually say no ==")
	# A segment that walls its own spawn into a one-cell pocket, exactly the pocket
	# _test_multispawn.gd uses. If check 2 passed only because FlowField.has_cell() is
	# always true, this fails.
	var sealed_seg := _make_segment(SEG_SEALED, &"p8_test_cond_sealed", Vector2i(25, 11),
		[Vector2i(0, 1), Vector2i(2, 1), Vector2i(1, 0), Vector2i(1, 2)], [],
		[_spawn(Vector2i(1, 1), 0, SEG_SEALED)] as Array[SpawnPointData])
	var src := _shipped_level_1()
	var tip := _link_chain([_make_root(src), sealed_seg, _make_tip(src)] as Array[LevelData])

	var open_board := MapComposer.compose_with(tip, {})
	var sealed_board := MapComposer.compose_with(tip, _set_of([SEG_SEALED]))
	_check("the sealing segment is refused nothing — it fits the board and composes in",
		sealed_board.active_segments.has(SEG_SEALED) and MapComposer.fits_on_screen(sealed_board))
	var active := _expected_active(sealed_board, 1)
	_check("its spawn %s is genuinely ACTIVE on the sealed board" % str(SEALED_SPAWN),
		active.has(SEALED_SPAWN), str(active))
	var field := _flow_field_for(sealed_board)
	_check("and the reachability check reports it as unreachable",
		not field.has_cell(SEALED_SPAWN))
	_check("while the spine's own spawns on the same board stay reachable",
		field.has_cell(CELL_BASE_A) and field.has_cell(CELL_BASE_B))
	_check("with the segment locked, that spawn is not on the board at all",
		not _expected_active(open_board, 1).has(SEALED_SPAWN))

# ---------------------------------------------------------------- 5: the hard limit

func _run_hard_limit() -> void:
	print("\n== 5: negative control — an oversized segment is REFUSED, not scrolled to ==")
	var budget := MapComposer.board_budget()
	var src := _shipped_level_1()

	# One row below the last visible row, and one column right of the last visible column.
	var too_tall := _make_segment(SEG_TOO_TALL, &"p8_test_cond_tall", Vector2i(3, budget.y),
		[Vector2i(0, 0)], [], [_spawn(Vector2i(1, 0), 0, SEG_TOO_TALL)] as Array[SpawnPointData])
	var too_wide := _make_segment(SEG_TOO_WIDE, &"p8_test_cond_wide", Vector2i(budget.x, 3),
		[Vector2i(0, 0)], [], [_spawn(Vector2i(0, 1), 0, SEG_TOO_WIDE)] as Array[SpawnPointData])
	var tip := _link_chain([_make_root(src), too_tall, too_wide, _make_tip(src)] as Array[LevelData])

	print("     (the two ERROR lines below are the refusals themselves — they are the point)")
	var composed := MapComposer.compose_with(tip, _set_of([SEG_TOO_TALL, SEG_TOO_WIDE]))
	_check("both oversized segments are dropped even though they are unlocked",
		composed.active_segments.is_empty(), str(composed.active_segments))
	_check("the composed board still fits the budget %s" % str(budget),
		MapComposer.fits_on_screen(composed), str(MapComposer.extent(composed)))
	_check("their spawn points are not on the board",
		composed.spawn_points.size() == 3, "%d spawn points" % composed.spawn_points.size())
	_check("nothing they own leaked into the geometry",
		composed.high_ground.size() == src.high_ground.size())

	# The same segments one cell further in are accepted, so the refusal is about the
	# limit and not about these two segments being special.
	var fits_tall := _make_segment(SEG_TOO_TALL, &"p8_test_cond_tall", Vector2i(3, budget.y - 1),
		[Vector2i(0, 0)], [], [] as Array[SpawnPointData])
	var tip2 := _link_chain([_make_root(src), fits_tall, _make_tip(src)] as Array[LevelData])
	var ok_board := MapComposer.compose_with(tip2, _set_of([SEG_TOO_TALL]))
	_check("moved one row up, the very same segment composes in",
		ok_board.active_segments.has(SEG_TOO_TALL)
			and ok_board.high_ground.has(Vector2i(3, budget.y - 1))
			and MapComposer.fits_on_screen(ok_board))

# ---------------------------------------------------------------- 6: MetaProgression

## The save's real unlocked_segments list, stashed while check 6 grants test conditions
## in memory and restored at the very end of _run().
var _saved_unlocks: Array[String] = []

func _run_meta_wiring() -> LevelData:
	print("\n== 6: unlock_condition is answered by MetaProgression (no save file written) ==")
	var save_path := "user://savegame.tres"
	var mtime_before: int = FileAccess.get_modified_time(save_path) if FileAccess.file_exists(save_path) else -1

	_check("an empty unlock_condition is always satisfied (unconditional segment)",
		MetaProgression.is_segment_unlocked(&""))
	_check("an unknown condition is not satisfied",
		not MetaProgression.is_segment_unlocked(COND_NORTH))

	var tip := _build_chain([0, 1, 2, 3])
	_check("with nothing unlocked, compose() composes the spine alone",
		MapComposer.compose(tip).active_segments.is_empty())

	# IN-MEMORY ONLY. MetaProgression.unlock_segment() would write the real save; this
	# test must never do that (see the file header, and _test_save_round_trip.gd's).
	_saved_unlocks = MetaProgression.current_save.unlocked_segments.duplicate()
	MetaProgression.current_save.unlocked_segments.append(String(COND_NORTH))
	MetaProgression.current_save.unlocked_segments.append(String(COND_EAST))

	_check("is_segment_unlocked() now answers true for the granted conditions",
		MetaProgression.is_segment_unlocked(COND_NORTH) and MetaProgression.is_segment_unlocked(COND_EAST))
	var live := MapComposer.live_unlocks(tip)
	_check("live_unlocks() maps conditions to exactly the right segment ids",
		live.size() == 2 and live.has(SEG_NORTH) and live.has(SEG_EAST), str(live.keys()))
	var partly := MapComposer.compose(tip)
	_check("compose() (the MetaProgression-reading entry point) composes exactly those two",
		partly.active_segments.size() == 2
			and partly.active_segments.has(SEG_NORTH) and partly.active_segments.has(SEG_EAST),
		str(partly.active_segments))
	_check("their spawns are on the board and the locked segments' are not",
		partly.spawn_points.size() == 5
			and _expected_active(partly, WAVE_COUNT).has(NORTH_SPAWN)
			and _expected_active(partly, WAVE_COUNT).has(EAST_SPAWN)
			and not _expected_active(partly, WAVE_COUNT).has(SOUTH_SPAWN),
		"%d spawn points" % partly.spawn_points.size())

	# Grant the rest for checks 7 and 8, which exercise the production path end to end.
	MetaProgression.current_save.unlocked_segments.append(String(COND_SOUTH))
	MetaProgression.current_save.unlocked_segments.append(String(COND_BAFFLE))

	var mtime_after: int = FileAccess.get_modified_time(save_path) if FileAccess.file_exists(save_path) else -1
	_check("the real user://savegame.tres was never written", mtime_before == mtime_after,
		"%d -> %d" % [mtime_before, mtime_after])

	return tip

# ---------------------------------------------------------------- 7: production path

func _run_game_wiring(tip: LevelData) -> void:
	print("\n== 7: a real Game composes the level itself and gates spawns on it ==")
	# The UNCOMPOSED chain tip is what gets registered — Game._ready() calls
	# MapComposer.compose() on whatever Data hands it, so this exercises the production
	# path rather than a board this test composed for it.
	var lv_index := Data.get_level_count()
	Data._levels.append(tip)
	Data._levels.sort_custom(func(a: LevelData, b: LevelData): return a.id < b.id)
	GameState.current_level_index = lv_index

	var game: Game = load("res://scenes/Game.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame

	_check("Game composed all four segments in",
		game.level.active_segments.size() == 4, str(game.level.active_segments))
	_check("Game's own board carries the composed walls",
		game.level.high_ground.size() == _shipped_level_1().high_ground.size() + 12,
		"%d cells" % game.level.high_ground.size())

	var expectations := {
		1: [CELL_BASE_A, CELL_BASE_B, CELL_GATED, NORTH_SPAWN],
		2: [CELL_BASE_A, CELL_BASE_B, CELL_GATED, NORTH_SPAWN, SOUTH_SPAWN],
		3: [CELL_BASE_A, CELL_BASE_B, CELL_GATED, NORTH_SPAWN, SOUTH_SPAWN, EAST_SPAWN],
		4: [CELL_BASE_A, CELL_BASE_B, CELL_GATED, NORTH_SPAWN, SOUTH_SPAWN, EAST_SPAWN],
	}
	for wave in expectations.keys():
		var want: Array = expectations[wave]
		var got: Array[Vector2i] = game._active_spawn_point_cells(wave)
		var same := got.size() == want.size()
		if same:
			for c in want:
				if not got.has(c):
					same = false
		_check("wave %d: real Game._active_spawn_point_cells() matches expectations" % wave,
			same, "got %s want %s" % [str(got), str(want)])

	# The gate really is the composed board, not the save flag: drop a segment out of
	# level.active_segments and its spawn must go dark immediately.
	game.level.active_segments.erase(SEG_NORTH)
	var after: Array[Vector2i] = game._active_spawn_point_cells(4)
	_check("removing a segment from the live board darkens BOTH its own spawn and the spine's gated one",
		not after.has(NORTH_SPAWN) and not after.has(CELL_GATED), str(after))
	game.level.active_segments.append(SEG_NORTH)

	game.queue_free()
	await get_tree().process_frame

# ---------------------------------------------------------------- 8: playthrough

func _run_playthrough() -> void:
	print("\n== 8: the composed level actually plays (LevelSimulator + SimStrategyPassive) ==")
	var sim := LevelSimulator.new()
	add_child(sim)
	var result: Dictionary = await sim.run(TEST_LEVEL_ID, 20260830, SimStrategyPassive.new())
	sim.queue_free()
	await get_tree().process_frame

	_check("result dict is non-empty", not result.is_empty(), str(result))
	if result.is_empty():
		return
	_check("did not time out", not result.get("timed_out", true), str(result))
	# Game.wave_index is 0-based and stops at waves.size() - 1 once the finale fires — see
	# _test_multispawn.gd's identical note.
	_check("the composed level reached its own final wave", result.get("wave", -1) == WAVE_COUNT - 1,
		"wave=%s (0-based, want %d)" % [str(result.get("wave")), WAVE_COUNT - 1])
	_check("survived to victory (composition did not break wave spawning)",
		result.get("victory", false) == true, str(result))

# ---------------------------------------------------------------- driver

func _run() -> void:
	if _shipped_level_1() == null:
		completed = true
		print("FAILED: level id 1 is missing, nothing to clone spine geometry from")
		get_tree().quit(1)
		return

	_run_screen_budget()
	_run_every_combination()
	_run_determinism()
	_run_reachability_has_teeth()
	_run_hard_limit()
	var composed_tip := _run_meta_wiring()
	await _run_game_wiring(composed_tip)
	await _run_playthrough()

	# Undo the in-memory unlock grants. Nothing was ever written to disk, but leaving a
	# mutated autoload behind would still be rude to anything sharing this process.
	MetaProgression.current_save.unlocked_segments = _saved_unlocks

	completed = true
	print("\n%s (%d failures)" % ["PASSED" if fails == 0 else "FAILED", fails])
	get_tree().quit(1 if fails > 0 else 0)
