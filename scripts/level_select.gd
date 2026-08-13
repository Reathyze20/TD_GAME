extends Control
# Attach to the root Control of LevelSelect.tscn. Lists every LevelData from
# Data, gated by MetaProgression.current_save.unlocked_levels, and shows the
# best star rating from level_stars. Level ids here are 1-based array
# position ("Level_01", "Level_02", ...), matching the convention game.gd's
# _level_complete() already writes into the save (see meta_progression.gd).

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UI.theme()

	var bg := ColorRect.new()
	bg.color = UI.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(centre)

	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(860, 0)
	box.add_theme_constant_override("separation", 14)
	centre.add_child(box)

	var header := HBoxContainer.new()
	box.add_child(header)
	header.add_child(UI.label("Select Level", UI.FS_TITLE, UI.ACCENT))
	header.add_child(UI.spacer(Vector2.ZERO, true))
	header.add_child(UI.label("%d ◆" % MetaProgression.current_save.insight,
		UI.FS_HEAD, UI.INSIGHT))

	box.add_child(UI.spacer(Vector2(0, 8)))

	for i in range(Data.get_level_count()):
		box.add_child(_build_level_card(i))

	box.add_child(UI.spacer(Vector2(0, 14)))

	var back := UI.button("Back", UI.FS_BODY, Vector2(160, 46))
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(back)
	back.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/Menu.tscn"))

func _build_level_card(index: int) -> PanelContainer:
	var level: LevelData = Data.get_level(index)
	var level_id := "Level_%02d" % (index + 1)
	var unlocked: bool = MetaProgression.current_save.unlocked_levels.has(level_id)
	var best_stars: int = MetaProgression.current_save.level_stars.get(level_id, 0)

	var panel := UI.panel(UI.BORDER_HI if unlocked else UI.BORDER, 1)
	if not unlocked:
		panel.modulate = Color(1, 1, 1, 0.5)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	panel.add_child(row)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 6)
	row.add_child(info)

	info.add_child(UI.label(level.display_name if unlocked else "??? — Locked",
		UI.FS_HEAD, UI.TEXT if unlocked else UI.TEXT_FAINT))

	if unlocked:
		info.add_child(_build_star_row(best_stars))
	else:
		info.add_child(UI.label("Clear the previous level to unlock", UI.FS_SMALL,
			UI.TEXT_FAINT))

	var play: Button
	if unlocked:
		play = UI.primary_button("Replay" if best_stars > 0 else "Play", UI.FOCUS,
			UI.FS_BODY, Vector2(140, 50))
		play.pressed.connect(_on_play.bind(index))
	else:
		play = UI.button("Locked", UI.FS_BODY, Vector2(140, 50))
		play.disabled = true
	play.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(play)

	return panel

func _build_star_row(best_stars: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	if best_stars <= 0:
		row.add_child(UI.label("Not yet cleared", UI.FS_SMALL, UI.TEXT_DIM))
		return row
	for i in range(3):
		row.add_child(UI.label("★", UI.FS_BODY,
			UI.DOPAMINE if i < best_stars else UI.TEXT_FAINT))
	return row

func _on_play(index: int) -> void:
	GameState.current_level_index = index
	get_tree().change_scene_to_file("res://scenes/Game.tscn")

func _add_label(parent: Node, text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	parent.add_child(l)
	return l
