# Horde performance, flow field movement (P4)

Same methodology and the SAME N steps as T11 below, rerun after docs/refactor/PATHFINDING.MD
P4 replaced per-unit `AStarGrid2D.get_id_path()` + `cell_path`/`path_index` walking with
every `Distraction` reading its next step from the one shared `FlowField` (P1) each frame —
see `scripts/enemy.gd` and `scripts/game.gd`'s `_rebuild_flow_field()`. `_perf_horde.gd` was
not touched; this is the same harness, same level (99), same vsync-off/wall-clock method.

Machine: this dev machine, single run, 2026-08-30T11:37:30.

| N | avg frame (ms) | avg FPS | worst frame (ms) | spawn+path (ms) |
|---|---|---|---|---|
| 50 | 6.27 | 159.4 | 10.59 | 901.3 |
| 100 | 12.38 | 80.8 | 16.44 | 2.0 |
| 200 | 25.19 | 39.7 | 31.22 | 3.6 |
| 500 | 52.64 | 19.0 | 100.54 | 9.9 |
| 1000 | 65.76 | 15.2 | 169.84 | 15.7 |

## Versus the T11 baseline

| N | avg ms: T11 → P4 | worst ms: T11 → P4 |
|---|---|---|
| 50 | 6.23 → 6.27 (+0.6%) | 8.23 → 10.59 (+28.7%) |
| 100 | 12.29 → 12.38 (+0.7%) | 20.34 → 16.44 (−19.2%) |
| 200 | 27.29 → 25.19 (−7.7%) | 36.41 → 31.22 (−14.3%) |
| 500 | 62.76 → 52.64 (−16.1%) | 108.91 → 100.54 (−7.7%) |
| 1000 | 88.28 → 65.76 (−25.5%) | 201.91 → 169.84 (−15.9%) |

**Better at every N from 200 up, roughly flat at 50-100, one noisy outlier.** N=50's worst
frame is the only regression (+2.36ms) and it lands in the SAME step whose own
`spawn+path` column shows 901.3ms — three orders of magnitude above every later step's
2-16ms. That is first-frame engine warm-up (first texture loads, first shader
compiles, first `ObjectPool` grows), not a per-unit movement cost; it was already present
under T11's own methodology (the harness doesn't isolate steady-state from cold-start), so
it is reported as measured rather than discarded, but it should not be read as "the new
movement is slower for a small horde." Every N from 200 up is unambiguously faster, and the
gap widens with N — consistent with the mechanism: the OLD path handed each spawned unit a
full `AStarGrid2D.get_id_path()` solve (a real per-spawn search cost baked into that step's
`spawn+path` window); the NEW path is one dictionary lookup into an already-built field, so
the per-spawn cost that used to scale with maze size no longer scales with anything. (T11's
own console output did not save its per-step `spawn+path` timings — only the frame table
survived into docs/PERF.md — so that specific number has no direct old-vs-new comparison
here; the frame-time columns above are the ones actually re-measured against a saved
baseline.)

## Does this reopen P3 (dirty-region flow field recompute)?

No, and the reason is different from P2's: `FlowField.build()` is not being called any more
often under this workload than it was under P1/P2's own benches — it runs exactly ONCE per
level here (nothing sinks a wall during this bench), same as at level start. What P4 adds is
a `direction()`/`has_cell()` READ per live distraction per frame — two `Dictionary` lookups,
O(1) each, independent of maze size. At N=1000 that is ~2000 lookups/frame, immeasurably
below any budget concern; the frametime cost visible in the table above is movement,
rendering and `_draw()` redraw across 1000 nodes, not field access. P3 stays closed. If a
future task starts rebuilding the field on a much tighter cadence (e.g. per-unit-per-frame
recompute rather than per-wall-change), THAT is the moment to re-measure — not this one.

## Tower targeting spatial hash (P4)

Not covered by this bench (`_perf_horde.gd` builds no habits — see its own header), so no
new numbers here; `tower.gd`'s `_aoe_targets()`, `has_enemy_in_cone()` and `_tick_auto_aim()`
now query `Game.query_distractions_near()` (a distraction-by-cell hash rebuilt once per
frame) instead of scanning `get_live_distractions()`. Worth being honest about the actual
payoff on THIS map: most habits carry ranges of 260-560px against a 480x224px playfield (see
`data/habits/*.tres`), so for most towers a range query still has to touch most of the
board — the hash does not shrink the CANDIDATE set much when the range already covers nearly
everything. Where it helps is that the hash only visits OCCUPIED cells: a horde marching
single-file down a lane leaves most of the board's cells empty, so even a full-board query
touches at most "cells the horde is standing on" rather than every live distraction
individually. Real, but modest on this map size — flagged rather than benched separately
because `_test_suppression`'s AoE/knockback coverage and the full `verify.sh` pass are what
actually exercise this path today, and inventing a synthetic multi-tower bench for a change
this small would cost more than it would prove (see P1/P2's own precedent of not
over-building past the measured budget).

---

# Horde performance (T11)

Frametime scaling with N live distractions all walking the path, on level 99 (Isometric Vertical Slice), vsync off. Cumulative: each N tops up the population from the previous step rather than resetting the level. Measured, not optimized — see docs/refactor/MIGRATION.MD T11.

Machine: this dev machine, single run, 2026-08-29T10:48:44.

| N | avg frame (ms) | avg FPS | worst frame (ms) |
|---|---|---|---|
| 50 | 6.23 | 160.6 | 8.23 |
| 100 | 12.29 | 81.4 | 20.34 |
| 200 | 27.29 | 36.6 | 36.41 |
| 500 | 62.76 | 15.9 | 108.91 |
| 1000 | 88.28 | 11.3 | 201.91 |

# Flow field / anti-block (P1, P2)

`FlowField.build()` — single unweighted BFS, `Data.GRID` 30x14 (largest current map). See docs/refactor/PATHFINDING.MD P1/P2 and `scripts/_test_flowfield.gd` / `scripts/_test_antiblock.gd`.

Machine: this dev machine, 2026-08-30.

| Measurement | Value | Budget |
|---|---|---|
| Full field rebuild, largest map | 583.9 µs avg / 50 runs | 5000 µs |
| Anti-block single-wall check, real map (level_1, 27 walls) | 559.5 µs avg / 50 runs | 1000 µs |
| Anti-block rapid sequential build (30 walls, real map) | 550.3 µs avg/wall (~1817 walls/sec ceiling) | — |

The rapid-build ceiling is ~0.55% of the interval between clicks for a 10 clicks/sec player (the only real "how fast can a player place something" reference in this codebase — see BLOCKED.md's P3 closure for the full reasoning). Basis for closing docs/refactor/PATHFINDING.MD's P3 as obsolete-but-revisitable.
