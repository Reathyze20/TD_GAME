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

Headless, import first. `--quit` / `--quit-after 1` on their own do **not** produce a full
import ([godot#77508](https://github.com/godotengine/godot/issues/77508)) — `--import` does:

```
godot --headless --path . --import
```

The actual check is the regression gate, `./verify.sh`. It runs every `scenes/_test_*.tscn`
fixture plus the Python content gates (roster, ASCII side-car, terrain contrast, art prompts
and colours, style failure modes), and ends with a
`pass / fail / skip / known-broken / flaky / no-display` summary — exiting non-zero only on
`fail`. It needs `$GODOT` pointing at the **console** build (the plain build writes no
stdout); run it with `$GODOT` unset once and it prints the exact `export` line to use:

```
export GODOT=".../Godot_v4.7.1-stable_win64_console.exe"
./verify.sh
```

Per-test logs land in `.dev/`. Expected failures are listed in `KNOWN_BROKEN_TESTS` inside
`verify.sh`, with the failing assertion for each in
[`docs/KNOWN_BROKEN.md`](docs/KNOWN_BROKEN.md) — a test in that list *passing* is itself
reported as a failure, so the list cannot rot.

## Layout

| Path        | What lives there                                                          |
|-------------|---------------------------------------------------------------------------|
| `scripts/`  | Gameplay code. All eight autoloads (`SignalBus`, `Data`, `GameState`, `ModifierManager`, `MetaProgression`, `Sfx`, `Music`, `Mirror`) at the top level; `resources/` holds the data-resource classes, `components/` the reusable node behaviours. Also the `_test_*` / `_shot_*` / `_play_*` harness scripts — see [Tests](#tests). |
| `scenes/`   | Scenes — `Menu`, `Game`, `LevelSelect`, `Education`, `MapEditor`, plus end screens; and the `_test_*` / `_shot_*` / `_play_*` harness scenes. |
| `data/`     | Content as `.tres` resources: levels, habits, distractions, waves, cards.  |
| `assets/`   | Pixel art — terrain atlases, tower/distraction sprites, decor, background. |
| `shaders/`  | Shader code.                                                              |
| `addons/`   | `td_level_designer` — the in-editor dock for authoring levels; `td_anim_lab` — a dock for tuning distraction sprite animations (frame rate, per-frame alignment, mismatched-facing metrics); `godot_ai` — the MCP/dev-tooling bridge (it registers the `_mcp_game_helper` autoload, which is **not** a game autoload). |
| `tools/`    | Python and GDScript helpers for the art/tileset pipeline.                 |
| `docs/`     | Design docs. **Start with [`docs/core/00_overview.md`](docs/core/00_overview.md)** — it defines *what* and *why*; everything else describes *how*. [`docs/ROSTER.md`](docs/ROSTER.md) lists what actually ships, generated from `data/` by `tools/roster.py`. |
| `LDtk/`     | A single `Test.ldtk` probe from an early evaluation of LDtk as an external level editor. Nothing reads it — levels are authored in-engine (see below). Kept as the record of that decision. |
| `verify.sh` | The regression gate described under [Running it](#running-it). |
| `CLAUDE.md` | Working agreement for AI agents on this repo: which doc to read for which task, Godot-4-only syntax, the "content is data, never code" rule, and the test contract. Worth reading first as a human too — it is the shortest description of how the project is meant to be changed. |

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

## Tests

There is **no `tests/` directory and no GUT** — deliberately. A test here is a pair:
`scripts/_test_<name>.gd` (`extends Node`) plus a same-named `scenes/_test_<name>.tscn`
whose root is a `Node` with that script attached — a standalone headless harness, not a
framework. Run one with `--main-scene`, never `--script`; under `--script` the autoloads
are not registered yet and reading `Data` or `GameState` is a compile error:

```
godot --headless --path . --main-scene "res://scenes/_test_levels.tscn"
```

The exit code comes from the `get_tree().quit()` at the end of the script. The pattern —
the `completed` sentinel and the watchdog `Timer` that makes a mid-coroutine error print
`FAIL` instead of looking like a hang — is documented in
[`docs/REFACTOR_PLAN.md`](docs/REFACTOR_PLAN.md) under *Verification pattern*.

Two sibling prefixes are **not** tests and have no pass/fail: `scenes/_shot_*.tscn` take
visual snapshots into `.dev/screenshots/`, and `scenes/_play_*.tscn` are manual playtests.

## Status

Work in progress — playable pilot with a campaign taking shape.
