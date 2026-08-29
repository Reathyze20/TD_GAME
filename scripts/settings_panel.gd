class_name SettingsPanel
extends PanelContainer
## The one settings surface in the game — SFX volume/mute, fullscreen, and the hint
## system toggle. Built in code via the UI factories and reused from two places (main
## menu and the in-game pause menu), which is why it is its own class rather than a
## private helper of either. Emits `closed` when dismissed; the opener owns the overlay.

signal closed

func _ready() -> void:
	add_theme_stylebox_override("panel", UI.card_style(UI.BORDER_HI, 1, UI.PANEL))
	custom_minimum_size = Vector2(440, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	add_child(box)

	box.add_child(UI.label("Settings", UI.FS_TITLE, UI.ACCENT))
	box.add_child(HSeparator.new())

	# --- SFX volume: apply live while dragging, persist once on release -----------
	var vol_row := HBoxContainer.new()
	vol_row.add_theme_constant_override("separation", 10)
	box.add_child(vol_row)
	vol_row.add_child(UI.label("SFX volume", UI.FS_BODY, UI.TEXT))
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = Sfx.get_volume_linear()
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(180, 24)
	slider.value_changed.connect(func(v: float): Sfx.preview_volume_linear(v))
	slider.drag_ended.connect(func(_changed: bool):
		Sfx.set_volume_linear(slider.value)
		Sfx.play(&"card"))   # audible sample of the committed level
	vol_row.add_child(slider)

	var mute := CheckButton.new()
	mute.text = "Mute sound effects"
	mute.add_theme_font_size_override("font_size", UI.FS_BODY)
	mute.button_pressed = Sfx.is_muted()
	mute.toggled.connect(func(on: bool): Sfx.set_muted(on))
	box.add_child(mute)

	# --- Music: its own slider, not a share of the SFX one ------------------------
	# The music carries Satisfaction (scripts/music.gd) — it is a gameplay channel, not
	# decoration. Folding it into the SFX slider would let a player who turns the sound
	# down silently lose one of the five things the game says with.
	var music_row := HBoxContainer.new()
	music_row.add_theme_constant_override("separation", 10)
	box.add_child(music_row)
	music_row.add_child(UI.label("Music volume", UI.FS_BODY, UI.TEXT))
	var music_slider := HSlider.new()
	music_slider.min_value = 0.0
	music_slider.max_value = 1.0
	music_slider.step = 0.05
	music_slider.value = Music.get_volume_linear()
	music_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	music_slider.custom_minimum_size = Vector2(180, 24)
	music_slider.value_changed.connect(func(v: float): Music.preview_volume_linear(v))
	music_slider.drag_ended.connect(func(_changed: bool):
		Music.set_volume_linear(music_slider.value))
	music_row.add_child(music_slider)

	box.add_child(HSeparator.new())

	var fullscreen := CheckButton.new()
	fullscreen.text = "Fullscreen"
	fullscreen.add_theme_font_size_override("font_size", UI.FS_BODY)
	fullscreen.button_pressed = MetaProgression.current_save.fullscreen
	fullscreen.toggled.connect(func(on: bool): MetaProgression.set_fullscreen(on))
	box.add_child(fullscreen)

	box.add_child(HSeparator.new())

	var hints := CheckButton.new()
	hints.text = "Show gameplay hints"
	hints.add_theme_font_size_override("font_size", UI.FS_BODY)
	hints.button_pressed = MetaProgression.current_save.hints_enabled
	hints.toggled.connect(func(on: bool): MetaProgression.set_hints_enabled(on))
	box.add_child(hints)

	var reset := UI.button("Reset seen hints", UI.FS_SMALL)
	reset.tooltip_text = "Hints show once each. This makes all of them show again."
	reset.pressed.connect(func():
		MetaProgression.reset_hints()
		reset.text = "Hints reset ✓"
		reset.disabled = true)
	box.add_child(reset)

	box.add_child(HSeparator.new())

	# --- The player's own data ----------------------------------------------------
	# The post-level receipt ends on "None of this left your computer", and a promise
	# about data the player cannot act on is a slogan rather than a guarantee. So the
	# delete button exists, it is not buried, and it works immediately. This game does
	# not get to make a point about the attention economy and then behave like it.
	box.add_child(UI.label("Your data", UI.FS_BODY, UI.TEXT))
	box.add_child(UI.wrapped(
		"Everything the post-level screen shows is stored only on this computer, in "
		+ "user://mirror.json. It is never sent anywhere.", 400, UI.FS_SMALL, UI.TEXT_DIM))
	var forget := UI.button("Delete my behaviour history", UI.FS_SMALL)
	forget.pressed.connect(func():
		Mirror.forget()
		forget.text = "Deleted ✓"
		forget.disabled = true)
	box.add_child(forget)

	box.add_child(UI.spacer(Vector2(0, 4)))

	var close := UI.primary_button("Close", UI.FOCUS, UI.FS_BODY, Vector2(0, 44))
	close.pressed.connect(func(): closed.emit())
	box.add_child(close)
