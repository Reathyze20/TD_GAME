# 03 — Global State & Signals

Systems interact constantly: a distraction dies and grants **Dopamine**, a habit is built and
spends it, a distraction reaches the core and drains **Focus**, and the HUD must reflect all of it.
Direct references between these systems turn into spaghetti, so we use two autoloads:

- **`SignalBus.gd`** — a global, logic-free **event router**. Systems emit here; others connect here.
- **`GameState.gd`** — the **source of truth** for the current match (Dopamine, Focus, Tolerance,
  phase). It reacts to the bus and emits its own change signals.

## 1. The event bus (`SignalBus.gd`)

No logic — only strictly-typed signal definitions.

```gdscript
extends Node
## AUTOLOAD: SignalBus — global event routing to decouple systems.

# --- Game flow ---
signal game_state_changed(new_state: String)
signal level_started(level_id: String)
signal game_over(victory: bool)

# --- Waves & spawns ---
signal wave_started(wave_number: int)
signal wave_completed(wave_number: int)
signal distraction_spawned(distraction: Node2D)
signal distraction_escaped(focus_damage: int)          # reached the Focus core

# --- Combat & economy ---
signal distraction_defeated(distraction: Node2D, dopamine_reward: int)
signal dopamine_changed(current: int, difference: int) # HUD listens
signal focus_changed(current: int, max_value: int)     # HUD + core visuals listen
signal tolerance_changed(current: int)                 # HUD listens (our mechanic)

# --- Building (see 07) ---
signal build_requested(spot: Node2D)                   # a high-ground spot was clicked
signal build_canceled()
signal habit_built(habit: Node2D, cost: int)
signal habit_upgraded(habit: Node2D, new_tier: HabitData, cost: int)
signal habit_sold(habit: Node2D, refund: int)
```

## 2. Match state (`GameState.gd`)

Holds live values, listens to the bus, and emits change signals when values move.

```gdscript
extends Node
## AUTOLOAD: GameState — source of truth for the current match.

enum MatchState { PREP, DEFENDING, PAUSED, GAME_OVER }

var current_state: MatchState = MatchState.PREP
var dopamine: int = 0
var focus: int = 20
var max_focus: int = 20
var tolerance: float = 0.0          # 0..100; higher => smaller future dopamine
var quick_hit_enabled: bool = false # per-level (introduced on level 2)
var current_wave: int = 0

func _ready() -> void:
	SignalBus.distraction_defeated.connect(_on_defeated)
	SignalBus.distraction_escaped.connect(_on_escaped)
	SignalBus.habit_built.connect(_on_spend)
	SignalBus.habit_upgraded.connect(_on_spend)
	SignalBus.habit_sold.connect(_on_refund)
	SignalBus.wave_started.connect(_on_wave_started)

# --- Public API ---
func reset_match(level: Dictionary) -> void:
	dopamine = level.start_dopamine
	focus = level.focus
	max_focus = level.focus
	tolerance = 0.0
	quick_hit_enabled = level.quick_hit
	current_wave = 0
	_set_state(MatchState.PREP)
	SignalBus.dopamine_changed.emit(dopamine, 0)
	SignalBus.focus_changed.emit(focus, max_focus)
	SignalBus.tolerance_changed.emit(int(tolerance))

func can_afford(amount: int) -> bool:
	return dopamine >= amount

## The Quick Hit mechanic: instant dopamine, but tolerance rises and future
## rewards shrink. This IS the lesson (see 00_overview + 08).
func quick_hit() -> void:
	if not quick_hit_enabled: return
	_modify_dopamine(15)
	set_tolerance(tolerance + 18.0)

func set_tolerance(value: float) -> void:
	tolerance = clampf(value, 0.0, 100.0)
	SignalBus.tolerance_changed.emit(int(tolerance))

# --- Internal handlers ---
func _on_defeated(_d: Node2D, base_reward: int) -> void:
	# Downregulation: tolerance eats into the reward.
	var reward := maxi(1, int(round(base_reward * (1.0 - 0.6 * (tolerance / 100.0)))))
	_modify_dopamine(reward)

func _on_spend(_n: Node2D, cost: int) -> void:      _modify_dopamine(-cost)
func _on_refund(_n: Node2D, refund: int) -> void:   _modify_dopamine(refund)

func _on_escaped(focus_damage: int) -> void:
	focus = maxi(0, focus - focus_damage)
	SignalBus.focus_changed.emit(focus, max_focus)
	if focus == 0 and current_state != MatchState.GAME_OVER:
		_set_state(MatchState.GAME_OVER)
		SignalBus.game_over.emit(false)

func _on_wave_started(n: int) -> void:
	current_wave = n
	_set_state(MatchState.DEFENDING)

# --- Helpers ---
func _modify_dopamine(amount: int) -> void:
	dopamine += amount
	SignalBus.dopamine_changed.emit(dopamine, amount)

func _set_state(s: MatchState) -> void:
	if current_state != s:
		current_state = s
		SignalBus.game_state_changed.emit(MatchState.keys()[current_state])
```

> **Tolerance decay** (in the `Game`/level `_process`): `set_tolerance(tolerance - delta * 4.0)`
> so a single Quick Hit hurts for a few seconds, then recovers — mirroring real downregulation.

## 3. Best practices

- **Autoload order:** `SignalBus` **before** `GameState` in Project Settings, so the bus exists
  when `GameState._ready()` connects.
- **Never write backwards:** the HUD/build UI must *request* (emit a signal); only `GameState`
  mutates its values, then emits `*_changed`. UI reacts.
- **Freed nodes:** signals carry node references (`distraction: Node2D`) — guard with
  `is_instance_valid()` before calling methods on them.

## Intersection with the prototype

`SignalBus.gd` **exists and is autoloaded** (unlike most "target-only" pieces in this doc set), but
it's a **stalled migration, not aspirational vapor**: a repo-wide search finds zero `.connect()`
calls to any `SignalBus.*` signal. Only two of its ~14 declared signals are ever emitted
(`distraction_defeated`/`distraction_escaped`, from `enemy.gd`) — and nothing listens to them
either. The HUD, economy, and every other system are wired entirely through a **second, parallel**
signal set declared directly on `GameState` (`dopamine_changed`, `focus_changed`, `wave_changed`,
`tolerance_changed`, `selected_habit_changed`), which `game.gd` connects to directly. Dopamine
reward already applies the **tolerance downregulation** formula, and **Quick Hit** already exists
(exact numbers: `+15` Dopamine, `+18` Tolerance, decays `-4.0`/sec while `> 0` — matches this doc).

- **MVP now:** `GameState`'s own signals are the only ones actually doing anything; treat
  `SignalBus` as present-but-inert rather than "not yet split out."
- **Target:** either finish the migration (move `GameState`'s signals onto `SignalBus` and connect
  everything through it) or delete the unused half of `SignalBus` — a bus nothing listens to is a
  worse trap than no bus at all, since it looks wired but silently isn't. Rename `enemy_*` →
  `distraction_*` for theme consistency (already done in practice — `enemy.gd` emits
  `SignalBus.distraction_defeated`/`distraction_escaped`, not `enemy_*` names).

## Implementation checklist

- [ ] `res://scripts/autoloads/` with `SignalBus.gd` (typed signals only) and `GameState.gd` —
      both scripts are real but live at `res://scripts/`, not an `autoloads/` subfolder.
- [ ] `project.godot` autoloads: `SignalBus` index 0, `GameState` index 1 — order is right but not
      adjacent: real order is `SignalBus`(0), `Data`(1), `GameState`(2), `ModifierManager`(3),
      `MetaProgression`(4). SignalBus is still before GameState, just not immediately before it.
- [x] Dopamine reward passes through the tolerance formula.
- [ ] `focus == 0` emits `game_over(false)` — no signal fires at all; `game.gd._on_distraction_reached_core()`
      calls `GameState.lose_focus()` then directly calls `_game_over()` → `change_scene_to_file(GameOver.tscn)`.
      Victory (`_level_complete()` → `Education.tscn`) is a separate, parallel path, not the same
      signal with `victory = true` — there is no unified `game_over(victory: bool)` anywhere.
- [x] All UI updates come *only* from `*_changed` signals — true, just `GameState`'s signals, not `SignalBus`'s.
