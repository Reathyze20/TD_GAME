extends Node
## Single-use verification shot for the UNIT_ART_SCALE fix (Data.UNIT_ART_SCALE,
## scripts/data.gd): before it, a moving combat unit's sprite drew at its raw PNG size
## times Data.pixel_scale() alone — 48px regulars, 96px boss — 2-3 grid cells on this
## 480x270/16px-tile board. Same bug class as the Focus-core prop fix (game.gd's
## CORE_PROP_ART_SCALE), one level down: combat units, not the objective prop.
##
## Clusters ~20 defender + distraction units tightly together (not scattered across
## the free floor like _shot_crowd.gd/_shot_defender_pivot.gd) — the question this
## harness answers is specifically "do 20 of them fit in a small area and stay tell-
## apart-able," per the task's own ask, not general crowd density across the whole map.
##
## Deliberately does NOT toggle any in-code override to get both before/after in one
## run (unlike _shot_defender_pivot.gd's debug_legacy_center_pivot) — UNIT_ART_SCALE
## has no such toggle and shouldn't grow one just for this one-off screenshot. Run once
## with the fix reverted (--tag before), once with it applied (--tag after); the caller
## is responsible for which working-tree state is on disk for each run.
##
## Spawn layout (cell picks, RNG seed, type order) is IDENTICAL between the two calls
## as long as this file itself is unchanged between runs — only Data.UNIT_ART_SCALE's
## call sites differ, so the screenshot pair isolates that one variable.
##
## Run (NOT --headless, drawing needs a real renderer; --main-scene, not --script, so
## autoloads are registered — see reference-godot-binary):
##   godot --path <proj> --main-scene res://scenes/_shot_unitscale.tscn -- \
##     --out .dev/screenshots/p_unitscale --tag after

const OUT_DIR := ".dev/screenshots"

## Real sprite-art distraction types (assets/distractions/<id>_frame_1.png) so the
## batched HordeRenderer path (scripts/components/horde_renderer.gd) is exercised, not
## just the procedural fallback — that path sizes sprites independently and needed its
## own fix (see Data.UNIT_ART_SCALE's header).
const DIST_TYPES := ["notification", "autoplay", "doomscroll", "phantom_buzz",
	"clickbait", "group_chat"]
const DEF_TYPES := ["broccoli_knight", "avocado_monk", "chilli_berserker", "garlic_mage"]

const TOTAL_UNITS := 20
const DEFENDER_COUNT := 8 ## 2 of each of the 4 recipes; the rest are distractions


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
	if img.save_png(path) != OK:
		printerr("_shot_unitscale: uložení selhalo: ", path)
		return
	print("_shot_unitscale: %s  %dx%d" % [path, img.get_width(), img.get_height()])


## Same HUD-avoidance band as _shot_defender_pivot.gd: sprites draw upward from their
## feet, so units need to sit clear of the top banner even though only their feet are
## anchored to the grid.
func _safe_cells(game: Game) -> Array[Vector2i]:
	var g := Data.GRID
	var out: Array[Vector2i] = []
	for cy in range(int(g.rows)):
		for cx in range(int(g.cols)):
			var c := Vector2i(cx, cy)
			if game.high_ground.has(c) or c == game.objective_cell:
				continue
			if cy >= 6 and cy < int(g.rows) - 4 and cx >= int(g.cols) * 0.4 and cx < int(g.cols) - 1:
				out.append(c)
	return out


## Nearest N safe cells to `anchor`, closest-first — this is what makes the 20 units a
## tight CLUSTER instead of a scatter: exactly the "do they fit in a small area and
## stay distinguishable" question the task asked.
func _cluster_cells(safe: Array[Vector2i], anchor: Vector2i, n: int) -> Array[Vector2i]:
	var sorted := safe.duplicate()
	sorted.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.distance_squared_to(anchor) < b.distance_squared_to(anchor))
	return sorted.slice(0, mini(n, sorted.size()))


func _spawn_defender(game: Game, type_key: String, pos: Vector2) -> DefenderUnit:
	var u := DefenderUnit.new()
	game.entities.add_child(u)
	u.setup_from_data(game, Data.get_defender(StringName(type_key)), pos, Vector2.ZERO, 240.0)
	u.global_position = pos
	u.state = DefenderUnit.State.IDLE
	u.queue_redraw()
	return u


func _run() -> void:
	var out_prefix := _arg("--out", "%s/unitscale" % OUT_DIR)
	var tag := _arg("--tag", "shot")

	var game: Game = load("res://scenes/Game.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	# Bez obrany jádro vyhoří a _game_over() přepne scénu ještě před fotkou — a vzal by
	# s sebou i tenhle uzel, protože harness je RODIČ Game. Viz reference-godot-binary.
	GameState.max_focus = 999999
	GameState.focus = 999999
	game.fog_enabled = false   # čisté pole, o mlhu tady nejde
	await get_tree().process_frame

	var safe_cells := _safe_cells(game)
	if safe_cells.size() < TOTAL_UNITS:
		printerr("_shot_unitscale: málo bezpečné podlahy (%d buněk) pro %d jednotek" %
			[safe_cells.size(), TOTAL_UNITS])

	# Anchor near the middle of the safe band so the cluster has room to spread in
	# every direction rather than pressing against a wall.
	var g := Data.GRID
	var anchor := Vector2i(int(int(g.cols) * 0.65), int(g.rows) / 2)
	var cells := _cluster_cells(safe_cells, anchor, TOTAL_UNITS)
	if cells.is_empty():
		printerr("_shot_unitscale: žádné volné buňky — nelze rozestavit jednotky")
		get_tree().quit(1)
		return

	var spawned_defenders := 0
	var spawned_distractions := 0
	for i in range(cells.size()):
		var cell: Vector2i = cells[i]
		var pos := game.cell_center(cell)
		if i < DEFENDER_COUNT:
			_spawn_defender(game, DEF_TYPES[i % DEF_TYPES.size()], pos)
			spawned_defenders += 1
		else:
			var dtype: String = DIST_TYPES[(i - DEFENDER_COUNT) % DIST_TYPES.size()]
			game.spawn_distraction(dtype, cell)
			spawned_distractions += 1

	for _f in range(6):
		await get_tree().process_frame

	print("_shot_unitscale[%s]: %d obránců, %d distrakcí, celkem %d jednotek, cluster kolem %s" %
		[tag, spawned_defenders, spawned_distractions,
		spawned_defenders + spawned_distractions, anchor])

	# Internal viewport, upscaled 4x nearest — stretch/mode="viewport" (project.godot)
	# means this is what actually shows on screen, not the raw 480x270 buffer.
	var img := get_viewport().get_texture().get_image()
	img.resize(img.get_width() * 4, img.get_height() * 4, Image.INTERPOLATE_NEAREST)
	_save(img, "%s_%s.png" % [out_prefix, tag])

	print("HOTOVO")
	get_tree().quit(0)
