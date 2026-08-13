# 02 — Data-Driven Resources

We strictly separate **gameplay logic** (nodes, scenes, scripts) from **balancing data** (stats,
costs, waves). Data lives in Godot 4 `Resource` files (`.tres`) so a designer can retune the game
in the Inspector without touching code. All resources use `class_name`, strict static typing, and
grouped `@export`s.

> Theme: these resources describe **distractions** and **habits** (see `00_overview.md`), and carry
> the two damage channels **Willpower** and **Awareness** plus the resistances **Compulsion** and
> **Rationalization**.

## 1. Distraction data (`DistractionData.gd`)

Stats + visual reference for one distraction type (`notification`, `autoplay`, `doomscroll`, …).

```gdscript
class_name DistractionData extends Resource   # was "EnemyData"

@export_category("Identity")
@export var id: StringName = &"notification"
@export var display_name: String = "Notification"
@export_multiline var description: String = "The ping that yanks your attention."
@export var icon: Texture2D

@export_category("Stats")
@export var max_health: int = 14
@export var base_speed: float = 130.0          # px/sec along the maze path
@export var is_flying: bool = false            # flyers ignore ground Allies (06)

@export_category("Resistances")
@export var compulsion: int = 0                # flat reduction vs Willpower damage
@export var rationalization: int = 0           # flat reduction vs Awareness damage

@export_category("Economy & Threat")
@export var dopamine_reward: int = 3           # dopamine granted on defeat
@export var focus_damage: int = 1              # Focus lost if it reaches the core

@export_category("Visuals")
@export var visual_scene: PackedScene          # sprite/animations (null = placeholder shape)
```

## 2. Habit data (`HabitData.gd`)

Defines a habit-tower's combat profile, targeting, and upgrade path.

```gdscript
class_name HabitData extends Resource          # was "TowerData"

enum TargetingMode { FIRST, LAST, STRONGEST, WEAKEST, CLOSEST }

@export_category("Identity")
@export var id: StringName = &"focus_timer"
@export var display_name: String = "Focus Timer"
@export_multiline var description: String = "Pomodoro focus. Reliable single-target."
@export var icon: Texture2D

@export_category("Construction")
@export var build_cost: int = 30               # dopamine
@export var upgrades: Array[HabitData] = []     # next-tier options

@export_category("Combat")
@export var attack_range: float = 150.0
@export var fire_cooldown: float = 0.45        # seconds between shots
@export var willpower_damage: int = 8          # direct (vs Compulsion)
@export var awareness_damage: int = 0          # mindful (vs Rationalization)
@export var reframe: int = 0                   # armor-shred: strips Compulsion/Rationalization

@export_category("Mechanics")
@export var default_targeting: TargetingMode = TargetingMode.FIRST
@export var is_aoe: bool = false               # hit everything in range (great vs swarms)
@export var projectile_scene: PackedScene      # null = instant/AoE, no travel
```

## 3. Status effect data (`StatusEffectData.gd`)

Buffs/debuffs a habit applies on hit. Themed effect types:

| Effect | `EffectType` | Meaning |
|---|---|---|
| **Calm** | `SLOW` | speed multiplier (`0.5` = 50% slower) |
| **Interrupt** | `STUN` | fully stops the distraction briefly |
| **Boredom** | `DOT` | damage over time as novelty fades |
| **Reframe** | `SHRED` | reduces Compulsion / Rationalization |

```gdscript
class_name StatusEffectData extends Resource

enum EffectType { SLOW, STUN, DOT, SHRED }     # Calm, Interrupt, Boredom, Reframe

@export var effect_type: EffectType
@export var intensity: float = 0.0             # slow mult, DOT damage, or shred amount
@export var duration: float = 1.0
@export var tick_rate: float = 0.0             # >0 => DOT ticks every tick_rate seconds
@export var particle_scene: PackedScene
```

## 4. Waves (`SpawnBatchData.gd` + `WaveData.gd`)

Split in two so waves can be composed (e.g. 10 `notification` from zone A, then after 2s, 3
`doomscroll` from zone B).

```gdscript
class_name SpawnBatchData extends Resource

@export var distraction: DistractionData
@export var count: int = 5
@export var spawn_interval: float = 0.3        # seconds between spawns in this batch
@export var delay_before_batch: float = 0.0    # wait before this batch starts
@export var spawn_zone: int = 0                # index into the level's spawn zones (see 04/08)
```

```gdscript
class_name WaveData extends Resource

@export var wave_number: int = 1
@export var dopamine_reward_on_clear: int = 0  # optional clear bonus
@export var batches: Array[SpawnBatchData] = []
```

## 5. File structure & conventions

```text
res://
├── data/
│   ├── distractions/   # notification.tres, autoplay.tres, doomscroll.tres, the_algorithm.tres
│   ├── habits/         # focus_timer.tres, mindfulness.tres, exercise.tres, accountability.tres
│   ├── waves/          # level_1_wave_1.tres …
│   └── effects/        # calm.tres, interrupt.tres, boredom.tres, reframe.tres
└── scripts/resources/  # the .gd class_name definitions above
```

- **Variations by duplication:** to make an "elite doomscroll", duplicate `doomscroll.tres`, rename,
  bump stats.
- **Null checks:** always guard `if data.visual_scene:` before instancing (placeholder shapes are valid).
- **Upgrade loops:** never link a tier-2 habit's `upgrades` back to tier-1.

## Intersection with the prototype

The prototype does **not** use `.tres` yet — it keeps the same data as typed `const` dictionaries
in `scripts/data.gd`: `DISTRACTION_TYPES`, `HABIT_TYPES`, `LEVELS`, plus four more this doc doesn't
mention yet (`INSIGHT_CARDS` — `08`; `MODIFIER_CARDS` — `10`; `INTERVENTIONS` — `12`;
`GROWTH_NODES` — `11`). That is a deliberate MVP shortcut: one file, no Inspector round-trips.

**No field mapping needed — the dictionaries already speak the target vocabulary directly.** An
earlier draft of this doc assumed the prototype used old field names (`reward`, `hp`, `cost`,
`fire_rate`, generic `damage`) that would need renaming during a `.tres` migration. That rename has
already happened *in the data itself*: `DISTRACTION_TYPES` entries use `dopamine_reward`,
`max_health`, `focus_damage`, `compulsion`, `rationalization` verbatim; `HABIT_TYPES` entries use
`build_cost`, `fire_cooldown`, **and already split `willpower_damage` / `awareness_damage` as two
separate keys** — e.g. `mindfulness` is pure Awareness (`willpower_damage: 0, awareness_damage: 5`),
`exercise` is pure Willpower. **The prototype is not single-damage-channel** — both channels and
both resistances are live today, mitigated in `enemy.gd::take_damage(willpower, awareness)`. A
`.tres` migration would only need to move these dictionary keys onto `@export` fields 1:1, no
renaming or damage-model rework required.

**Migration path:** when balancing gets heavy or a designer joins, promote the dictionaries to
`.tres` resources with the schemas above.

## Implementation checklist

- [ ] Create `res://scripts/resources/` with the 6 `class_name` scripts above.
- [ ] Strict typing, no implicit `Variant`s; `class_name` present in all.
- [ ] Create `res://data/{distractions,habits,waves,effects}/`.
- [ ] One sample `.tres` per type; confirm the Inspector exposes every `@export_category`.
