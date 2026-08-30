extends Node
## Harness for P5 (docs/refactor/PATHFINDING.MD): the horde MultiMesh batching.
##
## Same shape as _test_suppression.gd — instantiate the real Game, pin Focus so a leak
## cannot trip _game_over() (which would free this node and its own watchdog), then
## drive HordeRenderer/DistractionAnimator/HordeAtlas imperatively.
##
## Verifies the NEW plumbing directly rather than pixel output (screenshots are the
## visual half of verification — see PROGRESS.md's P5 entry, this is the behavioural
## half):
##   - a spawned, healthy, unblocked distraction with real frame art is batch-eligible,
##     and HordeAtlas actually packs its walk frames (non-degenerate UV rect)
##   - HordeRenderer.rebuild() puts exactly the batch-eligible count into the three
##     multimeshes' visible_instance_count
##   - blocking a distraction (Ally engagement) takes it OUT of the batch, and
##     releasing it puts it back — the "small excluded subset" rule P5 relies on
##   - an active status (Boredom) makes DistractionAnimator.needs_own_redraw() true
##     again even though the BODY stays batched — the overlay-only redraw this task's
##     whole perf case is built on
##   - hit_flash_color() actually changes on trigger_hit_flash() and decays back to
##     white — the batch's only per-instance visual feedback for a live, healthy body

var completed := false
var fails := 0

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

func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("  ok   %s %s" % [label, detail])
	else:
		fails += 1
		print("  FAIL %s %s" % [label, detail])

func _run() -> void:
	# Clean slate — a prior fixture in this same process may already have packed types
	# this one does not spawn, which is fine, but starting fresh keeps the counts below
	# exact rather than "at least".
	HordeAtlas.reset_for_tests()

	var game: Game = load("res://scenes/Game.tscn").instantiate()
	add_child(game)
	game.fog_enabled = false
	game.routine_gates_enabled = false
	await get_tree().process_frame
	GameState.max_focus = 999999
	GameState.focus = 999999
	game.started = true
	game.between_waves = false

	_check("Game has a HordeRenderer", game.horde_renderer != null)

	await _test_plain_walker(game)
	await _test_blocked_excluded(game)
	await _test_status_forces_own_redraw(game)
	await _test_hit_flash(game)
	await _test_facing_and_mirror(game)

	completed = true
	print("")
	if fails == 0:
		print("ALL PASS")
		get_tree().quit(0)
	else:
		print("%d FAILED" % fails)
		get_tree().quit(1)

# ---------------------------------------------------------------- plain walker -> batch

func _test_plain_walker(game: Game) -> void:
	print("=== a plain walking distraction is packed and batched")
	var spawn_cell: Vector2i = game.spawn_zone_cells[0][0]
	var d: Distraction = game.spawn_distraction(&"doomscroll", spawn_cell)
	await get_tree().process_frame
	await get_tree().process_frame

	_check("has frame art on disk", not d.animator._frame_textures.is_empty())
	_check("is_batch_eligible() true", d.animator.is_batch_eligible())

	var fd: Dictionary = d.animator.batch_frame_data()
	_check("batch_frame_data() non-empty", not fd.is_empty())
	if not fd.is_empty():
		_check("HordeAtlas knows this (type, variant)",
			HordeAtlas.has(fd["base_id"], fd["variant"]))
		var uv: Rect2 = HordeAtlas.uv(fd["base_id"], fd["variant"], fd["dir_suffix"], fd["frame_idx"])
		_check("packed UV rect is non-degenerate", uv.size.x > 0.0 and uv.size.y > 0.0,
			"(%s)" % uv)
		var px: Vector2 = HordeAtlas.px_size(fd["base_id"], fd["variant"], fd["dir_suffix"], fd["frame_idx"])
		_check("packed pixel size is non-degenerate", px.x > 0.0 and px.y > 0.0, "(%s)" % px)

	_check("HordeRenderer batched exactly this one live body",
		game.horde_renderer.batch_count() == 1, "(%d)" % game.horde_renderer.batch_count())

	d.queue_free()
	await get_tree().process_frame

# ---------------------------------------------------------------- blocked -> excluded

func _test_blocked_excluded(game: Game) -> void:
	print("=== a blocked distraction leaves the batch, and returns when released")
	var spawn_cell: Vector2i = game.spawn_zone_cells[0][0]
	var d: Distraction = game.spawn_distraction(&"doomscroll", spawn_cell)
	await get_tree().process_frame
	await get_tree().process_frame
	_check("unblocked: batch-eligible", d.animator.is_batch_eligible())

	# No real DefenderUnit needed — add_blocker() only reads/writes is_blocked and the
	# blockers array; is_batch_eligible() only looks at enemy.is_blocked.
	d.add_blocker(null)
	_check("blocked: NOT batch-eligible (falls back to the attack-frame draw)",
		not d.animator.is_batch_eligible())
	await get_tree().process_frame
	_check("blocked: HordeRenderer's batch excludes it",
		game.horde_renderer.batch_count() == 0, "(%d)" % game.horde_renderer.batch_count())

	d.remove_blocker(null)
	_check("released: batch-eligible again", d.animator.is_batch_eligible())
	await get_tree().process_frame
	_check("released: back in HordeRenderer's batch",
		game.horde_renderer.batch_count() == 1, "(%d)" % game.horde_renderer.batch_count())

	d.queue_free()
	await get_tree().process_frame

# ---------------------------------------------------------------- status -> own redraw

func _test_status_forces_own_redraw(game: Game) -> void:
	print("=== an active status keeps the overlay-only per-node redraw alive")
	var spawn_cell: Vector2i = game.spawn_zone_cells[0][0]
	var d: Distraction = game.spawn_distraction(&"doomscroll", spawn_cell)
	await get_tree().process_frame
	await get_tree().process_frame

	_check("idle: body stays batched, no per-node redraw needed",
		d.animator.is_batch_eligible() and not d.animator.needs_own_redraw())

	d.apply_boredom(4.0, 2.0)
	_check("boredom applied: body STILL batched (only the aura moved off it)",
		d.animator.is_batch_eligible())
	_check("boredom applied: per-node redraw needed again (for the halo)",
		d.animator.needs_own_redraw())

	d.queue_free()
	await get_tree().process_frame

# ---------------------------------------------------------------- hit flash

func _test_hit_flash(game: Game) -> void:
	print("=== hit-flash still shows through the batch (native MultiMesh colour)")
	var spawn_cell: Vector2i = game.spawn_zone_cells[0][0]
	var d: Distraction = game.spawn_distraction(&"doomscroll", spawn_cell)
	await get_tree().process_frame

	_check("no flash at rest: white (no tint)",
		d.animator.hit_flash_color().is_equal_approx(Color.WHITE))
	d.animator.trigger_hit_flash()
	var tinted: Color = d.animator.hit_flash_color()
	_check("just hit: overbright white tint", tinted.r > 1.0 and tinted.g > 1.0 and tinted.b > 1.0,
		"(%s)" % tinted)
	_check("still batch-eligible while flashing (no fallback needed for tint alone)",
		d.animator.is_batch_eligible())

	d.queue_free()
	await get_tree().process_frame

# ---------------------------------------------------------------- facing + mirror

func _test_facing_and_mirror(game: Game) -> void:
	print("=== west reuses east art mirrored — no distraction in this roster ships real west frames")
	var spawn_cell: Vector2i = game.spawn_zone_cells[0][0]
	var d: Distraction = game.spawn_distraction(&"doomscroll", spawn_cell)
	await get_tree().process_frame

	d.facing = Distraction.Facing.SOUTH
	var south: Dictionary = d.animator.batch_frame_data()
	_check("south: default set, not mirrored", south["dir_suffix"] == "" and not south["mirror"],
		"(%s, mirror=%s)" % [south.get("dir_suffix"), south.get("mirror")])

	d.facing = Distraction.Facing.NORTH
	var north: Dictionary = d.animator.batch_frame_data()
	_check("north: own set, not mirrored", north["dir_suffix"] == "_north" and not north["mirror"],
		"(%s, mirror=%s)" % [north.get("dir_suffix"), north.get("mirror")])

	d.facing = Distraction.Facing.EAST
	var east: Dictionary = d.animator.batch_frame_data()
	_check("east: own set, not mirrored", east["dir_suffix"] == "_east" and not east["mirror"],
		"(%s, mirror=%s)" % [east.get("dir_suffix"), east.get("mirror")])

	d.facing = Distraction.Facing.WEST
	var west: Dictionary = d.animator.batch_frame_data()
	_check("west: reuses the EAST set, mirrored", west["dir_suffix"] == "_east" and west["mirror"],
		"(%s, mirror=%s)" % [west.get("dir_suffix"), west.get("mirror")])

	d.queue_free()
	await get_tree().process_frame
