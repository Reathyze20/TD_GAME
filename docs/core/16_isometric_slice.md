# 16 — Isometric Slice (plan)

> **Status: PLAN, not built.** Nothing in `scripts/` is isometric yet. The only isometric
> code that exists is `scenes/pilot_isometric/` — a deliberately isolated pilot (see
> "What the pilot already proved" below). This document is the plan for turning that
> pilot into a **playable vertical slice** of the real game.

## What we are building

**One simple path, 2 enemy types, 3 towers — playable, in the real game code.**

Not a migration. The point is to answer *"does our actual game feel good in isometric?"*
with the real tower/enemy/pathfinding systems, on a small enough field that we are not
redrawing 679 sprites to find out.

Deliberately **out** of the slice: defenders/barracks, interventions, cards & draft,
bosses, Brain Fog, cast shadows, the second level, and the level editor's preview.
Each of those has its own geometric coupling (see §7) and none of them is needed to
judge whether isometric looks and plays better.

---

## 1. The good news: what survives untouched

This is the single most important finding of the code survey, and it is what makes the
slice affordable. The following is **pure cell-index logic with no screen pixels in it**,
and it does not care what shape a cell is drawn as:

| System | Where | Why it survives |
|---|---|---|
| `AStarGrid2D` pathfinding | `game.gd:258-277, 345-356, 1196-1204` | `region`, `set_point_solid`, `get_id_path` all speak `Vector2i`. Paths come back as **cells**, not pixels. `cell_size` only weights the search. |
| `Data.build_block()` | `data.gd:34-38` | `floor(cell/3)*3+1` on each axis — integer indices only. |
| Build-spot construction | `game.gd:287-304` | "is this whole 3×3 block high ground" — a cell test. |
| `_build_platforms()` | `game.gd:1151-1169` | Flood fill over cell adjacency. 8-neighbour still means "touching" in iso. |
| Spawn-zone expansion, `_in_bounds()`, `_apply_path_weights()` | `game.gd:313-321, 1125-1127, 345-356` | Cell indices. |
| **`LevelData` format** | `resources/level_data.gd:22-57` | `objective`, `spawn_zones`, `high_ground`, `path_cells`, `terrain_tiles` are all cells. Only `decor.pos` is stored in pixels. |
| Dual-grid corner bitmask | `game.gd:998-1010` | The 4-corner Wang logic is **identical** for iso diamonds. Only the atlas art and the layer offset change. |
| Economy, statuses, `ArcProfile`, `ModifierManager`, `GameState` | — | Untouched. |

**Consequence:** we are not rewriting the game. We are rewriting a *projection layer*
underneath it, plus terrain rendering, plus input picking.

## 2. What the pilot already proved

`scenes/pilot_isometric/iso_pilot.gd` (208 lines) is not throwaway — it already solved
four of the hardest items, and those solutions transfer directly:

- **Native iso TileSet** — `TILE_SHAPE_ISOMETRIC` + `TILE_LAYOUT_DIAMOND_DOWN`,
  `TILE_SIZE = Vector2i(64, 32)`. No hand-rolled iso transform.
- **Walls as geometry, not art** — `IsoWallSegment._draw()` computes the parallelogram
  corners from the same `TILE_SIZE` constant the floor uses, then stretches a flat
  material swatch over it with UVs. **Seams between wall and floor cannot occur** —
  it is not a matter of hitting the right pixel size in a generator prompt. This is the
  same generator-supplies-material / code-supplies-shape split the real game already
  uses for `WallFace` (`docs/PIXELLAB.md` §5c).
- **Foot anchoring** — sprite pivot read from the lowest opaque pixel via
  `Image.get_used_rect()`, so swapping art can't silently re-break placement.
- **Depth sorting is free** — `y_sort_enabled` on a shared parent already sorts iso
  correctly, because in a 2:1 projection `screen_y = (x+y) * tile_h/2`, so sorting by
  screen-Y *is* sorting by `x+y`. The real game already has this on `entities`
  (`game.gd:206-209`). **No custom depth-sort code is needed.**

It also surfaced one honest defect to fix in the slice: **a single floor tile repeated
across 8×8 reads as a visible wallpaper grid.** The real game already has the cure —
multiple variants picked per build-block (`terrain/path/*.png` does exactly this).

---

## 3. Phase 0 — Branch and shrink the field

- Work on a branch. `main` stays playable throughout; the slice will have broken art
  and disabled systems for most of its life.
- New small level (`data/levels/level_iso.tres`): one lane, one spawn zone, one
  objective. **Do not convert `level_1`/`level_2`** — between them they hold 8 114
  hand-placed coordinates and neither is needed to judge the look.
- Disable for the slice: `Game.shadow_enabled = false`, Brain Fog, barracks/defenders,
  interventions, cards, boss.

## 4. Phase 1 — The seam (highest leverage, do this first)

Everything else depends on this, and it splits into a safe part and a risky part.

**1a. Unify the duplicate converters — while still orthogonal.**
There are currently **four independent implementations** of the same grid↔pixel maths:

| Copy | Where |
|---|---|
| canonical | `game.gd:1115-1123` (`cell_center`, `world_to_cell`) |
| duplicate | `base_habit.gd:50-52` (rebuilds tower position by hand) |
| duplicate | `animation_test.gd:43-47, 124-128` |
| duplicate | `tools/map_editor.gd:479-482` (omits `origin_x`) |

Collapse all of them onto the canonical pair **with no behaviour change**, verify the
game plays identically, commit. If we skip this, the copies silently drift apart the
moment the projection changes, and the bug will look like "towers are in the wrong place
sometimes".

**1b. Widen the grid definition.** `Data.GRID.tile` is a single scalar (`data.gd:11-17`).
Isometric needs a `Vector2i` (`64,32`) plus a different `origin` relationship.
`Data.pixel_scale()` / `TERRAIN_ART_PX` (`data.gd:83, 96-97`) also assume a square
cell and need rethinking.

**1c. Make the canonical pair projective.** `cell_center()` → iso projection;
`world_to_cell()` → its inverse. ⚠ **`world_to_cell` cannot stay a `floor()`** — that is
only correct for axis-aligned squares. A diamond needs the inverse matrix (or delegating
to `TileMapLayer.local_to_map()`).

**Verification gate:** pathfinding returns the same cells as before and enemies walk the
lane correctly — *even while all the art is still wrong*. That proves the seam is right
before any art work starts.

## 5. Phase 2 — Terrain rendering

| Item | Where | Work |
|---|---|---|
| Corner terrain | `game.gd:941-1010` | TileSet → iso shape/layout + new atlas. **Bitmask logic unchanged.** |
| Wall faces | `game.gd:428-457` (`WallFace`) | "south edge = horizontal rect" is false in iso; a wall shows **two** faces at different angles. Port `iso_pilot.gd:144-173` (`draw_polygon` + UV). |
| Path layer | `game.gd:859-939` | Tile size + accent spread. |
| Background | `game.gd:364-393` | `ColorRect` + `Sprite2D` span an axis-aligned rect over the whole grid; an iso field is a diamond. |
| `WallShadow` | `game.gd:460-556` | Run-length merge into `Rect2`s — **disable for the slice**, revisit later. |

### ⚠ The structural part: walls stop being a background layer

This is **not** a coordinate change and it is easy to miss. Today walls are a static
layer *underneath* everything (`Z_WALL_FACE = -22`, `Z_TERRAIN = -20`, while `entities`
sits at `z = 0`). That is correct top-down: you always look *down* at a wall.

In isometric a wall is a **vertical object in the world** — a unit standing north of it
must be drawn *behind* it, and a unit south of it *in front* of it. With walls on a
background layer, a unit can never be occluded by a wall, which is one of the main
things that sells iso depth. **Walls must move into `entities` and be y-sorted**, exactly
as `iso_pilot.gd:114-118` already does.

Consequence: wall segments become per-object nodes rather than one merged draw pass.
`WallShadow`'s run-length merge (`game.gd:460-556`) exists specifically to avoid MSAA
seams across a single flat layer, so that optimisation does not carry over unchanged —
another reason to leave it disabled for the slice.

## 6. Phase 3 — Input and placement preview

Depends only on Phase 1, and is small:

- `_update_hover()` (`game.gd:3116-3129`) and `_unhandled_input()` (`game.gd:2113-2117`)
  are the **only two entry points** for field clicks — both just call `world_to_cell`.
- `_draw_placement_preview()` + `_draw_pixel_frame()` (`game.gd:1071-1113`) — the square
  `Rect2` hover frame becomes a diamond polygon.
- `_draw_static_field()` grid dots and spawn-zone rects (`game.gd:1048-1068`).

## 7. Phase 4 — Directions and animation

- `enemy.gd:182-189` `note_heading()` snaps to 4 cardinal axes (`abs(dir.x) > abs(dir.y)`),
  and the comment ties this to `DIAGONAL_MODE_NEVER`. In iso, those four world directions
  land on **diagonal screen directions** — the snap needs remapping.
- `distraction_animator.gd:204-217` keeps its `_south/_north/_east/_west` sets and its
  west-mirrors-east trick; the sets simply mean different screen directions now.
- Sprite pivot moves from centre to feet. Every draw path currently centres
  (`tower.gd:542-549`, `distraction_animator.gd:246-260`, `defender_unit.gd:519`) via
  `Rect2(-size/2, size)`. The pilot already solved this with `Image.get_used_rect()`.
- **The fake-perspective squashes become principled.** Contact shadows and ground glows
  are already drawn as flattened ellipses — `Vector2(1.0, 0.45)` at `tower.gd:585-588`,
  `(bob, 0.42*bob)` at `distraction_animator.gd:189-201` and `defender_unit.gd:511-515`,
  `(1.0, 0.45)` for the type glow. Those ratios were eyeballed to fake depth in top-down;
  in a true 2:1 projection the correct ground-plane squash is exactly **0.5**. Same for
  every range ring drawn with `PixelDraw.arc` — a circle on the ground is a 2:1 ellipse
  on screen (see §9).

## 8. Phase 5 — Art for the slice (~60–90 PNG, not 679)

Already isometric: `floor_tile`, `wall_material`, `tower_focus_pillar` (`assets/iso_pilot/`).

Still needed:
- **2 more tower heads** (Focus Pillar is done).
- **2 enemies × 4 iso walk directions + death.** Today a typical enemy ships ~35 frames
  across 4 states. `style_bible.md` §4 already measured that our 8–9-frame walks are
  above shipped-game practice (4–6) *and* that every extra frame is another chance for
  the generator to drift — so cutting to ~6 is an improvement, not a compromise.
- **2–3 floor variants**, to kill the wallpaper repetition the pilot exposed.

## 9. Open decision: what does "range" mean in isometric?

This is a **gameplay** decision, not a mechanical port, and it should be made
deliberately before Phase 1 lands.

Every radius in the game is euclidean pixels: `def.range`, `guard_radius`,
`disrupt_radius`, `haste_radius`, `heal_radius`, `ward_radius`, `CORE_ROUTINE_RADIUS`,
`ANCHOR_ROUTINE_RADIUS`, `TOWER_LAMP_RADIUS`, `RUSH_CLOSE_RADIUS`, `KNOCK_BUDGET`,
`BASE_HIT_PADDING`.

In a 2:1 projection **a circle on screen is an ellipse on the ground**: a 300 px range
reaches twice as many cells horizontally as vertically.

- **Option A — keep screen circles.** Cheap, matches what most isometric games do
  visually, but tower reach becomes anisotropic in game logic.
- **Option B — ground-plane ellipses.** Range tests convert to ground space; every
  preview must draw the matching ellipse or the preview lies.

Either way it touches `tower.gd:166-186`, `game.gd:3108-3114`, `enemy.gd:286-338`,
`defender_unit.gd:196-364`, `game.gd:2594-2609` — **and every preview draw**
(`tower.gd:576-577, 691-724`, `barracks.gd:193-197`, `game.gd:1092-1096, 2020-2021`).

## 10. Knowingly left broken

Recording these so they are not later mistaken for regressions:

- **Three independent re-implementations of the renderer** —
  `tools/stylized_renderer.gd` (has `CELL := 48` hardcoded), `tools/map_editor.gd:1251-1310`,
  `tools/board_preview.py`. The editor preview will disagree with the game until they are
  migrated. This already bit us once: the broken 48px wall atlas looked *fine* in the
  editor preview while the game drew garbage, precisely because the preview computed its
  own step size.
- **`Camera2D` is a bigger decision than it looks.** The pilot already introduces one
  (`iso_pilot.gd:199-208`, `zoom = 2.2`) — and the real game currently has **none**, by
  design. Three things silently depend on "world coordinates == screen coordinates":
  - `shaders/brain_fog.gdshader:13-17` samples `light_mask` through `SCREEN_UV` and
    documents the assumption explicitly. A camera forces passing the canvas transform
    as a uniform.
  - `_pop_text()` (`game.gd:4728-4741`) puts a **world**-positioned `Label` straight into
    the HUD `CanvasLayer`. It only lands in the right place because the two spaces
    coincide.
  - `_open_panel()` (`game.gd:2715-2726`) does the same with `cell_center(cell)`.

  Decide early whether the slice has a camera. Fixed-view (no camera) keeps all three
  working and is enough to judge the look.
- **Cast-shadow occluders** (`game.gd:668-756`) — rectangular polygons with a row-merge
  that exists to fix a seam bug, so "one occluder per cell" is not an option.
- `level_1` / `level_2`, defenders/barracks formation offsets (`barracks.gd:21`),
  `decor_layer.gd:96-116` pixel spread, the `td_anim_lab` hardcoded direction list.

**Docs that are already stale — do not trust them while doing this work.**
`docs/core/01_rendering_and_depth.md` lists a Z table (`-10` background … `100+` HUD)
that the code does not use — the real constants are `game.gd:38-47`
(`Z_BACKGROUND = -40` … `Z_FOG = 60`). Its "Intersection with the prototype" section
still claims the project has no `Sprite2D`, no `TileMap` and `tile = 48`. Likewise
`docs/PIXELLAB.md:646` documents a `HEAD_ART_SPAN := 2.0` constant in `tower.gd` that
**no longer exists** — it was replaced by `Data.pixel_scale()` (`tower.gd:533-540`), and
`docs/core/14` still quotes `TOWER_LIGHT_RADIUS = 150` where the code has
`TOWER_LAMP_RADIUS = 56` plus a wedge. Code is ground truth; verify before relying on
any doc number here.

## 11. Order of work

1. **Phase 0** — branch, small iso level, disable out-of-scope systems.
2. **Phase 1a** — unify the four converters, orthogonal, no behaviour change. *Commit.*
3. **Phase 1b/1c** — projective grid + inverse. *Gate: enemies still walk the lane.*
4. **Phase 2** — terrain + walls (port from the pilot).
5. **Phase 3** — input picking + diamond hover.
6. **Decide §9** (range semantics) before tuning anything.
7. **Phase 4/5** — directions, then slice art.

Phases 1–3 are the ones that decide whether this is a week or a month. Art (Phase 5) is
the largest *volume* but the least *risk* — and it is deliberately last, so we never
draw a sprite before knowing the projection underneath it is correct.
