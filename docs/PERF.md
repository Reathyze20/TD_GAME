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
