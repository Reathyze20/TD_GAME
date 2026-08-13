# 01 — Rendering & Depth (2.5D Y-Sort)

> Theme reminder (see `00_overview.md`): on screen, "enemies" are **distractions**, "towers" are
> **habits**, and the maze terrain is **high ground**. This doc is pure rendering plumbing — it
> applies the same whatever art we skin on top.

## 1. 2.5D "fake 3D" via Y-sorting

To get a top-down-with-depth look, we rely on **Y-sorting**. In Godot 4 the old `YSort` node is
gone; Y-sorting is now the `y_sort_enabled` property on any `CanvasItem` (`Node2D`, `Sprite2D`,
`TileMapLayer`, …).

When enabled, Godot draws nodes with a **lower Y** (higher on screen) *behind* nodes with a
**higher Y** (lower on screen). So a distraction walking "in front" of a habit tower renders
correctly, and vice-versa.

## 2. Global Z-index layers

Y-sorting handles objects on the *same* plane. Use **Z-index** only to group elements into strict
absolute layers. **Never** use Z-index to patch a Y-sort problem.

| Z-index | Layer | Contents | Y-sort? |
|--:|---|---|:--:|
| `-10` | Background | Base terrain / desk / grid (`TileMapLayer`) | No |
| `-5` | Decals | Route hints, scorch/scroll marks | No |
| `-1` | Shadows | Drop shadows for distractions/habits | No |
| `0` | Main entities | Habits, distractions, Allies, high-ground props | **Yes** |
| `5` | Air / projectiles | Bolts, "mindful" pulses, **flying** distractions | No |
| `10` | World UI / FX | Health bars, dopamine pop-numbers, impact FX | No |
| `100+` | HUD (`CanvasLayer`) | Top bar, build menu, pause, insight cards | n/a |

## 3. The golden rule of pivots

Y-sorting sorts by a node's **origin** `(0,0)`. **The origin must sit at the feet / base** of the
object.

- Set each `Sprite2D`'s **Offset** so the sprite's bottom-center rests on the node's origin — not
  the chest of a distraction or the middle of a habit building.
- Put shadows (Z `-1`) at `(0,0)` of the parent so they sit at the feet.

## 4. Required node hierarchies

For sorting to cascade, the parent container **and** its children need `y_sort_enabled = true`.

### A. Level / map scene

```text
Level (Node2D) [y_sort_enabled]
├── Environment (Node2D)
│   ├── Terrain (TileMapLayer)        [Z -10]
│   ├── HighGround (TileMapLayer)     [Z -5]  # buildable + blocking (see 07)
│   └── Decorations (Node2D) [y_sort_enabled]
├── EntityLayer (Node2D) [y_sort_enabled, Z 0]
│   ├── Habits (Node2D)   [y_sort_enabled]    # towers
│   ├── Distractions (Node2D) [y_sort_enabled]# enemies
│   └── Allies (Node2D)   [y_sort_enabled]    # barracks units (06)
├── ProjectileLayer (Node2D) [Z 5]
├── WorldUILayer (Node2D)    [Z 10]
└── HUD (CanvasLayer)        [Layer 100]
```

### B. Standard entity (distraction / habit)

```text
Distraction (Area2D) [y_sort_enabled]
├── Shadow (Sprite2D) [Z -1]         # anchored at (0,0)
├── Visuals (Node2D) [y_sort_enabled]# tween scale/rotation here, never the origin
│   └── Sprite (Sprite2D)            # bottom aligned to (0,0)
├── CollisionShape2D                 # at the feet
└── WorldUI (Node2D) [Z 10]
    └── HealthBar (ProgressBar)      # above the head
```

## 5. Flying distractions

Some distractions fly (e.g. `popup` / push notifications) — they ignore ground **Allies**
(see `06`). To render them without breaking the illusion:

1. Keep the `Area2D` **root on the ground** like a walker.
2. Offset the *sprite* up the Y axis (e.g. `position.y = -50`).
3. Keep the **shadow at `(0,0)`**.

Result: Godot sorts by the ground shadow, so the flyer passes correctly behind tall habits while
visually floating.

## Intersection with the prototype

The prototype is still **flat 2D with `_draw()` shapes** in `game.gd`/`enemy.gd`/`tower.gd` — there
is not a single `Sprite2D`, `TileMap`/`TileMapLayer` or texture anywhere in the project. Three
pieces of this doc have landed anyway, because they do not depend on art:

- **`Entities` Y-sort container.** `game.gd::_ready()` creates a `Node2D` named `Entities` with
  `y_sort_enabled = true`, and habits, distractions and Allies all parent under it (via
  `BuildSpot.build_habit()`, `Game.spawn_distraction()` and `Habit._spawn_one_ally()`). Y-sorting
  operates on any `CanvasItem`, so this genuinely works on `_draw()` shapes today: whatever stands
  lower on screen draws in front. Projectiles and VFX stay direct children of `Game`, added later
  in the tree, so they always render above the field. **This unblocks `06`'s last checklist item.**
- **Explicit CanvasLayer ordering.** World on the default canvas, glitch overlay at `layer = 5`,
  HUD at `layer = 10`. Leaving these implicit let the HUD be distorted by the glitch shader, which
  is worst exactly when Tolerance is high and the readouts matter most.
- **2D MSAA 4x** (`rendering/anti_aliasing/quality/msaa_2d=2`). Everything on screen is a vector
  circle, arc or line, so this is a visible edge-quality win now rather than a future nicety.

What is still deliberately **not** done, and why:

- **Sprite pivot offsets** — there are no sprites. In a `_draw()` renderer the "feet at origin"
  question is answered by the drawing code, not an inspector `Offset` field.
- **`TileMapLayer` + `TileSet` with a `buildable` custom data layer** — the grid is drawn by
  `game.gd::_draw()` and high ground comes from `Data.LEVELS[*].high_ground` arrays, which already
  feed `AStarGrid2D.set_point_solid()`. Migrating would move level authoring out of `data.gd`
  (where `02` deliberately put it as tunable text) and buy nothing until tile art exists. Note also
  that a 64×64 tile would break the layout: `Data.GRID.tile` is **48**, and a 40×19 grid at 48px is
  1920×912, fitted precisely between the 54px top HUD bar and the bottom bar.
- **Texture filtering (Nearest vs Linear)** — moot with no textures.

### Glitch shader and Dopamine particles

`shaders/distraction_glitch.gdshader` is a `canvas_item` shader on a full-rect `ColorRect`
(`mouse_filter = IGNORE`, or it would swallow every click on the play field). It samples
`hint_screen_texture` and applies band slip, chromatic split, scanlines and slight desaturation.
Intensity is driven from `_update_glitch()` by two terms: **Tolerance** as a sustained creep, and a
short spike when a distraction reaches the core. The rect is `visible = false` below ~0.01, so the
screen-texture pass costs nothing during clean play.

Dopamine bursts are code-built `GPUParticles2D` (`_spawn_dopamine_burst()`) that rise against
inverted gravity and fade via a `color_ramp`. They need a texture — `GPUParticles2D` renders a 1px
point without one — so an 8×8 soft dot is generated once in code and cached in a `static var`.
Mindfulness ring particles from the same spec were skipped: the habit already draws an expanding
wedge in `_pulse()`, and spawning a particle system every 0.55–0.7s per tower is a lot of node
churn for a visual that already exists.

## Implementation checklist

- [x] `y_sort_enabled = true` on the entity container — done as a single `Entities` node rather
      than separate `Habits` / `Distractions` / `Allies` children, which would defeat the point:
      per-type containers cannot interleave, and a distraction has to be able to sort in front of
      a habit. Sorting works on `_draw()` shapes, so this is live now.
- [ ] `TileMapLayer` (not the deprecated `TileMap`) for terrain/high ground, Z `-10` / `-5` —
      deliberately skipped; see the Intersection section (48px grid, level data lives in `data.gd`).
- [ ] Every entity `Sprite2D` bottom-aligned to `(0,0)` — no sprites exist to align.
- [ ] Shadows separated, Z `-1`, at `(0,0)` — only the flying `phantom_buzz` draws one, inline in
      its own `_draw()`, as its airborne tell.
- [ ] Entity health bars at Z `10` so they never hide behind taller sprites — bars are drawn inline
      after the body in each entity's `_draw()`, which is sufficient while nothing is tall.
- [x] Explicit CanvasLayer ordering: world (0) < glitch (5) < HUD (10).
- [x] 2D MSAA 4x for the vector `_draw()` art.
- [x] Screen-space glitch shader driven by Tolerance and core hits.
- [x] `GPUParticles2D` Dopamine burst on a defeat.
