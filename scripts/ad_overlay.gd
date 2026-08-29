class_name AdOverlay extends Control
## One parody interstitial, built from an AdData.
##
## Written once; every joke is a .tres. See scripts/resources/ad_data.gd for why the
## offer has to be genuine.
##
## THE GAME DOES NOT PAUSE behind this (game.gd shows it without touching the tree's
## pause state). While the player is laughing and hunting for the X, the wave runs.
## That is the attention economy in one interaction — but the price has to stay tiny
## (one or two Focus at most), because a joke that costs a level is not a joke.
##
## Deliberately drawn OFF the project's style: garish gradient, fat text, emoji. It has
## to look like it came from somewhere else, which is also why it never has to meet the
## art bar in docs/art/style_bible_measured.md.

signal closed(tapped: bool, seconds_open: float)

const _W := 720.0
const _H := 900.0

var _ad: AdData
var _elapsed := 0.0
var _x_button: Button = null
var _countdown_label: Label = null
var _hand: Control = null
var _dodged := false
var _done := false
var _watching := false
var _watch_left := 0.0

static func create(ad: AdData) -> AdOverlay:
	var o := AdOverlay.new()
	o._ad = ad
	return o

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	# ALWAYS so the ad still animates if something else pauses the tree; the wave behind
	# it is unaffected either way.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()

func _build() -> void:
	# Scrim. Dark enough to read the ad against, light enough that the player can still
	# see the wave they are losing behind it — the cost has to be visible to be a lesson.
	var scrim := ColorRect.new()
	scrim.color = Color(0, 0, 0, 0.55)
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(scrim)

	var frame := Control.new()
	frame.set_anchors_preset(Control.PRESET_CENTER)
	frame.custom_minimum_size = Vector2(_W, _H)
	frame.size = Vector2(_W, _H)
	frame.position = Vector2(-_W * 0.5, -_H * 0.5)
	add_child(frame)

	var grad := GradientTexture2D.new()
	grad.width = int(_W)
	grad.height = int(_H)
	grad.fill = GradientTexture2D.FILL_LINEAR
	grad.fill_from = Vector2(0, 0)
	grad.fill_to = Vector2(1, 1)
	var g := Gradient.new()
	g.set_color(0, _ad.color_a)
	g.set_color(1, _ad.color_b)
	grad.gradient = g
	var bg := TextureRect.new()
	bg.texture = grad
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.add_child(bg)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.add_theme_constant_override("separation", 18)
	box.offset_left = 40
	box.offset_right = -40
	box.offset_top = 46
	box.offset_bottom = -46
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	frame.add_child(box)

	_add_centered(box, _ad.emoji, 96, _ad.text_color)
	_add_centered(box, _ad.headline, 46, _ad.text_color)
	if _ad.subline != "":
		_add_centered(box, _ad.subline, 24, _ad.text_color)
	if _ad.stars != "":
		_add_centered(box, _ad.stars, 20, _ad.text_color)

	box.add_child(UI.spacer(Vector2(0, 20)))

	var cta := Button.new()
	cta.text = _ad.cta_text
	cta.custom_minimum_size = Vector2(0, 92)
	cta.add_theme_font_size_override("font_size", 32)
	cta.add_theme_color_override("font_color", Color("101010"))
	cta.add_theme_stylebox_override("normal", UI.flat(Color("ffe14d"), Color("ffffff"), 3, 12))
	cta.add_theme_stylebox_override("hover", UI.flat(Color("fff08a"), Color("ffffff"), 3, 12))
	cta.add_theme_stylebox_override("pressed", UI.flat(Color("e8c93a"), Color("ffffff"), 3, 12))
	cta.pressed.connect(_on_tapped)
	box.add_child(cta)

	if _ad.footnote != "":
		_add_centered(box, _ad.footnote, 15, Color(_ad.text_color, 0.75))

	_countdown_label = _add_centered(box, "", 18, Color(_ad.text_color, 0.8))

	# The X is a child of the frame, not the box, so its position is ours to abuse.
	_x_button = Button.new()
	_x_button.text = "✕"
	_x_button.add_theme_font_size_override("font_size", maxi(8, _ad.x_size_px - 6))
	_x_button.custom_minimum_size = Vector2(_ad.x_size_px, _ad.x_size_px)
	_x_button.size = Vector2(_ad.x_size_px, _ad.x_size_px)
	_x_button.add_theme_color_override("font_color", Color(_ad.text_color, 0.7))
	_x_button.add_theme_stylebox_override("normal", UI.flat(Color(0, 0, 0, 0.25)))
	_x_button.add_theme_stylebox_override("hover", UI.flat(Color(0, 0, 0, 0.45)))
	_x_button.position = Vector2(_W - _ad.x_size_px - 10, 10)
	_x_button.visible = false
	_x_button.pressed.connect(_on_closed_by_x)
	frame.add_child(_x_button)

	if not _ad.hand_path.is_empty():
		_build_hand(frame)

	Mirror.mark(&"ad_shown", String(_ad.id))

func _add_centered(parent: Node, text: String, size: int, color: Color) -> Label:
	var l := UI.label(text, size, color, HORIZONTAL_ALIGNMENT_CENTER)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(l)
	return l

## The incompetent cursor: the only animated thing in a real mobile ad, and the reason
## they work. It never picks right. A looping tween is 90% of the comedy for 20 lines.
func _build_hand(frame: Control) -> void:
	_hand = UI.label("👆", 64, Color.WHITE)
	frame.add_child(_hand)
	var tw := create_tween().set_loops()
	tw.tween_callback(func(): _hand.position = _ad.hand_path[0] * Vector2(_W, _H))
	for i in range(1, _ad.hand_path.size()):
		tw.tween_property(_hand, "position", _ad.hand_path[i] * Vector2(_W, _H),
			_ad.hand_leg_time).set_trans(Tween.TRANS_SINE)
	tw.tween_interval(0.35)

func _process(delta: float) -> void:
	if _done:
		return
	# Unscaled: the ad's dwell time is a real-world number and 2x must not shorten it.
	_elapsed += delta / maxf(Engine.time_scale, 0.0001)

	if _watching:
		var before := int(ceil(_watch_left))
		_watch_left -= delta / maxf(Engine.time_scale, 0.0001)
		var left := int(ceil(_watch_left))
		if left != before and _TAUNTS.has(left):
			_countdown_label.text = _TAUNTS[left]
		elif not _TAUNTS.has(left) and left > 0:
			_countdown_label.text = "%d" % left
		if _watch_left <= 0.0:
			_pay_out()
			_finish(true)
		return

	if not _x_button.visible and _elapsed >= _ad.x_delay:
		_x_button.visible = true

	if _ad.countdown_lies:
		var left: float = maxf(0.0, 5.0 - _elapsed)
		# Sticks on 3 instead of counting down. Then closes on its own at 3 anyway, so
		# the lie costs nothing and noticing it is the whole payload.
		var shown: int = maxi(3, int(ceil(left)))
		_countdown_label.text = "Skip in %d…" % shown
		if _elapsed >= 6.0:
			_finish(false)
			return

	if _ad.x_dodges and not _dodged and _x_button.visible:
		var local: Vector2 = _x_button.get_local_mouse_position()
		if local.length() < 90.0:
			_dodged = true
			# ONCE. A second dodge stops being a joke about ads and becomes one on the
			# player, and this game does not do that.
			_x_button.position = Vector2(14, _H - _ad.x_size_px - 14)

## Reward-video taunts, keyed by seconds REMAINING. The countdown is honest and the
## payout is real; the only thing the ad takes is the half-minute, and it names exactly
## what that half-minute was for.
const _TAUNTS := {
	20: "you're actually watching this.",
	10: "ten more seconds.",
	3: "you waited 30 seconds for pretend currency\nin a game about not doing that.",
}

func _on_tapped() -> void:
	if _done:
		return
	if _ad.reward_countdown > 0.0 and not _watching:
		_watching = true
		_watch_left = _ad.reward_countdown
		return
	_pay_out()
	_finish(true)

## The offer is real, which is the point. Knowing what it was does not appear to help,
## and that finding is the game's whole argument.
func _pay_out() -> void:
	if _ad.payload_dopamine != 0:
		GameState.add_dopamine(_ad.payload_dopamine)
	if _ad.payload_tolerance != 0.0:
		GameState.set_tolerance(GameState.tolerance + _ad.payload_tolerance)
	if _ad.payload_craving != 0.0:
		GameState.add_craving(_ad.payload_craving)
	Mirror.mark(&"ad_tapped", String(_ad.id))

func _on_closed_by_x() -> void:
	_finish(false)

func _finish(tapped: bool) -> void:
	if _done:
		return
	_done = true
	Mirror.mark(&"ad_span", _elapsed)
	closed.emit(tapped, _elapsed)
	queue_free()
