# 13 — Extended HUD & UI (Cards, Abilities, Growth Tree)

This doc extends the base HUD (`09`) with the UI for three new systems: the **card draft screen**
(`10`), the **intervention buttons** (`12`), and the **Growth Tree** (`11`). All UI lives in a
`CanvasLayer` (layer 100) with `process_mode = ALWAYS` so menus work while the field is paused.

> Theme reminder (see `00_overview.md`): "gold" is **Dopamine**, "lives" is **Focus**, the skill
> tree is the **Growth Tree**, "spells" are **interventions**, and card names use the themed
> vocabulary from `10`.

## 1. Complete UI hierarchy

```text
UILayer (CanvasLayer) [Layer: 100, process_mode: ALWAYS]
├── GameHUD (Control) [Full Rect]
│   ├── TopBar (HBoxContainer)         # Dopamine · Focus · Wave · Tolerance
│   ├── BottomBar (HBoxContainer)      # Intervention buttons (Screen Break, Deep Breath, …)
│   └── CallWaveButton (Button)        # appears between waves (08)
├── BuildMenu (Control)                # radial menu over high-ground spots (07)
├── DraftScreen (ColorRect)            # shown between waves for card selection (10)
│   └── HBoxContainer                  # 3 × CardUI (PanelContainers)
├── InsightCard (Control)              # between-level education card (08)
├── PauseMenu (ColorRect)
├── GameOverScreen (ColorRect)
└── GrowthTreeScreen (Control)         # shown only in Menu.tscn (11)
```

## 2. Draft screen (card selection between waves)

When a wave clears, if the wave number is a draft trigger (e.g. every 3rd wave), the game pauses
and the `DraftScreen` appears, offering 3 random cards from the pool. The player picks one; it is
added to `ModifierManager` (`10`), and play resumes.

```gdscript
# Inside UIManager.gd

@export var draft_screen: Control
@export var draft_card_container: HBoxContainer
@export var card_pool: Array[CardData]

func _ready() -> void:
    SignalBus.wave_completed.connect(_on_wave_completed)
    draft_screen.hide()

func _on_wave_completed(wave_number: int) -> void:
    if wave_number % 3 == 0:
        _show_draft_screen()

func _show_draft_screen() -> void:
    get_tree().paused = true
    draft_screen.show()

    # Clear old options.
    for child in draft_card_container.get_children():
        child.queue_free()

    # Pick 3 random unique cards.
    var options := card_pool.duplicate()
    options.shuffle()

    for i in range(mini(3, options.size())):
        var card_ui := preload("res://scenes/ui/CardUI.tscn").instantiate()
        draft_card_container.add_child(card_ui)
        card_ui.setup(options[i])
        card_ui.card_selected.connect(_on_card_drafted.bind(options[i]))

func _on_card_drafted(selected_card: CardData) -> void:
    ModifierManager.add_card(selected_card)
    draft_screen.hide()
    get_tree().paused = false
    # Next wave starts automatically or the player clicks CallWaveButton.
```

### CardUI scene

Each `CardUI` is a `PanelContainer` showing the card's `title`, `description`, and `icon`. On
click it emits `card_selected`. Cards with names like "Deep Work Session" and "Digital Detox"
reinforce the theme.

## 3. Intervention buttons on the HUD

The `BottomBar` contains `TextureButton` nodes, one per available intervention (`12`). Each button
shows a cooldown sweep overlay while the ability is recharging.

```gdscript
# InterventionButtonUI.gd

extends TextureButton

@export var intervention_manager: InterventionManager
@export var cooldown_overlay: TextureProgressBar

func _ready() -> void:
    intervention_manager.cooldown_updated.connect(_update_cooldown)
    pressed.connect(_on_pressed)

func _update_cooldown(time_left: float) -> void:
    if time_left > 0:
        disabled = true
        cooldown_overlay.show()
        cooldown_overlay.value = (time_left / intervention_manager.intervention_data.cooldown) * 100
    else:
        disabled = false
        cooldown_overlay.hide()

func _on_pressed() -> void:
    intervention_manager.start_targeting()
```

## 4. Growth Tree UI (main menu)

The Growth Tree is a separate screen in `Menu.tscn`. It reads from `MetaProgression` (`11`).

Each `GrowthNodeUI` (a `Button`) checks:

- `MetaProgression.has_growth(id)` → colour it **gold** (unlocked).
- Dependencies met but not purchased → colour it **normal** (available, show Clarity Star cost).
- Dependencies not met → **disabled** (greyed out).

Themed node names reinforce the growth metaphor: "Deep Sleep", "Morning Routine", "Neuroplasticity"
(see `11` for the full table).

## 5. Signal flow summary

```text
wave_completed(n) ──▶ UIManager._on_wave_completed()
                          │
                          ├── n % 3 == 0 → DraftScreen (pause, pick card)
                          │                  └── ModifierManager.add_card()
                          │                        └── modifiers_updated → Habit._recalculate_stats()
                          │
                          └── else → CallWaveButton.show() or auto-advance
```

## Intersection with the prototype

**More built than "additive future work" — three of the five "not built yet" items below are
actually live.** The prototype's HUD (`game.gd._build_hud()`, documented in `09`) already has:

- **TopBar** with Dopamine, Focus, Wave, Tolerance labels. ✔
- **BottomBar** with habit-select buttons, intervention buttons, and Quick Hit button. ✔
- **Floating "+X" Dopamine pops** on distraction defeat. ✔
- **Intervention buttons** (`12`) — real, in `_build_hud()`, live cooldown countdown text on the
  button itself rather than a radial `TextureProgressBar` sweep. ✔
- **Growth Tree screen** (`11`) — real, in `menu.gd` (`_open_growth_tree()`), a code-built overlay
  in `Menu.tscn` matching this doc's intent. ✔
- **Upgrade/sell panel** (`07`) — real, a code-built linear `PanelContainer`, not the radial menu
  described below; also includes a "Re-Aim Cone" button this doc doesn't mention at all.
- **Draft screen** (`10`) — fully built (`_show_draft_screen()`, 3 random cards, a "Skip this round"
  button this doc doesn't mention) and, as of the wave-trigger fix described in `10`, reachable too:
  it now fires once per level, right before the final wave. ✔

**Genuinely not built:**
- Insight card screen is a separate scene (`Education.tscn`) reached via a full scene swap, not
  integrated into one persistent `UILayer` — there is no persistent `UILayer` at all; every screen
  (`Menu`, `Game`, `Education`, `GameOver`) is its own bare-root `.tscn` that builds its own UI in
  code and hands off via `change_scene_to_file()`.
- True radial build/upgrade/sell menu — today's panel is a fixed-position linear list, not a
  radial layout around the clicked cell.

## Implementation checklist

- [ ] `UILayer` is a `CanvasLayer`, `layer = 100`, `process_mode = ALWAYS` — each screen has its
      own `CanvasLayer` HUD instead of one persistent layer shared across scene swaps.
- [x] `DraftScreen` pauses the tree, displays 3 random `CardData` options, and applies the
      choice to `ModifierManager` (`10`).
- [ ] `InterventionButtonUI` uses a `TextureProgressBar` for a radial cooldown sweep over the icon —
      real cooldown feedback exists, as button text, not a radial sweep.
- [x] `GrowthTreeScreen` reads `MetaProgression.has_growth()` and colours nodes accordingly.
- [ ] HUD components use correct Godot anchor presets (`Top Wide`, `Bottom Wide`) for resolution
      independence — current HUD uses fixed pixel positions sized for the fixed `1920x1080` canvas.
- [x] `mouse_filter = IGNORE` on all visual labels/wrappers — the bug from `09` applies here too.
