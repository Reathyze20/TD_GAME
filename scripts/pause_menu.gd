class_name PauseMenu
extends Control
## In-game pause overlay: dim + PAUSED + Resume / Restart / Settings / Quit to menu.
## Parented under the game's _hud_root, which is PROCESS_MODE_ALWAYS — that is what
## keeps this menu interactive while get_tree().paused is true, and it is also why the
## dim layer must be MOUSE_FILTER_STOP: every HUD button underneath keeps processing
## while paused, and only the dim standing in front of them blocks their clicks.
##
## The game node itself is PAUSABLE, so its hotkey handler is dead while paused —
## Esc/P to resume are caught HERE, not in game.gd.

signal resume_requested
signal restart_requested
signal quit_requested

var _settings_overlay: Control = null

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.62)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 12)
	center.add_child(box)

	box.add_child(UI.label("PAUSED", UI.FS_DISPLAY, UI.ACCENT, HORIZONTAL_ALIGNMENT_CENTER))
	box.add_child(UI.label("The feed can wait.", UI.FS_BODY, UI.TEXT_DIM,
		HORIZONTAL_ALIGNMENT_CENTER))
	box.add_child(UI.spacer(Vector2(0, 10)))

	var resume := UI.primary_button("Resume", UI.FOCUS, UI.FS_HEAD, Vector2(300, 54))
	resume.pressed.connect(func(): resume_requested.emit())
	box.add_child(resume)

	var restart := UI.button("Restart level", UI.FS_BODY, Vector2(300, 46))
	restart.pressed.connect(func(): restart_requested.emit())
	box.add_child(restart)

	var settings := UI.button("Settings", UI.FS_BODY, Vector2(300, 46))
	settings.pressed.connect(_open_settings)
	box.add_child(settings)

	var quit := UI.button("Quit to menu", UI.FS_BODY, Vector2(300, 46))
	quit.tooltip_text = "The run is abandoned — Insight you carried is NOT banked mid-run."
	quit.pressed.connect(func(): quit_requested.emit())
	box.add_child(quit)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if Input.is_action_just_pressed("td_cancel") or Input.is_action_just_pressed("td_pause"):
			# Settings-on-top swallows the first Esc; the second resumes the game.
			if _settings_overlay != null and is_instance_valid(_settings_overlay):
				_close_settings()
			else:
				resume_requested.emit()
			get_viewport().set_input_as_handled()

func _open_settings() -> void:
	_close_settings()
	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.5)
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
