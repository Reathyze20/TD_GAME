# 09 — HUD & UI

The UI is **reactive**: it never polls in `_process()`. It listens to `SignalBus` (see `03`) and
updates only when a value changes. Everything lives in a `CanvasLayer` so it scales cleanly and
never tangles with the 2.5D Y-sorted world.

> Theme: the HUD shows **Dopamine** (currency), **Focus** (base health), **Wave**, and — from level
> 2 — **Tolerance** plus the **Quick Hit** button. Between levels it shows an **insight card** (08).

## 1. Screen hierarchy

Distinct screens; only the HUD is visible during play.

```text
Level (Node2D)
└── UILayer (CanvasLayer) [Layer 100, process_mode = ALWAYS]
    ├── HUD (Control) [Full Rect]
    │   ├── TopBar (HBoxContainer)  # Dopamine · Focus · Wave · Tolerance
    │   ├── BuildBar (HBoxContainer) # habit buttons + Quick Hit
    │   └── CallWaveButton (Button)  # appears when a wave is ready (08)
    ├── BuildMenu (Control)          # radial menu over a high-ground spot (07)
    ├── PauseMenu (ColorRect)        # dark overlay, hidden by default
    ├── GameOverScreen (ColorRect)   # hidden by default
    └── InsightCard (Control)        # between-level education card (08)
```

## 2. The HUD script (`HUD.gd`)

Connects readouts to global state via the bus.

```gdscript
class_name HUD extends Control

@export var dopamine_label: Label
@export var focus_label: Label
@export var wave_label: Label
@export var tolerance_label: Label

func _ready() -> void:
	SignalBus.dopamine_changed.connect(_on_dopamine)
	SignalBus.focus_changed.connect(_on_focus)
	SignalBus.wave_started.connect(_on_wave)
	SignalBus.tolerance_changed.connect(_on_tolerance)

	_on_dopamine(GameState.dopamine, 0)
	_on_focus(GameState.focus, GameState.max_focus)
	_on_tolerance(int(GameState.tolerance))
	tolerance_label.visible = GameState.quick_hit_enabled

func _on_dopamine(current: int, difference: int) -> void:
	dopamine_label.text = "Dopamine: %d" % current
	# Optional: float a green "+X" when difference > 0.

func _on_focus(current: int, max_value: int) -> void:
	focus_label.text = "Focus: %d/%d" % [current, max_value]
	if current <= 5 and current > 0:
		focus_label.modulate = Color.RED   # danger

func _on_wave(n: int) -> void:
	wave_label.text = "Wave: %d/%d" % [n, GameState.max_wave]

func _on_tolerance(v: int) -> void:
	tolerance_label.text = "Tolerance: %d%%" % v
```

## 3. Pause & game over (`UIManager.gd`)

Pausing uses `process_mode`. The `Level` is `PAUSABLE`; the `UILayer` is **`ALWAYS`** so menus keep
working while the field freezes.

```gdscript
class_name UIManager extends CanvasLayer

@export var hud: Control
@export var pause_menu: Control
@export var game_over_menu: Control
@export var result_label: Label

func _ready() -> void:
	SignalBus.game_over.connect(_on_game_over)
	pause_menu.hide()
	game_over_menu.hide()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and \
			GameState.current_state in [GameState.MatchState.DEFENDING, GameState.MatchState.PREP]:
		_toggle_pause()

func _toggle_pause() -> void:
	get_tree().paused = not get_tree().paused
	pause_menu.visible = get_tree().paused

func _on_game_over(victory: bool) -> void:
	get_tree().paused = true
	hud.hide()
	game_over_menu.show()
	result_label.text = "FOCUS RESTORED" if victory else "FOCUS DEPLETED"
	result_label.modulate = Color("2bd6c0") if victory else Color("ff6b6b")

func _on_restart_pressed() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()   # Level._ready() re-runs GameState.reset_match()
```

## 4. Anchors & responsiveness

- Use **anchor presets**, not hardcoded pixels. `TopBar` → *Top Wide*; `BuildBar` → *Bottom Wide*.
- Wrap edges in `MarginContainer` (~16 px) so text never touches the screen edge.
- **`mouse_filter = IGNORE`** on every purely-visual label/wrapper. (See the callout below — this
  bit us for real.)

## Intersection with the prototype

The prototype's HUD is **built in code** inside `game.gd` (`_build_hud()`): a `CanvasLayer` with
Dopamine/Focus/Wave/Tolerance labels, habit buttons, a Quick Hit button, a centered message label,
and floating "+X" dopamine pops. It already matches this doc's *behavior*; it just isn't a separate
`.tscn` yet.

> **⚠️ Real bug we already hit and fixed (keep it fixed):** a full-width, invisible centered
> `Label` defaults to `mouse_filter = STOP` and **silently ate clicks** meant for the field —
> making central high-ground tiles un-buildable. **All display labels must be `MOUSE_FILTER_IGNORE`.**
> The prototype also builds on the **highlighted hover cell**, so "you build where the green frame
> is." See `07` for the build interaction.

- **MVP now:** code-built HUD; single `GameState` acts as the bus.
- **Target:** extract `HUD.tscn` + `UIManager.tscn`, wire to a real `SignalBus`, add the radial
  build/upgrade menu (`07`) and the insight-card screen (`08`).

## Implementation checklist

- [ ] `UILayer` is a `CanvasLayer`, `layer = 100`, `process_mode = ALWAYS`.
- [ ] Every readout updates from a `*_changed` signal — no `_process()` polling.
- [ ] `mouse_filter = IGNORE` on all visual labels/wrappers.
- [ ] Field clicks are ignored while a menu/UI owns the pointer
      (`get_viewport().gui_get_hovered_control()` / `gui_is_dragging()` — see `07`).
