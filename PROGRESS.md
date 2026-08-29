# Progress

Log of tasks completed by run.sh, one entry per run, newest last.

<!-- Format:
## 2026-08-29 — <task from MIGRATION.md>
- what changed
- verify.sh result
- commit hash
-->

## 2026-08-29 — T0: verification gate (docs/refactor prerequisite, not in MIGRATION.md itself)
- Wrote verify.sh: reads $GODOT, imports the project, runs every scenes/_test_*.tscn
  under a 120s timeout each (log per test in .dev/), skips _test_legacy_*, regenerates
  and diffs docs/ROSTER.md, never stops at the first failure, prints a
  pass/fail/skip/known-broken summary. Added .dev/ to .gitignore.
- Ran it on a clean checkout of this branch BEFORE any migration work. Found 7
  pre-existing test failures, all sharing one root cause already documented in
  _test_levels.gd's own docstring: level_1/level_2's `objective` point lies outside
  the current 24x24 grid (a leftover from a prior grid-size migration), so
  `AStarGrid2D.get_id_path()` throws "out of bounds" any time a harness spawns a
  distraction on the default level instead of an iso level (98/99):
  _test_deep_reading, _test_fog_bandwidth, _test_los, _test_phase4,
  _test_shadow_occlusion, _test_suppression, _test_zen_pulsar.
  docs/ROSTER.md is also stale against current data/ content (new distractions
  `comparison`/`energy_drink`, habit `focus_pillar`, intervention `moment_of_clarity`
  aren't reflected) — unrelated content drift, not caused by this task.
  _test_phase3 was observed flaky once (timing race in "slow expired while blocked"),
  passed on every other run — noted, not chased.
  None of the above was fixed, per instruction — this entry exists so it's visible
  instead of silently blocking every later task's "verify.sh must pass" gate. Added
  KNOWN_BROKEN_TESTS / ROSTER_KNOWN_STALE to verify.sh as the baseline (mirrors
  _test_levels.gd's own KNOWN_BROKEN convention). Whichever future task's scope
  happens to cover one of these should fix it for real and remove it from that list.
- Also found and fixed a real bug in my own first draft: piping roster.py straight
  into `> docs/ROSTER.md` truncated the tracked file in place when the generator
  crashed (Windows cp1250 stdout default choking on a `→` character). Fixed by
  forcing PYTHONIOENCODING=utf-8 and generating to a temp file first.
- Gap noted, not fixed: scripts/_test_iso_math.gd and scripts/_test_game_iso_slice.gd
  are tracked in git but never had a scenes/*.tscn wrapper, even at the commit that
  introduced them (405df22) — invisible to this gate and to CLAUDE.md's
  "iso math/slice" fixture list.
- verify.sh: PASS (13 pass, 0 fail, 0 skip, 8 known-broken) after the baseline was added.
- Also manually verified: an injected assertion failure is reported by name and doesn't
  stop the rest of the suite; an injected infinite loop (bypassing the test's own
  internal watchdog) is caught by verify.sh's external 120s timeout, reported as
  "(timeout after 120s)", and leaves no orphaned Godot process. Both reverted.
- Commits: 61b07c8 (unrelated CLAUDE.md structure fix, reviewed earlier this session),
  5d72b07 (verify.sh + .gitignore)

## 2026-08-29 — T1: ověřovací síť (docs/refactor/MIGRATION.MD)
- Partial. Added .github/workflows/ci.yml (downloads pinned Godot 4.7.1 Linux headless,
  caches it, runs ./verify.sh on push/PR).
- Did NOT install GUT or found tests/ — conflicts with CLAUDE.md's "Testy jsou smlouva",
  which explicitly documents this repo as deliberately not using GUT. Logged to
  BLOCKED.md with options instead of guessing.
- verify.sh: PASS (13 pass, 0 fail, 0 skip, 8 known-broken).
- Not verified: a live green CI run (T1's own done-criterion) — would need a push,
  which the branch rules forbid from this session.
- Commit: 04eb8f3
