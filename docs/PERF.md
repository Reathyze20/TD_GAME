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
