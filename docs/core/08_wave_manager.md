# 08 — Wave Manager

The **WaveManager** drives match progression: it reads `WaveData` / `SpawnBatchData` resources
(`02`), spawns **distractions** from **spawn zones** at timed intervals, tracks active distractions,
and determines when a wave is cleared. Between waves it optionally surfaces a **Quick Hit** window
(`03`) and, after the final wave, an **insight card** that ties the level's mechanics to a real
neuroscience concept.

> Theme reminder (see `00_overview.md`): "enemies" are **distractions**, "gold" is **Dopamine**,
> "base health" is **Focus**, and the instant-dopamine button is **Quick Hit**. Insight cards are
> the educational payoff for each level.

## 1. Architecture: zones, not lanes

Early drafts assumed a fixed `Path2D` curve. We use **`AStarGrid2D` maze pathfinding** instead
(`04`): distractions spawn from one of several **spawn zones** (rectangles of open cells defined
per level in `data.gd`) and independently route around **high ground** to the **Focus core**
(the objective cell). There are no `PathFollow2D` nodes and no shared curve.

```text
Level (Node2D)
├── Environment (Node2D)
│   ├── Terrain (TileMapLayer)                      [Z -10]
│   └── HighGround (TileMapLayer)                   [Z -5]
├── EntityLayer (Node2D) [y_sort_enabled]
│   ├── Habits (Node2D)   [y_sort_enabled]
│   ├── Distractions (Node2D) [y_sort_enabled]      # where spawned distractions live
│   └── Allies (Node2D)   [y_sort_enabled]          # (06)
├── WaveManager (Node)                               # this system
└── HUD (CanvasLayer)                                # wave counter, Quick Hit button, etc. (09)
```

## 2. Wave state tracking

A wave is **not** over when spawning finishes — it ends when spawning is done **and** every spawned
distraction has either been defeated or escaped. The WaveManager maintains an `active_distractions`
counter:

- **+1** each time a distraction spawns.
- **−1** each time `SignalBus.distraction_defeated` or `SignalBus.distraction_escaped` fires.

Only when `active_distractions == 0` and `is_spawning == false` is the wave considered cleared.

## 3. Core script (`WaveManager.gd`)

Uses Godot 4 `await` coroutines for clean, linear spawn logic that automatically pauses when the
scene tree is paused.

```gdscript
class_name WaveManager extends Node

# ---- Exports & references ----
@export var waves: Array[WaveData] = []
@export var distraction_container: Node2D          # EntityLayer/Distractions
@export var distraction_scene: PackedScene          # base Distraction.tscn template

# ---- Internal state ----
var current_wave_index: int = 0
var active_distractions: int = 0
var is_spawning: bool = false
var wave_in_progress: bool = false

func _ready() -> void:
    SignalBus.distraction_defeated.connect(_on_distraction_removed)
    SignalBus.distraction_escaped.connect(_on_distraction_escaped)

# ---- Public API ----

func start_next_wave() -> void:
    if wave_in_progress or current_wave_index >= waves.size():
        return

    var wave_data := waves[current_wave_index]
    wave_in_progress = true
    is_spawning = true

    SignalBus.wave_started.emit(current_wave_index + 1)

    _process_wave(wave_data)

# ---- Coroutine spawn logic ----

func _process_wave(wave_data: WaveData) -> void:
    for batch in wave_data.batches:
        # 1. Wait for batch delay.
        if batch.delay_before_batch > 0:
            await get_tree().create_timer(batch.delay_before_batch, false).timeout

        # 2. Spawn distractions in this batch, one at a time.
        for i in range(batch.count):
            _spawn_distraction(batch.distraction, batch.spawn_zone)

            if batch.spawn_interval > 0 and i < batch.count - 1:
                await get_tree().create_timer(batch.spawn_interval, false).timeout

    is_spawning = false
    _check_wave_completion()

func _spawn_distraction(distraction_data: DistractionData, zone_index: int) -> void:
    var d := distraction_scene.instantiate() as Distraction
    distraction_container.add_child(d)
    d.setup(distraction_data, _get_game_ref())

    # Place in the correct spawn zone and assign a maze path.
    var spawn_cell := _random_cell_in_zone(zone_index)
    d.global_position = _get_game_ref().cell_center(spawn_cell)
    _get_game_ref().assign_path(d)

    active_distractions += 1
    SignalBus.distraction_spawned.emit(d)

# ---- Completion tracking ----

func _on_distraction_removed(_d: Node2D, _dopamine: int) -> void:
    _decrement()

func _on_distraction_escaped(_focus_damage: int) -> void:
    _decrement()

func _decrement() -> void:
    active_distractions -= 1
    if not is_spawning:
        _check_wave_completion()

func _check_wave_completion() -> void:
    if active_distractions <= 0 and not is_spawning and wave_in_progress:
        wave_in_progress = false

        # Optional clear bonus (dopamine).
        var bonus := waves[current_wave_index].dopamine_reward_on_clear
        if bonus > 0:
            GameState._modify_dopamine(bonus)

        SignalBus.wave_completed.emit(current_wave_index + 1)

        current_wave_index += 1

        if current_wave_index >= waves.size():
            SignalBus.game_over.emit(true)   # victory — all waves cleared
```

> **`process_always = false`** (the second parameter in `create_timer(time, false)`) is critical:
> it makes the timer respect `get_tree().paused = true`, so wave spawning halts correctly when the
> player pauses.

## 4. Quick Hit window (between waves)

When a wave clears and Quick Hit is enabled (`level.quick_hit == true`, introduced on level 2),
the player gets a brief window to press the **Quick Hit** button for instant Dopamine — at the cost
of rising **Tolerance** (`03`). This IS the lesson: *cheap, instant dopamine is borrowed — you pay
it back with tolerance.*

Between waves, `GameState.quick_hit_enabled` gates the button visibility in the HUD (`09`).
Tolerance decays naturally in `game.gd._update_tolerance()` at 4 units/sec, so a single Quick Hit
hurts for a few seconds then recovers — mirroring real receptor downregulation.

## 5. Insight cards (between levels)

After the **final wave** of a level, the game transitions to `Education.tscn`, which displays an
**insight card** — a short, non-preachy summary tying a neuroscience concept to what the player
just experienced.

Cards are defined in `data.gd` (`INSIGHT_CARDS` array, keyed by `level_id`):

```gdscript
const INSIGHT_CARDS := [
    {
        "level_id": 1,
        "title": "Variable Rewards",
        "concept": "Intermittent Reinforcement",
        "description": "Apps release dopamine not when you get a result, but in ANTICIPATION of
            it. The uncertainty of what you will find when refreshing the feed is what keeps you
            coming back.",
        "takeaway": "Turn off non-essential notifications. Make checking your phone a conscious
            choice rather than a reflex to a ping.",
        "color": "4aa3ff",
    },
    {
        "level_id": 2,
        "title": "Tolerance",
        "concept": "Dopamine Downregulation",
        "description": "Every Quick Hit paid a little less than the one before — and after
            enough of them, even honest wins paid less too. That is downregulation: a brain
            flooded with cheap dopamine turns the volume down on ALL of it.",
        "takeaway": "Cheap dopamine isn't free — it's borrowed against everything else you
            enjoy. A stretch without the feed resets the price of everything slower.",
        "color": "ffd479",
    },
]
```

*(The real data now lives in `data/insight_cards/*.tres` — `InsightCardData` resources keyed by
`level_id`; the array above is kept as a shape reference.)*

- **Level 1 card** ("Variable Rewards" / Intermittent Reinforcement) ties to the swarm of cheap
  `notification` spawns the player just fought through — the ping is designed around uncertainty,
  not the content behind it.
- **Level 2 card** ("Tolerance" / Dopamine Downregulation) ties to the Quick Hit button the player
  has been pressing all level: the shrinking payouts and the rising floor ARE downregulation, and
  the card names what the economy already did to them.

> **Content gap — RESOLVED:** this doc used to flag that level 2 turns on `quick_hit`/Tolerance
> but no card taught it. The level-2 card was retargeted from "Friction & Habits" to Tolerance
> once Quick Hit actually worked (cooldown + tolerance-scaled payout + permanent floor). The
> friction/choice-architecture topic is a good candidate for a future level 3's card.

> **Latent fragility:** each card carries a `level_id`, but `education.gd` doesn't actually filter
> on it — it indexes `INSIGHT_CARDS` **positionally** by `GameState.current_level_index`. That
> happens to line up correctly today (2 cards, 2 levels, declared in order), but reordering the
> array or adding a level 3 without also appending its card in the right slot would silently show
> the wrong card rather than error. Cheap to harden now (filter by `level_id` instead of index),
> easy to forget once there are more levels.

The education screen shows the card, then offers "Continue" (next level) or "Finish" (back to menu).

## 6. Early wave calling (target feature)

A "Call Wave" button appears between waves. Clicking it skips the inter-wave timer and grants
bonus Dopamine proportional to the time remaining (e.g. 2 Dopamine per second skipped). Because
`start_next_wave()` guards on its own `wave_in_progress` flag, it is safe to call from external UI.

## Intersection with the prototype

The prototype's wave system is **fully functional** in `game.gd` — just inlined rather than
separated into a `WaveManager` node:

- **Spawn zones** (not `Path2D` lanes): `spawn_zone_cells` holds open cells per rectangle. Each
  distraction gets a random cell from a zone, is placed there, and receives a cell path from
  `assign_path()` → `AStarGrid2D`. ✔
- **Timed spawning**: `_start_wave()` builds a `spawn_queue` sorted by time offsets. `_process()`
  pops entries when `wave_time` reaches them. This is the timer-based equivalent of the `await`
  coroutine above. ✔
- **Wave tracking**: `enemies.size() > 0` guards `_check_wave_progress()`, so a wave only
  ends when all distractions are gone and spawning is done. ✔
- **Untimed build phase + early-call bonus** (NOT the auto-advance this doc once described):
  between waves the game waits for the player's **Start Wave**, and starting within
  `WAVE_BONUS_WINDOW` (30s) pays `WAVE_BONUS_PER_SEC` (1 ◆) per second still on the clock — §6's
  "Call Wave" bonus is real. ✔
- **Insight cards**: `_level_complete()` transitions to `Education.tscn`; card data lives in
  `data/insight_cards/*.tres` (`InsightCardData`). ✔
- **Quick Hit**: `do_quick_hit()` in `game.gd` — tolerance-scaled payout (base +15), 6s cooldown,
  +18 Tolerance spike and a permanent +2 bump to the Tolerance *floor* per use; the HUD button
  appears only when `GameState.quick_hit_enabled`. ✔

**Gaps vs. target:** wave data is expanded at load by `Data.build_waves()` from each level's
`wave_curve` (`WaveCurveEntryData` .tres) rather than hand-authored `WaveData` files, there is no
per-batch `delay_before_batch`, and no separate `WaveManager` node. These are clean additions when
wave complexity grows.

## Implementation checklist

- [ ] `WaveManager.gd` uses `await get_tree().create_timer(time, false).timeout` — `false`
      so timers pause with the tree.
- [ ] `is_spawning` + `active_distractions` together gate `_check_wave_completion()`, preventing
      a wave from ending if the first distraction is killed before the second one spawns.
- [ ] Distractions spawn from **spawn zones** via `AStarGrid2D` cell paths — no `Path2D` /
      `PathFollow2D` / `curve.sample_baked`.
- [ ] `distraction_defeated` / `distraction_escaped` signals decrement the counter (themed names).
- [ ] After the final wave, emit `game_over(true)` (victory) and transition to the insight card.
- [ ] **Quick Hit** window appears between waves when `quick_hit_enabled`; Tolerance decays at
      ~4 units/sec.