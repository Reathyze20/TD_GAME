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

## `_test_deep_reading` — data/test contract, NOT art

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

## `_test_zen_pulsar` — missing file, with a name and a commit

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

## `_test_shadow_occlusion` — two defects stacked, neither one a texture

This is the entry P0e singled out, and the "missing texture" reading was wrong twice over.

**Defect 1 — it cannot run headless, and verify.sh runs it headless.**

```
ERROR: Parameter "t" is null.
   at: texture_2d_get (./servers/rendering/dummy/storage/texture_storage.h:110)
SCRIPT ERROR: Cannot call method 'get_size' on a null value.
   at: _sample (res://scripts/_test_shadow_occlusion.gd:67)
```

The null is not a texture asset. It is `get_viewport().get_texture().get_image()` at
`_run()` line 157 returning null, because `--headless` installs the **dummy renderer**
(`RendererDummy`, per the error's own path) and there are no rendered pixels to read back.
The test's own header says so in as many words: *"Needs a real renderer (--main-scene, NOT
--headless: shadows are computed on the GPU and this reads pixels back from the
viewport)"*, and its documented invocation carries no `--headless` flag. `verify.sh` runs
every fixture with `--headless`.

- **Class:** harness mismatch — not any of P0e's three.
- **First red:** `5d72b07` (T0, the commit that added `verify.sh` and with it the
  `--headless` invocation, at what is line 79 in that version). The test predates it
  (`e3df867`) and was written to be run by hand.

**Defect 2 — with a real renderer it still fails, and that failure is real.**

```
blocked point (272.0, 137.0): off=0.0967 on=0.0967 (delta +0.0000)
clear   point (640.0, 137.0): off=0.7281 on=0.7281 (delta +0.0000)
FAIL clear point gained more brightness from the light than the blocked point did
FAIL clear point gained brightness off->on at all delta=0.0000
```

Run without `--headless` the readback works — those are real base-art luminances — but
toggling `shadow_enabled` changes the picture by **exactly zero** at both sample points,
including the clear one sitting at r=184 well inside the core lamp's r=330. The lamp adds
nothing to the rendered image at all.

`game.gd`'s own comment (around line 2036) explains what the effect depends on: *"Light2D's
default blend mode is ADD, and nothing in this project uses CanvasModulate, so the base art
already renders at full authored brightness with zero lights present — adding a Light2D does
not darken anything, it only ADDS a warm pool"*. So the whole feature rests on that ADD pass
landing on the field art, and measurably it does not.

- **Class:** real regression in rendering.
- **First red (this symptom):** `26814f9` (T5). At `04b6fc5`, T5's parent, the test fails
  *earlier* and differently — it cannot even find a sample pair (`blocked=(inf, inf) r=0`),
  the out-of-bounds-level mask described at the top. **No green commit was found**: every
  reachable earlier commit is masked by that older defect, so "it worked before T5" is
  plausible but unproven.
- **Suspect, unproven:** `_build_square_terrain()` (`game.gd:661`, described in its own
  comment as a T5 first-pass placeholder) drawing over or outside the lights' reach. Worth
  checking before anything else, but nobody has.

## `_test_fog_bandwidth` — real regression, arc width does nothing

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

## `_test_suppression` — real regression, knockback into a wall

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
| `_test_zen_pulsar` | missing file | `0465a23` | `0465a23` |
| `_test_shadow_occlusion` | harness mismatch + render regression | `5d72b07` (headless) | `26814f9` (zero delta) |
| `_test_fog_bandwidth` | logic regression | ≤ `5d72b07` | `26814f9` |
| `_test_suppression` | logic regression | ≤ `5d72b07` | `26814f9` |
| `_test_phase3` | test-design defect — **fixed** 2026-08-30 | n/a (race) | n/a |

`verify.sh`'s inline comments next to `KNOWN_BROKEN_TESTS` still carry the older, partly
wrong causes. They were left untouched on purpose — P0e's brief is "NEOPRAVUJ nic" — so
**this file supersedes them** until someone reconciles the two.
