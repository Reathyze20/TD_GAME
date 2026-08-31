extends Control
# Attach to the root Control of Education.tscn. Shows the card for the level just
# finished (GameState.current_level_index), then advances to the next level or the menu.

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var idx: int = GameState.current_level_index
	# Looked up by the level's OWN id. `idx` is a position in Data's array and `idx + 1`
	# only happened to equal the id while the ids ran 1, 2, 3… — the isometric levels are
	# 98 and 99, so the old arithmetic silently fell through to the fallback card.
	var card: InsightCardData = null
	if idx >= 0 and idx < Data.get_level_count():
		card = Data.get_insight_card(Data.get_level(idx).id)
	# A level with no card of its own borrows the last one rather than crashing on a
	# null title. If even that is missing there is nothing honest to show, so the
	# screen skips straight past the lesson instead of taking the run down with it.
	if card == null and Data.get_level_count() > 0:
		card = Data.get_insight_card(Data.get_level(Data.get_level_count() - 1).id)
	if card == null:
		card = InsightCardData.new()
	var has_next: bool = (idx + 1) < Data.get_level_count()

	theme = UI.theme()

	var bg := ColorRect.new()
	bg.color = UI.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Centred by anchors rather than a hardcoded rect, and sized to its content — the
	# fixed 1200x680 box left the shorter card floating in a half-empty frame.
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(centre)

	var panel := UI.panel(UI.ACCENT, 1)
	panel.custom_minimum_size = Vector2(275, 0)
	centre.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)

	var concept: String = card.concept
	var desc: String = _fill_placeholders(card.description)

	_add_label(box, "LEVEL CLEAR", UI.FS_SMALL, UI.FOCUS, false)

	# Stars at the moment they are earned — they used to appear only later, on the
	# level-select and campaign screens, which quietly threw away the payoff beat.
	var stats: Dictionary = GameState.last_run_stats
	if not stats.is_empty():
		var earned: int = int(stats.get("stars", 0))
		var star_row := HBoxContainer.new()
		star_row.add_theme_constant_override("separation", 2)
		box.add_child(star_row)
		for i in range(3):
			star_row.add_child(UI.label("★", UI.FS_TITLE,
				UI.DOPAMINE if i < earned else UI.TEXT_FAINT))
		star_row.add_child(UI.spacer(Vector2(4, 0)))
		var summary := UI.label("%d distractions defeated  ·  %d waves  ·  %d/%d Focus kept"
			% [int(stats.get("kills", 0)), int(stats.get("waves_cleared", 0)),
				int(stats.get("focus", 0)), int(stats.get("max_focus", 0))],
			UI.FS_BODY, UI.TEXT_DIM)
		summary.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		star_row.add_child(summary)

	_add_label(box, card.title, UI.FS_TITLE, UI.TEXT, false)
	if concept != "":
		_add_label(box, concept.to_upper(), UI.FS_MICRO, UI.ACCENT, false)
	box.add_child(HSeparator.new())
	_add_wrapped(box, desc, UI.FS_HEAD, UI.TEXT)

	# The source, small and directly under the claim it belongs to. A game that teaches
	# people to distrust confident unsourced claims about their own brain cannot make
	# confident unsourced claims about their own brain. Optional, so a card that is
	# purely about the player's behaviour is not forced to invent a paper.
	if card.citation != "":
		_add_wrapped(box, card.citation, UI.FS_MICRO, UI.TEXT_FAINT)

	# The takeaway is the one line the player should leave with, so it gets a frame of
	# its own rather than being a differently-coloured paragraph among paragraphs.
	var take := UI.panel(UI.DOPAMINE, 1)
	box.add_child(take)
	take.add_child(UI.wrapped("→ " + _fill_placeholders(card.takeaway), 250,
		UI.FS_HEAD, UI.DOPAMINE))

	# The mirror, under the lesson and above the bookkeeping. Deliberately in that order:
	# the insight card explains the concept, the receipt shows the player doing it, and
	# the second one lands only because the first one just named the thing.
	var receipt := Receipt.build(1000.0)
	if receipt != null:
		box.add_child(HSeparator.new())
		box.add_child(receipt)

	# Same breakdown the defeat screen shows, so a win and a loss speak the same language
	# about what the run was worth.
	var run: Dictionary = GameState.last_run_insight
	if not run.is_empty():
		var row := HBoxContainer.new()
		box.add_child(row)
		row.add_child(UI.label("Insight banked  +%d ◆" % int(run.get("total", 0)),
			UI.FS_HEAD, UI.INSIGHT))
		row.add_child(UI.spacer(Vector2.ZERO, true))
		row.add_child(UI.label("%d ◆ total" % MetaProgression.current_save.insight,
			UI.FS_BODY, UI.TEXT_DIM))
		var parts: Array[String] = []
		for line: Dictionary in run.get("lines", []):
			parts.append("%s +%d" % [line.label, int(line.amount)])
		var spent: int = int(run.get("spent", 0))
		if spent > 0:
			parts.append("%d ◆ spent on cards" % spent)
		if not parts.is_empty():
			_add_wrapped(box, "  ·  ".join(parts), UI.FS_SMALL, UI.TEXT_FAINT)

	box.add_child(UI.spacer(Vector2(0, 3)))

	var btn := UI.primary_button("Continue" if has_next else "Finish", UI.FOCUS,
		UI.FS_HEAD, Vector2(60, 14))
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(btn)
	btn.pressed.connect(_on_continue.bind(has_next, idx))

	_show_between_level_ad(idx)

## The first interstitial a player ever sees lands HERE, on a results screen, costing
## nothing. That order is the one thing in the whole ad system that cannot be got wrong:
## an ad that takes Focus before the player knows this game does jokes reads as
## hostility, and they never come back to find out it was one.
##
## Mid-wave ads (and the ones with a working button) only start once the joke is
## established. See docs/design/dopamine_mechanics.md §6, "Křivka důvěry".
func _show_between_level_ad(idx: int) -> void:
	var lvl: LevelData = Data.get_level(idx)
	if lvl == null:
		return
	for ad: AdData in lvl.ads:
		if not ad.between_levels:
			continue
		var overlay := AdOverlay.create(ad)
		add_child(overlay)
		return

## Substitutes live balance values into card copy. A card that claims "one in 20" while
## the constant says something else is worse than no card at all — this whole screen's
## credibility rests on the numbers matching what the player just played. Add a
## placeholder here rather than hardcoding a figure into a .tres.
func _fill_placeholders(text: String) -> String:
	var drop_rate := 0
	if GameState.INSIGHT_DROP_CHANCE > 0.0:
		drop_rate = int(round(1.0 / GameState.INSIGHT_DROP_CHANCE))
	return text.replace("{drop_rate}", str(drop_rate))

func _add_label(parent: Node, text: String, font_size: int, color: Color, center: bool) -> void:
	parent.add_child(UI.label(text, font_size, color,
		HORIZONTAL_ALIGNMENT_CENTER if center else HORIZONTAL_ALIGNMENT_LEFT))

func _add_wrapped(parent: Node, text: String, font_size: int, color: Color) -> void:
	parent.add_child(UI.wrapped(text, 250, font_size, color))

func _on_continue(has_next: bool, idx: int) -> void:
	if has_next:
		GameState.current_level_index = idx + 1
		get_tree().change_scene_to_file("res://scenes/Game.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/Victory.tscn")
