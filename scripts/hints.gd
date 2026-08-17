class_name HintLayer
extends Control
## One-shot contextual hints + per-run enemy introductions, shown as queued toasts
## under the top bar. Both share this widget because they are the same interaction —
## a short card that arrives, explains one thing, and leaves.
##
##   show_hint(id)          — persisted one-shots: each id ever shows ONCE per save
##                            (MetaProgression.hints_seen), toggleable in Settings.
##   show_enemy_intro(def)  — per-run: first spawn of each distraction type gets a
##                            name + description + derived trait chip.
##
## Explicitly PROCESS_MODE_PAUSABLE: parented under the game's _hud_root (ALWAYS),
## a toast would otherwise keep its dismiss timer running behind the pause menu's dim
## and expire unseen.

const HINTS := {
	"first_build":
		"Habit placed. It fires only during waves — and only while inside your Routine. "
		+ "The glowing tether shows what holds each habit up.",
	"first_aim":
		"Aim with the mouse: direction sets the cone's facing, DISTANCE sets its width — "
		+ "close is wide, far is narrow. Left-click locks it, right-click cancels. "
		+ "Same energy either way: narrow = fewer, harder shots that pierce and shove; "
		+ "wide = a faster, softer wall. Scroll over the habit's panel to retune it anytime.",
	"no_routine":
		"A habit outside your Routine stalls and does nothing. Build an Anchor near it "
		+ "to extend the Routine, or build closer to your Focus core.",
	"first_draft":
		"Cards cost Insight — the same currency the Growth Tree spends between runs. "
		+ "Buy now to survive, or bank it for permanent upgrades. Skipping is allowed.",
	"quick_hit":
		"Quick Hit pays now, but every use permanently raises your Tolerance floor — "
		+ "ALL rewards shrink for the rest of the level. Borrowed, not free.",
	"boss_shield":
		"The Denial Shield blocks every direct hit. Damage over time still lands "
		+ "through it — or hold fire until the shield drops.",
	"first_lean":
		"A lean wave: defeats pay no Dopamine here. What you saved — and the "
		+ "early-call bonus — is what you have.",
}

const HINT_SECONDS := 8.0
const INTRO_SECONDS := 5.0

var _queue: Array[Control] = []
var _current: Control = null
var _slot: CenterContainer

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_slot = CenterContainer.new()
	_slot.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_slot.offset_top = 84
	_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_slot)

func show_hint(id: String) -> void:
	if not MetaProgression.current_save.hints_enabled:
		return
	if not HINTS.has(id) or MetaProgression.is_hint_seen(id):
		return
	MetaProgression.mark_hint_seen(id)
	_enqueue(_make_toast("💡", null, "", HINTS[id], HINT_SECONDS, true))

## Per-run, not persisted — game.gd tracks which types this run has already met.
func show_enemy_intro(def: DistractionData) -> void:
	if not MetaProgression.current_save.hints_enabled:
		return
	_enqueue(_make_toast("", Color(def.color), def.display_name,
		_intro_text(def), INTRO_SECONDS, false))

func _intro_text(def: DistractionData) -> String:
	var trait_line := _trait_for(def)
	if trait_line != "":
		return "%s\n%s" % [def.description, trait_line]
	return def.description

## One derived chip, first match wins — the single most tactically relevant fact.
func _trait_for(def: DistractionData) -> String:
	if def.is_flying:
		return "◈ Flying — ignores walls and blockers, heads straight for your Focus"
	if def.is_boss or def.shield_interval > 0.0:
		return "◈ Shielded — periodically immune to direct hits"
	if "disrupt_interval" in def and def.disrupt_interval > 0.0:
		return "◈ Disruptor — pings your habits and briefly stops them"
	# Above the plain armour line on purpose: these archetypes all carry high compulsion
	# too, and "Armored" would be the true-but-useless answer for every one of them.
	if "haste_interval" in def and def.haste_interval > 0.0:
		return "◈ Energiser — speeds up everything around it. Kill it first"
	if "overdrive_hp_pct" in def and def.overdrive_hp_pct > 0.0:
		return "◈ Overdrive — wounding it makes it faster. Finish what you start"
	if "fast_shot_damage_mult" in def and def.fast_shot_damage_mult < 1.0:
		return "◈ Doughy — shrugs off rapid fire, gives way to AoE and boredom"
	if def.compulsion >= 3:
		return "◈ Armored — resists %s" % Data.TERM.damage
	if def.speed >= 110.0:
		return "◈ Fast"
	return ""

# ---------------------------------------------------------------- toast plumbing

func _enqueue(toast: Control) -> void:
	_queue.append(toast)
	if _current == null:
		_show_next()

func _show_next() -> void:
	if _queue.is_empty():
		_current = null
		return
	_current = _queue.pop_front()
	_slot.add_child(_current)
	# The dismiss timer starts when the toast is SHOWN, not when it was queued —
	# otherwise a toast waiting behind another would expire before its turn.
	# false => the SceneTreeTimer pauses with the tree, so a toast can't expire
	# unseen behind the pause menu either.
	var toast := _current
	get_tree().create_timer(float(toast.get_meta("toast_seconds", HINT_SECONDS)), false) \
		.timeout.connect(func(): _dismiss(toast))

func _dismiss(toast: Control) -> void:
	if toast != _current:
		return   # a stale auto-dismiss timer for an already-closed toast
	_current.queue_free()
	_current = null
	_show_next()

func _make_toast(icon: String, swatch_color, title: String, body: String,
		seconds: float, got_it: bool) -> Control:
	var panel := UI.panel(UI.BORDER_HI, 1)
	panel.custom_minimum_size = Vector2(560, 0)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	panel.add_child(row)

	if swatch_color != null:
		var swatch := ColorRect.new()
		swatch.color = swatch_color
		swatch.custom_minimum_size = Vector2(16, 16)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(swatch)
	elif icon != "":
		row.add_child(UI.label(icon, UI.FS_HEAD, UI.ACCENT))

	var text_box := VBoxContainer.new()
	text_box.add_theme_constant_override("separation", 2)
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text_box)
	if title != "":
		text_box.add_child(UI.label(title, UI.FS_BODY, UI.TEXT))
	text_box.add_child(UI.wrapped(body, 460, UI.FS_SMALL, UI.TEXT_DIM))

	if got_it:
		var ok := UI.button("Got it", UI.FS_SMALL)
		ok.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		ok.pressed.connect(func(): _dismiss(panel))
		row.add_child(ok)
	else:
		# Intros dismiss on any click — they are information, not a decision.
		panel.gui_input.connect(func(event: InputEvent):
			if event is InputEventMouseButton and event.pressed:
				_dismiss(panel))

	panel.set_meta("toast_seconds", seconds)
	return panel
