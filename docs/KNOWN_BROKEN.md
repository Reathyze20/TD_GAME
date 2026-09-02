# Known-broken fixtures

Inventory of every entry in `verify.sh`'s `KNOWN_BROKEN_TESTS` and `FLAKY_TESTS`, written
for `docs/refactor/PATHFINDING.MD` P0e. **Diagnosis only at the time of writing — nothing
was fixed under P0e itself.** One entry (`_test_phase3`) was fixed afterward, on
2026-08-30, under CLAUDE.md's narrow flaky-test exception; see its own section below.

For each: what exactly fails, which class it belongs to, and the first commit that shows
*that* failure. Regenerate any run below with

```
godot --headless --path . --main-scene res://scenes/<name>.tscn
```

except `_test_shadow_occlusion`, which must NOT be run headless — see its entry.

## Two things this inventory corrected

**1. Three of the six were misfiled.** The list in `verify.sh` (and the summary that fed
it) called `_test_deep_reading` and `_test_zen_pulsar` "art expectations" and
`_test_shadow_occlusion` "a missing texture". None of those three is right. The first is a
data/test contract that diverged, the second is a genuinely missing *file* but with a
knowable name and commit, and the third is two unrelated defects stacked on top of each
other, neither of them a texture. All three misreadings came from reading a failure line
without checking what the named thing actually was.

**2. "First red commit" is ambiguous here, and the ambiguity is the story.** Three
fixtures were already failing at the T0 baseline (`5d72b07`) for a *shared, unrelated*
reason: `level_1`/`level_2` carried `objective = (109, 34)` against a 24x24 grid, so
`AStarGrid2D.get_id_path()` threw "out of bounds" for any harness that instantiated
`Game.tscn`, and everything those tests measured came back zero. T5 (`26814f9`) rebuilt
`level_1` with a valid objective and **unmasked** what was underneath. So each of those
entries has two dates: when it first went red at all, and when today's symptom first
appeared. Both are given.

## Method note, because one pass of it was wrong

The first attempt at this walked a detached worktree across eleven commits with
`git checkout -q --detach "$c" 2>/dev/null`. The checkouts silently failed after the third
commit and the loop kept running tests against a stale tree, producing a clean, plausible,
**entirely fictional** table in which every fixture passed at every commit. It was caught
only because static evidence (`git cat-file -e`, `git show <commit>:<file>`) contradicted
it. Every commit-level claim below was re-derived with `--force` and a
`git rev-parse HEAD` printed after each checkout, or from static git queries that need no
checkout at all.

---

## `_test_deep_reading` — **five of six failures FIXED 2026-09-02 (M9)**; one left, undiagnosed

Both causes this entry described turned out to be **stale expectations, not defects**, and a
third failure had appeared that this entry never recorded.

**1. `head_aims` — removed from the leak guard, with the user's say-so.** The check exists
to catch Deep Reading's traits bleeding into other habits through the POOLED projectile,
and a trait can only leak from a habit that HAS it — `real_hobby` carries
`head_aims = false` like everyone else, so there was nothing to leak from. It was also
asserting the opposite of a deliberate decision: `head_aims` is false on **all fifteen**
habits in `data/`, and `tower.gd` (~line 610) says why in as many words — *"presne to je
duvod, proc `head_aims` zustava u cele rodiny false: rotace bitmapy je spatna operace"*.
Eight-direction head art replaced rotation; nothing aims a head any more.
`projectile_spin` and `boredom` — the two traits Deep Reading actually sets — stay.

**2. `both still outrange everything else` — a threshold longer than the board.** This
entry never mentioned it, because it went red *after* the entry was written: the check
demanded `range >= 500.0`, and P8b (`612a043`, 2026-08-30) rescaled every fire radius to
the real 480x224 field, taking `real_hobby` to 260. 500 px is longer than the whole board.
Exactly the artifact class `BLOCKED.md` already closed for `_test_phase7` (*"hardcoded
400px ... was a pre-migration scale artifact"*). Now derived from the roster's own maximum,
which is what the label claimed all along and cannot rot on the next rescale.

**3. Still failing, and NOT understood:**

```
FAIL a second habit does stack (0.0/s vs 0.0/s)
```

In `_test_dot_source_semantics` the shot does not land — the target's health never moves
and no Boredom is applied — while a **byte-identical** `_shoot()` call in the sub-test
directly above it does land and leaves its DoT. Probed state at the failing call:

```
PROBE pre  valid=true dead=false hp=99999 pos=(8.0, 153.0) active=1
PROBE post valid=true dead=false hp=99999 pos=(8.0, 153.0) active=2 dps=0.00
```

**Ruled out, each by measurement rather than reasoning:**

- *Frame-vs-tick pacing.* `_shoot()` waits six `process_frame`s while projectiles move on
  the sim tick, which looks like the classic mismatch — but the test fails **identically**
  under `--fixed-fps 60`, where the two are 1:1.
- *The muzzle spawning off the board.* `from` is 30 px west of the target, and level 1's
  spawn column puts the target at x=8, so the muzzle lands at x=-22, outside the field.
  Firing from the **east** instead (`from + 30px`, angle PI) fails identically.

**Still open:** `active=1` at the section's start — a projectile from the previous sub-test
is in flight when this one begins, and `_drain_projectiles()` evidently did not clear it.
That is the most concrete remaining thread and nobody has pulled it.

**Class:** two stale expectations (fixed) plus one real, undiagnosed miss.
**Stays in `KNOWN_BROKEN_TESTS`** with one failure instead of six.

### Original entry (2026-08-30), superseded above

```
FAIL focus_timer still aims its head and fires plain bolts
FAIL focus_timer_2 still aims its head and fires plain bolts
FAIL exercise still aims its head and fires plain bolts
FAIL exercise_2 still aims its head and fires plain bolts
```

`scripts/_test_deep_reading.gd:181` asserts, for those four habits,
`h.head_aims and projectile_spin == 0.0 and boredom == 0.0` — a guard that the Deep
Reading line's traits did not leak into unrelated habits through the pooled projectile.

All four `.tres` now carry `head_aims = false`. The other two properties are still 0, so
**only the `head_aims` half fails**: the roster was changed so those heads no longer
swivel, and the assertion still demands that they do. Nothing is missing and nothing is
broken at runtime; a deliberate data change was never reflected in the test that pins it.

- **Class:** data/test contract divergence (none of P0e's three).
- **First red:** `0465a23` ("test", 2026-08-29). `git show 4c6ed86:data/habits/focus_timer.tres`
  has no `head_aims` key at all (script default `true`); `git show 0465a23:...` has
  `head_aims = false`. The assertion itself is older (`331134c`).
- **Note for whoever fixes it:** this is the one entry where the correct fix might be to
  change the test rather than the code, which CLAUDE.md says needs the user's say-so.

## `_test_zen_pulsar` — **FIXED 2026-09-02 (M9)**; the precondition named the wrong file

**Removed from `KNOWN_BROKEN_TESTS`. The fixture passes.**

This entry was half right and its conclusion was wrong. The frames really are gone —
`assets/towers/head_zen_pulsar_frame_1..8.png` do not exist — but **nothing needs them**.

The failing line is a *precondition* for the art-fallback section, and that section's
premise is only "the base tier has head art at all". It does: `head_zen_pulsar.png` ships.
The animation is optional to the very function under test — `tower.gd _head_art_key()`
accepts **either** spelling (`head_%s.png` OR `head_%s_frame_1.png`, ~line 643), and the
loader takes the static file first and only then looks for frames. The fixture was stricter
than the code it exists to exercise.

The precondition now mirrors `_head_art_key()`'s own condition, so the two cannot disagree
again the next time the art changes shape. **No art was generated** — the task forbids it
and none was needed.

### Original entry (2026-08-30), superseded above

```
FAIL the base has head art
```

`scripts/_test_zen_pulsar.gd:110` is
`FileAccess.file_exists("res://assets/towers/head_zen_pulsar_frame_1.png")`.

That file is gone. What survives is `assets/towers/head_zen_pulsar.png` (plus its
`.import`) — the single-frame sprite. The eight-frame set
(`head_zen_pulsar_frame_1..8.png`) was removed wholesale.

- **Class:** missing texture (P0e's second class), though the *asset* is missing rather
  than a path being renamed.
- **First red:** `0465a23`. Proven per-commit with `git cat-file -e`: present at
  `405df22` and `4c6ed86`, absent from `0465a23` onward.
- **Open question for the fix:** whether the frame set should come back or the assertion
  should point at `head_zen_pulsar.png`. The two checks *after* it already pass — the
  upgrade tiers correctly fall back to the base sprite key — so the line under test works;
  only the file it names is gone.

## `_test_shadow_occlusion` — FIXED 2026-09-02 (was: "two defects stacked, neither one a texture")

**Both defects are gone, and the second one was never real.** The fixture is green,
removed from `KNOWN_BROKEN_TESTS`, and stays in `REQUIRES_DISPLAY_TESTS` — needing a real
renderer is a permanent property of what it measures, not a defect. Below: what each
defect turned out to be, kept in full because the second one is a lesson about this
inventory's own method.

### Defect 1 — "it cannot run headless, and verify.sh runs it headless"

Correctly diagnosed, and already resolved before this fix, by `dcfd43e`'s
`REQUIRES_DISPLAY_TESTS` / `SKIP-NO-DISPLAY` category: the fixture is no longer attempted
under `--headless` (where `RendererDummy` has no pixels to read back) and runs for real,
without `--headless`, when `$DISPLAY` or `VERIFY_WITH_DISPLAY=1` is set. Nothing more was
needed here.

### Defect 2 — "with a real renderer it still fails, and that failure is real" — WRONG

This entry recorded a **real regression in rendering**: *"toggling `shadow_enabled`
changes the picture by exactly zero at both sample points... The lamp adds nothing to the
rendered image at all."* That conclusion does not survive re-measurement. The lamp works.

The whole thing was one stale constant in the test's own sampler:

```gdscript
var scale := Vector2(sz.x / 1920.0, sz.y / 1080.0)   # _test_shadow_occlusion.gd:_sample()
```

`project.godot` declares a **480x270** viewport with `stretch/mode="viewport"` and integer
scaling — it has since the T5 square migration and the 480x270 UI rescale — and
`get_viewport().get_texture().get_image()` comes back at exactly 480x270. World
coordinates are already canvas coordinates, so the correct ratio is 1.0; the hardcoded one
is 480/1920 = **0.25**. Every sample was read at a quarter of its intended position.

The evidence was in this entry the whole time and got read past. Its own quoted failure is

```
blocked point (272.0, 137.0): off=0.0967 on=0.0967 (delta +0.0000)
clear   point (640.0, 137.0): off=0.7281 on=0.7281 (delta +0.0000)
```

`y=137` is **this 480x270 board's core row** (`objective_cell (28, 7)` -> world
`(456, 137)`). On a 1920x1080 canvas the core would sit near y=548. So that measurement
was already taken after the rescale, and at scale 0.25 it read pixels at (68, 34) and
(160, 34) — the top edge of the window, off the playfield, where of course nothing changes
when a lamp 100+ px away toggles. The reading was honest; what it was pointed at was not.

**Re-measured with the ratio derived from the live viewport instead of assumed** (five
angles, `shadow_enabled` off vs on, core lamp `r=165`):

| radius | 10 | 25 | 40 | 55 | 70 | 85 | 100 | 115 | 130+ |
|---|---|---|---|---|---|---|---|---|---|
| luma delta | +0.1190 | +0.0275 | +0.0248 | +0.0183 | +0.0131 | +0.0078 | +0.0026 | 0.0000 | 0.0000 |

The lamp contributes 0.119 luma at r=10 and stays above the fixture's own 0.003 threshold
out to about r=100. (1/255 = 0.0039, so past ~r=100 the signal is under the 8-bit floor of
the readback itself — "zero" there means "unmeasurable this way", not "absent".) The
suspect this entry named — `_build_square_terrain()` drawing over the lights — is
**cleared**, and nobody needs to check it.

### What actually still needed fixing, and it was the search, not the renderer

With the sampler corrected the fixture failed at its FIRST check instead:
`blocked=(inf, inf) r=0`. That part of this entry's 2026-09-02 note was right — the cause
is `CORE_ROUTINE_RADIUS` shrinking 330 -> 165 at P8b — and here is the measurement behind
it. The old search wanted a wall cell in the ring (24 px, `0.80 * r`], i.e. **(24, 132]**.
On the shipped level, of 27 wall cells:

- **24** are further than 132 px from the core (nearest wall of all: **128 px**),
- **3** are inside the ring but rejected because the point "just past" them lands inside
  the same wall mass,
- **0** candidates survive.

Widening the ring cannot fix this, and the table above says why: every wall on this level
is at r>=128, and past ~r=100 the lamp contributes nothing measurable. A wider ring buys
only "clear point gained no brightness" failures that say nothing about occlusion — the
exact false failure the fixture's own comments already warned about twice.

**The fix:** the test now PLANTS its own occluder (one cell, 1.5 tiles short of a sample
radius derived from the live `CORE_ROUTINE_RADIUS`) using the game's own "a cell just
became a wall" recipe from `_set_sunk()`, then measures. That also removes an undeclared
dependency nobody could see — the fixture silently required the shipped level to carry a
wall in a particular annulus around its objective, so level authoring could break it from
a distance, which is exactly what happened. **All three original assertions and their
thresholds are unchanged**; two preconditions were added (the planted wall really occludes;
the clear point really is still clear), and a fault-injection run with the occluder rebuild
commented out fails 2 of 3 as it should, so the pass is not vacuous.

Measured result, bit-identical across three consecutive runs:

```
blocked point (460.8894, 192.8865): off=0.1020 on=0.1020 (delta +0.0000)
clear   point (410.0456, 169.1776): off=0.1020 on=0.1203 (delta +0.0183)
ALL PASS
```

### The method lesson, since this file already has a section on one

This inventory's §"Two things this inventory corrected" opens by saying three entries were
misfiled because someone *"read a failure line without checking what the named thing
actually was."* Defect 2 is the same mistake one level up: a **measurement** was trusted
without checking what the measuring instrument was pointed at. `(272.0, 137.0)` was printed
in the entry, and `137` was already enough to notice the canvas had moved. The class
"real regression in rendering" was assigned to a number that a stale constant produced.

### Side finding, not fixed here (out of scope, worth someone's attention)

`Game._set_sunk()` — the sinking-wall mechanic — rebuilds platforms, walls, path previews
and the flow field when a cell turns solid or hollow, but does **not** call
`_build_shadow_occluders()`. So a wall that sinks or re-solidifies at runtime changes
collision and pathing while its cast shadow keeps the old shape. Found while reusing that
function's recipe; not touched, since it is a game-side question and this task's brief was
the fixture.

## `_test_fog_bandwidth` — **the headline claim was FALSE**; corrected 2026-09-02 (P8b)

**„Arc width has no effect on lighting at all" is not true, and the measurement that said
so was aimed into the light.** The fixture hard-coded `facing_angle = 0.0` — due EAST —
while level 1's objective sits at `x = 28` of 30 columns, i.e. **east of every build spot
on the board**. A habit may only be built inside the core's own Routine disk, so a cone
pointed at the core is pointed at ground that is lit no matter what the dial does. And
`_lit_cells` is the UNION of every light source, so the fixture was asking "did the whole
board change" — which the core's disk answers "no" to, whatever the habit does.

Two changes to the measurement, no assertion touched:

1. **Measure the habit's OWN contribution** (`_lit_cells` minus a baseline captured before
   the habit was built) instead of the union.
2. **Derive the facing from the core** (`(habit.position - objective_pos).angle()`)
   instead of writing `0.0`, so re-authoring a level cannot silently aim the test into the
   light again. The turn check compares ±45° around that direction rather than flipping
   180°, since a straight flip swings the cone back into the core's disk where the habit
   lights nothing of its own — one side of the comparison would be empty by construction.

With that, the same three assertions read:

| check | before | after |
|---|---|---|
| turning the habit moves the light | −0 cells, +9 | **−6, +6** |
| a wider arc lights more board (15° → 120°) | 18 → 18 cells | **3 → 15** |

**The arc dial works.** At `0.0` rad the habit contributes exactly **zero** cells of its
own at every width from 15° to 120° — that was a dead direction, not a dead parameter.

### What the honest measurement then exposed — a real defect, and a new one

One check now fails that used to pass **vacuously** (the core's disk lit its probes):

```
FAIL the firing edge is lit along its whole length (2 of 6 probes dark)
```

Instrumented, the pattern is the opposite of a range problem — the **near** probes are
dark and the far ones are lit:

```
si=-1 f=0.3 ang=150deg pos=(265.2, 164.0) block=(16, 10) vis=false
si=-1 f=0.6 ang=150deg pos=(218.5, 191.0) block=(13, 10) vis=true
si=-1 f=0.9 ang=150deg pos=(171.7, 218.0) block=(10, 13) vis=true
si=+1 f=0.3 ang=210deg pos=(265.2, 110.0) block=(16,  4) vis=false
si=+1 f=0.6 ang=210deg pos=(218.5,  83.0) block=(13,  4) vis=true
si=+1 f=0.9 ang=210deg pos=(171.7,  56.0) block=(10,  1) vis=true
```

**Cause, read from `game.gd _mark_lit()`:** the fog grid is quantised to
`Data.BUILD_BLOCK` = 3 cells = **48 px blocks**, and a block counts as lit when its
**centre** falls inside the wedge. Firing and targeting, by contrast, test points exactly
(`is_point_in_cone`). Close to the tower those two disagree: the probe at
`0.3 × 180 px = 54 px` sits on the firing edge, but its block's centre is 45° off the
axis — outside even the skirted half-angle (`60° × 0.5 × LIGHT_SKIRT 1.35 = 40.5°`). The
angular width of one 48 px block shrinks with distance, which is exactly why the far
probes pass.

That contradicts two written promises: `is_pos_visible()`'s own comment (*"errs slightly
generous at light edges and **never hides something standing in plain light**"*) and the
skirt's stated contract in the fixture (*"sight must cover fire… fading inward instead
would leave it shooting into its own dark edge, which is the one thing this fog must never
do"*). Near a tower it does exactly that.

**Not fixed here.** Both plausible repairs — finer fog granularity, or marking a block when
the wedge *reaches* it rather than when its centre is inside — change how the fog LOOKS
around every tower. That is a visual judgement, and it is written up with options in
`BLOCKED.md`.

**Class:** measurement defect (now fixed) stacked on a real quantisation defect (open).
**Stays in `KNOWN_BROKEN_TESTS`** — 1 failure, with the cause above rather than the one
this entry used to give.

### Original entry (2026-08-30), kept for the record — its headline is superseded above

```
FAIL level has an empty spot outside the Routine
FAIL turning the habit moves the light (-0 cells, +7)
FAIL a wider arc lights more board (36 -> 36 cells, arc 15 -> 120)
```

The middle two are the substantive ones. Rotating a habit changes the lit set
asymmetrically — it loses **0** cells and gains 7, which is not what turning a cone does —
and widening the arc from 15° to 120° lights **the same 36 cells**, i.e. the arc dial has
no effect on lighting whatsoever. Everything else in this fixture passes, including the
whole Bandwidth accounting block and basic fog visibility, so this is narrowly the wedge
light.

The first failure ("an empty spot outside the Routine") is a level-content assertion, not
a system one: the placeholder `level_1` has no empty build spot outside the Routine radius
for the test to use.

- **Class:** real regression in logic.
- **First red at all:** at or before `5d72b07` (T0), where it fails with
  `turning the habit moves the light (-0 cells, +0)` and `0 -> 0 cells` — the masked
  everything-is-zero shape.
- **First red with today's symptom:** `26814f9` (T5), where the strings are already
  character-for-character what they are now (`-0 cells, +7`, `36 -> 36`).
- **Bearing on the queue:** P9/P10/P11 build on this. P8b exists to fix it first.

### CORRECTED 2026-08-30 (P8b) — two of the three claims above are WRONG

Measured in the engine, not read off the code. Keeping the original text above because
the corrections only make sense against it.

**"the arc dial has no effect on lighting whatsoever" is false.** The same habit turned
to face west gives `arc 15 / 60 / 120 -> 38 / 43 / 50` lit blocks. The dial works. The
fixture happens to pin `facing_angle = 0.0` before both measurements, which on `level_1`
points the cone east into the core's own disc, where the union the fixture asserts on
(`_lit_cells.size()`) swallows every block the dial adds.

**"Rotating a habit ... loses 0 cells, which is not what turning a cone does" is not a
defect either.** The habit sits west of the core inside the core's disc, so everything
the cone lit while facing east was already lit by the core; turning it away can lose
nothing. `-0/+N` is the correct answer to the question the fixture asks.

**The one real defect was in the CONSTANTS, not the fog code.** `CORE_ROUTINE_RADIUS`
330, `HabitData.range` 360 and the lamp/defender/projectile radii were authored for the
pre-T5 isometric board and carried across `26814f9` byte-identical onto a board a
quarter the size. Fixed in P8b by halving all of them (derivation:
`docs/refactor/PATHFINDING.MD`, P8b). That turned the first failure green — `level_1`
now really does have an empty spot outside the Routine.

**Still red, and now known to be unfixable from code:** the two arc assertions. Every
build spot on `level_1` lies west of an objective parked at `x = 28` of 30 columns, so
the core's disc necessarily covers everything east of any spot the player is allowed to
build on. Verified across every admissible `CORE_ROUTINE_RADIUS`, and re-verified after
the range halved. Needs either `level_1` re-authored in MapEditor or a sanctioned change
to the fixture — a user decision, not a code one.

## `_test_suppression` — FIXED 2026-08-30 (was: knockback into a wall)

```
FAIL and never into a wall ((-26.0, 0.0))
```

One check out of a long green fixture. Knockback shoves a body 26 px straight along −X
into a wall; the other three knockback assertions pass, and every arc/spread/pierce block
above it passes.

- **Class:** real regression in logic.
- **First red at all:** at or before `5d72b07` (T0), as `one hit moves it (+0.0px)` — the
  masked shape again (nothing moved because nothing pathed).
- **First red with today's symptom:** `26814f9` (T5), string-identical to today.
- **Root cause:** `Distraction.apply_knockback()` (`scripts/enemy.gd`) only checked
  whether the shove's DESTINATION cell was `high_ground`. `Data.GRID.tile` is 16px while
  the knockback budget is 26px, so a push starting adjacent to a one-cell-thick wall could
  land past it without the destination cell ever being the wall cell itself — tunnelling
  straight through a wall it visibly crossed.
- **Fix, bundled into P4 (docs/refactor/PATHFINDING.MD) since movement's position/cell
  model was already being rewritten:** `apply_knockback()` now samples the swept segment
  in fixed steps of `Data.GRID.tile / 4.0` (`Distraction._knockback_crosses_wall()`) — a
  step small enough that a one-tile wall can never fall entirely between two samples. If
  ANY sample lands in `high_ground`, the whole push is rejected (matching the existing
  budget's all-or-nothing spirit: `_knock_left` is still spent, same as before, so a
  blocked shove doesn't buy a free retry). No assertion in `_test_suppression.gd` changed;
  only the collision detection did.

## `_test_phase3` — FIXED 2026-08-30 (was: flaky by test design, not broken)

```
FAIL slow expired while blocked: factor reset to 1.0 (got 0.5)
```

Was always this one assertion, and passed in most runs (it passed in the P0c and P0e
verification runs and failed in the P0b and P0d ones, on an unchanged tree).

`scripts/_test_phase3.gd:168-174` applied a slow with a **0.05 s** duration and then
waited **10 `process_frame`s** before asserting it had expired. The duration was in
seconds and the wait was in frames, so whether the assertion held depended on the frame
delta at that moment — a real-time race with the machine's speed and load, nothing to do
with the status system it was meant to be testing.

- **Class:** none of the three — a test-design defect, not a code regression.
- **First red:** not meaningful for a race. The construct dated from the initial commit
  (`6a24927`) and had always been able to fail.
- **Fix (approved by the user):** replaced the 10-frame wait with
  `await get_tree().create_timer(0.15).timeout` — waits on real elapsed seconds (3x
  margin over the 0.05s duration) regardless of frame rate. Only the wait mechanism
  changed; no assertion or expected value was touched. Qualified under CLAUDE.md's narrow
  flaky-test exception (added the same day): FLAKY not KNOWN-BROKEN, timing-only change,
  proven with 20/20 clean runs before landing. `FLAKY_TESTS` in `verify.sh` is now empty.
  Full reasoning in PROGRESS.md's own entry for this fix.

---

## Summary

| fixture | class | first red (any) | first red (today's symptom) |
|---|---|---|---|
| `_test_deep_reading` | data/test contract | `0465a23` | `0465a23` |
| `_test_zen_pulsar` — **FIXED 2026-09-02** | missing file | `0465a23` | `0465a23` |
| `_test_shadow_occlusion` | harness mismatch + **stale sampler constant, NOT a render regression** — **fixed** 2026-09-02 | `5d72b07` (headless) | `26814f9` (zero delta, since disproven) |
| `_test_fog_bandwidth` | **measurement defect (fixed 2026-09-02) + fog block quantisation (open)** — the "arc does nothing" headline was FALSE | ≤ `5d72b07` | `26814f9` |
| `_test_suppression` | logic regression — **fixed** 2026-08-30 (P4) | ≤ `5d72b07` | `26814f9` |
| `_test_phase3` | test-design defect — **fixed** 2026-08-30 | n/a (race) | n/a |

`verify.sh`'s inline comments next to `KNOWN_BROKEN_TESTS` still carry the older, partly
wrong causes. They were left untouched on purpose — P0e's brief is "NEOPRAVUJ nic" — so
**this file supersedes them** until someone reconciles the two.
