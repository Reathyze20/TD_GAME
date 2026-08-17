# TD Project

A small, snappy **tower-defense game in Godot 4.7 (GDScript)** — in the spirit of *Sir We Have an
Orc Problem*, with maze paths — that teaches players how their attention gets hijacked: the
neuroscience of dopamine, the attention economy, and "digital obesity".

It teaches **through fun, well-designed levels, not lectures.**

## Theme

Every generic tower-defense object is mapped onto the theme:

| Generic TD          | This game                                                                 |
|---------------------|---------------------------------------------------------------------------|
| Castle / base life  | **Focus Meter** — the player's attention; drains when distractions get through |
| Enemies             | **Distractions** — digital noise marching toward your focus                |
| Towers              | **Habits** — healthy routines that defend attention                        |
| Gold / currency     | **Dopamine** — earned by defeating distractions                            |
| Walls / maze        | **High ground** — structure & boundaries you build habits on               |

Two bespoke mechanics sit on top: **Tolerance** (an overuse penalty, 0–100) and **Quick Hit**
(an instant-currency button that raises it).

All player-facing text is in English.

## Running it

Open the project folder in **Godot 4.7**. The main scene is `scenes/Menu.tscn`.

Headless smoke check:

```
godot --headless --path . --quit
```

## Layout

| Path        | What lives there                                                          |
|-------------|---------------------------------------------------------------------------|
| `scripts/`  | Gameplay code. Autoloads (`SignalBus`, `Data`, `GameState`, `ModifierManager`, `MetaProgression`, `Sfx`) at the top level; `resources/` holds the data-resource classes, `components/` the reusable node behaviours. |
| `scenes/`   | Scenes — `Menu`, `Game`, `LevelSelect`, `Education`, `MapEditor`, plus end screens. |
| `data/`     | Content as `.tres` resources: levels, habits, distractions, waves, cards.  |
| `assets/`   | Pixel art — terrain atlases, tower/distraction sprites, decor, background. |
| `shaders/`  | Shader code.                                                              |
| `addons/`   | `td_level_designer` — an in-editor dock for authoring levels.              |
| `tools/`    | Python and GDScript helpers for the art/tileset pipeline.                 |
| `docs/`     | Design docs. **Start with [`docs/core/00_overview.md`](docs/core/00_overview.md)** — it defines *what* and *why*; everything else describes *how*. [`docs/ROSTER.md`](docs/ROSTER.md) lists what actually ships, generated from `data/` by `tools/roster.py`. |

## Data-driven by design

Levels, habits, distractions and waves are Godot `Resource` files under `data/`, not hardcoded.
Levels are authored natively in the Godot editor via `scenes/MapEditor.tscn` and the
`td_level_designer` dock, then **baked** into their `.tres`. See
[`docs/EDITOR_GUIDE.md`](docs/EDITOR_GUIDE.md).

## Art pipeline

Pixel art is generated via PixelLab and assembled with the scripts in `tools/`. The conventions —
tileset layout, the corner-based terrain rendering, pixel scale — are documented in
[`docs/ART_PIPELINE.md`](docs/ART_PIPELINE.md), [`docs/TILESETY.md`](docs/TILESETY.md) and
[`docs/PIXELLAB.md`](docs/PIXELLAB.md).

## Status

Work in progress — playable pilot with a campaign taking shape.
