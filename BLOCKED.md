# Blocked

Design decisions found ambiguous or contradictory during autonomous runs.
Not fixed by guessing — recorded here with options, then moved past.

## T1 (docs/refactor/MIGRATION.MD) — "Nainstaluj GUT pro Godot 4 do addons/. Založ tests/."

Conflicts with CLAUDE.md's "Testy jsou smlouva" section, which is explicit and detailed
about this project deliberately NOT using GUT: "v repu není `tests/` adresář ani GUT
(`addons/gut` neexistuje, nikde v repu není zmínka o něm)." It documents an established
alternative instead — `scripts/_test_*.gd` + `scenes/_test_*.tscn` pairs, run via
`--main-scene`, with a `completed := false` sentinel + `Timer` watchdog — with a whole
list of existing fixtures already built on it and a hard rule not to rename/disturb them
without reason.

verify.sh (T0, this session) was built to drive exactly that existing pattern, per
CLAUDE.md's own instructions on what to read for testing work
(docs/REFACTOR_PLAN.md "Verification pattern"). Installing GUT and founding `tests/`
alongside it would mean two parallel, disconnected test frameworks in the same repo,
with `verify.sh` blind to whichever one it doesn't drive.

**Options:**
1. Skip the GUT/`tests/` part of T1 entirely; keep the existing `_test_*` harness
   pattern as the only test framework, and treat T1 as satisfied by verify.sh's CI
   wiring alone. Lowest-risk, no new dependencies, consistent with CLAUDE.md as
   written today.
2. Install GUT for future tasks (T2, S1, etc. all say "napiš testy" without specifying
   a framework) while leaving existing `_test_*` fixtures untouched, and update
   verify.sh to run both. Doubles the testing surface and contradicts CLAUDE.md's
   explicit "v repu není GUT" unless that section is rewritten to reflect the change.
3. Migrate everything to GUT, retiring the `_test_*.gd`/`_test_*.tscn` pattern. Highest
   effort, touches 20 existing fixtures explicitly protected by CLAUDE.md
   ("neruš, nepřejmenovávej bez důvodu"), and reverses a documented architectural
   decision without being asked to.

**What I did:** proceeded with option 1 for now (no GUT installed, no `tests/` founded).
New tests for T2 onward will use the existing `_test_*.gd`/`_test_*.tscn` pattern that
verify.sh already drives. Added `.github/workflows/ci.yml` running `verify.sh` as T1's
other half. A live "zelený běh v CI" per T1's own done-criterion can't be confirmed from
here without pushing, which the branch rules in CLAUDE.md forbid — flagging that gap
rather than silently marking T1 complete.

## T5 (docs/refactor/MIGRATION.MD) — "Přidej do GridProjection čtvercovou variantu a přepni na ni. Nastav project.godot: base resolution 480x270, integer scaling, Nearest filter."

Not a docs/core conflict (checked before starting — docs/core/16_isometric_slice.md
itself says "Status: PLAN, not built... Not a migration", and CLAUDE.md already
anticipates and authorizes exactly this switch: "Výjimka pro migraci na top-down...
Nová čtvercová projekce dostane vlastní fixtures"). Two OTHER project docs
(`docs/art_style.md`, `docs/game_design.md`, both outside docs/core/) still assert
isometric is "the live rendering/grid model" — those are simply stale relative to this
branch and not something to act on now, just flagging so they don't get read as
current by mistake.

The reason this is blocked is CLAUDE.md's own autonomous-run rule: "ZASTAV... pokud:
úkol vyžaduje vizuální posouzení" (stop if the task requires visual judgment). Both
halves of what's left genuinely do:

1. **Flipping `GridProjection.active_mode` to `MODE_SQUARE` live.** `Data.GRID` is
   authored specifically for a 1920x1080 canvas (`origin_x=960` is literally half of
   it — verified). Switching projections without also rescaling the grid, HUD, and art
   would not render "a top-down version of the game" — it would render a broken one,
   since a 24x24 iso-scaled board has no correct top-down analogue until it's
   rescaled, and MIGRATION.MD's own T6 ("Migrace bakovaných levelů") is where level
   rescaling happens. Flipping the switch now would produce a visibly wrong result
   that no test would catch (verify.sh would still pass — nothing currently asserts
   what the board should look like), so this needs a human to look at it, not an
   autonomous "tests are green, ship it."
2. **The project.godot resolution/scaling/filter change** (1920x1080 → 480x270,
   integer scaling, Nearest filter). Confirmed none of these three settings exist
   today (no stretch/scale_mode, no default_texture_filter override) — this is a new
   decision, not a tweak to an existing explicit value. It's also large: ~50 hardcoded
   pixel constants across `game.gd`'s code-built HUD, `menu.gd`, `animation_test.gd`,
   the `_shot_*` screenshot harnesses, and `tools/` would all need re-deriving for a
   480x270 canvas to look right, not just compile.
3. **What "flat top-down" should actually look like.** There IS a user-approved
   precedent — `docs/art/iso_bible.md` §2b, "PLOCHÝ STYL": flat colors, no terrain
   texture, height read only from top:left:right shading ratio, referencing Rogue
   Tower, explicitly the user's own decision. But it's written for isometric terrace
   faces (a top face + two visible side faces) — a top-down square view has no visible
   side faces the same way, so this needs reinterpretation, not direct reuse, and
   that reinterpretation is a design call.

**What I did:** implemented and tested the part that has no visual-judgment content —
`GridProjection` now has a `MODE_SQUARE` alongside the live `MODE_ISO` default
(`active_mode`/`GROUND_Y_SCALE`/`set_mode()`), with `cell_center()`, `world_to_cell()`,
`board_bounds()`, and `screen_dir_to_grid_axes()` branching per mode, and
`to_ground()`/`to_screen()`/`ground_distance()`/`ground_dir_to_screen()` working
correctly for both automatically (they're already parameterized purely by
`GROUND_Y_SCALE`). `layer_origin()`/`diamond_corners()`/`cell_diamond()` stay iso-only
on purpose — there's no square equivalent to write without first deciding what walls
and terraces look like top-down, which is exactly the visual-design question above.
Added `_test_square_projection.gd`/`.tscn` (per CLAUDE.md: "Nová čtvercová projekce
dostane vlastní fixtures") — 18 checks, all pass, and it switches into `MODE_SQUARE`
and back to `MODE_ISO` around itself so nothing else in the suite is affected.
`active_mode` defaults to `MODE_ISO` and nothing in the running game ever calls
`set_mode(MODE_SQUARE)` — the live game is untouched, byte-for-byte, by this change.

**Options for the two visual-judgment pieces above, once a human is ready:**
1. Do T5's resolution switch and T6's level rescale together in one deliberate pass,
   informed by a real screenshot comparison at the new resolution before committing to
   it — since a resolution change with no rescaled content can't be meaningfully
   judged in isolation.
2. Decide the flat-top-down wall/terrace look first (a design pass, maybe its own
   mockup) before touching project.godot at all, so the resolution/scale decision is
   made knowing what needs to fit inside it.
3. Treat "T5 complete" as just what's implemented here (the mode infrastructure) and
   let a later, dedicated session/task own flipping the switch — matches how this
   entry treats it today.

## S5 (docs/refactor/SYSTEMS.MD) — "Přepiš stav nepřátel z uzlů na pole struktur" / S6 — "Nahraď jeden-uzel-na-nepřítele jedním MultiMeshInstance2D"

Not started. Two reasons, either alone would be enough to stop and ask rather than guess:

**1. Scope.** S5 asks to rewrite the entire live-enemy representation from
Node-per-Distraction (current architecture: `scripts/enemy.gd`'s `Distraction`, a full
`Node2D` with `_process`, its own `cell_path`/`path_index` walk, `StatusManager`,
`take_damage`/`take_direct_damage`, knockback, animation) to a flat array of structs
keyed by "distance along path" instead of world position, with targeting reframed as a
range query over that sorted array. This is not a contained module — it is the game's
entire enemy simulation loop, and virtually everything this session has touched
(`GridProjection`'s targeting math, `PathMetrics`, tower cone/LOS checks, the
`StatusManager`/`ArcProfile` components CLAUDE.md names as the three established
behavior components) either reads live `Distraction` node state directly or assumes it
exists as a `Node2D` with a `global_position`. S6 then asks to replace per-node drawing
with one shared `MultiMeshInstance2D` for the whole horde, which only makes sense once
S5's array-of-structs exists — the two are really one project split across two lines.

**2. A likely conflict with an established, deliberate rendering choice.**
CLAUDE.md names `DistractionAnimator` as one of the three existing single-responsibility
components ("procedurální vektorová kresba nepřátel přímo v Canvas, žádné sprite
listy" — procedural vector drawing directly on canvas, no sprite lists) — read this
session at `scripts/components/distraction_animator.gd` (contact shadows, type glow,
status auras, `_draw_generic_fallback`, all `_draw()`-based vector shapes, not
textures). `MultiMeshInstance2D` renders many instances of ONE shared `Texture2D` (or a
`Mesh`) with per-instance transform/color/custom-data — it has no mechanism for
per-instance arbitrary procedural `_draw()` calls. Implementing S6 as literally
specified would mean either abandoning `DistractionAnimator`'s whole approach (a
deliberate choice CLAUDE.md documents, not an oversight to "fix") or pre-baking every
distraction's current visual state into a texture atlas each frame to feed the
MultiMesh — a fundamentally different, much more complex rendering architecture that
the task text doesn't acknowledge needing.

**What I did:** nothing — flagging both before spending any implementation effort,
since guessing at either the data-model split or the rendering reconciliation risks
throwing away real work if the actual intent turns out different. T11's own perf
numbers (docs/PERF.md: 1000 distractions average 88ms/11 FPS, worst-frame 202ms) are
already on record as the "why bother" baseline these two tasks would be measured
against, so the motivation is real — just not something to attempt without agreement
on: (a) whether `DistractionAnimator`'s procedural-vector style is meant to survive
this, and if so how, and (b) how much of `Distraction`'s current per-node behavior
(status effects, individual pathing, knockback) needs to keep working identically vs.
being redesigned as part of the array-of-structs move.
