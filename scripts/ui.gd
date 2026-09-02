class_name UI extends RefCounted
## Shared visual language for every screen in the game.
##
## Every UI in this project is built in code, which is fine — but it meant colours and
## font sizes were hex literals scattered across game.gd, menu.gd, level_select.gd,
## education.gd, game_over.gd and victory.gd, drifting apart with every edit. This file
## is the single source: change a token here and it changes everywhere.
##
## Use `UI.theme()` on a root Control and the whole subtree inherits button/panel/label
## styling for free — no per-widget overrides needed for the common cases.

# ---------------------------------------------------------------- palette
#
# Dark, low-chroma ground so the play field reads, with one saturated accent per
# meaning. Colour carries information here: a player should be able to tell Dopamine
# from Insight from Focus without reading a word.

const BG          := Color("0a0c14")   ## Page background.
const SURFACE     := Color("111524")   ## Bars and chrome sitting on the background.
const PANEL       := Color("161b2c")   ## Cards, panels, popovers.
const PANEL_HI    := Color("1e2438")   ## Hovered/raised panel.
const TRACK       := Color("0d1120")   ## Empty part of a meter.
const BORDER      := Color("262c40")   ## Default hairline.
const BORDER_HI   := Color("3d5a99")   ## Focused/affordable outline.

const TEXT        := Color("e6eaf5")   ## Primary copy.
const TEXT_DIM    := Color("8a90a8")   ## Secondary copy, captions.
const TEXT_FAINT  := Color("5b6178")   ## Disabled, hints.

## One accent per game noun — these are the game's vocabulary in colour form.
const DOPAMINE    := Color("ffd479")   ## The fast currency.
const INSIGHT     := Color("7ef2e6")   ## The slow currency.
const FOCUS       := Color("7cffb2")   ## Your attention / base health.
const TOLERANCE   := Color("ff8a3d")   ## Downregulation.
const DANGER      := Color("ff6b6b")   ## Loss, costs, warnings.
const ACCENT      := Color("9bd0ff")   ## Neutral highlight, headings.

# ---------------------------------------------------------------- type scale
#
# A real scale rather than ad-hoc sizes. Six steps is enough for a game HUD and stops
# the "is this 15 or 16px?" drift that makes a UI feel unconsidered.

## T5 topdown migration (2026-08-29): project.godot's canvas shrank 1920x1080 -> 480x270
## (exactly /4) for the square-projection pixel-art rescale — GridProjection.gd's own
## header comment and BLOCKED.md's T5 entry cover why. These six sizes were tuned for the
## old canvas and are divided by the same /4 here so nothing overflows its container at
## the new resolution; not a fresh design pass. At native pixel sizes this small a
## generic vector fallback font will likely look rough once nearest-filter-upscaled 4x —
## a real, flagged follow-up (candidates: a dedicated small pixel font, or splitting HUD
## text onto a viewport that isn't subject to the low-res rescale), not something to
## silently call finished.
const FS_DISPLAY := 12
const FS_TITLE   := 8
const FS_HEAD    := 5
const FS_BODY    := 4
const FS_SMALL   := 3
const FS_MICRO   := 3

const RADIUS     := 2
const RADIUS_SM  := 1

## The /4 above reached the font sizes and STOPPED THERE. Every number below is a
## style-box CONTENT MARGIN and each was still the 1920x1080 value until 2026-09-02:
## a Button wrapped 4 px text in 10 px of padding per side, so 20 of a habit button's
## 33 px was padding. With up to 24 controls in the bottom bar that alone is ~440 px
## on a 480 px canvas, which is why _build_bottom_bar's row measured 690 px wide and put
## Start Wave -- the one call to action -- entirely off screen (measured by
## scenes/_shot_scale_audit.tscn, not eyeballed). Same /4, applied late.
const PAD_BUTTON  := 2   # was 10
const PAD_PANEL   := 4   # was 14
const PAD_TOOLTIP := 2   # was 8
const PAD_CHIP    := 2   # was 8

# ---------------------------------------------------------------- style boxes

static func flat(bg: Color, border: Color = Color.TRANSPARENT, border_width: int = 0,
		radius: int = RADIUS, margin: int = 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	if border_width > 0:
		s.border_color = border
		s.set_border_width_all(border_width)
	s.set_corner_radius_all(radius)
	if margin > 0:
		s.set_content_margin_all(margin)
	return s

## Panel with a hairline border — the default container look.
static func card_style(border_color: Color = BORDER, border_width: int = 1,
		bg: Color = PANEL) -> StyleBoxFlat:
	return flat(bg, border_color, border_width, RADIUS, PAD_PANEL)

# ---------------------------------------------------------------- theme
#
# Built once and shared. Assign with `some_control.theme = UI.theme()`; children inherit,
# so a screen only overrides where it genuinely differs.

static var _theme: Theme = null

static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font_size = FS_BODY

	# --- Button: flat, quiet at rest, clearly reactive. Godot's stock button chrome
	# reads as a desktop app dialog, which is what made the draft screen look unfinished.
	t.set_stylebox("normal", "Button", flat(PANEL, BORDER, 1, RADIUS_SM, PAD_BUTTON))
	t.set_stylebox("hover", "Button", flat(PANEL_HI, BORDER_HI, 1, RADIUS_SM, PAD_BUTTON))
	t.set_stylebox("pressed", "Button", flat(TRACK, BORDER_HI, 1, RADIUS_SM, PAD_BUTTON))
	t.set_stylebox("focus", "Button", flat(Color.TRANSPARENT, BORDER_HI, 1, RADIUS_SM, PAD_BUTTON))
	t.set_stylebox("disabled", "Button", flat(SURFACE, BORDER, 1, RADIUS_SM, PAD_BUTTON))
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", ACCENT)
	t.set_color("font_disabled_color", "Button", TEXT_FAINT)
	t.set_font_size("font_size", "Button", FS_BODY)

	t.set_color("font_color", "Label", TEXT)
	t.set_stylebox("panel", "PanelContainer", card_style())

	t.set_color("font_color", "TooltipLabel", TEXT)
	t.set_stylebox("panel", "TooltipPanel", flat(SURFACE, BORDER, 1, RADIUS_SM, PAD_TOOLTIP))

	_theme = t
	return t

# ---------------------------------------------------------------- builders

static func label(text: String, size: int = FS_BODY, color: Color = TEXT,
		align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	# Display-only by default: a Label that eats clicks over the play field is a bug
	# that only shows up as "the map stopped responding in one corner".
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

static func wrapped(text: String, width: float, size: int = FS_BODY,
		color: Color = TEXT_DIM, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := label(text, size, color, align)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(width, 0)
	return l

static func button(text: String, size: int = FS_BODY,
		min_size: Vector2 = Vector2.ZERO) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	if min_size != Vector2.ZERO:
		b.custom_minimum_size = min_size
	# Every button clicks (primary_button routes through here too). The Sfx autoload is
	# looked up through the tree at press time — autoload identifiers don't resolve
	# inside a static factory, and a missing Sfx must never break a button.
	b.pressed.connect(func():
		var sfx: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null(^"/root/Sfx")
		if sfx != null:
			sfx.play(&"click"))
	return b

## The one call-to-action on a screen. Filled rather than outlined, so there is never a
## question about where to click next.
static func primary_button(text: String, tint: Color = FOCUS, size: int = FS_HEAD,
		min_size: Vector2 = Vector2.ZERO) -> Button:
	var b := button(text, size, min_size)
	var base := Color(tint.r * 0.22, tint.g * 0.22, tint.b * 0.22, 1.0)
	var hi := Color(tint.r * 0.34, tint.g * 0.34, tint.b * 0.34, 1.0)
	b.add_theme_stylebox_override("normal", flat(base, tint, 1, RADIUS_SM, PAD_BUTTON))
	b.add_theme_stylebox_override("hover", flat(hi, tint, 2, RADIUS_SM, PAD_BUTTON))
	b.add_theme_stylebox_override("pressed", flat(base, tint, 2, RADIUS_SM, PAD_BUTTON))
	b.add_theme_stylebox_override("disabled", flat(SURFACE, BORDER, 1, RADIUS_SM, PAD_BUTTON))
	b.add_theme_color_override("font_color", tint)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	return b

static func panel(border_color: Color = BORDER, border_width: int = 1,
		bg: Color = PANEL) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", card_style(border_color, border_width, bg))
	# Godot's Container defaults to MOUSE_FILTER_PASS, so every non-button pixel of a
	# panel — padding, title, stat lines — fell through to the play field underneath.
	# On the in-game upgrade panel that meant clicking its own margin closed it AND acted
	# on the cell it was covering.
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	return p

static func spacer(min_size: Vector2 = Vector2.ZERO, expand: bool = false) -> Control:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if min_size != Vector2.ZERO:
		c.custom_minimum_size = min_size
	if expand:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c

## A compact "LABEL / value" readout for the HUD bar. Returns the panel; the value Label
## is handed back through `out_value` so the caller can keep updating it.
static func stat_chip(caption: String, accent: Color, out_value: Array,
		value_size: int = FS_HEAD) -> PanelContainer:
	var p := panel(BORDER, 1, SURFACE)
	p.add_theme_stylebox_override("panel", flat(SURFACE, BORDER, 1, RADIUS_SM, PAD_CHIP))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	p.add_child(box)
	box.add_child(label(caption.to_upper(), FS_MICRO, TEXT_FAINT))
	var value := label("—", value_size, accent)
	box.add_child(value)
	out_value.append(value)
	return p
