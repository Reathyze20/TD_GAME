# 11 — Meta-Progression & Save

Players earn **Clarity Stars** by completing levels. Stars are spent in a **Growth Tree** (skill
tree) on the main menu to unlock permanent passive upgrades that carry across all future runs —
e.g. "All Focus Timer habits deal +10% Willpower", "Start each level with +20 Dopamine", or
"Tolerance decays 15% faster".

We use Godot 4's native `ResourceSaver` / `ResourceLoader` to serialize a custom `SaveGame`
resource to the `user://` directory.

> Theme reminder (see `00_overview.md`): "gold" is **Dopamine** (in-level currency), "stars" are
> **Clarity Stars** (meta currency earned by winning), "towers" are **habits**, and "skill tree"
> is the **Growth Tree**. The tree's upgrades are framed as real-life growth insights — investing
> effort into understanding yourself yields compounding returns.

## 1. Save resource (`SaveGame.gd`)

Serializable snapshot of the player's long-term progress.

```gdscript
class_name SaveGame extends Resource

@export var total_clarity_stars: int = 0
@export var unlocked_levels: Array[String] = ["level_01"]
## IDs of Growth Tree nodes the player has purchased.
@export var unlocked_growth: Array[String] = []

const SAVE_PATH: String = "user://savegame.tres"

static func save_exists() -> bool:
    return ResourceLoader.exists(SAVE_PATH)

static func load_save() -> SaveGame:
    if save_exists():
        return ResourceLoader.load(SAVE_PATH) as SaveGame
    return SaveGame.new()   # default if no save exists

func write_savegame() -> void:
    ResourceSaver.save(self, SAVE_PATH)
```

> **`user://`** is mandatory — `res://` is read-only in exported builds.

## 2. Meta-progression manager (`MetaProgression.gd`)

An autoload that loads the save on startup and provides an API for the Growth Tree and level
completion.

```gdscript
extends Node
## AUTOLOAD: MetaProgression — persistent growth across runs.

var current_save: SaveGame

func _ready() -> void:
    current_save = SaveGame.load_save()

# ---- Growth Tree API ----

func has_growth(growth_id: String) -> bool:
    return current_save.unlocked_growth.has(growth_id)

func unlock_growth(growth_id: String, cost: int) -> bool:
    if current_save.total_clarity_stars >= cost and not has_growth(growth_id):
        current_save.total_clarity_stars -= cost
        current_save.unlocked_growth.append(growth_id)
        current_save.write_savegame()
        return true
    return false

# ---- Level completion ----

func complete_level(level_id: String, stars_earned: int, next_level_id: String) -> void:
    current_save.total_clarity_stars += stars_earned
    if not current_save.unlocked_levels.has(next_level_id):
        current_save.unlocked_levels.append(next_level_id)
    current_save.write_savegame()
```

## 3. Growth Tree nodes (design)

Each node in the Growth Tree is a small permanent buff, themed as a self-improvement insight:

| id | Name | Cost | Effect | Flavour |
|---|---|---|---|---|
| `deep_sleep` | Deep Sleep | 2 ★ | +10% Willpower for all habits | "Rest sharpens resolve." |
| `starter_dopamine` | Morning Routine | 1 ★ | +20 starting Dopamine per level | "Structure breeds momentum." |
| `fast_recovery` | Neuroplasticity | 3 ★ | Tolerance decays 15% faster | "The brain adapts — in both directions." |
| `wide_awareness` | Peripheral Vision | 2 ★ | +15% range for Mindfulness | "Notice distractions before they grab you." |

> **Shipped roster differs from this table — check before writing UI copy or tuning costs.**
> `Data.GROWTH_NODES` has exactly 3 nodes today, not 4: `fast_recovery`/Neuroplasticity doesn't
> exist in code yet. And `starter_dopamine`'s real effect is **"+1 Dopamine per defeat"**
> (`dopamine_bonus`, flat, every kill, for the rest of the run it's unlocked), not "+20 starting
> Dopamine per level" — a recurring per-kill economy bonus, not a one-time level-start grant. `deep_sleep`
> and `wide_awareness` match this table exactly.

## 4. Integration with the Modifier system (`10`)

On level start, `ModifierManager.reset()` clears in-level cards, then injects **growth modifiers**
for each unlocked node:

```gdscript
# In ModifierManager._ready() or at level start:
for growth_id in MetaProgression.current_save.unlocked_growth:
    var card := _growth_to_card(growth_id)
    if card:
        active_cards.append(card)
```

This way the Growth Tree and the roguelike card draft share the same modifier pipeline — no
separate stat paths.

## Intersection with the prototype

**Built and genuinely working — not a stub.** `SaveGame.gd` and `MetaProgression.gd` both exist,
are both autoloaded (`SignalBus` → `Data` → `GameState` → `ModifierManager` → `MetaProgression`,
in that order in `project.godot`), and `write_savegame()` really calls
`ResourceSaver.save(self, "user://savegame.tres")` — confirmed called from both `unlock_growth()`
and `complete_level()`, and `game.gd` genuinely calls `MetaProgression.complete_level()` at the end
of every level (`_level_complete()`) and reads/applies growth at the start of every level. This is
one of the more complete "target" systems in the whole doc set.

- `has_growth()` / `unlock_growth()` / `complete_level()` all match this doc's signatures (`complete_level`
  additionally defaults `next_level_id` to `""`).
- **§4's injection loop is real**, just under a different name: `MetaProgression.apply_growth_modifiers()`
  (not inline in `ModifierManager._ready()`) iterates `unlocked_growth`, looks each id up in
  `Data.GROWTH_NODES`, and calls `ModifierManager.add_card(node_data.modifier)` — `game.gd._ready()`
  calls it every level, right after `ModifierManager.reset()`. Unlike the card-draft screen (`10`),
  **this path is not blocked by anything** — a purchased Growth node reliably applies from level 1.
- The Growth Tree screen is real, in `menu.gd` (`_open_growth_tree()` / `_close_growth_tree()`), a
  code-built overlay rather than a dedicated `.tscn` — same "built in code, not a separate scene"
  pattern as every other UI screen in this project (`09`, `13`).
- Only real gaps vs. this doc: no `.tres` Growth Tree resources (const dictionary instead, per
  `02`'s MVP shortcut), and the roster is 3 nodes instead of 4 (see the callout under §3).

## Implementation checklist

- [x] `SaveGame.gd` extends `Resource` with static `load_save()` / `write_savegame()` to `user://`.
- [x] `MetaProgression.gd` autoload: `has_growth()`, `unlock_growth()`, `complete_level()`.
- [ ] Growth Tree data as `.tres` resources or a const dictionary — done as a const dictionary
      (`Data.GROWTH_NODES`), but only 3 of the 4 nodes above exist; `.tres` migration still open.
- [x] On level start, `ModifierManager` silently injects growth modifiers into `active_cards` —
      via `MetaProgression.apply_growth_modifiers()`, called from `game.gd._ready()`.
- [x] `ResourceSaver.save()` always targets `user://` (never `res://`).