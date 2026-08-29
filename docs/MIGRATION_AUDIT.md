# MIGRATION_AUDIT.md — Inventura perspektivy (T3)

READ-ONLY audit. Nothing in the code was changed. All line numbers refer to branch
`iso-to-topdown` at commit `3edfef4`.

The board today is a **2:1 diamond isometric projection**: `Data.GRID` is `cols 24, rows 24,
tile 32, tile_w 64, tile_h 32, origin (960, 120)` (`scripts/data.gd:11-19`).

Two distinct spaces exist in the codebase and the distinction is load-bearing:

* **screen space** — what `position` / `global_position` hold, what Godot draws.
* **"ground space"** — screen space with the Y component multiplied by 2 (un-squashing the
  2:1 projection). Combat range and line-of-sight are measured here; several other radii are not
  (see §1.4). There is no named type or helper for this — it is written out by hand at every site.

---

## 1. Every map↔screen coordinate conversion

### 1.1 Canonical layer — `scripts/data.gd`

| What | Where | Direction |
|---|---|---|
| `GRID` dictionary (cols/rows/tile/tile_w/tile_h/origin_x/origin_y) | `scripts/data.gd:11-19` | — |
| `Data.build_block(cell)` — cell → 3×3 block key | `scripts/data.gd:28-32` | grid→grid (integer only, perspective-agnostic) |
| `Data.cell_center(cell)` — **the** grid→screen converter | `scripts/data.gd:36-44` | grid → screen |
| `Data.world_to_cell(pos)` — **the** screen→grid converter (clamps out-of-grid input) | `scripts/data.gd:46-54` | screen → grid |
| `Data.in_bounds(cell)` | `scripts/data.gd:56-58` | grid only |
| `Data.pixel_scale()` / `ISO_PIXEL_SCALE` | `scripts/data.gd:120, 137, 139-143` | art raster, not coordinates |

The projection formula itself (verified against source):

```
cell_center:   x = ox + (cx - cy) * tw/2
               y = oy + (cx + cy + 1) * th/2
world_to_cell: col = floor(dx/tw + dy/th)
               row = floor(dy/th - dx/tw)
```

A round-trip test over all 24×24 cells exists: `scripts/_test_iso_math.gd:12-22` — but note (per
PROGRESS.md T0) this script has no matching `.tscn` and cannot actually be run by verify.sh today.

### 1.2 Thin re-exports (not new math, but they hide the dependency)

* `scripts/game.gd:1451-1452` `Game.cell_center()` → `Data.cell_center()`
* `scripts/game.gd:1454-1455` `Game.world_to_cell()` → `Data.world_to_cell()`
* `scripts/game.gd:1457-1458` `Game._in_bounds()` → `Data.in_bounds()`
* `scripts/animation_test.gd:43-44, 121-122`
* `tools/map_editor.gd:929-930`

These are harmless today but mean "calls `Data`" is not greppable as a single symbol.

### 1.3 Independent projection math outside `Data` — **the T4 targets**

These are the sites that would have to change or be routed through `GridProjection`.
Marked **[G]** where the value feeds gameplay, **[V]** where it only feeds rendering.

**Ground↔screen Y squash (hardcoded `* 0.5` / `* 2.0`):**

| # | File:line | What |
|---|---|---|
| 1 | `scripts/game.gd:1514` | **[G]** `cast_to_wall()` ray march: `from + Vector2(dir.x, dir.y * 0.5) * d` |
| 2 | `scripts/game.gd:1521-1526` | **[G]** `has_line_of_sight()`: `dy = (to.y - from.y) * 2.0` |
| 3 | `scripts/tower.gd:177-183` | **[G]** auto-aim centroid in ground space (`* 2.0`) |
| 4 | `scripts/tower.gd:261-269` | **[G]** `is_point_in_cone()` — range **and** arc test (`* 2.0`) — verified against source |
| 5 | `scripts/tower.gd:438` | **[G]** shot direction + muzzle spawn: `Vector2(cos, sin * 0.5)` |
| 6 | `scripts/projectile.gd:102` | **[G]** `direction_vec = Vector2(cos(a), sin(a) * 0.5)` — the flight path itself |
| 7 | `scripts/projectile.gd:180` | **[G]** knockback direction re-normalised from the flattened vector |
| 8 | `scripts/game.gd:3550-3554` | **[G]** aiming mode: mouse → `facing_angle` + `arc_angle` (`* 2.0`) |
| 9 | `scripts/game.gd:4130-4132` | **[G]** split-spawn scatter `Vector2(cos, sin * 0.5)` |
| 10 | `scripts/enemy.gd:248-259` | **[V]** `note_heading()` — grid axes → screen diagonals (`dir.x * 0.5 ± dir.y`), picks the walk animation |
| 11 | `scripts/tower.gd:648, 835-836, 850, 889` | **[V]** turret head / recoil / muzzle direction flattening |
| 12 | `scripts/tower.gd:975, 997` | **[V]** wedge-preview ray directions — must stay in step with #1 |
| 13 | `scripts/tower.gd:798, 813, 903` | **[V]** range ring / ground glow as 2:1 ellipse |
| 14 | `scripts/impact_fx.gd:47-53` | **[V]** impact fan flattened |
| 15 | `scripts/defender_unit.gd:511` | **[V]** contact shadow squash — **`0.42`, not `0.5`** (eyeballed, pre-iso) |
| 16 | `scripts/components/distraction_animator.gd:192-195` | **[V]** contact shadow squash — `1.45` drop, alpha by `is_flying` |
| 17 | `scripts/game.gd:1449` | **[V]** placement preview radius ellipse `(pr, pr * 0.5)` |

**Diamond geometry built from `tile_w`/`tile_h` rather than from `cell_center`:**

| # | File:line | What |
|---|---|---|
| 18 | `scripts/game.gd:505-543` | **[V]** `_build_wall_segments()` — top cap + face parallelograms |
| 19 | `scripts/game.gd:585-598` | **[V]** `TerraceShadow._draw()` — per-cell diamond |
| 20 | `scripts/game.gd:637-641, 655` | **[V]** `_build_terrace_blocks()` — anchor derived from art + `th * 0.5` |
| 21 | `scripts/game.gd:660-673` | **[V]** `_spawn_wall_segment()` — `WALL_HEIGHT` extrusion |
| 22 | `scripts/game.gd:1385-1418` | **[V]** `_draw_static_field()` — spawn/trod diamonds, build dots |
| 23 | `scripts/game.gd:1425-1443` | **[V]** `_draw_placement_preview()` — 3×3 hover diamond |
| 24 | `scripts/game.gd:2443-2453` | **[G/V]** `board_bounds()` — **its own** derivation of the iso diamond AABB; feeds `Camera2D` limits at `game.gd:2455-2480` |

**Second, independent projection: Godot's own `TileMapLayer` isometric transform.**
Godot's `DIAMOND_DOWN` `map_to_local()` returns `((x-y+1)*w/2, (x+y+1)*h/2)`, i.e. **half a tile
to the right** of `Data.cell_center()`. The difference is corrected by offsetting the layer:

| # | File:line | What |
|---|---|---|
| 25 | `scripts/game.gd:1093-1096` | `TileSet` set to `TILE_SHAPE_ISOMETRIC` / `TILE_LAYOUT_DIAMOND_DOWN`, `tile_size = (tw, th)` |
| 26 | `scripts/game.gd:1178-1192` | **the half-tile fix**: `path_layer.position = (origin_x - tw*0.5, origin_y)`, with the measurement written up in the comment |
| 27 | `tools/map_editor.gd:345-362` | same fix in the editor (`_layer_origin()`) |
| 28 | `tools/map_editor.gd:127-130, 193-195, 708-711` | editor's own iso `TileSet` + layer placement |
| 29 | `scripts/_probe_align.gd:16-25` | the probe that measured the (32, 0) drift |
| 30 | `scripts/_test_mapeditor.gd:60-92` | asserts editor `map_to_local()` == `Data.cell_center()` |

**Editor / tooling with their own formulas** (`MIGRATION.MD` T8 says do not touch
`addons/td_level_designer/`, which in fact contains no coordinate math — the editor lives in
`tools/map_editor.gd`):

| # | File:line | What |
|---|---|---|
| 31 | `tools/map_editor.gd:1808-1810` | **a second inline iso formula**: `(cx-cy)*tw/2, (cx+cy)*th/2` — note **no `+1`** on Y. It computes cell *corners*, not centres, so it is arguably correct (corner vs centre = `th/2`), but it is a separate hand-written projection. Not run to confirm — see uncertainty §3. |
| 32 | `tools/map_editor.gd:934-943` | `_cell_diamond()` from `tw`/`th` |
| 33 | `tools/map_editor.gd:1419, 1439-1440` | `D.world_to_cell()` for reading objective / spawn rects back out of the scene |
| 34 | `tools/stylized_renderer.gd:19, 243, 376, 385-394, 407-408, 425` | **square** preview renderer with `const CELL := 48` hardcoded — disagrees with the game (already flagged in `docs/core/16_isometric_slice.md` §10) |
| 35 | `tools/regrid_levels.py` | offline 40×19 → 120×57 regrid; documents that the projection was not supposed to move |

**Stale square-grid math still present in `scripts/` (top-down leftovers):**

| # | File:line | Status |
|---|---|---|
| 36 | `scripts/game.gd:898-987` `_build_shadow_occluders()` — `ox + span.x * tile, oy + y * tile` | **LIVE-CALLED** at `game.gd:252` (verified). Square math on an iso board. Only matters when `level.shadows` is on, and both iso levels set `shadows = false`, so it is currently invisible rather than fixed. **Flagging as a real inconsistency.** |
| 37 | `scripts/game.gd:2334-2335` | **LIVE**: "whole board" intervention frame built as `Rect2(origin, cols*tile, rows*tile)` — a square, while the board is a diamond. Cosmetic but wrong today. |
| 38 | `scripts/game.gd:2200-2205, 2220` | `_draw()` locals `w = cols*tile`, `h = rows*tile`, `base_radius = tile*0.45` — square-derived |
| 39 | `scripts/game.gd:3213-3214` | panel placement mixes screen px with `g.tile * 2.2` |
| 40 | `scripts/decor_layer.gd:105-108` | **square forward *and* inverse conversion** written out by hand (`origin + cell*tile + tile/2`, then `int((centre - origin)/tile)`). Its builder `Game._build_decor_layer()` (`game.gd:989`) is **not called anywhere** — dead on this branch, but it is a complete second coordinate system living in `scripts/`. |
| 41 | `scripts/game.gd:781-786, 790-806, 837-…` | `WallShadow` / `_build_wall_shadow_layer` / `_build_wall_face_layer` — square, **uncalled** |
| 42 | `scripts/game.gd:1044-1046, 1273-1345` | `_build_terrain_layer` / `_build_corner_terrain` — square `TileSet`, `position = origin - tile/2`. **Dead code, explicitly documented as such** at `game.gd:5059-5064` |

**Plain `Data.*` call sites (correct today, but they are where a projection swap surfaces).**
Non-exhaustive but complete for gameplay paths:
`game.gd:299, 515, 592, 655, 1019, 1387, 1404, 1417, 1435-1438, 1448, 1505, 1532, 1916-1917, 1927, 1950, 2214, 2374, 2550, 3641, 3881, 4103, 4995`;
`enemy.gd:225, 522`; `base_habit.gd:53`; `barracks.gd:149`; `boss.gd:51`; `projectile.gd:207`.

### 1.4 The unresolved half of the projection: **which radii are ground-space and which are not**

`docs/core/16_isometric_slice.md` §9 poses this as an open design decision (Option A: keep screen
circles; Option B: convert to ground space). **The branch shipped a mix, and no document says that
was deliberate.** This is the single most important thing for a human to confirm before T4/T5:

**Ground space (Option B) — anisotropy corrected:**
* tower range + cone — `tower.gd:261-272` (verified: `dy = (target_pos.y - global_position.y) * 2.0`)
* auto-aim — `tower.gd:177-183`
* line of sight / wall shading — `game.gd:1510-1527`
* projectile flight + max travel — `projectile.gd:102, 213`
* player aiming — `game.gd:3550-3554`

**Screen space (Option A) — still a screen circle, therefore an ellipse on the ground:**
* `is_position_in_routine()` — `game.gd:3627-3632` (verified: plain `pos.distance_to(src_pos)`,
  no ground-space correction), using `CORE_ROUTINE_RADIUS = 330.0` / `ANCHOR_ROUTINE_RADIUS = 260.0`
  (`game.gd:4207-4208`). This gates **whether a habit works at all** (`game.gd:3592`) and
  **whether a cell is buildable** (`game.gd:2948-2950`).
* intervention AoE damage / freeze — `game.gd:3086, 3095`
* Brain Fog lit-cell marking — `game.gd:1918, 1927-1931` (drives `is_pos_visible()`, `game.gd:1945-1950`,
  which gates the projectile hit loop and `is_point_in_cone`)
* defender guard zone — `defender_unit.gd:202-203`
* barracks rally leash — `barracks.gd:147`
* enemy `distance_to_core()` — `enemy.gd:261-262`
* sinking-wall block choice — `game.gd:4995`

So today a tower's *reach* is isotropic on the ground but its *light*, the *Routine* that switches it
on, and the *guard zone* around it are not. Under a top-down square projection this whole distinction
collapses (ground space == screen space), which is a genuine simplification — but it also means the
gameplay values above will silently change shape. Any T2-style characterization test that pins them
will move.

---

## 2. Are the baked levels in `data/` perspective-dependent?

**Answer: the schema is perspective-agnostic; the live level files are grid-only; but the levels are
grid-*size*-dependent and two of the four are on a dead grid.**

### 2.1 Schema — `scripts/resources/level_data.gd`

| Field | Line | Space | Perspective-dependent? |
|---|---|---|---|
| `objective: Vector2i` | `:79` | grid cell | No |
| `spawn_zones: Array[Rect2i]` | `:80` | grid rects | No |
| `high_ground: Array[Vector2i]` | `:82` | grid cells | No |
| `terrain_tiles: Dictionary` | `:93` | cell → `Vector3i(source, atlas_x, atlas_y)` | Art only; deliberately split from `high_ground` (`:86-92`) |
| `tile_overrides: Dictionary` | `:104` | cell → art path | Art only, explicitly "ČISTĚ VZHLED" (`:98-101`) |
| `path_cells: Array[Vector2i]` | `:125` | grid cells | No |
| `trods: Array[TrodData]` | `:137` | grid cells | No |
| **`decor: Array[Dictionary]`** | **`:106-112`** | **`pos: Vector2` in field PIXELS** | **YES — the one screen-space field in the schema** |

`decor` is the only screen-space storage. Everything else is `Vector2i` / `Rect2i` grid indices.

**However: no live level actually uses `decor`.** `grep '^decor = '` over `data/levels/` matches only
`level_1.tres.bak` and `level_1.tres.bak2` (backups). `level_1.tres`, `level_2.tres`,
`level_iso.tres` and `level_iso_1.tres` have no `decor` block. The consumer,
`DecorLayer.build()` (`scripts/decor_layer.gd:52-60`), therefore always falls through to its seeded
scatter — and its builder `Game._build_decor_layer()` is not called at all on this branch.

### 2.2 The actual files

| File | `id` | `objective` | Grid it assumes | Playable? |
|---|---|---|---|---|
| `data/levels/level_1.tres` | 1 | `Vector2i(109, 34)` | ~120×57 (old top-down regrid) | **No** — outside the 24×24 `Data.GRID` (independently confirmed: this exact out-of-bounds objective is the root cause of 6 of the 7 pre-existing `verify.sh` test failures logged in PROGRESS.md's T0 entry) |
| `data/levels/level_2.tres` | 2 | `Vector2i(106, 31)` | ~120×57 | **No** |
| `data/levels/level_iso.tres` | 99 | `Vector2i(22, 13)` | 24×24 | Yes |
| `data/levels/level_iso_1.tres` | 98 | `Vector2i(1, 22)` | 24×24 | Yes |

`level_1.tres` also has `path_cells` with **negative** Y (`Vector2i(0, -3)`), i.e. off-grid.
`scripts/data.gd:122-136` states plainly that level_1/level_2 "are currently unplayable pending
their own migration".

Also perspective-adjacent, though art rather than geometry: `tile_overrides` in `level_iso_1.tres`
names paths relative to `assets/terrain/iso/` (`"props/spawn_rift"`), and `terrain_tiles` in
`level_2.tres` indexes the square `high_ground_tileset.tres`. A top-down migration needs new art
keys, but not new coordinates.

**Conclusion for T6:** the level data does **not** need a projection change — it needs a **grid
rescale** for level_1/level_2 (120×57 → whatever the top-down grid becomes) and nothing at all for
the two iso levels beyond art keys. `tools/regrid_levels.py` is the existing precedent for exactly
this operation and documents why an exact-integer ratio is required.

---

## 3. Is Y-sorting / elevation a gameplay mechanic or purely visual?

### 3.1 Y-sorting: **purely visual.**

* Enabled once, on one container: `entities.y_sort_enabled = true` — `scripts/game.gd:228-231`.
* Nothing reads sort order back. No targeting, pathfinding, damage or LOS code consults draw order.
* `docs/core/01_rendering_and_depth.md` §1-§3 describes it as pure rendering plumbing.
* `docs/core/16_isometric_slice.md` §2 notes it transfers to iso for free: in a 2:1 projection
  `screen_y = (x+y)*th/2`, so sorting by screen-Y *is* sorting by `x+y`. Under a square top-down
  projection it stays correct for the same reason.
* Fixed z-index bands are `game.gd:52-61` (`Z_BACKGROUND -40` … `Z_FOG 60`).

One consequence worth knowing: because `position` is both the y-sort key and the gameplay
measurement point, they cannot be separated. This is stated explicitly and was learned the hard
way — see §3.2.

### 3.2 Elevation / `WALL_HEIGHT`: **purely visual, and deliberately so.**

`const WALL_HEIGHT := 32.0` — `scripts/game.gd:424`.

* `scripts/base_habit.gd:54-72` is the definitive comment, verified verbatim against source. A
  habit built on high ground gets `_iso_lift = game.WALL_HEIGHT` (`:71-72`), and that value is
  applied **only inside `_draw()`** as a canvas transform (`tower.gd:747, 770`; `barracks.gd:165`).
  The node's `position` stays at ground level.
* The comment records that the first attempt subtracted `WALL_HEIGHT` from `position` directly and
  was reverted, because `position` is simultaneously the y-sort key and "the point every
  range/distance/targeting check measures from" — raising it "would have silently shrunk every
  combat range … against enemies that stay at ground level".
* Other `WALL_HEIGHT` uses are all geometry for drawing: `game.gd:520-523` (wall cap),
  `game.gd:665-666` (wall face extrusion), `game.gd:1434-1448` (hover preview lift).
* There is **no elevation field** on any entity, no `z`/`height` on `DistractionData` or
  `HabitData`, and no height term in any damage, range or pathing formula.

**High ground does not give a height *advantage*.** A tower on a plateau has exactly the range a
tower on flat ground would have.

`is_flying` (`scripts/resources/distraction_data.gd:12`) is the closest thing to a second elevation,
and it is a **boolean gameplay flag, not a height value**: flyers skip A* (`game.gd:1530-1531`),
steer straight (`enemy.gd:213`), ignore knockback terrain checks (`enemy.gd:521-523`) and are
untargetable by defenders (`defender_unit.gd:218`). No coordinate is involved.

---

## 4. Does "High ground" affect range / targeting / LOS, or is it just a name?

**Answer: it is a real, load-bearing gameplay mechanic — but through *occlusion and buildability*,
not through *height*.** Four distinct effects, all keyed off the same `high_ground` cell set:

`LevelData.high_ground` is documented as "Gameplay truth: these cells block movement AND are the
only buildable spots" (`scripts/resources/level_data.gd:81-82`). At runtime it becomes
`Game.high_ground` (`game.gd:32`, filled at `game.gd:302-309`).

**(a) It blocks movement.**
`astar.set_point_solid(cell, true)` — `game.gd:309`. Also blocks knockback landing
(`enemy.gd:521-523`) and rally placement (`barracks.gd:149`; preview `game.gd:2374`) and projectile
travel (`projectile.gd:206-211`).

**(b) It is the only buildable terrain.**
Build spots are created only where a whole 3×3 block is high ground — `game.gd:311-328`.

**(c) It blocks line of sight — this is the real "range" effect.**
* `cast_to_wall()` — `game.gd:1510-1518`
* `has_line_of_sight()` — `game.gd:1520-1527`
* consumed by `Tower.is_point_in_cone()` — `tower.gd:278` (so a target behind a wall is genuinely
  unhittable), by the AoE pulse — `tower.gd:555`, by the shaded wedge preview — `tower.gd:970-1000`,
  and by the projectile's wall death — `projectile.gd:206-211`.

**(d) Slabs, not cells — the self-shadowing rule.**
`_build_platforms()` (`game.gd:1482-1500`) 8-connectivity flood-fills `high_ground` into slabs;
`platform_at()` (`game.gd:1504-1505`) reports which slab a position stands on. **A ray never blocks
on the slab it started from** (`game.gd:1515`). This is the documented LOS bug fix: the old rule
exempted only the single start cell, and since every build spot is on high ground in 48-cell slabs,
towers shadowed themselves — measured as "the ray died after 24 px against a ~300 px reach, in 7 of
8 directions" (`game.gd:1471-1481`).

**The test harness confirms all of this mechanically.** `scripts/_test_los.gd` asserts:
* every build spot stands on high ground and the slabs are more than one piece (`:55-62`)
* **"PAPRSEK SE NIKDY NESMÍ ZASTAVIT NA VLASTNÍ PLOŠINĚ STŘELCE"** — 40 spots × 16 directions,
  none may die on its own slab (`:68-90`)
* the nearest foreign cut-off is further than one tile (`:91-93`)
* **and, crucially, that a *foreign* wall still stops the ray** (`:95-109`) — so the mechanic is
  proven live, not merely disabled.

**(e) It is also a runtime-mutable mechanic.**
The `sinking_walls` spike (`level_data.gd:52`; `game.gd:4961-5055`) erases cells from `high_ground`
and `level.high_ground` above a Tolerance threshold, re-runs `_build_platforms()`, rebuilds walls,
and repaths every live distraction. So `high_ground` is not static level data at runtime.

**One honest gap, already documented in the code.** `game.gd:1585-1589`: the Brain Fog light does
**not** stop at walls, while `is_point_in_cone()` does. A cell behind high ground can be *lit* and
still unshootable. Recorded there deliberately so it is not rediscovered as a bug.

**Caveat for the migration.** `game.gd:4941-4943` claims the sinking-walls mechanic "is
isometric-native: height IS the projection, so a block dropping to path level is legible in iso and
literally invisible top-down. This is the first mechanic the flat version of the game cannot have."
That is an art/legibility claim, not a mechanical one — the mechanic itself is pure cell-set
mutation and will keep working — but it is a design decision a human should make consciously before
T5.

---

## Summary for T4/T5 planning

* One canonical conversion pair exists and most call sites already use it. The migration is
  tractable.
* The genuinely hard part is **not** `cell_center`/`world_to_cell`. It is the ~17 hand-written
  `* 0.5` / `* 2.0` ground-space conversions (§1.3 rows 1-17), nine of which are gameplay-critical,
  plus the Godot `TileMapLayer` half-tile offset (§1.3 rows 25-30).
* Under a square top-down projection the ground↔screen distinction collapses entirely. That is a
  large simplification, but it will change the *shape* of every Option-A radius listed in §1.4
  relative to every Option-B radius. Those two sets currently disagree, and a top-down migration
  silently makes them agree. **Any T2 characterization test that pins targeting or Routine gating
  should be checked against this before T5 lands.**
* Y-sorting and elevation are purely visual and need no gameplay work.
* High ground is a real mechanic (block / build / occlude / slab-exempt) that is entirely
  cell-based, so it survives a projection change untouched.
* `data/levels/*.tres` need a grid **rescale**, not a projection change; `decor` is the only
  screen-space field in the schema and no live level uses it.

## Explicit uncertainties

1. **Is the Option A / Option B split in §1.4 intentional?** No document states it. It reads more
   like each site was fixed as it was noticed. A human should confirm before T4 freezes the
   behaviour.
2. **`_build_shadow_occluders()` (`game.gd:898-987`) uses square math on an iso board and is
   live-called** (verified: called at `game.gd:252`). Both iso levels set `shadows = false`, so
   misbehavior could not be observed directly. Not verified to be *only* reachable behind that flag.
3. **`tools/map_editor.gd:1808-1810`** computes cell *corners* with `(cx+cy)` where
   `Data.cell_center()` uses `(cx+cy+1)`. Likely correct (corner vs centre = `th/2`), but not run
   in the editor to confirm.
4. **Dead-code claims** (`_build_decor_layer`, `_build_terrain_layer`, `_build_corner_terrain`,
   `_build_wall_shadow_layer`, `_build_wall_face_layer`) are based on grep finding no call sites plus
   the in-code note at `game.gd:5059-5064`. Reflection / `call()` dispatch would defeat that.
5. `addons/td_anim_lab/` and `addons/godot_ai/` were not audited — grep found no coordinate math in
   `addons/` at all, and `MIGRATION.MD` T8 puts `addons/td_level_designer/` out of scope anyway.

---

*Compiled by a research agent (read-only, no code changes) and spot-checked against source before
being committed — the canonical projection formula, the base_habit.gd elevation rationale, the
Routine-radius screen-space claim, the tower cone ground-space claim, and the shadow-occluder
live-call were independently re-verified line-for-line and matched exactly.*
