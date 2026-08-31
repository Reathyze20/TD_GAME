extends Control
# Attach to the root Control of GameOver.tscn. Retry replays the current level
# (GameState.current_level_index is unchanged); Menu returns to the start screen.

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UI.theme()

	var bg := ColorRect.new()
	bg.color = UI.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 3)
	add_child(box)

	_add_label(box, "FOCUS DEPLETED", UI.FS_DISPLAY, UI.DANGER)
	_add_label(box, "The distractions got through. Your attention ran out.",
		UI.FS_HEAD, UI.TEXT_DIM)

	# How far the run got — a defeat with a number attached is a benchmark to beat,
	# not just a wall. Guarded for a direct scene launch, same as the breakdown below.
	var stats: Dictionary = GameState.last_run_stats
	if not stats.is_empty():
		_add_label(box, "Survived %d of %d waves  ·  %d distractions defeated"
			% [int(stats.get("waves_cleared", 0)), int(stats.get("max_wave", 0)),
				int(stats.get("kills", 0))], UI.FS_BODY, UI.TEXT)

	_add_insight_breakdown(box)

	box.add_child(UI.spacer(Vector2(0, 6)))

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 4)
	box.add_child(buttons)

	var retry := UI.primary_button("Retry", UI.FOCUS, UI.FS_HEAD, Vector2(50, 14))
	buttons.add_child(retry)
	retry.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/Game.tscn"))

	var menu := UI.button("Menu", UI.FS_HEAD, Vector2(45, 14))
	buttons.add_child(menu)
	menu.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/Menu.tscn"))

## The point of the defeat screen. A run that ends with "you lost, nothing gained" is a
## dead end; itemising what the attempt was worth turns it into progress the player can
## immediately go spend. Renders whatever lines bank_run() produced, so changing
## the formula never means editing this screen.
func _add_insight_breakdown(parent: Node) -> void:
	var run: Dictionary = GameState.last_run_insight
	if run.is_empty():
		return

	parent.add_child(UI.spacer(Vector2(0, 7)))

	# The takings sit in a panel of their own — this is the reason to look at this screen
	# rather than reflexively hitting Retry, so it gets a frame instead of being one more
	# line of centred text.
	var panel := UI.panel(UI.INSIGHT, 1)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	panel.custom_minimum_size = Vector2(140, 0)
	parent.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	panel.add_child(box)

	box.add_child(UI.label("Insight banked  +%d ◆" % int(run.get("total", 0)),
		UI.FS_TITLE, UI.INSIGHT, HORIZONTAL_ALIGNMENT_CENTER))
	box.add_child(HSeparator.new())

	for line: Dictionary in run.get("lines", []):
		var row := HBoxContainer.new()
		box.add_child(row)
		row.add_child(UI.label(String(line.label), UI.FS_BODY, UI.TEXT_DIM))
		row.add_child(UI.spacer(Vector2.ZERO, true))
		row.add_child(UI.label("+%d" % int(line.amount), UI.FS_BODY, UI.TEXT))

	# The spend is shown as context, not as a loss — it bought cards that were played.
	var spent: int = int(run.get("spent", 0))
	if spent > 0:
		var row := HBoxContainer.new()
		box.add_child(row)
		row.add_child(UI.label("Spent on cards during the run", UI.FS_SMALL, UI.TEXT_FAINT))
		row.add_child(UI.spacer(Vector2.ZERO, true))
		row.add_child(UI.label("−%d" % spent, UI.FS_SMALL, UI.TEXT_FAINT))

	box.add_child(HSeparator.new())
	box.add_child(UI.label("%d ◆ total — spend it in the Growth Tree"
		% MetaProgression.current_save.insight, UI.FS_BODY, UI.ACCENT,
		HORIZONTAL_ALIGNMENT_CENTER))

func _add_label(parent: Node, text: String, font_size: int, color: Color) -> void:
	parent.add_child(UI.label(text, font_size, color, HORIZONTAL_ALIGNMENT_CENTER))
