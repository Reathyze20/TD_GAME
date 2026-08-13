extends Control
# Attach to the root Control of Victory.tscn. Shown once after the insight
# card of the LAST level (see education.gd's has_next check) — the campaign-
# complete counterpart to GameOver.tscn's defeat screen.

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
	box.add_theme_constant_override("separation", 12)
	add_child(box)

	_add_label(box, "FOCUS RECLAIMED", UI.FS_DISPLAY, UI.FOCUS)
	_add_label(box, "You defended your attention through every distraction thrown at it.",
		UI.FS_HEAD, UI.TEXT_DIM)

	box.add_child(UI.spacer(Vector2(0, 20)))

	var chips := HBoxContainer.new()
	chips.alignment = BoxContainer.ALIGNMENT_CENTER
	chips.add_theme_constant_override("separation", 14)
	box.add_child(chips)
	var star_out: Array = []
	chips.add_child(UI.stat_chip("Clarity Stars", UI.DOPAMINE, star_out, UI.FS_TITLE))
	star_out[0].text = "%d ★" % MetaProgression.current_save.total_clarity_stars
	var ins_out: Array = []
	chips.add_child(UI.stat_chip("Insight", UI.INSIGHT, ins_out, UI.FS_TITLE))
	ins_out[0].text = "%d ◆" % MetaProgression.current_save.insight

	box.add_child(UI.spacer(Vector2(0, 20)))

	var panel := UI.panel(UI.BORDER, 1)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	panel.custom_minimum_size = Vector2(620, 0)
	box.add_child(panel)

	var summary := VBoxContainer.new()
	summary.add_theme_constant_override("separation", 6)
	panel.add_child(summary)

	for i in range(Data.get_level_count()):
		var level: LevelData = Data.get_level(i)
		var level_id := "Level_%02d" % (i + 1)
		var stars: int = MetaProgression.current_save.level_stars.get(level_id, 0)
		summary.add_child(_build_level_row(level.display_name, stars))

	box.add_child(UI.spacer(Vector2(0, 24)))

	var menu := UI.primary_button("Return to Menu", UI.FOCUS, UI.FS_HEAD, Vector2(260, 56))
	menu.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(menu)
	menu.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/Menu.tscn"))

## Name left, stars right — a ragged centred row makes three levels look like a list of
## unrelated things instead of a scorecard you can scan down.
func _build_level_row(display_name: String, stars: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.add_child(UI.label(display_name, UI.FS_BODY, UI.TEXT))
	row.add_child(UI.spacer(Vector2.ZERO, true))
	for i in range(3):
		row.add_child(UI.label("★", UI.FS_BODY,
			UI.DOPAMINE if i < stars else UI.TEXT_FAINT))
	return row

func _add_label(parent: Node, text: String, font_size: int, color: Color) -> void:
	var l := UI.label(text, font_size, color, HORIZONTAL_ALIGNMENT_CENTER)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(l)
