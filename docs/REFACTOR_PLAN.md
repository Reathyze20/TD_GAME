# Architecture Refactor — Working Plan

**Status: Phases 1–3 of 7 complete.** This is a living work document, not a reference doc — update
the status table as phases land. The numbered docs in `docs/core/` describe the *target
architecture*; this file tracks the *migration to it*.

## Why

Move the codebase from "working prototype" to "extensible base you can build on" along five pillars:

1. **Data-Driven Resources** — stats in `.tres` files editable in the Inspector, not `const` dicts in code.
2. **Composition** — small reusable component nodes instead of monolithic per-entity scripts.
3. **Inheritance** — shared base classes where a real behavioral fork exists.
4. **Event-Driven** — a live `SignalBus` instead of direct cross-script calls.
5. **Pool-Ready** — projectiles/VFX reusable instead of `instantiate()`/`queue_free()` churn.

**Key context:** `docs/core/00`–`13` already contain a fully written target architecture (exact
Resource schemas, `SignalBus` design, component suggestions), each with a maintained
"Intersection with the prototype" section. This is not a green-field redesign — it is *finishing
an already-documented migration*, and those docs are a primary source alongside the code.

## Explicitly NOT doing

These appear in `docs/core/` as "target" ideas but are rejected — by the docs' own Intersection
sections, or by closed project decisions. Do not reintroduce them.

| Rejected | Why |
|---|---|
| `Area2D` roots / `CollisionShape2D` hit detection | Project is 100% vector `_draw()`, zero physics bodies, by design — hits resolve via distance/cone math |
| `Sprite2D` children for knockback tweens | No sprite children exist; doc 06 already flags its own snippet as wrong |
| Parabolic arcs, predictive lead, `TargetingMode`, `WIND_UP` telegraph | Doc 05: continuous-sweep-no-lock-on is "a legitimate, already-tuned arcade design" |
| 5-state Ally machine, fixed-squad barracks | Doc 06: shipped 2-state production-building model is deliberately better |
| `TileMapLayer`, persistent `UILayer`, radial build menu, `.tscn`-per-screen | Contradicts "vector-only, no TileMap" + "scripts build their own nodes in code" |
| Generic `HealthComponent` / `HitboxComponent` | No physics anywhere; `Distraction.take_damage()` (2 mitigated channels, floor-of-1) and `Ally.take_damage()` (no mitigation) diverge too much to share meaningfully |
| Per-tower-type subclassing | Only 3 real behavior forks exist across 5 habit types (`is_blocker`, `aoe`, `has_work_cycle`) — the rest is pure data |

## Phase status

| # | Phase | Status |
|---|---|---|
| 1 | Data-Driven Resources | ✅ **Done** |
| 2 | Event Bus activation | ✅ **Done** |
| 3 | `StatusManager` component | ✅ **Done** |
| 4 | `AttackComponent` + `BaseHabit`/`Habit`/`Barracks` | ✅ **Done** |
| 5 | Coupling cleanup | ✅ **Done** |
| 6 | `ObjectPool` + projectile/FX pooling | ✅ **Done** |
| 7 | Final docs sync | ✅ **Done** |

---

## Phase 1 — Data-Driven Resources ✅ DONE

**Shipped:** 11 Resource classes in `scripts/resources/`, 35 `.tres` instances under `data/`,
and `data.gd` rewritten from `const` dicts into a typed facade (`Data.get_habit(id)`,
`get_distraction`, `get_card`, `get_all_cards`, `get_intervention`, `get_growth_node`,
`get_insight_card`, `get_level`, `get_level_count`). `build_waves()` keeps its linear-growth math
but emits `WaveData`/`SpawnBatchData`.

Resource classes: `DistractionData`, `HabitData`, `CardData` + `CardEffectData`,
`InterventionData`, `GrowthNodeData`, `InsightCardData`, `WaveCurveEntryData`, `LevelData`,
`SpawnBatchData`, `WaveData`.

**Call sites migrated (11 files):** `data.gd`, `game.gd` (~25 sites), `tower.gd`, `enemy.gd`,
`ally.gd`, `build_spot.gd`, `modifier_manager.gd`, `meta_progression.gd`, `education.gd`,
`menu.gd`, `game_state.gd`.

**Also fixed along the way:** insight cards now look up by `level_id` instead of array position
(previously-documented latent fragility — reordering levels would have silently shown the wrong card).

### Lessons — read before Phases 2-7

- **`Resource` has no `.get(key, default)` / `.has(key)`.** Dictionary-style access is everywhere
  in this codebase. Every `def.get("x", default)` became `def.x` (the Resource field always exists,
  with the default baked into the class), and `def.has("reframe")` became `def.reframe > 0`.
- **Field renames must be checked against call sites first.** `display_name`/`short_name`/
  `attack_range`/`is_aoe` had to be reverted to `name`/`short`/`range`/`aoe` because `game.gd`,
  `menu.gd`, and `tower.gd` already read those names.
- **Godot silently ignores stale property names in `.tres`.** `.tres` files generated *before* a
  field rename kept the old keys and fell back to class defaults with **no error** — `mindfulness`
  silently had wrong range and AoE off. Regenerate `.tres` after any schema rename, and verify by
  reading the actual saved file.
- **Static parse checks are not enough.** The above only surfaced in a live-scene test. Always run
  both `--import` (parse) *and* a live harness (behavior).
- **Ally takes explicit typed params now**, not a duck-typed def — it is built from either
  `HabitData` (barracks, permanent) or `InterventionData` (Call a Friend, `ally_lifetime > 0`),
  which share no base beyond `Resource`.

---

## Phase 2 — Event Bus activation ✅ DONE

**Shipped:** `SignalBus` (16 → 12 signals after deleting `game_state_changed`,
`dopamine_changed`, `focus_changed`, `tolerance_changed`) is now fully wired:
- `GameState._ready()` connects to `distraction_defeated` and `distraction_escaped` —
  the economy (tolerance-scaled reward, card bonuses, kill count) and Focus loss are now
  bus-reactive, not driven imperatively by `game.gd`.
- `game.gd._ready()` connects to `game_over(victory: bool)` for unified end-of-level
  routing (victory → stars/save/Education, defeat → GameOver screen).
- All 12 surviving signals are emitted at their correct call sites.
- Build/upgrade/sell remain imperative (hazard 1: affordability is a gate).
- Cancel-during-aiming refunds 100% (hazard 2: preserved).
- `game_ended` guard prevents same-frame double-fire (hazard 3: preserved).

**Test harness:** `_test_phase2.gd` / `_test_phase2.tscn` — 11 checks: defeat reward at
tolerance 0 and 50, Focus loss, build/upgrade/sell/cancel economy, failed-build abort,
victory signal fires once.

Wire the dormant `SignalBus` (16 signals declared, 2 emitted, **0 listeners** today). Doc 03's own
verdict: *"finish the migration, or delete the unused half — a bus nothing listens to is a worse
trap than no bus at all."* Every signal gets an explicit disposition; none are left in limbo.

| Signal | Disposition |
|---|---|
| `distraction_defeated`, `distraction_escaped` | **Keep dual-channel deliberately.** `Distraction`'s local `defeated`/`reached_core` stay (per-instance work: kill feedback, particles, glitch spike). The same `_die()`/`_reach_core()` also emit to the bus for `GameState` (economy/focus). Two channels, two audiences — not duplication. |
| `habit_built`, `habit_upgraded`, `habit_sold` | Wire as **notification-only** — see Hazard 1. |
| `build_requested`, `build_canceled` | Wire notify-only around aiming-mode entry/exit. |
| `wave_started`, `wave_completed`, `distraction_spawned` | Wire — maps 1:1 to existing call sites. |
| `level_started` | Wire, emitted once from `_ready()`. |
| `game_over(victory: bool)` | Wire as a **unified** signal — see Hazard 3. |
| `game_state_changed`, `dopamine_changed`, `focus_changed`, `tolerance_changed` | **Delete.** No `MatchState` enum exists and isn't worth inventing. The other three collide in shape with `GameState`'s real working signals (`dopamine_changed(value)` vs bus's `(current, difference)`) — don't run two differently-shaped signals with the same name. |

`GameState` becomes a bus **listener**, but its outward `*_changed` API (which the HUD, including
the Left/Field/Kills counter, already connects to) does not change shape.

### Hazard guards — these are load-bearing

1. **Build/upgrade must stay imperative, not signal-reactive.** `_build_on()`/`_do_upgrade()` call
   `GameState.spend_dopamine()` as a **gate that aborts the action** on insufficient funds. This is
   structurally unlike `distraction_defeated` (fires after a completed fact, nothing to abort). If
   `habit_built` became "build first, emit, GameState deducts," the affordability check disappears
   and **buildings become free**. Keep the spend/refund calls exactly where they are.
2. **Cancel-during-aiming refunds 100%, sell refunds 50% — deliberately.** The aiming-cancel path
   in `_unhandled_input()` does `add_dopamine(full cost)` then calls `sell_habit()` purely for its
   cleanup side effect, discarding its 50% return. A signal-driven refund must not flatten this to
   50%, nor double-pay by combining both.
3. **`game_over(victory)` unification must preserve the asymmetry.** `_level_complete()` computes
   a star rating and calls `MetaProgression.complete_level()` (writes the save); `_game_over()`
   does neither. The shared `game_ended` guard must survive the merge, or a same-frame kill +
   core-breach becomes a double-fire path again.

**Verify:** identical Dopamine/Focus/Wave/Tolerance/Kills readouts in the same scripted scenario
before and after.

---

## Phase 3 — `StatusManager` component ✅ DONE

**Shipped:** `scripts/components/status_manager.gd` (`class_name StatusManager extends Node`)
extracts the three status effects (Calm/Slow, Reframe, Boredom) from `Distraction`
(`enemy.gd`) into a reusable child `Node`.

**Key design decisions:**
- `StatusManager` is pure logic — no `_process()`, no visuals. The parent calls
  `tick(delta)` explicitly at the top of its own `_process()`, before any early returns.
- `boredom_damage(amount: int)` signal notifies the parent of whole-point Boredom
  accumulations, keeping the mid-tick kill check in Distraction's `take_direct_damage()`.
- `reframe_changed(amount: int)` signal lets the parent `queue_redraw()` for the
  cracked-ring visual tell without polling.
- `Distraction` keeps **thin delegating wrappers** (`apply_slow()`, `apply_reframe()`,
  `apply_boredom()`, `effective_compulsion()`, `effective_rationalization()`) so `tower.gd`
  and `game.gd` call sites are completely unchanged.

**Preserved byte-for-byte:** strongest-wins with inverted comparison for slow (lower =
stronger), duration never truncated via `maxf()`, fractional `_boredom_accum` so low DPS
still lands, Boredom mid-tick kill check, statuses ticking before blocked/unrouted early
returns, Reframe stripping both Compulsion and Rationalization.

**Test harness:** `_test_phase3.gd` / `_test_phase3.tscn` — 23 checks: slow/reframe/boredom
strongest-wins and expiry, fractional accumulator, mid-tick kill, status ticking while
blocked, economy parity regression.

### Lessons — read before Phase 4

- **GDScript closures capture primitives by value.** A `var count := 0` captured by a
  lambda is a copy — `count += 1` inside the lambda does not affect the outer variable.
  Use an `Array` (`[0]`) or `Dictionary` for mutable state shared with lambdas.
- **Godot signals are synchronous by default.** `signal.emit()` calls all connected
  handlers inline before returning. This is what makes the boredom mid-tick kill work:
  `boredom_damage.emit(whole)` → `_on_boredom_damage()` → `take_direct_damage()` →
  `_die()` all within the same `tick()` call.
- **Test harness game_over double-fire.** When disconnecting the real handler to intercept
  `game_over`, the test must still set `game_ended = true` — otherwise `_process()` →
  `_check_wave_progress()` fires the signal again on the next frame.

Extract Calm/Reframe/Boredom from `Distraction` into a child `Node`
(`scripts/components/status_manager.gd`) — doc 04's own explicitly-named remaining gap.

**Preserve byte-for-byte:**
- "Strongest wins, duration never truncated" — including the **inverted** comparison direction:
  slow uses `factor <= slow_factor` (lower is stronger), reframe/boredom use `>=` (higher is stronger).
- Statuses tick **before** any `_process()` early return, so a blocked/unrouted distraction still
  sheds Calm/Reframe on schedule and still takes Boredom damage.
- Boredom's fractional accumulator (`_boredom_accum`) so low DPS still lands over time, and its
  mid-tick kill check.
- Reframe strips **both** Compulsion and Rationalization; both floor at 0.

**Hard constraint:** `Distraction` keeps `apply_slow`/`apply_reframe`/`apply_boredom`/`take_damage`
as thin **delegating wrappers**. `tower.gd`'s AoE pulse calls these directly in a specific order
(Reframe before damage), and Phase 4 must not have to re-verify Phase 3's internals.

---

## Phase 4 — `AttackComponent` + `BaseHabit`/`Habit`/`Barracks` ⬜

**Components:** `AttackComponent` base + `SweepAttack` / `PulseAttack`, selected by `HabitData.aoe`.

**Inheritance:** `BaseHabit` (build cost, cell, upgrade bookkeeping, `_draw()` framing) →
`Habit` (attack component + work/rest cycle) and `Barracks` (Accountability's ally training).
`BaseHabit` rather than `Barracks extends Habit`, because `is_blocker` currently forks the *entire*
`_process()`/`_draw()` body — a Habit parent would drag in firing state (`cooldown`, `_aim`,
`arc_angle`) a barracks never uses.

**Preserve:** cone math exactly; continuous sweep with no lock-on; Reframe-before-damage ordering in
the AoE pulse; the wave-active gate (`game.started and not game.between_waves`) on both firing and
the work timer; sweep halting during a break; Allies parented as **siblings** under `entities`, not
children of the barracks (Y-sort would break).

**Verify, two tiers** — the aiming state machine is real mouse input, not pure logic:
- (a) automated harness: cone math, cooldown timers, wave-active gate.
- (b) **manual in-editor click-through**: build→aim→lock, build→aim→cancel, re-aim,
  right-click-deselect. The harness cannot realistically drive these.

---

## Phase 5 — Coupling cleanup ✅ DONE

Replace direct `game.distractions` / `game.allies` / `game.habits` reach-ins from `tower.gd`,
`ally.gd`, `enemy.gd`, `projectile.gd`, `build_spot.gd` with either a small typed accessor on
`Game` (for genuine per-frame "what's live now" queries — targeting scans are legitimately polling,
**not** events) or bus events (for state changes).

Target the known-fragile spots specifically: the write-only `habits`/`allies` arrays (populated by
other scripts, never read by their owner), the duck-typed `"allies" in game` check, and
bidirectional field-name coupling on public vars. **Not** eliminating every direct read.

---

## Phase 6 — `ObjectPool` + pooling ⬜

Generalize the existing `_burst_pool` in `game.gd` (already pool-shaped — the one working
precedent) into `scripts/object_pool.gd`: factory callable + fixed size + `acquire()`/`release()`.

Apply to `Projectile` (zero pooling today; fires as often as every 0.06s at Deep Focus tier) and
its impact FX.

**Note honestly:** impact-FX pooling is **new object design, not a generalization** —
`_create_impact_fx()` builds a throwaway `Node2D` with a self-freeing closure tween, the opposite
shape of the pre-built/`restart()` burst pool. And pooling fixes allocation/GC churn **only** — it
does not touch `Projectile._process()`'s O(projectiles × live distractions) per-frame proximity
scan. That scan is a separate optimization, out of scope.

---

## Phase 7 — Final docs sync ✅ DONE

Update `docs/core/00_overview.md`'s status table and any Intersection sections not already updated
inline. Also fix confirmed pre-existing drift: doc 07 says habits are parented via
`game.add_child(h)`; the real code uses `game.entities.add_child(h)`.

---

## Verification pattern (used every phase)

Temp `.gd` (`extends Node`) + minimal `.tscn` wrapper, run headless:

```
--headless --path "<proj>" --main-scene "res://scenes/_test_x.tscn"
```

- **`--script` mode does NOT have autoloads** (`Data`, `GameState`…) — they aren't registered yet,
  so referencing them is a compile error. Use `--main-scene` with a `Node`-rooted temp scene.
- Use a `completed := false` sentinel set only at the very end, plus a `Timer` watchdog that
  reports failure if it is still false — a mid-test script error silently aborts the coroutine
  without raising, which otherwise looks like a hang or produces a false pass.
- **Any harness that spawns distractions without building towers must pin `GameState.focus` and
  `max_focus` high.** Otherwise Focus hits 0, `_game_over()` calls `change_scene_to_file()`, and
  that frees the *entire* current scene tree — including the harness and its watchdog. Looks
  exactly like an engine hang; is not.
- Delete both temp files (and the `.gd.uid` sidecar) after the run.
