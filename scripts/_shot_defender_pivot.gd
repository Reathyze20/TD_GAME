extends Node
## Vyfotí STEJNÉ rozestavění jednotek na poli dvakrát: jednou se starým
## center-pivoted kreslením DefenderUnit (bug, který tenhle úkol opravuje) a jednou
## s opraveným bottom-anchored kreslením — přímé porovnání hypotézy zadání: "jednotky
## na poli vypadají špatně, protože nejsou vizuálně ukotvené k podlaze (chybí stín /
## špatný pivot / špatné pořadí kreslení), ne kvůli úhlu kamery."
##
## Rozestavění (pozice, typy, náhoda) je pro obě fotky BYTOVĚ STEJNÉ — jediná
## proměnná mezi "before" a "after" je DefenderUnit.debug_legacy_center_pivot, přesně
## jako _shot_shadows.gd přepíná game.shadow_enabled. Nekreslí žádný verdikt o tom,
## která fotka je hezčí — to není úkol tohohle harnesse.
##
## Navíc zvlášť značí:
##  - jeden PŘEKRÝVAJÍCÍ SE pár (obránce + distrakce na sousedních buňkách, stejný
##    sloupec) — tam je pivot bug i y-sort nejlíp vidět, protože se sprity fyzicky kryjí.
##  - jeden NEBATCHOVANÝ pár (obránce svírá distrakci přes add_blocker) — ověřuje
##    y-sort i pro distrakci, která NEJDE přes HordeRenderer (viz
##    DistractionAnimator.is_batch_eligible(): enemy.is_blocked ji z dávky vyřadí).
##
## Spuštění (NE --headless, kreslení potřebuje skutečný renderer; --main-scene, ne
## --script, protože autoloady (Data, GameState) běží jen tam — viz reference-godot-binary):
##   godot --path <proj> --main-scene res://scenes/_shot_defender_pivot.tscn -- --out .dev/screenshots/defender_pivot

const OUT_DIR := ".dev/screenshots"

## Distraction typy se skutečným sprite artem (assets/distractions/<id>_frame_1.png) —
## schválně, aby "normální" jednotky šly přes batchovaný HordeRenderer stejně jako
## v reálné hře, ne přes procedurální fallback.
const DIST_TYPES := ["notification", "autoplay", "doomscroll", "phantom_buzz", "group_chat"]
## Všechny čtyři existující DefenderData recepty (data/defenders/*.tres).
const DEF_TYPES := ["broccoli_knight", "avocado_monk", "chilli_berserker", "garlic_mage"]


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
		printerr("_shot_defender_pivot: uložení selhalo: ", path)
		return
	print("_shot_defender_pivot: %s  %dx%d" % [path, img.get_width(), img.get_height()])


## Volná podlaha, řádek po řádku — stejná selekce jako _shot_crowd.gd.
func _free_cells(game: Game) -> Array[Vector2i]:
	var g := Data.GRID
	var out: Array[Vector2i] = []
	for cy in range(int(g.rows)):
		for cx in range(int(g.cols)):
			var c := Vector2i(cx, cy)
			if not game.high_ground.has(c) and c != game.objective_cell:
				out.append(c)
	return out


## Najde první dvojici sousedních volných buněk ve stejném sloupci (c, c+(0,1)), obě
## mimo `used` — základ jak pro překrývající se pár, tak pro nebatchovaný pár. Sprity
## jsou vysoké několik desítek px na 16px dlaždici, takže i sousední řádek stačí na
## pořádný překryv.
func _find_adjacent_pair(free_cells: Array[Vector2i], used: Dictionary) -> Array:
	var free_set: Dictionary = {}
	for c in free_cells:
		free_set[c] = true
	for c in free_cells:
		if used.has(c):
			continue
		var below := c + Vector2i(0, 1)
		if free_set.has(below) and not used.has(below):
			return [c, below]
	return []


func _spawn_defender(game: Game, type_key: String, pos: Vector2) -> DefenderUnit:
	var u := DefenderUnit.new()
	game.entities.add_child(u)
	u.setup_from_data(game, Data.get_defender(StringName(type_key)), pos, Vector2.ZERO, 240.0)
	u.global_position = pos
	u.state = DefenderUnit.State.IDLE
	u.queue_redraw()
	return u


## `center`/`half_size` are CANVAS coordinates (a defender's world position). Since the
## stretch mode became "canvas_items" the readback image is 4x that space, so the window
## is converted per grab instead of applied raw — ui.gd's readback note has the why.
func _crop_zoom(img: Image, center: Vector2, half_size: int) -> Image:
	var rect := UI.readback_rect(get_viewport(), img,
		Rect2(center - Vector2(half_size, half_size), Vector2(half_size, half_size) * 2.0))
	if rect.size.x <= 0 or rect.size.y <= 0:
		return img
	var crop := img.get_region(rect)
	# The 4x upscale existed to make a 480x270-buffer crop inspectable. The crop now
	# already arrives at window resolution, so scale by whatever is left to reach the
	# same apparent size rather than blindly multiplying again.
	var factor := maxi(1, int(round(4.0 / UI.readback_scale(get_viewport(), img))))
	if factor > 1:
		crop.resize(crop.get_width() * factor, crop.get_height() * factor,
			Image.INTERPOLATE_NEAREST)
	return crop


func _run() -> void:
	var out_prefix := _arg("--out", "%s/defender_pivot" % OUT_DIR)

	var game: Game = load("res://scenes/Game.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	# Bez obrany jádro vyhoří a _game_over() přepne scénu ještě před fotkou — a vzal by
	# s sebou i tenhle uzel, protože harness je RODIČ Game. Viz reference-godot-binary.
	GameState.max_focus = 999999
	GameState.focus = 999999
	game.fog_enabled = false   # čisté pole, ne mlha — o mlhu tady nejde
	await get_tree().process_frame

	var all_free_cells := _free_cells(game)
	if all_free_cells.size() < 20:
		printerr("_shot_defender_pivot: málo volné podlahy (%d buněk) — level se nezdá vhodný" % all_free_cells.size())

	# Game's default build-phase HUD (top banner, bottom build bar, and a hover tooltip
	# that sits over the LEFT third of the board) is on screen the instant Game.tscn is
	# instantiated and nothing has hidden it — same as it would be for anyone opening a
	# level. Rather than fighting that chrome, this keeps every spawned unit's FEET
	# inside a band clear of it, biased to the right half and mid-rows of the board.
	# Falls back to the full free-floor list if a level is too small/walled for the
	# band to hold enough cells.
	var g := Data.GRID
	var safe_cells: Array[Vector2i] = []
	for c: Vector2i in all_free_cells:
		if c.y >= 6 and c.y < int(g.rows) - 3 and c.x >= int(g.cols) * 0.5 and c.x < int(g.cols) - 1:
			safe_cells.append(c)
	var free_cells: Array[Vector2i] = safe_cells if safe_cells.size() >= 20 else all_free_cells

	var used: Dictionary = {}

	# --- 1) Rozptýlené jednotky, jedna od každého typu, rovnoměrně po volné podlaze ---
	var stride: int = maxi(1, free_cells.size() / 16)
	var scatter_defenders := 0
	var scatter_distractions := 0
	var idx := 0
	var pick := 0
	while pick < DEF_TYPES.size() + DIST_TYPES.size() and idx < free_cells.size():
		var cell: Vector2i = free_cells[idx]
		idx += stride
		if used.has(cell):
			continue
		used[cell] = true
		var pos := game.cell_center(cell)
		if pick < DEF_TYPES.size():
			_spawn_defender(game, DEF_TYPES[pick], pos)
			scatter_defenders += 1
		else:
			game.spawn_distraction(StringName(DIST_TYPES[pick - DEF_TYPES.size()]), cell)
			scatter_distractions += 1
		pick += 1

	# --- 2) Překrývající se pár (obránce nahoře, distrakce hned pod ním) — tady je
	# pivot bug i y-sort nejlíp vidět, protože se sprity fyzicky kryjí. ---
	var overlap_pair := _find_adjacent_pair(free_cells, used)
	var overlap_def: DefenderUnit = null
	var overlap_dist: Distraction = null
	if overlap_pair.size() == 2:
		used[overlap_pair[0]] = true
		used[overlap_pair[1]] = true
		overlap_def = _spawn_defender(game, "broccoli_knight", game.cell_center(overlap_pair[0]))
		overlap_dist = game.spawn_distraction(StringName("doomscroll"), overlap_pair[1])
	else:
		printerr("_shot_defender_pivot: nenašel jsem volnou dvojici buněk pro překryvový pár")

	# --- 3) Nebatchovaný pár: obránce svírá distrakci (add_blocker), takže distrakce
	# jde přes DistractionAnimator._draw() (individuálně y-sortovaná), NE přes
	# HordeRenderer — ověřuje y-sort pro přesně ten případ, který úkol chce potvrdit. ---
	var melee_pair := _find_adjacent_pair(free_cells, used)
	var melee_def: DefenderUnit = null
	var melee_dist: Distraction = null
	if melee_pair.size() == 2:
		used[melee_pair[0]] = true
		used[melee_pair[1]] = true
		melee_def = _spawn_defender(game, "chilli_berserker", game.cell_center(melee_pair[0]))
		melee_dist = game.spawn_distraction(StringName("autoplay"), melee_pair[1])
		melee_dist.add_blocker(melee_def)
		melee_def.engaged_target = melee_dist
		melee_def.state = DefenderUnit.State.ATTACK
	else:
		printerr("_shot_defender_pivot: nenašel jsem volnou dvojici buněk pro melee pár")

	var total_defenders: int = scatter_defenders + int(overlap_def != null) + int(melee_def != null)
	var total_distractions: int = scatter_distractions + int(overlap_dist != null) + int(melee_dist != null)
	print("_shot_defender_pivot: %d obránců, %d distrakcí, celkem %d jednotek" %
		[total_defenders, total_distractions, total_defenders + total_distractions])
	if overlap_pair.size() == 2:
		print("_shot_defender_pivot: overlap pár @ %s / %s (world %s)" %
			[overlap_pair[0], overlap_pair[1], game.cell_center(overlap_pair[0])])
	if melee_pair.size() == 2:
		print("_shot_defender_pivot: melee pár @ %s / %s — is_blocked=%s, is_batch_eligible=%s" %
			[melee_pair[0], melee_pair[1], melee_dist.is_blocked, melee_dist.animator.is_batch_eligible()])

	for _f in range(6):
		await get_tree().process_frame

	var defenders := get_tree().get_nodes_in_group("defenders")

	# --- BEFORE: reprodukce starého center-pivot bugu, byte-for-byte (viz
	# DefenderUnit.debug_legacy_center_pivot) ---
	DefenderUnit.debug_legacy_center_pivot = true
	for u in defenders:
		if is_instance_valid(u):
			u.queue_redraw()
	for _f in range(4):
		await get_tree().process_frame
	var img_before := get_viewport().get_texture().get_image()
	_save(img_before, "%s_before.png" % out_prefix)

	# --- AFTER: opravené bottom-anchored kreslení (default, false) ---
	DefenderUnit.debug_legacy_center_pivot = false
	for u in defenders:
		if is_instance_valid(u):
			u.queue_redraw()
	for _f in range(4):
		await get_tree().process_frame
	var img_after := get_viewport().get_texture().get_image()
	_save(img_after, "%s_after.png" % out_prefix)

	# Zoom na overlap pár — tam je rozdíl nejčitelnější.
	if overlap_pair.size() == 2:
		var center: Vector2 = (game.cell_center(overlap_pair[0]) + game.cell_center(overlap_pair[1])) * 0.5
		_save(_crop_zoom(img_before, center, 40), "%s_before_overlap_zoom.png" % out_prefix)
		_save(_crop_zoom(img_after, center, 40), "%s_after_overlap_zoom.png" % out_prefix)

	# Zoom na melee/nebatchovaný pár — ověřuje y-sort na nebatchované distrakci.
	if melee_pair.size() == 2:
		var mcenter: Vector2 = (game.cell_center(melee_pair[0]) + game.cell_center(melee_pair[1])) * 0.5
		_save(_crop_zoom(img_after, mcenter, 40), "%s_after_melee_zoom.png" % out_prefix)

	print("HOTOVO")
	get_tree().quit(0)
