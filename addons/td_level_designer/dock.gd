@tool
extends VBoxContainer
## The TD Level Designer dock: actions always visible, metrics readable at any zoom,
## plus a campaign overview across every level. Pure VIEW — every rule and computation
## stays in tools/map_editor.gd; this binds to the MapEditor node of the edited scene
## and renders its state. If that scene isn't open, one button opens it.

const EDITOR_SCENE := "res://scenes/MapEditor.tscn"

var _ed: MapEditor = null     ## bound MapEditor in the edited scene (null = none open)
## Unbound MapEditor instance for campaign math only — level_stats() works straight from
## LevelData resources, so the overview needs no scene at all. Kept OUT of the tree:
## in the tree its canvas drawing and _process would run inside the dock.
var _calc: MapEditor = null

var _header: Label
var _action_line: Label
var _open_btn: Button
var _action_buttons: Array[Button] = []
var _designer_cb: CheckBox
var _live_cb: CheckBox
var _traffic_cb: CheckBox
var _rows_box: VBoxContainer
var _chart: DifficultyChart
var _campaign_tree: Tree

func _ready() -> void:
	name = "TD Designer"
	_calc = MapEditor.new()
	_build_ui()
	var t := Timer.new()
	t.wait_time = 1.0
	t.autostart = true
	add_child(t)
	# Fallback binding: scene_changed alone misses the scene that is already open when
	# the plugin (or the editor) starts, and a closed scene must release the binding.
	t.timeout.connect(_poll)
	_poll()

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _calc != null:
		_calc.free()
		_calc = null

# ---------------------------------------------------------------- binding

func _poll() -> void:
	# Only the scene lookup needs the editor; the enable/disable state must be right
	# in every context, including headless checks.
	if Engine.is_editor_hint():
		bind_scene(EditorInterface.get_edited_scene_root())
	_refresh_header()

## Called by the plugin on every scene switch (and by the poll as a safety net).
func bind_scene(root: Node) -> void:
	if _ed != null and not is_instance_valid(_ed):
		_ed = null
	var found := _find_editor(root)
	if found == _ed:
		return
	if _ed != null:
		if _ed.analysis_updated.is_connected(_refresh):
			_ed.analysis_updated.disconnect(_refresh)
		_ed.draw_info_boxes = true
		_ed.queue_redraw()
	_ed = found
	if _ed != null:
		_ed.analysis_updated.connect(_refresh)
		# The dock owns the info display now; the canvas keeps only the map overlays.
		_ed.draw_info_boxes = false
		_ed.queue_redraw()
		_designer_cb.set_pressed_no_signal(_ed.playtest_designer_mode)
		_live_cb.set_pressed_no_signal(_ed.live_analyze)
		_traffic_cb.set_pressed_no_signal(_ed.show_traffic)
	_refresh()

func _find_editor(node: Node) -> MapEditor:
	if node == null:
		return null
	if node is MapEditor:
		return node
	for child in node.get_children():
		var found := _find_editor(child)
		if found != null:
			return found
	return null

# ---------------------------------------------------------------- UI construction

func _build_ui() -> void:
	add_theme_constant_override("separation", 6)

	_header = Label.new()
	_header.add_theme_font_size_override("font_size", 14)
	add_child(_header)

	_action_line = Label.new()
	_action_line.add_theme_font_size_override("font_size", 11)
	_action_line.add_theme_color_override("font_color", Color(0.6, 0.65, 0.75))
	add_child(_action_line)

	_open_btn = Button.new()
	_open_btn.text = "Open MapEditor.tscn"
	_open_btn.pressed.connect(func():
		if Engine.is_editor_hint():
			EditorInterface.open_scene_from_path(EDITOR_SCENE))
	add_child(_open_btn)

	var grid := GridContainer.new()
	grid.columns = 2
	add_child(grid)
	_add_action(grid, "Load", "Reload the target level onto the canvas",
		func(): _ed._load_from_level())
	_add_action(grid, "Analyze", "Re-measure the map now",
		func(): _ed._analyze())
	_add_action(grid, "Bake", "Validate, back up (.bak), write geometry to the .tres",
		func(): _ed._bake_to_level())
	_add_action(grid, "Playtest", "Bake, then launch the game straight into this level",
		func(): _ed._playtest())
	_add_action(grid, "Save Settings", "Write waves/economy/boss only — no geometry",
		func(): _ed._save_level_settings())
	_add_action(grid, "New Level", "Copy this level into the next free level_N.tres",
		func(): _ed._create_new_level())
	_add_action(grid, "Add Zone", "Add a spawn zone rectangle (drag it into place)",
		func():
			_ed._add_spawn_zone()
			_refresh())

	_designer_cb = _add_check("Designer-mode playtest",
		"F1 +500 Dopamine · F2 +10 Insight · F3 turbo 5× · F4 clear wave · no telemetry",
		func(on: bool): _ed.playtest_designer_mode = on)
	_live_cb = _add_check("Live analysis",
		"Re-analyze ~1s after every edit",
		func(on: bool): _ed.live_analyze = on)
	_traffic_cb = _add_check("Traffic heatmap",
		"Tint cells by how many enemy routes cross them",
		func(on: bool):
			_ed.show_traffic = on
			_ed.queue_redraw())

	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(tabs)

	var level_tab := VBoxContainer.new()
	level_tab.name = "Level"
	tabs.add_child(level_tab)
	_chart = DifficultyChart.new()
	level_tab.add_child(_chart)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	level_tab.add_child(scroll)
	_rows_box = VBoxContainer.new()
	_rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_rows_box)

	var camp_tab := VBoxContainer.new()
	camp_tab.name = "Campaign"
	tabs.add_child(camp_tab)
	var refresh := Button.new()
	refresh.text = "Refresh campaign overview"
	refresh.tooltip_text = "Recompute stats for every level in data/levels/"
	refresh.pressed.connect(_refresh_campaign)
	camp_tab.add_child(refresh)
	_campaign_tree = Tree.new()
	_campaign_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_campaign_tree.columns = 6
	_campaign_tree.hide_root = true
	_campaign_tree.set_column_titles_visible(true)
	var titles: Array[String] = ["level", "waves", "peak", "detour", "core", "boss"]
	for i in range(titles.size()):
		_campaign_tree.set_column_title(i, titles[i])
	camp_tab.add_child(_campaign_tree)

func _add_action(parent: Node, label: String, tip: String, action: Callable) -> void:
	var b := Button.new()
	b.text = label
	b.tooltip_text = tip
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(func():
		if _ed != null and is_instance_valid(_ed):
			action.call())
	parent.add_child(b)
	_action_buttons.append(b)

func _add_check(label: String, tip: String, on_toggle: Callable) -> CheckBox:
	var cb := CheckBox.new()
	cb.text = label
	cb.tooltip_text = tip
	cb.toggled.connect(func(on: bool):
		if _ed != null and is_instance_valid(_ed):
			on_toggle.call(on))
	add_child(cb)
	return cb

# ---------------------------------------------------------------- refresh

func _refresh_header() -> void:
	var bound := _ed != null and is_instance_valid(_ed)
	_open_btn.visible = not bound
	for b in _action_buttons:
		b.disabled = not bound
	_designer_cb.disabled = not bound
	_live_cb.disabled = not bound
	_traffic_cb.disabled = not bound
	if not bound:
		_header.text = "no MapEditor scene open"
		_action_line.text = ""
		return
	var tl: LevelData = _ed.target_level
	if tl == null:
		_header.text = "⚠ no Target Level assigned"
	else:
		var fname := tl.resource_path.get_file() if tl.resource_path != "" else "<unsaved>"
		_header.text = "editing: %s (id %d)" % [fname, tl.id]
	_action_line.text = _ed.last_action if _ed.last_action != "" else "no writes yet this session"

func _refresh() -> void:
	_refresh_header()
	if _rows_box == null:
		return
	for child in _rows_box.get_children():
		child.queue_free()
	if _ed == null or not is_instance_valid(_ed):
		_chart.summary = {}
		_chart.queue_redraw()
		return
	if _ed._report_lines.is_empty():
		var hint := Label.new()
		hint.text = "Assign a Target Level in the Inspector, then Load."
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_rows_box.add_child(hint)
	for rl in _ed._report_lines:
		var row := Label.new()
		row.text = String(rl.text)
		row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_theme_font_size_override("font_size", 12)
		var col := Color(0.75, 0.8, 0.9)
		if int(rl.ok) == 1:
			col = Color(0.55, 1.0, 0.65)
		elif int(rl.ok) == 0:
			col = Color(1.0, 0.45, 0.45)
		row.add_theme_color_override("font_color", col)
		_rows_box.add_child(row)
	_chart.summary = _ed._last_summary
	var tl: LevelData = _ed.target_level
	_chart.lean_waves = tl.lean_waves if tl != null else []
	_chart.has_boss = tl != null and tl.boss != null
	_chart.wave_count = tl.wave_count if tl != null else 0
	_chart.queue_redraw()

## One row per level in data/levels/, sorted by id — the campaign's difficulty ramp on
## one screen. Red cells carry the same judgments Analyze makes for a single map.
func _refresh_campaign() -> void:
	_campaign_tree.clear()
	var root := _campaign_tree.create_item()
	var dir := DirAccess.open(MapEditor.LEVELS_DIR)
	if dir == null:
		return
	var stats: Array[Dictionary] = []
	dir.list_dir_begin()
	var fn := dir.get_next()
	while fn != "":
		if not dir.current_is_dir() and fn.ends_with(".tres"):
			var lvl := load(MapEditor.LEVELS_DIR + fn) as LevelData
			if lvl != null:
				stats.append(_calc.level_stats(lvl))
		fn = dir.get_next()
	dir.list_dir_end()
	stats.sort_custom(func(a: Dictionary, b: Dictionary): return int(a.id) < int(b.id))
	for s in stats:
		var it := _campaign_tree.create_item(root)
		it.set_text(0, "%d · %s" % [int(s.id), String(s.name)])
		it.set_text(1, "%d (%d)" % [int(s.waves), int(s.spawns)])
		it.set_text(2, str(int(s.peak)))
		it.set_text(3, "%.2f" % float(s.detour))
		it.set_text(4, str(int(s.core_spots)))
		it.set_text(5, "yes" if bool(s.boss) else "—")
		if float(s.detour) < MapEditor.TARGET_DETOUR:
			it.set_custom_color(3, Color(1.0, 0.45, 0.45))
		if int(s.core_spots) < MapEditor.TARGET_CORE_SPOTS_MIN \
				or int(s.core_spots) > MapEditor.TARGET_CORE_SPOTS_MAX:
			it.set_custom_color(4, Color(1.0, 0.45, 0.45))

# ---------------------------------------------------------------- chart

## Compact version of the on-canvas difficulty chart, as real UI: crisp at any viewport
## zoom, and always in view next to the metrics it explains.
class DifficultyChart extends Control:
	var summary: Dictionary = {}
	var lean_waves: Array = []
	var has_boss := false
	var wave_count := 0

	func _init() -> void:
		custom_minimum_size = Vector2(0, 130)

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.08, 0.1, 0.16))
		var font := ThemeDB.fallback_font
		if summary.is_empty():
			draw_string(font, Vector2(10, 22), "no analysis yet",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.5, 0.55, 0.65))
			return
		var totals: Array = summary.totals
		var peak: int = int(summary.peak)
		if peak <= 0 or totals.is_empty():
			return
		draw_string(font, Vector2(8, 16),
			"spawns/wave · peak %d @ w%d · blue=lean · red ring=boss"
			% [peak, int(summary.peak_wave)],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.7, 0.75, 0.85))
		var top := 24.0
		var bot := size.y - 16.0
		var bw := (size.x - 16.0) / float(totals.size())
		for i in range(totals.size()):
			var v := int(totals[i])
			var bh := (bot - top) * float(v) / float(peak)
			var wave_no := i + 1
			var col := Color(0.95, 0.62, 0.25, 0.9)
			if lean_waves.has(wave_no):
				col = Color(0.35, 0.6, 0.95, 0.9)
			var bx := 8.0 + bw * float(i)
			draw_rect(Rect2(bx + 1.0, bot - bh, maxf(1.0, bw - 2.0), bh), col)
			if has_boss and wave_no == wave_count:
				draw_rect(Rect2(bx + 1.0, bot - bh, maxf(1.0, bw - 2.0), bh),
					Color(1.0, 0.3, 0.3, 0.95), false, 2.0)
			if wave_no == 1 or wave_no == totals.size() or wave_no % 5 == 0:
				draw_string(font, Vector2(bx, size.y - 4), str(wave_no),
					HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.55, 0.6, 0.72))
