extends Control
# Attach to the root Control of Menu.tscn (the main scene). Builds its UI in code.

var _stars_label: Label      ## Insight readout.
var _clarity_label: Label    ## Clarity Stars readout.
var _growth_overlay: Control = null
var _settings_overlay: Control = null

func _ready() -> void:
	# The menu is the boundary of an editor playtest session: any level started from
	# here is a real run, so the designer cheats must not leak into it.
	GameState.designer_mode = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UI.theme()

	var bg := ColorRect.new()
	bg.color = UI.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Anchored rather than positioned at a measured y — the block stays centred whatever
	# the window size, instead of drifting off a 1080p assumption.
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 4)
	add_child(box)

	_add_label(box, "DOPAMINE DEFENSE", UI.FS_DISPLAY, UI.ACCENT)
	_add_label(box, "Defend your Focus from digital distractions.", UI.FS_TITLE, UI.TEXT)
	_add_label(box, "Build habits. Spend Dopamine. Learn how the feed hooks you.",
		UI.FS_HEAD, UI.TEXT_DIM)

	box.add_child(UI.spacer(Vector2(0, 5)))

	# Currencies as chips rather than a run-on sentence, so the two are visibly separate
	# things: Insight is spent in the tree, Stars are a record of how well you cleared.
	var chips := HBoxContainer.new()
	chips.alignment = BoxContainer.ALIGNMENT_CENTER
	chips.add_theme_constant_override("separation", 4)
	box.add_child(chips)
	var ins_out: Array = []
	chips.add_child(UI.stat_chip("Insight", UI.INSIGHT, ins_out, UI.FS_TITLE))
	_stars_label = ins_out[0]
	var star_out: Array = []
	chips.add_child(UI.stat_chip("Clarity Stars", UI.DOPAMINE, star_out, UI.FS_TITLE))
	_clarity_label = star_out[0]
	_update_stars_display()

	box.add_child(UI.spacer(Vector2(0, 5)))

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 5)
	box.add_child(btn_row)

	var start := UI.primary_button("Start Game", UI.FOCUS, UI.FS_HEAD, Vector2(60, 15))
	btn_row.add_child(start)
	start.pressed.connect(_on_start)

	var growth := UI.button("Growth Tree", UI.FS_HEAD, Vector2(60, 15))
	btn_row.add_child(growth)
	growth.pressed.connect(_open_growth_tree)

	var settings := UI.button("Settings", UI.FS_HEAD, Vector2(60, 15))
	btn_row.add_child(settings)
	settings.pressed.connect(_open_settings)

func _open_settings() -> void:
	_close_settings()
	# Dimmed rather than opaque — unlike the Growth Tree this is a small centred card,
	# and the menu staying faintly visible behind it says "you haven't gone anywhere".
	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.6)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)
	_settings_overlay = overlay

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)

	var panel := SettingsPanel.new()
	panel.closed.connect(_close_settings)
	center.add_child(panel)

func _close_settings() -> void:
	if _settings_overlay and is_instance_valid(_settings_overlay):
		_settings_overlay.queue_free()
	_settings_overlay = null

func _update_stars_display() -> void:
	if _stars_label:
		_stars_label.text = "%d ◆" % MetaProgression.current_save.insight
	if _clarity_label:
		_clarity_label.text = "%d ★" % MetaProgression.current_save.total_clarity_stars

func _add_label(parent: Node, text: String, font_size: int, color: Color) -> Label:
	var l := UI.label(text, font_size, color, HORIZONTAL_ALIGNMENT_CENTER)
	parent.add_child(l)
	return l

func _on_start() -> void:
	get_tree().change_scene_to_file("res://scenes/LevelSelect.tscn")

func _open_growth_tree() -> void:
	_close_growth_tree()

	# Fully opaque: at 0.97 the menu's own headings read through the panel gaps and made
	# the tree look like it was printed on tracing paper.
	var overlay := ColorRect.new()
	overlay.color = UI.BG
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	_growth_overlay = overlay

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 30)
	margin.add_theme_constant_override("margin_right", 30)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 10)
	overlay.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	margin.add_child(box)

	# Header row: title left, spendable balance right — the number you are about to
	# commit belongs next to the prices, not buried in a paragraph.
	var header := HBoxContainer.new()
	box.add_child(header)
	header.add_child(UI.label("Growth Tree", UI.FS_TITLE, UI.ACCENT))
	header.add_child(UI.spacer(Vector2.ZERO, true))
	header.add_child(UI.label("%d ◆ available" % MetaProgression.current_save.insight,
		UI.FS_HEAD, UI.INSIGHT))

	box.add_child(UI.wrapped(
		"Insight is earned on every run, won or lost. Spend it here on permanent upgrades that carry across levels — or spend it on cards mid-run. Not both.",
		400, UI.FS_BODY, UI.TEXT_DIM))

	box.add_child(UI.spacer(Vector2(0, 2)))

	# One column per branch, built from whatever Data found on disk. Adding a growth
	# .tres shows up here with no change to this file; adding a whole branch only needs
	# an entry in Data.GROWTH_BRANCHES for its name and colour.
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 5)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(columns)

	for branch: StringName in Data.growth_branches():
		columns.add_child(_build_growth_branch(branch))

	var close := UI.button("Close", UI.FS_BODY, Vector2(45, 12))
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(_close_growth_tree)
	box.add_child(close)

func _build_growth_branch(branch: StringName) -> VBoxContainer:
	var meta := Data.growth_branch_meta(branch)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# Branch header sits on a tinted strip so the three columns read as three distinct
	# tracks rather than one long list that happens to have gaps in it.
	var head_panel := PanelContainer.new()
	var branch_color := Color(meta.color)
	head_panel.add_theme_stylebox_override("panel", UI.flat(
		Color(branch_color.r * 0.18, branch_color.g * 0.18, branch_color.b * 0.18),
		branch_color, 1, UI.RADIUS_SM, 3))
	col.add_child(head_panel)

	var head_box := VBoxContainer.new()
	head_box.add_theme_constant_override("separation", 1)
	head_panel.add_child(head_box)
	head_box.add_child(UI.label(String(meta.display).to_upper(), UI.FS_HEAD, branch_color,
		HORIZONTAL_ALIGNMENT_CENTER))
	head_box.add_child(UI.wrapped(String(meta.blurb), 0, UI.FS_SMALL, UI.TEXT_DIM,
		HORIZONTAL_ALIGNMENT_CENTER))

	for node: GrowthNodeData in Data.growth_nodes_in_branch(branch):
		col.add_child(_build_growth_node(node, branch_color))
	return col

## One node card. Four states, and they must be distinguishable at a glance: maxed,
## affordable, too expensive, and locked behind a prerequisite — the last one is the
## only state where the player can't fix it with more Insight, so it says what to buy.
func _build_growth_node(nd: GrowthNodeData, branch_color: Color) -> PanelContainer:
	var rank := MetaProgression.get_rank(nd.id)
	var maxed := MetaProgression.is_maxed(nd.id)
	var unlocked_reqs := MetaProgression.requirements_met(nd.id)
	var price := MetaProgression.next_rank_cost(nd.id)
	var affordable := MetaProgression.can_unlock(nd.id)

	# Border carries the state; a locked node is also dimmed, so "can't yet" and
	# "can't afford" don't look the same.
	var border := UI.BORDER
	if maxed:
		border = UI.FOCUS
	elif affordable:
		border = branch_color
	elif unlocked_reqs:
		border = UI.BORDER_HI
	var panel := UI.panel(border, 1)
	panel.add_theme_stylebox_override("panel", UI.flat(UI.PANEL, border, 1, UI.RADIUS_SM, 3))
	if not unlocked_reqs:
		panel.modulate = Color(1, 1, 1, 0.5)

	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 1)
	panel.add_child(info)

	var title_row := HBoxContainer.new()
	info.add_child(title_row)
	title_row.add_child(UI.label(nd.name, UI.FS_BODY,
		UI.FOCUS if rank > 0 else UI.TEXT))
	title_row.add_child(UI.spacer(Vector2.ZERO, true))
	if nd.max_rank > 1:
		# Rank pips rather than "2/3": at three ranks the shape reads faster than the number.
		title_row.add_child(UI.label("●".repeat(rank) + "○".repeat(maxi(0, nd.max_rank - rank)),
			UI.FS_SMALL, branch_color))

	info.add_child(UI.wrapped(nd.description, 0, UI.FS_SMALL, UI.TEXT_DIM))

	var btn: Button
	if maxed:
		btn = UI.button("Maxed", UI.FS_SMALL, Vector2(0, 9))
		btn.disabled = true
	elif not unlocked_reqs:
		btn = UI.button("🔒 Requires %s" % _requirement_names(nd), UI.FS_SMALL, Vector2(0, 9))
		btn.disabled = true
	elif affordable:
		btn = UI.primary_button("Unlock — %d ◆" % price, branch_color, UI.FS_SMALL,
			Vector2(0, 9))
	else:
		btn = UI.button("Unlock — %d ◆" % price, UI.FS_SMALL, Vector2(0, 9))
		btn.disabled = true
	if affordable:
		btn.pressed.connect(func():
			if MetaProgression.unlock_rank(nd.id):
				_update_stars_display()
				_open_growth_tree()   # cheapest correct refresh: rebuild the whole tree
		)
	info.add_child(btn)
	return panel

func _requirement_names(nd: GrowthNodeData) -> String:
	var names: Array[String] = []
	for req: StringName in nd.requires:
		if MetaProgression.get_rank(req) >= 1:
			continue
		var req_node: GrowthNodeData = Data.get_growth_node(req)
		names.append(req_node.name if req_node != null else String(req))
	return ", ".join(names)

func _close_growth_tree() -> void:
	if _growth_overlay and is_instance_valid(_growth_overlay):
		_growth_overlay.queue_free()
	_growth_overlay = null
