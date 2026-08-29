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

## 2026-08-29 — T4 part 4: remaining ellipse-radius squash sites
- Migrated the 3 sites from part 3's own remainder note directly (small, mechanical,
  same identity already proven at tower.gd:796): game.gd's objective pulse-wave and
  health-ring ellipses (wave_r, ring_r x2) and distraction_animator.gd's Slow/Calm
  status ring, all now dividing by GridProjection.GROUND_Y_SCALE instead of a bare
  `* 0.5` on PixelDraw.ellipse()'s second radius argument.
- verify.sh: PASS (14 pass, 0 fail, 0 skip, 8 known-broken); every KNOWN_BROKEN log
  byte-identical except the same recurring timing-jitter value.
- Commit: 105d011

## 2026-08-29 — T4 part 5: one more genuine miss, found by a final sweep
- Before calling T4's original audit inventory done, swept scripts/+tools/ once more
  for tw/th/cos/sin combined with *0.5/*2.0. Found one real remaining site:
  impact_fx.gd's splat/smear ring ("SMOUHA" block) used
  Vector2(cos(a)*rx, sin(a)*rx*0.5) — the same ground_dir_to_screen(a)*rx identity as
  everywhere else, just with the radius folded into the literal, which is why neither
  the T3 audit's grep nor part 3's verification workflow caught it (different literal
  shape than dir.y*0.5). Migrated it.
- Everything else the sweep found was correctly out of scope: TileSet tile_size
  configuration (not a coordinate conversion), the already-declined
  _build_terrace_blocks() art-anchor line (T4 part 3 reasoned through this explicitly —
  reads a fixed tile_h/2 fraction for texture alignment, not a diamond), unrelated
  blink/bob animation math, a line inside confirmed-dead WallShadow code, and
  PixelDraw.ellipse()'s own generic rx/ry parameters (squash supplied by callers).
- Verified: full verify.sh unchanged; a real screenshot (_shot_splat.tscn, built
  specifically for this effect) shows all four splat stages still rendering as
  properly flattened 2:1 ellipses.
- verify.sh: PASS (14 pass, 0 fail, 0 skip, 8 known-broken).
- Commit: 919ab97
- **T4's audit-derived inventory (~42 sites) is now fully migrated through
  GridProjection**, except the confirmed-dead code cataloged in part 3 — deliberately
  left for S9 (docs/refactor/SYSTEMS.MD) to decide fix-vs-delete, since it has zero
  call sites and migrating its formulas would add verification risk for no behavioral
  benefit. T4's own "hotovo když" also requires T2's tests to stay green throughout,
  which they have at every step (_test_economy_characterization + every other
  previously-passing fixture, checked after every single commit in this migration).

## 2026-08-29 — T5: GridProjection.MODE_SQUARE added; switch-over blocked
- Before starting, checked for a docs/core conflict (T5 switches away from isometric,
  and CLAUDE.md says to flag rather than guess if a task conflicts with docs/core).
  None found: docs/core/16_isometric_slice.md itself says "Status: PLAN, not
  built... Not a migration", and CLAUDE.md already anticipates this exact switch (the
  `_test_legacy_iso_*` rename rule, "Nová čtvercová projekce dostane vlastní
  fixtures"). Two non-core docs (docs/art_style.md, docs/game_design.md) still say
  isometric is live — just stale, not something to act on.
- Implemented the half of T5 with no visual-judgment content: GridProjection now has
  MODE_ISO (still the live default) and MODE_SQUARE, switched via set_mode(), which
  keeps GROUND_Y_SCALE in sync (2.0/1.0). cell_center()/world_to_cell()/board_bounds()/
  screen_dir_to_grid_axes() branch per mode; to_ground()/to_screen()/ground_distance()/
  ground_dir_to_screen() needed zero changes — already pure functions of
  GROUND_Y_SCALE, so they're correct for both modes automatically. layer_origin()/
  diamond_corners()/cell_diamond() stay iso-only — no square wall/terrace visual has
  been designed yet, so there's nothing correct to write there.
- Added _test_square_projection.gd/.tscn per CLAUDE.md's own instruction — 18 checks,
  all pass, self-contained (switches into MODE_SQUARE and back to MODE_ISO around
  itself, confirmed not to affect any other fixture).
- **Stopped before**: flipping active_mode live, and the project.godot resolution
  change (1920x1080 -> 480x270, integer scaling, Nearest filter) — both are genuine
  visual-design decisions (CLAUDE.md's own autonomous rule: stop on tasks requiring
  visual judgment), not engineering ones. Data.GRID is authored specifically for
  1920x1080 (origin_x=960 is literally half of it); flipping the switch today would
  render a visibly broken board, not a top-down one, and nothing in verify.sh would
  catch that since no test asserts what the board should look like. Full reasoning,
  the docs findings, and three options logged to BLOCKED.md.
- verify.sh: PASS (15 pass, 0 fail, 0 skip, 8 known-broken) — the live game is
  byte-for-byte unaffected by this commit; active_mode defaults to MODE_ISO and
  nothing in the running game calls set_mode(MODE_SQUARE).
- Commit: 684f14a

## 2026-08-29 — T9: path metrics extracted into scripts/path_metrics.gd
- T5's chain (T6/T7/T8) is stalled on the blocked visual-design decisions, but T9's own
  text says "Nezávisí na renderu" (doesn't depend on rendering) — confirmed genuinely
  unblocked, so continued here instead of idling.
- Researched first: found at least 5 independent reimplementations of "is there a
  path / how long is it" (tools/map_editor.gd's hand-rolled BFS + traffic/detour-factor
  analysis at _analyze(); scripts/_test_levels.gd's inline connectivity loop over
  astar.get_id_path; one-line wrapper duplicates in _test_sink.gd, _test_trod.gd,
  _test_iso_math.gd) — and confirmed NOTHING anywhere computes real-world path length;
  every existing "length" check measures Array.size() (step count), not distance.
  Also confirmed tools/map_editor.gd's _bake_to_level() does NOT check connectivity at
  all today — a level can be baked with an unreachable spawn zone; only _test_levels.gd
  would ever catch it. That gap is T10's to close, not T9's, but worth having found.
- Added scripts/path_metrics.gd (class_name PathMetrics, mirrors GridProjection's
  shape): is_contiguous(), path_length() (real distance, not cell count),
  distance_along()/position_at_distance() (T9's "position at distance X" query,
  clamped to the path ends, linearly interpolated), shortest_path()/is_reachable()
  (unweighted 4-connectivity BFS over an arbitrary solid-cell set — no Game, no
  AStarGrid2D reference needed).
- Deliberately did NOT touch game.gd's live weighted AStarGrid2D routing (genuinely
  different question — honors path_off_lane_cost, tightly coupled to live repathing)
  or migrate the 5 existing duplicate implementations onto the new module in this same
  change (map_editor.gd's BFS is the most promising future consolidation, since it's
  already unweighted like this one — but that's a real behavior-surface change to the
  level editor worth its own pass, paced the same way T4/T5 split large changes).
- _test_path_metrics.gd/.tscn: 37 checks (T9 asks for 20+), including the three named
  degenerate cases explicitly: length-1 path, a path doubling back over itself, and a
  small maze with a dead-end branch that must not fool shortest_path.
- verify.sh: PASS (15 pass, 0 fail, 9 known-broken — _test_phase3's established
  flakiness triggered this run, unrelated).
- Commit: 865eea3

## 2026-08-29 — T10: render-independent maze-validity validator
- Researched the mechanic before writing anything: "hráč nemůže cestu úplně zazdít"
  reads like it could describe a live player action. Confirmed it doesn't — grepped
  every astar.set_point_solid() call site; only Game._build_field() (authored
  high_ground, once, at load) and the sinking-walls spike (which only ever REMOVES
  solid cells, per docs/core/17_living_map.md). No live action ever adds a new solid
  cell, so this is already structurally guaranteed; the real risk is an AUTHORED
  high_ground layout sealing a spawn zone at design time, which is what got built.
- Also confirmed: tools/map_editor.gd's _analyze() already computes this exact
  "unreachable spawn cells" question as an advisory-only BLOCKER row, but
  _bake_to_level() never gates on it — a level can be saved broken today, and only
  _test_levels.gd's live smoke test would ever catch it.
- Added scripts/level_validator.gd (class_name LevelValidator, built on T9's
  PathMetrics): unreachable_spawn_cells(level) mirrors Game._build_field()'s own
  spawn-cell filter exactly, is_fully_reachable() is the boolean form. No Game
  instantiation needed — this is the render-independent version of what
  _test_levels.gd already checks live.
- Deliberately did NOT wire LevelValidator into map_editor.gd's _bake_to_level() to
  make it a hard save-time gate — that changes live editor behavior the user actively
  works in, a bigger decision than "add a validator" alone. Flagging as a real,
  identified follow-up rather than doing it here.
- _test_maze_validity.gd/.tscn: validates every level in data/levels/, reusing the
  same KNOWN_BROKEN entries as _test_levels.gd (level_1/level_2, same root cause since
  T0); both playable levels (98, 99) pass. Also proves the validator isn't a rubber
  stamp: a synthetic level with a high_ground ring fully sealing a spawn cell is
  correctly flagged, and opening exactly one gap in that ring is correctly detected
  as fixed.
- verify.sh: PASS (16 pass, 0 fail, 9 known-broken).
- Commit: 82c67b3

## 2026-08-29 — S8: save/load round-trip — found and fixed two real bugs, one real incident
- Researched the mechanic first: S8's own text names "built towers, Tolerance,
  dopamine, wave progress" as what must round-trip. Confirmed none of that is ever
  persisted anywhere — SaveGame/MetaProgression is 100% cross-run meta-progression
  (Insight, Growth Tree, unlocked levels/stars). No mid-run save/resume feature exists
  to test. Tested SaveGame itself instead — real, existing, never tested before today.
- **Found two real, compounding bugs in SaveGame.load_save()**: (1) ResourceLoader's
  default cache mode returns whatever was cached for a path the first time anything
  loaded it in-process, ignoring later writes entirely. (2) CACHE_MODE_REPLACE looks
  like the fix but isn't — verified via get_instance_id() that it returns the SAME
  object instance every time and only overwrites fields the file explicitly mentions;
  ResourceSaver omits any @export field equal to its script default, so a field going
  from non-default back to default between saves keeps its stale prior value under
  REPLACE, silently. CACHE_MODE_IGNORE is the actual fix (verified: genuinely fresh
  instance each time). Both bugs are invisible in real play (one load_save() call per
  process launch) but are exactly what save-then-reload-within-a-run does.
- **Real incident, twice, while investigating**: my property-based test round-tripped
  through the REAL user://savegame.tres directly at first. A naive backup/restore step
  (existence-check only, not content) reported success while the file was actually
  left corrupted — traced to a SEPARATE, pre-existing bug in my own earlier
  _test_economy_characterization.gd (T2): it swaps MetaProgression.current_save for a
  blank object for perk isolation, documented at the time as "never written to disk"
  — wrong. game.do_quick_hit() calls Hints.show_hint("quick_hit") ->
  MetaProgression.mark_hint_seen() -> current_save.write_savegame() the first time
  that hint fires, landing on the REAL save path while current_save was the swapped
  blank object. Restoring the in-memory reference afterward did nothing for what had
  already hit disk. This overwrote my real save (Insight, Growth Tree, level stars)
  down to just a couple of hint ids, twice, before being traced to this file. Both
  times fully recovered — the original content happened to still be visible verbatim
  earlier in this session's own conversation history, and was independently confirmed
  field-by-field via SaveGame's own loader afterward.
- **Fixed both**: scripts/save_game.gd now uses CACHE_MODE_IGNORE.
  _test_economy_characterization.gd now backs up the real save file's raw BYTES in
  _ready() (before anything runs) and restores them unconditionally on every exit path
  (normal completion and watchdog timeout) — confirmed via checksum, not just
  existence, that this harness's own run leaves the real file byte-identical.
- **Checked for the same exposure elsewhere**: grepped every show_hint() call site in
  game.gd (first_build, first_aim, first_lean, no_routine, boss_shield, quick_hit,
  first_draft) against every current _test_*.gd. Only my own T2 harness calls
  do_quick_hit(); the one other live risk (first_lean) is only reachable through the
  real wave-start method, which _test_phase7.gd's lean_wave coverage bypasses by
  setting the GameState flag directly. No other current test is exposed.
- **Residual risk, not fixed here, worth knowing**: this is a general class of danger
  — ANY future test that instantiates Game.tscn, triggers a not-yet-seen hint (most
  directly do_quick_hit(), or a real lean-wave/boss-shield/draft/build/aim/no-Routine
  moment), and either doesn't restore MetaProgression.current_save's on-disk backing
  at all, or (like the T2 bug) restores the in-memory reference without also
  restoring the disk bytes, can silently corrupt this developer's real save file
  again. A systemic fix (e.g. an environment-variable-driven override for
  SaveGame.SAVE_PATH during headless test runs, so no test can ever reach the real
  path at all) would close this permanently; not done here since it's materially
  bigger than "add a test" and touches how every future test that cares about
  MetaProgression would be written. Flagging for whoever picks up more save-related
  work next, rather than guessing at that design now.
- _test_save_round_trip.gd/.tscn: 100 migration-stable random states, all
  round-tripping cleanly with CACHE_MODE_IGNORE; never touches the real save path at
  all (a dedicated scratch path instead) — the safer design this whole investigation
  converged on.
- verify.sh: PASS (17 pass, 0 fail, 9 known-broken). Real save file confirmed
  byte-identical (md5) before and after the full suite run.
- Commits: fc9511f (the SaveGame fix + new test), 7f2c563 (the T2 harness fix)

## 2026-08-29 — S2 groundwork: two determinism bugs fixed; driver not built yet
- Researched feasibility before touching anything: no physics-engine dependency
  anywhere in combat/targeting (all manual math — good), clean directly-callable
  build/quick-hit entry points needing no faked input (good), but the research
  identified concrete non-determinism leaks that would make "same seed twice, same
  result" provably false no matter how good a driver script is.
- **Fixed**: (1) tower.gd's per-tower `_rng` (feeds actual shot trajectory via
  ArcProfile.lane_angle -> hit/miss, NOT cosmetic) was calling `randomize()` against
  OS entropy at build time — now seeded from `hash(grid position) ^
  GameState.run_seed`, preserving the original "avoid lockstep between towers" intent
  while making it reproducible when run_seed is deterministic. (2) sfx.gd's per-cue
  anti-spam throttle gated a shared-global-RNG draw behind real `Time.get_ticks_msec()`
  — under non-realtime pacing (a fixed-timestep simulator) this could silently
  skip/take an extra draw on the SAME global stream every other system reads from
  (jackpot rolls, spawn-cell picks, burnout lapses), desyncing everything after it in
  a way that would be very hard to trace back to audio code. Now gated on an internal
  simulated-time accumulator instead. Added `GameState.run_seed` (drawn fresh each
  `reset_for_level()`) as the one new piece of API — a future caller doing `seed(x)`
  before loading a level makes both of these, and the game's other shared-stream
  draws, reproducible from that single call.
- Verified behavior-preserving: full verify.sh unchanged; every KNOWN_BROKEN log
  diffed byte-identical against a pre-change snapshot (one exception, the same
  recurring timing-jitter value already seen throughout this session).
- **Not done**: the actual S2 driver, and a real design gap the research surfaced —
  the task text's "kam postavit co, kdy zmáčknout Quick Hit" undersells what a
  decision script needs to express. Wave-advance (`_on_start_wave_pressed`) has no
  automatic trigger except a specific "autoplay" distraction archetype, so a
  simulated level would stall in the build phase forever without an explicit
  wave-advance action in the script format; draft-card interstitials
  (`_on_card_picked`/`_on_draft_skip`) are a similar gap. Also unverified: whether
  Godot's `--fixed-fps` actually produces bit-identical per-frame deltas across two
  runs (needed since `_update_tolerance` and similar systems accumulate real
  `_process` delta, not simulated ticks) — a real spike, not just a code read. And a
  design note for whoever builds the driver: Tween-gated effects (interventions'
  0.22s impact delay) don't advance under a hand-rolled "call every node's _process
  myself" driver — the existing `_test_*` harnesses already have to special-case this
  (`_test_phase7.gd`'s genuine 900ms real-time wait), which argues for driving the
  simulation through the real engine loop (`--fixed-fps`) rather than reimplementing
  per-node update dispatch by hand. This is real, separately-scoped work — a fuller
  task than these two bugfixes, left for a dedicated follow-up.
- verify.sh: PASS (18 pass, 0 fail, 8 known-broken).
- Commit: 2c0b35e

## 2026-08-29 — S9: cleanup audit against CLAUDE.md's own rules (SYSTEMS.MD)
- Ran a multi-agent audit (parallel scan across scripts/ for missing type hints,
  hardcoded values vs @export, $Node/signal-bus coupling, Godot 3 idioms; adversarial
  verify pass on each proposed fix) — 54 findings, 17 confirmed mechanically safe,
  11 rejected by the audit's own verification on a scanner formatting bug (their
  "current code" field was literally the string "undefined"), 13 hardcoded-vs-@export
  judgment calls, 3 signal-bus judgment calls, 0 Godot-3 idioms (migration already
  clean).
- **Applied**: the mechanical type-hint fixes — return types (`exposed_habit() ->
  Habit`), parameter types (`DefenderUnit`, `MapEditor`, `Game`), and `=` -> `:=` on
  locals with a genuinely concrete static type — across game.gd, barracks.gd,
  enemy.gd, distraction_animator.gd, grid_projection.gd, level_validator.gd, and
  ~30 dev/test-harness scripts (`_shot_*`, `_perf_*`, `_play_*`, `_test_*`). Two of
  the audit's rejected findings (barracks.gd:108/116, enemy.gd:373) were
  independently re-verified against live source and applied too.
- **Real finding made while applying this, not by the audit**: this project's
  GDScript setup treats a variable type *inferred as Variant* as a compile ERROR,
  not a warning. Several of the audit's own "adversarially verified safe" `:=`
  conversions — mirror.gd, defender_unit.gd, projectile.gd, enemy.gd, build_spot.gd,
  barracks.gd — actually broke compilation (cascading into ~11 unrelated test
  failures on the first verify.sh run, since these are non-autoload scripts whose
  class_name registration every Game-instantiating test depends on). Extrapolating
  the same "mechanical" pattern to sibling lines myself across dev/test harnesses
  surfaced more of the same, several as a **120s hang** rather than a clean error
  (a script parse failure means the scene's `_ready()` never completes, so
  verify.sh's per-test timeout is what actually kills it — looks exactly like a
  stuck test until you read the real `.dev/<test>.log`). Four concrete failure
  shapes, all documented in docs/DEBT.md with the full file list: untyped
  Dictionary/Array indexing, `GDScript.new()`, `load(path).instantiate()` without
  an explicit type annotation, and a method call on an under-typed receiver (e.g.
  `var game: Node` instead of `Game` — the callee's own concrete return type
  doesn't help if the receiver itself is generic). Every one of these was caught by
  actually running verify.sh, not by static reasoning — the compiler is the ground
  truth here, not an agent's (or my own) semantic analysis.
- **Not applied, cataloged in docs/DEBT.md instead**: 9 of the audit's rejected
  findings (plausibly safe but not independently re-verified given the gotcha
  above — includes a 46-line bulk finding in game.gd that needs a line-by-line
  check, not a blanket pass); all 13 hardcoded-vs-@export judgment calls (Quick
  Hit, Burnout, Tolerance decay, Routine radius, aim-fatigue, sinking-walls,
  hands-off-finale, wave-bonus constants — real balance numbers with no @export
  override, but whether each should be exposed vs. deliberately uniform is a
  design call); all 3 signal-bus coupling judgment calls (one genuinely worth
  fixing — enemy.gd's disrupt-target search reaches three levels into the tower
  system's internals — two are consistent, codebase-wide idioms rather than
  isolated shortcuts).
- verify.sh: PASS (18 pass, 0 fail, 8 known-broken — matches the pre-existing
  baseline exactly).
- Commit: 88ac943

## 2026-08-29 — S2 research + one more determinism leak fixed
- Ran a 4-agent research workflow (entry points, game-over capture, a fresh
  determinism audit, harness conventions) to design S2's driver, plus two empirical
  spikes (see below) to settle the two open questions the earlier S2-groundwork entry
  flagged as needing "a real spike, not just a code read."
- **Spike 1 (positive)**: `godot --headless --fixed-fps 60` gives a byte-identical
  `_process(delta)` value (exactly 1/60) across two independent runs of a 300-frame
  harness. All gameplay-critical logic (tower.gd, enemy.gd, defender_unit.gd,
  projectile.gd, game.gd) runs on `_process`, not `_physics_process`, so this settles
  the timestep question for the driver.
- **Spike 2 (positive, the bigger risk)**: research flagged that `create_tween()`
  Tweens advance via the engine's own per-frame delta with no dt-hook a caller can
  invoke directly — existing `_test_*.gd` harnesses fall back to real-time-bounded
  polling loops (`Time.get_ticks_msec()` / `create_timer().timeout`) for exactly this
  reason (_test_phase7.gd's airplane_mode sky-strike wait). Built a second spike: a
  0.5s `tween_property` under `--fixed-fps 60`, two runs. Its `finished` signal fired
  at the identical frame (31) with byte-identical intermediate values both times.
  Tweens ARE governed by the same deterministic engine delta `--fixed-fps` controls —
  the driver can advance Tween-gated effects with plain frame-counting, no wall-clock
  waits needed. Both spikes were one-off harnesses, deleted after use per CLAUDE.md.
- **One more real bug found and fixed**: the determinism audit found `sfx.gd`'s
  `play_defeat()` (called on every enemy kill) had the identical wall-clock-vs-
  `_sim_ms` bug already fixed in `play()` during the earlier S2-groundwork pass, left
  unpatched. Fixed the same way. Also flipped verify.sh's `ROSTER_KNOWN_STALE` flag
  off (roster caught up during the S9 commit). verify.sh: 19 pass, 0 fail, 7
  known-broken. Commit: f48775c.
- **Research complete, driver not yet built**: full entry-point tracing for all five
  decision-script actions (build/aim/quick-hit/start-wave/draft), the game-over signal
  capture pattern (existing harnesses disconnect `game._on_bus_game_over` right after
  `add_child(game)` to survive the destructive `change_scene_to_file()` teardown), and
  harness conventions are all documented in this session's research (not yet written
  to a permanent doc). The one real unresolved design gap: card-draft detection/option
  discovery has no public API at all — `_show_draft_screen()`'s rolled hand is a
  throwaway local variable, never stored on the Game instance, only recoverable by
  reflecting into each Buy button's bound Callable via `Signal.get_connections()`, or
  by adding a small non-behavioral field to expose it. This is a real design decision,
  not a mechanical one — surfaced for a judgment call before the driver is built
  rather than picked unilaterally.
