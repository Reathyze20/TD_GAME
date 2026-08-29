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

## 2026-08-29 — T2 (MIGRATION.MD) / S1 (SYSTEMS.MD): economy characterization tests
- One harness covers both — they ask for the same thing at different minimum counts.
  26 checks on Tolerance (clamping/floor/raise/clear, passive decay incl. fasting's
  2.5x), Quick Hit (payout curve, cooldown, tolerance spike + permanent floor gain,
  disabled/game_ended guards), and the defeat-reward formula (downregulation curve,
  floor-at-1, lean waves = 0, Streak x Tolerance compounding, jackpot/steady-payout
  schedule, flat dopamine_bonus modifiers), plus one real spawn+kill for wiring.
- Neutralized this machine's real savegame.tres (Growth Tree ranks would otherwise
  add perks on top of the formulas under test) by swapping
  MetaProgression.current_save for a blank in-memory SaveGame for the run — never
  written to disk, restored after. Most checks fire SignalBus.distraction_defeated
  directly with a chosen base_reward instead of spawning real DistractionData, so
  they test the formula, not any one distraction's tuned balance number.
- Added tools/make_test_scene.gd (PackedScene.pack + ResourceSaver.save) to generate
  the trivial `_test_*.tscn` wrapper programmatically per CLAUDE.md's "Scény" rule,
  instead of hand-typing it. Reusable for later fixtures in this plan.
- Found while re-verifying: _test_phase3 fails intermittently (2 of 5 runs across this
  session, always "slow expired while blocked: factor reset to 1.0 (got 0.5)") on runs
  that touched no production code — a real-time-frame-count race
  (scripts/_test_phase3.gd:171-174 assumes 10 `await process_frame`s always exceeds
  0.05s of accumulated delta), not something this task caused. Added to
  KNOWN_BROKEN_TESTS in verify.sh rather than chasing it — out of T2's scope.
- verify.sh: PASS (13 pass, 0 fail, 0 skip, 9 known-broken).
- Commit: 4d3f3c7

## 2026-08-29 — T3: perspective inventory audit (read-only)
- Delegated to a background research agent (opus, per the plan's own "Model: opus"
  annotation), then spot-checked line-for-line against source before writing
  docs/MIGRATION_AUDIT.md myself (the agent has no Write access) — every claim checked
  matched exactly, including verbatim comment text.
- ~42 coordinate-conversion sites outside Data.cell_center()/world_to_cell(), 17 of
  them hand-written ground-space *0.5/*2.0 conversions, 9 gameplay-critical. Plus a
  second, independent projection (Godot's own TileMapLayer DIAMOND_DOWN) corrected by
  a half-tile layer offset.
- Baked levels: schema is perspective-agnostic (grid Vector2i/Rect2i throughout except
  one unused `decor.pos` field). level_1/level_2 sit on a dead ~120x57 grid — this is
  the exact root cause already logged in T0's KNOWN_BROKEN_TESTS — and need a rescale
  (tools/regrid_levels.py is the existing precedent), not a reprojection.
- Y-sort and elevation (WALL_HEIGHT): both purely visual. base_habit.gd documents that
  an earlier attempt to move the lift into `position` was reverted because `position`
  is simultaneously the y-sort key and what every range/targeting check measures from.
- High Ground: a real mechanic (blocks A*, only buildable terrain, blocks LOS via
  cast_to_wall/has_line_of_sight with slab-based self-exemption, mutable at runtime by
  the sinking-walls spike) — but through occlusion, never through height. No height
  term exists in any range/damage formula.
- **Flagged for a human decision before T4/T5**: targeting/LOS are already in ground
  space (2:1-corrected), but Routine gating, Brain Fog visibility, intervention AoE and
  guard zones are still raw screen-space circles. No document says this split is
  intentional. A top-down migration silently makes these two currently-disagreeing
  radius families agree — worth deciding on purpose rather than by default.
- verify.sh: PASS (13 pass, 0 fail, 0 skip, 9 known-broken) — docs-only change.
- Commit: 7914373

## 2026-08-29 — T11: horde perf bench, N=50..1000
- _perf_horde.gd/.tscn spawns N distractions into the spawn zone (so they walk the
  actual path) on iso level 99 (default level's objective is out of bounds on the
  current grid, see T0), measuring wall-clock frametime cumulatively at each N. Same
  methodology as the existing _perf_probe.gd (wall-clock around process_frame, vsync
  forced off — TIME_PROCESS reads smoothed/stale on this machine).
- Results in docs/PERF.md: 50 -> 6.23ms/160 FPS, 100 -> 12.29ms/81 FPS,
  200 -> 27.29ms/37 FPS, 500 -> 62.76ms/16 FPS, 1000 -> 88.28ms/11 FPS. Worst-frame
  spikes are notably worse than average at scale (500: 108.91ms worst vs 62.76ms avg;
  1000: 201.91ms worst vs 88.28ms avg) — real stutter, not just a lower average.
  Not investigated further — T11 says measure only.
- verify.sh: PASS (13 pass, 0 fail, 0 skip, 9 known-broken).
- Commit: 032dddf

## 2026-08-29 — T4 part 1: GridProjection + gameplay-critical sites (in progress)
- Added scripts/grid_projection.gd (class_name GridProjection extends RefCounted, NOT
  an autoload — CLAUDE.md forbids adding those without asking). Data.cell_center()/
  world_to_cell()/in_bounds() now delegate to it, unchanged for every existing caller.
- Migrated the 9 gameplay-critical hand-written ground-space (*0.5/*2.0) sites the T3
  audit flagged onto new to_ground()/to_screen()/ground_distance()/
  ground_dir_to_screen() helpers: has_line_of_sight/cast_to_wall + aiming-mode mouse
  vector + split-spawn scatter (game.gd), auto-aim + is_point_in_cone + shot-spawn
  direction (tower.gd), projectile flight direction (projectile.gd). Each is the exact
  prior formula, algebraically substituted — not rewritten.
- Verified behavior-preserving by snapshotting every KNOWN_BROKEN test's log before the
  change and diffing after: _test_los and _test_shadow_occlusion (most directly
  exercising this code) came back byte-identical; every other difference was a
  line-number shift in an error backtrace, or one unrelated timing-jitter value in
  _test_fog_bandwidth's respawn-timer check (same class of real-time race as the
  already-flaky _test_phase3, unrelated to this change).
- verify.sh: PASS (14 pass, 0 fail, 0 skip, 8 known-broken — _test_phase3 happened to
  pass this run, still flaky).
- **T4 is NOT complete.** ~33 sites remain from the audit: visual-only ground-space
  squash (turret head/recoil/muzzle, range rings, impact fan, contact shadows,
  placement preview ellipse), hand-rolled diamond geometry (wall segments, terrace
  shadow/blocks, static field draw, board_bounds), the Godot TileMapLayer half-tile
  offset (game.gd + tools/map_editor.gd), and several sites in code the audit found
  uncalled (decor_layer.gd, wall shadow/face layers, old terrain layer). T4's own
  "hotovo když" ("v kódu není žádný jiný převod souřadnic") is not yet true. Continuing.
- Commit: 69e16f5

## 2026-08-29 — T4 part 2: visual-only ground-space sites (in progress)
- Migrated tower.gd's 8-direction head aim, recoil offset, muzzle kick, muzzle flash
  direction, and wedge-preview ray directions onto ground_dir_to_screen()/to_screen();
  the range-ring and placement-preview ellipse radii (game.gd, tower.gd) now divide by
  the named GridProjection.GROUND_Y_SCALE constant instead of a bare 0.5 literal; the
  impact particle burst's splat direction (impact_fx.gd). Added
  GridProjection.screen_dir_to_grid_axes() for enemy.gd's note_heading() (8-way
  walk-cycle facing) — a related but distinct formula, verified against source first.
- Deliberately did NOT touch defender_unit.gd:511 (0.42, eyeballed art constant, not
  the 2:1 squash) or distraction_animator.gd:192-195 (1.45 drop, same reason) — forcing
  either onto GROUND_Y_SCALE would be an actual behavior change. Also deferred the two
  draw_set_transform(..., Vector2(1.0, 0.5)) canvas-transform sites in tower.gd
  (pedestal shadow, muzzle flash halo) — same squash, different code shape, wanted each
  verified on its own rather than batched blind.
- Verified three ways: full verify.sh unchanged (14 pass, 0 fail, 8 known-broken);
  every KNOWN_BROKEN log diffed byte-identical against a pre-change snapshot (one
  exception, the same _test_fog_bandwidth timing-jitter value already seen in part 1);
  and a real screenshot from _shot_aim.tscn (built specifically to check 8-direction
  head art) shows all 8 towers still facing their assigned angles correctly, range-ring
  ellipse still a proper 2:1 ellipse.
- Commit: 749ff29
- **Still remaining for T4**: the TileMapLayer half-tile offset, hand-rolled diamond
  geometry (~7 sites), the 2 deferred canvas-transform sites, and the uncalled-code
  sites. Pausing here for now — this is a large, high-risk task and a good amount of
  it has been done with heavy verification each step; the remainder deserves the same
  care in a focused follow-up rather than being rushed at the end of an already long
  session.

## 2026-08-29 — T4 part 3: diamond geometry, TileMapLayer offset, remaining squash sites
- Ran a research + adversarial-verification workflow: 4 parallel read-only agents (one
  per remaining site group) proposed diffs, then an independent verifier checked each
  against the live source. The verifier correctly rejected several call-site diffs for
  referencing GridProjection methods that didn't exist yet (layer_origin,
  diamond_corners, cell_diamond, board_bounds) — but those same 4 methods, proposed as
  standalone additions, verified safe in isolation, and the verifier's own algebra check
  on the "broken" call-site diffs confirmed they'd be correct once the methods existed.
  Applied by hand in the right order: added the 4 methods first, then wired up the call
  sites — re-verifying each snippet against the actual current file myself before
  editing, not just trusting the agents' quotes.
- Added to GridProjection: layer_origin(span) (the Godot TileMapLayer half-tile
  DIAMOND_DOWN correction — was two independently hand-written copies in game.gd and
  tools/map_editor.gd that could silently drift apart; proven algebraically identical
  for span=1 and span=Data.BUILD_BLOCK=3, now one shared source), diamond_corners()/
  cell_diamond(cell) (the 4-point diamond offset math hand-written at 5 draw sites), and
  board_bounds() (verbatim move — kept as the exact same float-op sequence rather than
  reconstructed from the corner primitives, since it feeds Camera2D limits).
- Migrated onto them: _build_path_layer, tools/map_editor.gd's _layer_origin (now a
  one-line delegate), _build_wall_segments, TerraceShadow._draw, _draw_static_field
  (both diamond blocks), _draw_placement_preview's 3x3 block outline, board_bounds.
- Also migrated 3 deferred draw_set_transform squash sites (tower.gd pedestal shadow +
  muzzle flash) plus 3 more the verification sweep found genuinely missed (game.gd's
  objective/Focus-core glow; distraction_animator.gd's type-glow and boredom-halo
  auras) and one inside the function this session's T4 part 2 entry had excluded for
  ITS OTHER eyeballed constants (distraction_animator.gd's contact-shadow bob scale —
  its own comment says "(2:1 projection)", confirmed distinct from the 1.45 drop
  distance that was the actual reason for the earlier exclusion).
- NOT touched: defender_unit.gd's 0.42 (still genuinely eyeballed, not 2:1), and 3
  PixelDraw.ellipse-radius squashes expressed as a second-argument multiply rather than
  a transform scale or corner offset (game.gd wave_r/ring_r at ~2251/2255/2259,
  distraction_animator.gd's Slow/Calm ring at ~441) — same idea, different code shape,
  left for a follow-up.
- Verified: clean import; full verify.sh unchanged (14 pass, 0 fail, 8 known-broken,
  _test_mapeditor still green — it specifically asserts editor/game layer positions
  agree, exactly what layer_origin() now unifies); every KNOWN_BROKEN log diffed against
  a pre-change snapshot (only line-number shifts from the net -25 lines removed, plus
  the same recurring timing-jitter value); and a real screenshot (_shot_iso_board.tscn)
  shows terraces, wall faces, the placement-preview diamond, and the Routine ring all
  rendering correctly.
- Also produced (workflow, catalog-only, feeds S9's docs/DEBT.md later): confirmed-dead
  code with zero call sites anywhere (_build_decor_layer, _build_wall_shadow_layer,
  _build_wall_face_layer, _build_terrain_layer/_build_corner_terrain), and 3 live
  square-math oddities correctly out of scope for T4 to fix (_build_shadow_occluders —
  invisible today since both iso levels set shadows=false; the intervention whole-board
  Rect2; _draw()'s square-derived w/h/base_radius locals).
- verify.sh: PASS (14 pass, 0 fail, 0 skip, 8 known-broken).
- Commit: 4a543fd
- T4 is now close to complete: only the 3 ellipse-radius squash sites above remain from
  the audit's original inventory.
