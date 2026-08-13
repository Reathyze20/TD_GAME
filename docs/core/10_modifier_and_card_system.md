# 10 — Modifier & Card System (Roguelike Drafting)

To add replayability and dynamic scaling, the player **drafts a card** between waves (or at
specific wave intervals). Cards apply global **modifiers** that buff habits, debuff distractions,
or alter the Dopamine economy. Because we use a data-driven architecture (`02`), cards are just
`Resource` files, and a central `ModifierManager` stores the active modifiers and recalculates
habit stats when a new card is drafted.

> Theme reminder (see `00_overview.md`): "towers" are **habits**, "enemies" are **distractions**,
> "gold" is **Dopamine**, and the two damage channels are **Willpower** and **Awareness**.
> Card names and descriptions should reinforce the attention/dopamine theme — e.g. "Deep Work
> Session" (habit damage buff), "Digital Detox" (distraction slow), "Reward Scheduling"
> (Dopamine bonus).

## 1. Card data (`CardData.gd`)

Defines what the card does. `StatType` categorizes the stat being modified; `TargetHabit` scopes
which habits receive the buff.

```gdscript
class_name CardData extends Resource

enum StatType {
    HABIT_WILLPOWER,       # buff habit Willpower damage
    HABIT_AWARENESS,       # buff habit Awareness damage
    HABIT_RANGE,           # buff habit attack range
    HABIT_FIRE_RATE,       # buff habit fire cooldown (lower = faster)
    DISTRACTION_SPEED,     # debuff distraction movement speed
    DOPAMINE_BONUS,        # economy: bonus Dopamine per defeat
}

enum TargetHabit {
    ALL,                   # affects every habit type
    FOCUS_TIMER,           # Pomodoro — single-target
    MINDFULNESS,           # AoE + Calm
    EXERCISE,              # heavy hitter
    ACCOUNTABILITY,        # deploys Allies (06)
}

@export_category("Identity")
@export var id: StringName = &"card_base"
@export var title: String = "Unknown Buff"
@export_multiline var description: String = "Modifies a stat."
@export var icon: Texture2D

@export_category("Effect")
@export var stat_type: StatType
@export var target_habit: TargetHabit = TargetHabit.ALL
## E.g., 0.1 for +10% bonus, or 5.0 for +5 flat Willpower.
@export var modifier_value: float = 0.0
## Is the modifier a flat addition or a percentage multiplier?
@export var is_percentage: bool = true
```

### Example cards (themed)

| id | Title | StatType | Target | Value | Flavour |
|---|---|---|---|---|---|
| `deep_work` | Deep Work Session | `HABIT_WILLPOWER` | ALL | +15% | "Undivided attention hits harder." |
| `breath_focus` | Breath Focus | `HABIT_RANGE` | MINDFULNESS | +20% | "Calm radiates further." |
| `runners_high` | Runner's High | `HABIT_FIRE_RATE` | EXERCISE | −10% cooldown | "Endorphins accelerate recovery." |
| `digital_detox` | Digital Detox | `DISTRACTION_SPEED` | — | −15% | "Stepping away slows the feed." |
| `reward_schedule` | Reward Scheduling | `DOPAMINE_BONUS` | — | +2 flat | "Planned rewards feel bigger." |

## 2. Modifier manager (`ModifierManager.gd`)

Tracks drafted cards and provides an API for habits to calculate their final stats. Can be an
autoload or placed in the `Level` scene.

```gdscript
extends Node
## AUTOLOAD: ModifierManager — tracks active drafted cards and calculates final stats.

var active_cards: Array[CardData] = []

signal modifiers_updated

func add_card(card: CardData) -> void:
    active_cards.append(card)
    modifiers_updated.emit()

func reset() -> void:
    active_cards.clear()
    modifiers_updated.emit()

func get_modified_stat(base_stat: float, stat_type: CardData.StatType,
        habit_type: CardData.TargetHabit = CardData.TargetHabit.ALL) -> float:
    var flat_bonus: float = 0.0
    var multi_bonus: float = 1.0

    for card in active_cards:
        if card.stat_type != stat_type:
            continue
        if card.target_habit != CardData.TargetHabit.ALL and card.target_habit != habit_type:
            continue
        if card.is_percentage:
            multi_bonus += card.modifier_value
        else:
            flat_bonus += card.modifier_value

    return (base_stat + flat_bonus) * multi_bonus
```

## 3. Applying modifiers to habits

Update `Habit.gd` (`05`) to listen for the `modifiers_updated` signal and recalculate its combat
stats. This keeps the habit's `HabitData` immutable while allowing runtime buffs.

```gdscript
# Inside Habit.gd

var base_willpower: int
var base_awareness: int
var current_willpower: int
var current_awareness: int
var habit_type: CardData.TargetHabit    # assigned in setup()

func setup(habit_data: HabitData) -> void:
    # ... previous setup code ...
    base_willpower = data.willpower_damage
    base_awareness = data.awareness_damage

    ModifierManager.modifiers_updated.connect(_recalculate_stats)
    _recalculate_stats()                 # initial calculation

func _recalculate_stats() -> void:
    current_willpower = int(ModifierManager.get_modified_stat(
        float(base_willpower),
        CardData.StatType.HABIT_WILLPOWER,
        habit_type
    ))
    current_awareness = int(ModifierManager.get_modified_stat(
        float(base_awareness),
        CardData.StatType.HABIT_AWARENESS,
        habit_type
    ))

    var new_range := ModifierManager.get_modified_stat(
        data.attack_range,
        CardData.StatType.HABIT_RANGE,
        habit_type
    )
    # Update the physical detection circle.
    var circle := range_shape.shape as CircleShape2D
    circle.radius = new_range
```

## 4. Thematic integration

Cards reinforce the game's educational message:

- **Buff cards** are named after real healthy behaviours (Deep Work, Breath Focus, Runner's High),
  teaching that *investing in good habits compounds*.
- **Economy cards** (Reward Scheduling) mirror how *planned, spaced rewards* produce better
  dopaminergic outcomes than random quick hits.
- **Debuff cards** (Digital Detox) show that *setting boundaries weakens distractions*.
- **Two-sided cards** (Quick Fix, Always On, Bigger Screen, Borrowed Focus, All-Nighter) are the
  strongest teaching tool in the set: each buys genuine power with a genuine cost, so the player
  *chooses* their trade-off instead of collecting free upgrades. They carry signature mechanic 2
  from `00_overview.md` — cheap dopamine now is borrowed, and you repay it — into the draft itself.

Card descriptions should be one-liners — concise, non-preachy, evidence-flavoured.

## Two-sided cards and the Tolerance floor

A card is a title plus an **`effects` array**; each effect is one stat modifier with its own
`target`, so a single card can raise one habit while slowing every other, or sharpen the player
while speeding up the feed. Costs come in two flavours:

- **Stat costs** — an effect that helps the distractions (`distraction_speed +18%`,
  `distraction_health +25%`) or weakens the economy (`dopamine_bonus -2`).
- **`tolerance_cost`** — the sharpest one, and the reason this system exists. It raises
  `GameState.tolerance_floor`, a **baseline Tolerance that decay cannot erode**. Quick Hit spikes
  still recover fully; a card's cost does not. That asymmetry is the point: it models
  downregulation as it actually works — the baseline moves and stays moved — and because
  `_on_distraction_defeated()` scales every reward by `1 - 0.6 * (tolerance/100)`, the player feels
  it on every single kill for the rest of the level.

Two constraints this imposes on future work:

- **A cost the player cannot see is not a trade-off, it is a trap.** The Tolerance readout was
  originally gated on `quick_hit_enabled` (level 2 only), which would have made a `tolerance_cost`
  card silently punish level-1 players. It now also shows whenever `tolerance_floor > 0`.
- **Reward is floored at 1 Dopamine** after `dopamine_bonus` is applied. Without that floor a
  negative bonus subtracts Dopamine on a kill and prints a `+-1` popup.

## Intersection with the prototype

**Built and wired end-to-end, and now reachable in play.** `ModifierManager`
(`scripts/modifier_manager.gd`) is a real autoload with `add_card()` / `reset()` /
`get_modified_stat()` matching this doc's API almost exactly (cards are plain `Dictionary`s from
`Data.MODIFIER_CARDS` — 13 of them, themed — rather than `CardData` Resources, and
`StatType`/`TargetHabit` are string constants, not enums). One divergence worth knowing: a card
holds an **`effects` array**, not the single `stat_type`/`value` pair this doc's schema implies, so
`get_modified_stat()` sums across every effect of every active card. Growth Tree modifiers (`11`)
use the same shape. `Habit` (`tower.gd`) already connects to
`modifiers_updated` and calls `_recalculate_stats()` exactly as §3 describes, and `Distraction`
(`enemy.gd`) also consumes it for `digital_detox`-style speed debuffs. The draft screen itself is
fully built in `game.gd` (`_show_draft_screen()` / `_make_card_ui()` / `_on_card_picked()`) as a
code-built overlay with a "Skip this round" option this doc doesn't even mention — not `13`'s
`CardUI.tscn`, but functionally equivalent.

**Fixed (was previously unreachable):** `game.gd::_check_wave_progress()` used to gate
`_show_draft_screen()` on `(wave_index + 1) % 3 == 0`, which could never be true before the last
wave in a 3-wave level (see git history for the exact bug trace, if you need it). It now fires once
per level, on `wave_index == level.waves.size() - 2` — the second-to-last wave, i.e. right before
each level's hardest wave — which works for either pilot level's 3-wave structure and for any
future longer level without further changes. All 13 `MODIFIER_CARDS` are reachable now.

**One draft per level is a real constraint on card design.** A cost that only bites for the final
wave is barely a cost, which is exactly why `tolerance_cost` raises a floor rather than adding a
decaying spike. If the draft ever fires more than once per level, revisit the two-sided cards'
numbers — stacking two `tolerance_cost` picks compounds fast.

`ModifierManager` is also already the injection point for Growth Tree modifiers (`11`) —
`MetaProgression.apply_growth_modifiers()` calls `ModifierManager.add_card()` for every unlocked
node at level start, and that path **does** work today (see `11`).

## Implementation checklist

- [ ] `CardData.gd` as a `Resource` with themed `StatType` and `TargetHabit` enums — real cards are
      untyped `Dictionary` literals in `Data.MODIFIER_CARDS` instead (matches `02`'s MVP shortcut).
- [x] `ModifierManager.gd` autoload with `add_card()`, `reset()`, and `get_modified_stat()`.
- [x] `Habit.gd` connects to `modifiers_updated` and calls `_recalculate_stats()`.
- [ ] Sample `.tres` cards in `res://data/cards/` with themed names and descriptions — 13 themed
      cards exist (8 clean, 5 two-sided), but as `data.gd` dictionary entries, not `.tres` files.
- [x] Two-sided risk/reward cards where the player chooses a cost alongside the gain, with both
      halves rendered in the draft (green upside, red cost) so the trade is legible before picking.
- [x] Draft screen integration presents 3 random cards between waves — fires once per level, right
      before the final wave (see above).
