# 04 — Distractions & Maze Pathfinding

Distractions are the "enemies": small, swarmy, data-driven shells populated at runtime by a
`DistractionData` resource (`02`). Each one **pathfinds around fixed high ground** to the Focus
core, takes typed damage, and can suffer status effects.

> **This is the one hard reconciliation.** Early drafts assumed a fixed `Path2D` + `curve.sample_baked`.
> We do **open maze pathfinding with `AStarGrid2D`** instead: enemies spawn from **zones** and route
> around **high ground** (which is also where habits are built, `07`). Because the maze is *terrain*
> (fixed per level), a route is computed **once at spawn** and never needs recomputing.

## 1. Why a maze, not a lane

Fixed lanes = predefined paths. We explicitly want emergent routes: many small distractions
flowing from several spawn zones, weaving around high ground toward the core. `AStarGrid2D`
(`DIAGONAL_MODE_NEVER`) gives us that for free and matches the "structure & boundaries defend your
attention" theme.

## 2. Node structure

Use `Area2D` as the root (fast projectile overlap; **no physics resolution needed** — distractions
follow a cell path, not a physics body). This keeps hundreds of small distractions cheap.

```text
Distraction (Area2D) [y_sort_enabled]
├── StatusManager (Node)          # Calm / Interrupt / Boredom / Reframe
├── Shadow (Sprite2D) [Z -1]      # at (0,0)
├── Visuals (Node2D) [y_sort_enabled]
│   └── Sprite / AnimatedSprite2D # bottom aligned to (0,0)
├── CollisionShape2D              # hit/click area
└── WorldUI (Node2D) [Z 10]
    └── HealthBar (ProgressBar)
```

## 3. Core script (`Distraction.gd`)

The `Game`/level owns the `AStarGrid2D` and hands each distraction a **cell path**
(`Array[Vector2i]`). The distraction walks it cell-to-cell with a small scatter so a swarm doesn't
stack into one sprite.

```gdscript
class_name Distraction extends Area2D

signal defeated(d)
signal reached_core(d)

var data: DistractionData
var current_health: int
var is_dead := false

# Maze movement
var cell_path: Array = []          # Array[Vector2i], from AStarGrid2D (assigned by Game)
var path_index := 0
var scatter := Vector2.ZERO        # small per-unit offset (anti-clumping)

# Blocking (see 06 — Allies halt distractions in melee)
var is_blocked := false
var blocker = null

# Modified stats (StatusManager writes these)
var current_speed: float
var current_compulsion: int
var current_rationalization: int

func setup(d: DistractionData, game_ref) -> void:
	data = d
	game = game_ref
	current_health = d.max_health
	current_speed = d.base_speed
	current_compulsion = d.compulsion
	current_rationalization = d.rationalization
	var s := Data.GRID.tile * 0.16
	scatter = Vector2(randf_range(-s, s), randf_range(-s, s))

func set_cell_path(p: Array) -> void:
	cell_path = p
	path_index = 1 if p.size() > 1 else 0   # skip the cell we start on

func _process(delta: float) -> void:
	if is_dead: return
	if is_blocked:                            # melee vs an Ally (06)
		_handle_melee(delta)
		return
	if cell_path.is_empty(): return          # no route yet — idle, don't false-trigger the core
	if path_index >= cell_path.size():
		_reach_core(); return
	var target: Vector2 = game.cell_center(cell_path[path_index]) + scatter
	var to := target - global_position
	var dist := to.length()
	var step := current_speed * delta
	if dist <= step:
		global_position = target
		path_index += 1
	else:
		global_position += to / dist * step
```

### Damage (two channels)

Willpower is mitigated by **Compulsion**, Awareness by **Rationalization**. `Reframe` (armor-shred)
strips both over time (applied via `StatusManager`).

```gdscript
func take_damage(willpower: int, awareness: int) -> void:
	if is_dead: return
	var wp := maxi(1, willpower - current_compulsion) if willpower > 0 else 0
	var aw := maxi(1, awareness - current_rationalization) if awareness > 0 else 0
	current_health -= wp + aw
	if current_health <= 0: _die()

func _die() -> void:
	is_dead = true
	SignalBus.distraction_defeated.emit(self, data.dopamine_reward)
	queue_free()

func _reach_core() -> void:
	is_dead = true
	SignalBus.distraction_escaped.emit(data.focus_damage)
	queue_free()
```

## 4. Status effects (`StatusManager` child)

Keeps `Distraction.gd` lean. A habit hits and calls
`distraction.get_node("StatusManager").apply(effect_data)`.

- **Calm (SLOW):** multiplies `current_speed` while active, restores on expiry.
- **Interrupt (STUN):** sets speed to 0 (or an `is_stunned` flag) for the duration.
- **Boredom (DOT):** a tick accumulator; every `tick_rate` seconds calls `take_damage`.
- **Reframe (SHRED):** lowers `current_compulsion` / `current_rationalization` while active.

## 5. Flying distractions

`data.is_flying == true` → the distraction ignores ground **Allies** (Allies never set `is_blocked`
on it). Render per `01` §5 (sprite offset up, shadow on the ground). Only ranged habits can hit it.

## Intersection with the prototype

This is basically **already built** in `scripts/enemy.gd` + `game.gd` — the prototype is the
reference implementation for the maze model:

- `game.gd` owns the `AStarGrid2D`, marks `high_ground` cells solid, and `assign_path()` gives each
  enemy an `Array[Vector2i]` from a spawn cell to the objective. ✔
- `enemy.gd` walks `cell_path` with a `scatter` offset and idles on an empty path. ✔
- Spawn happens from **zones** (`spawn_zone_cells`), verified reachable (0 unreachable in tests). ✔

**Already done, ahead of this section's own gap list:** the rename to `class_name Distraction` is
complete, and `take_damage(willpower: int, awareness: int)` already splits Willpower/Awareness with
Compulsion/Rationalization mitigation (`maxi(1, dmg - resist)` per channel) — both are shipped, not
outstanding.

Real remaining gap vs. this doc (target work): there is still no `StatusManager` **child node** —
statuses live as plain fields on `Distraction` with a `_tick_statuses(delta)` countdown. Two of the
four are implemented: **Calm** (`apply_slow`, reused for Interrupt via `deep_breath`'s factor-0.0
freeze), **Reframe** (`apply_reframe`, see below) and **Boredom** (`apply_boredom`). Boredom is a
damage-over-time that routes through `take_direct_damage()` and so **bypasses both Compulsion and
Rationalization** — you cannot rationalise your way out of something simply being boring, which
makes it the dependable answer to heavily-resistant types. It is applied by the `real_hobby` habit
(`05`), and draws a dull grey halo as the novelty drains.
`is_blocked` **is now wired** for Allies (`06`), as an array of blockers rather than the single
reference sketched at line 58.

**Reframe (shipped).** `reframe_amount` strips that many points from *both* Compulsion and
Rationalization while it lasts; `effective_compulsion()` / `effective_rationalization()` floor at 0
and are what `take_damage()` actually mitigates against. Only the Mindfulness line applies it
(3 for 2.5s, 6 for 3.5s at tier 2), which deliberately makes the Awareness habit a **set-up for
everything else** rather than a damage dealer: an Ally's 6 Willpower against Doomscroll's
Compulsion 4 lands for 2 unreframed and 5 reframed. Distractions under Reframe draw a broken white
ring, because a combo the player cannot see is a combo they cannot plan.

**Flyers are in (`phantom_buzz`, "Phantom Buzz").** `is_flying` is no longer a dead stub. A flyer
gets **no cell path at all** — `game.assign_path()` skips it and `Distraction._fly()` steers it in a
straight line at `objective_pos`, so it ignores the high-ground maze entirely and no Ally can
intercept it (`Ally._find_target()` filters `is_flying`, a rule that was previously untestable).
That is the whole design: it is the urge that comes from *inside*, so structure and support cannot
stand between it and your Focus. `compulsion: 2 / rationalization: 0` makes the lesson mechanical —
Willpower cannot brute-force it, Awareness notices it fine. It draws a ground shadow so "why did my
Allies ignore that one" has a visible answer.

It is introduced on **level 2 only** (3 in wave 2, 5 in wave 3). Level 1's final wave already
carries a note that it needs a hands-on difficulty pass, and flyers bypass the maze — putting them
there would compound precisely the wave that is already too hard.

**All three statuses follow one rule: strongest wins, duration is never truncated.** This replaced
one-shot `SceneTreeTimer`s, which had a real bug — a Mindfulness pulse (`apply_slow(0.5, 1.0)`)
landing during Deep Breath's `apply_slow(0.0, 3.5)` freeze both thawed it to 0.5 and then cleared
it after 1s, silently cutting a 3.5s Interrupt to about one second whenever a Mindfulness habit
covered the same ground. Statuses also tick *before* `_process()`'s early returns, so a blocked or
unrouted distraction still sheds them on schedule.

## Implementation checklist

- [ ] `Area2D` root (no physics), cell-path movement via `AStarGrid2D` (no `PathFollow2D`/`Path2D`
      curve) — movement via `AStarGrid2D` is done, but the real root is a plain `Node2D`, not an
      `Area2D` (no collision shape; hits are resolved by other actors checking raw distance).
- [x] `scatter` offset so same-instant spawns don't overlap.
- [x] `take_damage` applies Compulsion/Rationalization mitigation.
- [x] `_die()`/`_reach_core()` emit `distraction_defeated` / `distraction_escaped` on the bus.
- [ ] `StatusManager` child applies `StatusEffectData` (Calm/Interrupt/Boredom/Reframe) — Calm
      (`apply_slow`, doubling as Interrupt at factor 0.0) and Reframe (`apply_reframe`) both work,
      but as fields on `Distraction` with a `_tick_statuses()` countdown, not a child node.
      **All four effects now exist**; only the container node is outstanding.
- [x] `is_blocked` halts movement and triggers melee retaliation (for `06`) — shipped, but as an
      **Array** of `blockers` rather than this doc's single `blocker` reference, so several Allies
      can hold one distraction at once. Retaliation damage comes from a per-type `melee_damage`
      stat. See `06`'s Intersection section.
