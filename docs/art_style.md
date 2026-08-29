# Art Style — TD Project

> **Ground truth for AI tooling (MCP / codegen / art generation).** Load this before
> generating, judging, or installing any sprite. Numbers here are measured from shipped
> assets and live code constants, not eyeballed — where the project's own docs later
> re-measure something, this file should be updated to match, not the other way round.
> Full reasoning and traps live in `docs/art/iso_bible.md` (current, isometric) and
> `docs/art/style_bible_measured.md` (legacy top-down, still true for un-migrated assets).

## Status: two rasters exist — use the isometric one for anything new

This project is mid-migration from a top-down square grid to a native isometric board
(branch `feat/iso-slice`). **The isometric raster is current and live**; the top-down one is
**legacy** — its levels are currently unplayable and its formula is no longer used by the
coordinate math (`Data.cell_center()`/`world_to_cell()` compute an isometric projection
unconditionally). Generate new art against the isometric numbers unless you are explicitly
told to touch top-down-only assets (old distraction spritesheets, `assets/towers/_topdown_backup/`).

## View angle

**True 2:1 isometric**, diamond-down tile layout (`TILE_SHAPE_ISOMETRIC` +
`TILE_LAYOUT_DIAMOND_DOWN` in Godot's TileSet). Not a 30° "true" dimetric axonometric — it's
the classic 2:1 pixel-art iso ratio (every tile is twice as wide as it is tall).

- Depth sort is free: `screen_y = (x + y) * tile_h / 2`, so sorting by screen-Y already
  sorts by world depth. No custom depth logic needed — just put a sprite in a `y_sort_enabled`
  container.
- A circle on the ground is a **2:1 ellipse on screen** (squash ratio **0.5**). Apply this to
  every contact shadow, ground glow, and range ring drawn on the iso board.
- Light direction is **fixed: from the upper-left**, consistently, across every volumetric
  object and every terrain surface. Top faces lightest, right/side faces darker, never
  ambient/flat lighting on a 3D-read object.

## Raster — the one rule everything else depends on

**Isometric (current, live):**

| | Value |
|---|---|
| Tile / cell | **64 × 32 screen px** (`Data.GRID.tile_w`, `tile_h`) — a 2:1 diamond |
| Pixel scale | **1.0×** — art is authored and shipped **at final screen size**, no upscaling (`Data.ISO_PIXEL_SCALE`). This is a deliberate departure from the legacy pipeline below. |
| Consequence | 1 art pixel = 1 screen pixel. Draw sprites directly at the size you want them to appear. |

**Legacy top-down (superseded, kept for un-migrated assets only):**

| | Value |
|---|---|
| Cell | 48 screen px (`Data.GRID.tile`, historical) |
| Terrain art pixel | 16 px (`TERRAIN_ART_PX`) |
| Pixel scale | **×3** upscale (art authored small, engine scales it up) |

Do not mix the two formulas on one asset. Never guess a pixel-scale number — read
`Data.pixel_scale()` and `Data.GRID`, or measure the installed PNG directly; this project
has twice shipped for weeks on a silently mismatched raster (art at one scale, code reading
another) before it was caught by measurement. `tools/pl_iso.py check` runs this check before
installing new iso art into `assets/`.

## Measured sizes of what's actually installed today

Canvas sizes as shipped on disk (not the visible diamond footprint, which is smaller —
tiles/terrace pieces carry padding for lips, skirts, and anchoring):

| Asset class | Path | Canvas size |
|---|---|---|
| Ground / lane terrain tiles (iso) | `assets/terrain/iso/ground/*.png`, `.../lane/*.png` | 64×64 |
| Terrace kit (block/cap/pillar/stairs) | `assets/terrain/iso/terrace/*.png` | 102×83, one shared anchor point |
| Tower heads (iso) | `assets/towers/head_*.png` | 64×64 (some directional frames 68×68) |
| Iso pilot floor tiles | `assets/iso_pilot/*.png` | 64×32 (bare diamond, no padding) |
| Iso pilot enemy placeholders | `assets/iso_pilot/enemy_*.png` | 32×48 |
| Distraction animation frames (legacy top-down, not yet redone for iso) | `assets/distractions/*_frame_*.png` | 48×48 |

## Palette

**One master palette for the whole project:** `docs/art/palette_48.hex` (48 hex colors — also
rendered as `palette_48.png`). Everything draws from it; nothing gets its own private palette.
A 32-color version exists (`palette_32.hex`) but measurably hurts 6 of 10 creatures — use 48.

- **Budget per sprite:** target **~40 colors**, hard ceiling **56** (p90 of measured shipped
  PixelLab originals — not a stylistic guess, see `style_bible_measured.md` for the measurement).
  This is nearly flat across sprite sizes; don't scale the budget by pixel area.
  A generic "≤24 colors" rule is too tight — 88% of source generations would fail it.
- **Neutrals need explicit grays in the palette.** A gray pixel with near-zero chroma sits
  near the center of color space and, with no true neutral available, gets misassigned to
  the nearest saturated color from an unrelated sprite — the classic failure mode
  (`sprite_cleanup.py --master` weights chroma 2.5× for exactly this reason).

## Color / value hierarchy — the iso board (theme: "Deep Focus / Cortex Terrace")

Measured as **sum of RGB channels** (0–765), same metric used to audit every shipped PNG.

| Layer | What it represents | Sum(RGB) band | Hue |
|---|---|---|---|
| Off-board void | frame, eye shouldn't go here | ~20 | cold black |
| **Low ground** (tissue, not buildable) | grey matter — quiet, largest area | **60–110** | dark indigo/violet |
| **Path** (lane distractions walk) | dopamine pathway burned into tissue | **120–160** | matte amber/bronze — the only warm thing on the ground |
| **High ground top** (buildable) | myelin / white matter terrace | **380–450** | pale bone/ceramic — reads as "you can build here" with zero UI |
| High-ground wall, lit face | same ceramic material | ~280 (70% of top) | same hue, warmer |
| High-ground wall, shadow face | same ceramic material | ~180 (45% of top) | same hue, cooler |
| Synapse/accent details | ≤6% of area, **clustered in strands, never scattered evenly** | 300+ | cyan / gold |
| Focus core | the single calm light in the scene | highest in the image | warm gold-white |

The top : lit-wall : shadow-wall ratio is **100 : 70 : 45** — one consistent light source
from above, not an arbitrary stylistic pick. Getting this wrong (e.g. 100:66:66, walls
indistinguishable) reads as a floating slab with no sides.

**Height is the only information the terrain carries, and it must carry it alone** — the
buildable/non-buildable read has to work with zero UI overlay text.

## Terrain: flat, no texture. Characters: stay detailed.

This is the single most important, most counter-intuitive rule in the current direction —
**it is asymmetric on purpose:**

- **Terrain is flat, untextured color.** No noise, no per-tile detail. Height reads *only*
  from the top/left-wall/right-wall value ratio above. A textured/noisy terrain tile, when
  tiled 3×3, reads as a repeating waffle-grid (measured brightness variance 142–227 on
  generated noisy tiles vs. 32 on the flat ones) — flat has no repetition to expose because
  there's nothing to repeat.
- **No per-tile grid line/edge**, even though it looks like it should help with distance
  reading. Measured: the alpha diamond isn't exact 2:1 (rows grow every 6px instead of 4),
  so adjacent tiles overlap by ~2,720 px — a dark edge line on one tile lands on top of its
  neighbor's interior and reads as a **dark seam between tiles**, not a grid. Default is
  `--edge none`.
- **Characters (towers, distractions, defenders) stay fully detailed.** This is a deliberate
  split, not laziness: the terrain is on screen 100% of the time and carries exactly one
  piece of information (buildable / walkable). An enemy is on screen for ~3 seconds before
  it reaches the core, and the player must identify *which* enemy it is by silhouette and
  color alone — that's where the detail budget belongs.
  > Rule of thumb: the shorter something is on screen and the faster the player must decide
  > about it, the more detail it earns. Terrain is on screen forever → least detail. An
  > enemy has three seconds → most detail.

## Volumetric objects (towers, large props) — the shape language

Applies to anything meant to read as a 3D object standing on the terrain (not flat terrain
tiles, which get none of this):

1. **Split the form into at least three stepped bands/facets** (typically base → body →
   crown) — not one silhouette with details painted on top.
2. **One consistent light source, from above.** Top faces lightest, sides darker, underside
   nearly in shadow — the same direction across the whole object, not radiating outward.
3. **Rounded/beveled edges**, not sharp right angles.
4. **Contact AO at the foot**, so the object visually sits on (not floats above) the ground.
5. **A small, non-flat rim-light** on the upper lit edge.

**What stood on the terrace must actually touch it.** Sprites are anchored by canvas bottom
but stand on content bottom — measure the empty margin at the foot (`_measure_foot_pad()`
does this per-sprite, taking the minimum across all 8 facing directions so a rotating object
doesn't bob) and shift the sprite down by it, or a gap of bare terrace appears between the
object and its own shadow.

**Towers specifically:** dark/desaturated body, bright accent — not the reverse. Split each
sprite by **saturation**: body (sat < 0.25) gets multiplied down to target luminance ~300 so
it doesn't wash out against the terrace (382–450); the accent (sat > 0.45) keeps its own
brightness. Darken what blends in, never the whole sprite — early attempts that darkened
everything made accents (gold eggs, crystals) go muddy too.

**Per-habit accent color** (silhouette identifies which habit, color/accent names it):

| Habit | Form | Accent hex |
|---|---|---|
| Focus Timer | twisted nerve-column, amber node + ring | amber |
| Mindfulness | dendritic crown | `#b07dff` |
| Exercise | thick glowing-core joint | `#ff8a3d` |
| Deep Reading (real_hobby) | slender tower fraying into fibers | `#ffc766` |
| Zen Pulsar | synaptic bulb + ring | `#5fe4f6` |
| Accountability (Guild) | nest of cell bodies | `#2bd6c0` |
| Anchor | rooted anchor + crystal | `#33e6f2` |
| Focus Pillar | fluted column + crystal | `#5fe4f6` |

## Outline, shading, silhouette (applies across both rasters)

- **Outline: 1px darker shade of the same hue, never black.** Characters and towers get an
  outline; terrain does not.
- **Shading: 3 tones**, shadow hue-shifted **≥20° toward cool** (measured minimum across
  shipped categories: distractions 58°, towers 86°, defenders 29°, decor 48° — 20° is a
  floor, not a target). No dithering.
- Measuring hue-shift alone can't distinguish good cool-shadow shading from a sprite that's
  just multi-colored (e.g. a green body with a red hat) — use it as a floor check, not proof
  of technique.

## Animation

| | Value |
|---|---|
| Walk | 6 frames |
| Attack | 5 frames |
| Death | 8 frames |
| Idle | 2 frames |
| Base timing | 10 FPS |
| Impact frame | hold 3× normal |
| Wind-up frame | hold 1× (snappy) |

Fewer frames is a deliberate correction, not a budget cut: every extra frame in an
AI-generated animation is another chance for the generator to drift off-model, and shipped
commercial games run leaner than this project's older 8–16-frame animations did.

## Generation pipeline rules

- **Generation background: magenta `#FF00FF`.** No trace of it may survive in the final
  sprite body.
- **Generator supplies material, code supplies geometry — for anything that must tile or
  meet a shared edge seamlessly** (walls, floor tiles, the terrace block/cap kit). Two
  independently generated art pieces never agree on a shared edge (measured: 3px mismatch).
  Code computes the shape from the same shared constant (`Data.GRID.tile_w/tile_h`) that the
  floor uses, and the generator only fills the resulting polygon with a flat material swatch.
- **`style_images` inherits both style *and* dimension from a reference** — the cheapest way
  to keep a set visually and geometrically consistent: generate one tile/object well, then
  reference it for the rest of the family instead of eight independent calls.
- **A raised, tileable floor tile is not something the current generator can do in one call**
  — height and seamless tiling live in two different tools that don't combine (a
  building/room tool gives height but won't tile; a tileset tool tiles but ignores height
  parameters). Terrain that must lock to the grid is generated as flat material only; actual
  height comes from code-drawn geometry (the terrace kit), not from a tall generated tile.

## World theme — what to actually draw

**Canonical theme for the isometric board: "Deep Focus / Cortex Terrace."** One sentence it
all follows from: *Focus is dark and quiet. Distraction is light and noise. A habit is
something you build on top of that chaos.* Isometric height is used as free game information
— light/high ground is buildable, dark/low ground is not, with no UI needed to say so.

| Layer | What it visually is | Why |
|---|---|---|
| Low ground | grey matter — wet, dark, grooved tissue | where the noise moves, and it's quiet on purpose |
| Path | a dopamine pathway burned into the tissue, warm amber | literally the Dopamine HUD color |
| High ground | myelin / white matter — pale waxy bundled terrace | a myelinated pathway *is* a habit: automatic, fast |
| Towers | structures grown from the myelin, one bioluminescent accent each | a habit isn't a machine bolted onto the tissue — it's tissue that overgrew |
| Focus core | the one calm warm light on the board | the thing being defended |

**Do not use `docs/design/fae_theme.md`.** That "Podměsíčí" folklore reskin (Wisp, Hob,
Glimmer, Hearth, capital-T "the Trod", etc.) was adopted and retired the same day
(2026-08-21) — it solved an art problem (silhouette-less neuroanatomy) that a flat-terrain
style later solved differently. It is kept in the repo as a historical record only. If you
see those names anywhere, they are stale.

## Known debts (don't mistake these for new bugs to "fix")

- Distractions are still the old top-down detailed style, not yet regenerated for iso — the
  one layer that still speaks a different visual language than the rest of the board.
- Decorations and the spawn-rift prop are still textured, so they visually stick out against
  flat terrain now.
- Three independent renderer re-implementations exist and can silently disagree with the
  real game: `tools/stylized_renderer.gd` (hardcodes `CELL := 48`, the old top-down cell),
  `tools/map_editor.gd`, `tools/board_preview.py`. **Never trust the map editor preview over
  the actual running game** when judging whether art/terrain looks right — verify in-game or
  via a real screenshot harness.
- Screenshot/verification harnesses must run at **1920×1080** (the project's fixed canvas,
  `stretch/mode="canvas_items"`). A smaller harness resolution silently rescales the canvas
  and any crop taken from `global_position` will miss.

## Where to go deeper

- `docs/art/iso_bible.md` — full isometric direction, per-asset generation recipes
  (`tools/pl_iso.py` `RECIPES`), traps already paid for, current asset checklist.
- `docs/art/style_bible_measured.md` — the legacy top-down measurements and rules, still authoritative
  for anything not yet migrated.
- `docs/PIXELLAB.md`, `docs/ART_PIPELINE.md`, `docs/TILESETY.md` — tool-level pipeline docs.
- `docs/art/palette_48.hex` / `palette_32.hex` — the actual palette files.
