#!/usr/bin/env bash
# verify.sh — full regression gate for the autonomous run loop (run.sh).
# Runs every _test_*.tscn fixture, not just the one relevant to the current
# task, since an unattended agent can't judge "relevant" for itself.
set -uo pipefail

if [ -z "${GODOT:-}" ]; then
  echo "FAIL: \$GODOT is not set." >&2
  echo "  Export it to the console build, e.g.:" >&2
  echo '  export GODOT="/c/Users/reath/Downloads/Godot_v4.7.1-stable_win64.exe/Godot_v4.7.1-stable_win64_console.exe"' >&2
  exit 1
fi

if [ ! -f "$GODOT" ]; then
  echo "FAIL: \$GODOT does not point to an existing file: $GODOT" >&2
  exit 1
fi

TIMEOUT_S=120
LOG_DIR=".dev"
mkdir -p "$LOG_DIR"

# Known-broken debt (see PROGRESS.md / BLOCKED.md for how each one was found).
# Pre-existing failures don't block the "verify.sh must pass" gate for
# unrelated tasks — otherwise the very first autonomous task would be stuck
# forever. Mirrors _test_levels.gd's own KNOWN_BROKEN convention: visible,
# not silent, and meant to shrink to empty. Remove an entry the moment its
# test is fixed for real; if a task's own scope covers one of these, fix it
# and remove it as part of that task's commit.
#
# A test in this list is EXPECTED TO FAIL. Failing costs nothing; PASSING is a FAIL, with
# a message saying to remove the entry (P0f). That asymmetry is the whole point: a
# baseline that only ever suppresses failures rots into a list nobody prunes, and a
# fixture that quietly started working again is indistinguishable from one still broken.
#
# One-line causes only -- the full inventory, with the exact failing assertion, the class
# and the first red commit for each, is docs/KNOWN_BROKEN.md (P0e). Three of the causes
# that used to be spelled out here were WRONG, which is why they now live in one place
# that was actually checked instead of being paraphrased at the call site.
KNOWN_BROKEN_TESTS=(
  # head_aims is false in all four habits' .tres; the test still demands true. A data
  # change nobody reflected in the test that pins it. First red: 0465a23.
  _test_deep_reading
  # Arc width has no effect on lighting at all (15 deg -> 120 deg lights the same 36
  # cells) and rotation moves the lit set asymmetrically. Real. First red: 26814f9.
  _test_fog_bandwidth
  # assets/towers/head_zen_pulsar_frame_1..8.png are gone; head_zen_pulsar.png survives.
  # A genuinely missing file, not an expectation. First red: 0465a23.
  _test_zen_pulsar
)

# Fixtures that read back rendered pixels (get_viewport().get_texture().get_image()).
# --headless installs the dummy renderer, which has no pixels to read back, so these
# don't fail so much as crash on a null texture -- SKIPPED (not KNOWN-BROKEN, not run at
# all) unless $DISPLAY or VERIFY_WITH_DISPLAY=1 is set, in which case they run WITHOUT
# --headless, for real. This only gates whether a test can be ATTEMPTED; whether its
# result then counts against the gate once it runs is still KNOWN_BROKEN_TESTS/
# FLAKY_TESTS' job, same as any other fixture -- the two lists compose.
# _test_shadow_occlusion stays here after being FIXED and removed from KNOWN_BROKEN_TESTS
# (2026-09-02): needing a real renderer is a permanent property of what it measures (it
# reads back GPU-rendered pixels to prove a LightOccluder2D really blocks a Light2D), not
# a defect that got fixed. The two lists are independent -- this one says "can this be
# attempted", the one above says "does its result gate the build".
REQUIRES_DISPLAY_TESTS=(
  _test_shadow_occlusion
)
_is_requires_display() {
  local candidate="$1"
  local entry
  for entry in "${REQUIRES_DISPLAY_TESTS[@]}"; do
    [ "$entry" = "$candidate" ] && return 0
  done
  return 1
}
_has_display() {
  [ -n "${DISPLAY:-}" ] || [ "${VERIFY_WITH_DISPLAY:-}" = "1" ]
}

# Tests that are neither reliably green nor reliably red go here. A separate list,
# because the known-broken rules above would be wrong in BOTH directions for them: a
# flaky test that passes is not "fixed", and one that fails is not news.
#
# An entry here is a BUG TO FIX, not a permanent exemption; it just cannot be gated on.
# Empty as of 2026-08-30: _test_phase3, the entry that motivated this list, was fixed
# under CLAUDE.md's narrow flaky-test exception -- see docs/KNOWN_BROKEN.md and
# PROGRESS.md's own entry for why the fix qualified and the 20/20 clean-run proof.
FLAKY_TESTS=()
ROSTER_KNOWN_STALE=0

# Tests that need process-launch-time flags Godot only accepts as CLI args (no
# runtime-settable equivalent from GDScript) — --fixed-fps is one: S2's
# LevelSimulator determinism proof needs the engine's per-frame delta (and every
# create_tween() the game uses) to be a bit-identical synthetic constant across runs,
# which only --fixed-fps guarantees (Engine.time_scale still scales a REAL measured
# delta, so it would not give byte-identical reproduction). Runs several full level
# playthroughs back to back, so it also gets a longer per-test timeout.
FIXED_FPS_TESTS=(
  _test_level_simulator
  _test_timecontrol
  _test_multispawn
  _test_segments
)
_needs_fixed_fps() {
  local candidate="$1"
  local entry
  for entry in "${FIXED_FPS_TESTS[@]}"; do
    [ "$entry" = "$candidate" ] && return 0
  done
  return 1
}

echo "== import =="
"$GODOT" --headless --path . --import
import_status=$?
if [ "$import_status" -ne 0 ]; then
  echo "FAIL: project import (exit $import_status)"
  exit 1
fi
# --quit / --quit-after 1 do not perform a real import (Godot issue #77508) —
# the bare --import above is required and is allowed to exit on its own.

pass=0
fail=0
skip=0
known=0
flaky=0
nodisplay=0
failed_names=()

_is_known_broken() {
  local candidate="$1"
  local entry
  for entry in "${KNOWN_BROKEN_TESTS[@]}"; do
    [ "$entry" = "$candidate" ] && return 0
  done
  return 1
}

_is_flaky() {
  local candidate="$1"
  local entry
  for entry in "${FLAKY_TESTS[@]}"; do
    [ "$entry" = "$candidate" ] && return 0
  done
  return 1
}

shopt -s nullglob
echo "== orphan test scripts =="
# Every scripts/_test_*.gd needs the scenes/_test_*.tscn that runs it. The loop above
# iterates over SCENES, so a script without one is never executed: it looks like a fixture
# in any file listing, reports nothing, and inflates the apparent coverage. A test that
# verifies nothing while looking like one is worse than no test at all, so this is a FAIL
# and not a note.
#
# Found 2026-08-30 (P0d): _test_iso_math.gd and _test_game_iso_slice.gd had sat in
# scripts/ since the iso pilot (405df22) with no scene EVER committed for either -- both
# were `extends SceneTree` harnesses for --script, the mode CLAUDE.md's verification
# pattern forbids. They were deleted; this check is what stops the next pair from lasting
# as long.
orphan_scripts=()
for script in scripts/_test_*.gd; do
  base=$(basename "$script" .gd)
  if [ ! -f "scenes/$base.tscn" ]; then
    orphan_scripts+=("$script")
  fi
done
if [ ${#orphan_scripts[@]} -ne 0 ]; then
  echo "FAIL orphan test scripts (${#orphan_scripts[@]}) - each needs scenes/<name>.tscn, or delete it (with its .gd.uid):"
  for o in "${orphan_scripts[@]}"; do
    echo "  - $o"
  done
  fail=$((fail + 1))
  failed_names+=("orphan test scripts")
else
  echo "PASS orphan test scripts"
  pass=$((pass + 1))
fi

echo "== orphan test scenes =="
# The opposite direction of the check above. The main loop below iterates SCENES, not
# scripts -- a scenes/_test_*.tscn whose scripts/<name>.gd does not exist still gets
# picked up, runs as an empty scene with no assertions, and exits 0 immediately. That is
# a silent false PASS: it inflates the pass count and looks identical to real coverage
# in the summary, which is worse than the orphan-script case above (that one at least
# never runs at all).
orphan_scenes=()
for scene in scenes/_test_*.tscn; do
  base=$(basename "$scene" .tscn)
  case "$base" in
    _test_legacy_*) continue ;;  # deliberately parked, see the dead-clause note below
  esac
  if [ ! -f "scripts/$base.gd" ]; then
    orphan_scenes+=("$scene")
  fi
done
if [ ${#orphan_scenes[@]} -ne 0 ]; then
  echo "FAIL orphan test scenes (${#orphan_scenes[@]}) - each needs scripts/<name>.gd, or delete the scene:"
  for o in "${orphan_scenes[@]}"; do
    echo "  - $o"
  done
  fail=$((fail + 1))
  failed_names+=("orphan test scenes")
else
  echo "PASS orphan test scenes"
  pass=$((pass + 1))
fi

echo "== fixed-fps roster sanity =="
# A name in FIXED_FPS_TESTS with no matching scene is not necessarily wrong --
# _test_multispawn and _test_segments are pre-staged for P6/P8 and that is fine, the
# list is allowed to lead the scene it names. But a typo here would silently mean the
# real fixture (once it exists) never gets --fixed-fps and either hangs or gives up its
# determinism guarantee without a word about why -- so this warns, and only warns; it
# must never fail, since a pre-staged entry is an expected, permanent state, not debt.
for fixed_fps_name in "${FIXED_FPS_TESTS[@]}"; do
  if [ ! -f "scenes/$fixed_fps_name.tscn" ]; then
    echo "WARN FIXED_FPS_TESTS lists '$fixed_fps_name' but scenes/$fixed_fps_name.tscn does not exist yet -- pre-staged, or a typo?"
  fi
done

for scene in scenes/_test_*.tscn; do
  name=$(basename "$scene" .tscn)
  # DEAD CLAUSE ON PURPOSE (P0d, 2026-08-30). Nothing in scenes/ is named
  # _test_legacy_* today and `skip` has been 0 in every run since the square migration.
  # It was written for a rename that never happened -- the two iso harnesses it was meant
  # to catch turned out to have no .tscn at all and were deleted rather than renamed, see
  # CLAUDE.md. Kept anyway: it costs one glob test per scene and it is the agreed way to
  # park a fixture whose subject a migration has retired, which P8's segment work may yet
  # need. If you find it still matching nothing years from now, that is not a bug.
  case "$name" in
    _test_legacy_*)
      echo "SKIP $name"
      skip=$((skip + 1))
      continue
      ;;
  esac

  if _is_requires_display "$name" && ! _has_display; then
    echo "SKIP-NO-DISPLAY $name — needs a real renderer (GPU pixel readback via --headless's dummy renderer returns null); set DISPLAY or VERIFY_WITH_DISPLAY=1 to run it"
    nodisplay=$((nodisplay + 1))
    continue
  fi

  log="$LOG_DIR/$name.log"
  echo "== $name =="
  extra_args=()
  test_timeout="$TIMEOUT_S"
  if _needs_fixed_fps "$name"; then
    extra_args=(--fixed-fps 60)
    test_timeout=520
  fi
  # _is_requires_display implies _has_display here (the no-display case already
  # `continue`d above), so this is the one and only place --headless is dropped.
  godot_args=(--path . --main-scene "res://$scene")
  if ! _is_requires_display "$name"; then
    godot_args=(--headless "${godot_args[@]}")
  fi
  timeout "$test_timeout" "$GODOT" "${godot_args[@]}" \
    "${extra_args[@]}" >"$log" 2>&1
  status=$?

  if [ "$status" -eq 124 ]; then
    # A timeout is never baselined — known-broken, flaky or neither. A hang is always
    # news, and a hung test proves nothing about the assertion it was baselined for.
    echo "FAIL $name (timeout after ${test_timeout}s) — see $log"
    fail=$((fail + 1))
    failed_names+=("$name (timeout)")
  elif _is_flaky "$name"; then
    # Both outcomes are expected, so neither is reported as a pass or a fail. Counted on
    # its own line so the summary stays IDENTICAL run to run and a real change stands out.
    if [ "$status" -eq 0 ]; then
      echo "FLAKY-PASS $name — known-flaky, not gated either way — docs/KNOWN_BROKEN.md"
    else
      echo "FLAKY-FAIL $name (exit $status) — known-flaky, not gated either way — $log"
    fi
    flaky=$((flaky + 1))
  elif [ "$status" -ne 0 ]; then
    if _is_known_broken "$name"; then
      echo "KNOWN-BROKEN $name (exit $status) — pre-existing, see docs/KNOWN_BROKEN.md — $log"
      known=$((known + 1))
    else
      echo "FAIL $name (exit $status) — see $log"
      fail=$((fail + 1))
      failed_names+=("$name (exit $status)")
    fi
  else
    if _is_known_broken "$name"; then
      # A baselined test that passes is a FAIL on purpose. It is the only moment the list
      # can be pruned honestly, and letting it slide as a PASS is how a stale baseline
      # goes on suppressing a real regression months later.
      echo "FAIL $name fixed itself — remove it from KNOWN_BROKEN_TESTS in verify.sh"
      echo "  (and drop its entry from docs/KNOWN_BROKEN.md in the same commit)"
      fail=$((fail + 1))
      failed_names+=("$name (fixed itself — remove from KNOWN_BROKEN_TESTS)")
    else
      echo "PASS $name"
      pass=$((pass + 1))
    fi
  fi
done

echo "== roster regex =="
# Runs BEFORE the roster generation below, on purpose: if roster.py's .tres reading is
# broken, the generated ROSTER.md is confidently wrong rather than absent, and comparing
# it against the tracked copy proves nothing. This checks the reader against a fixture
# (tools/_fixtures/, .gdignore'd so it can never become game content) that carries both
# ext_resource spellings Godot emits — with and without uid= between type= and path=.
regex_log="$LOG_DIR/roster_regex.log"
PYTHONIOENCODING=utf-8 python tools/test_roster.py >"$regex_log" 2>&1
regex_status=$?
if [ "$regex_status" -ne 0 ]; then
  echo "FAIL roster regex (exit $regex_status) — see $regex_log"
  grep "FAIL" "$regex_log" | sed 's/^/  /'
  fail=$((fail + 1))
  failed_names+=("roster regex")
else
  echo "PASS roster regex"
  pass=$((pass + 1))
fi

echo "== roster =="
roster_tmp="$LOG_DIR/ROSTER.md.generated"
# PYTHONIOENCODING: on this machine python's stdout defaults to the legacy
# Windows cp1250 codepage even when redirected to a file, which crashes on
# roster.py's arrow characters. Force UTF-8 so generation itself can't fail
# on encoding, independent of whether the content is stale.
PYTHONIOENCODING=utf-8 python tools/roster.py --md >"$roster_tmp"
roster_status=$?
if [ "$roster_status" -ne 0 ]; then
  echo "FAIL roster (tools/roster.py exited $roster_status, docs/ROSTER.md left untouched) — see $roster_tmp"
  fail=$((fail + 1))
  failed_names+=("roster (generator crashed)")
else
  # Never redirect roster.py's output straight onto the tracked file: a crash
  # mid-write would truncate it in place. Compare the generated copy first,
  # and only overwrite docs/ROSTER.md once generation has actually succeeded.
  cp "$roster_tmp" docs/ROSTER.md
  if git diff --quiet HEAD -- docs/ROSTER.md; then
    if [ "$ROSTER_KNOWN_STALE" = "1" ]; then
      echo "PASS roster (was KNOWN-STALE — remove ROSTER_KNOWN_STALE from verify.sh)"
    else
      echo "PASS roster"
    fi
    pass=$((pass + 1))
  elif [ "$ROSTER_KNOWN_STALE" = "1" ]; then
    echo "KNOWN-STALE roster (pre-existing content drift, see PROGRESS.md)"
    git diff --stat HEAD -- docs/ROSTER.md
    known=$((known + 1))
  else
    echo "FAIL roster (docs/ROSTER.md was stale — regenerated; review and commit the diff below)"
    git diff --stat HEAD -- docs/ROSTER.md
    fail=$((fail + 1))
    failed_names+=("roster")
  fi
fi

echo "== level side-cars =="
# docs/levels/<id>.md is a DERIVED, read-only rendering of each level's geometry
# (docs/refactor/PATHFINDING.MD P0b). The .tres stays authoritative and the game never
# loads the side-car, which is exactly why it needs a gate: a derived document that
# nothing checks goes stale silently and then lies in a diff. Same class of check as the
# roster above -- regenerate from the source and compare -- except --check never writes,
# so a verification run cannot quietly "fix" the thing it is verifying.
sidecar_log="$LOG_DIR/level_sidecars.log"
PYTHONIOENCODING=utf-8 python tools/level_to_ascii.py --check >"$sidecar_log" 2>&1
sidecar_status=$?
if [ "$sidecar_status" -ne 0 ]; then
  echo "FAIL level side-cars (exit $sidecar_status) - see $sidecar_log"
  grep "FAIL" "$sidecar_log" | sed 's/^/  /'
  fail=$((fail + 1))
  failed_names+=("level side-cars")
else
  echo "PASS level side-cars"
  pass=$((pass + 1))
fi

echo "== terrain contrast =="
# Since 2026-08-29 the terrain is not generated — tools/flat_terrain.py installs flat
# colours for 0 generations. That removed the generation round in which the path-vs-tissue
# contrast used to get measured, so STYLE_BIBLE.md §4's gates would have decayed into prose
# nobody checks. This re-measures them: thresholds read from the bible, values read from
# flat_terrain.py, no local copy of either. The whole board's legibility under Brain Fog
# rests on that one luminance difference.
terrain_log="$LOG_DIR/terrain_contrast.log"
PYTHONIOENCODING=utf-8 python tools/check_terrain_contrast.py >"$terrain_log" 2>&1
terrain_status=$?
if [ "$terrain_status" -ne 0 ]; then
  echo "FAIL terrain contrast (exit $terrain_status) — see $terrain_log"
  grep "FAIL" "$terrain_log" | sed 's/^/  /'
  fail=$((fail + 1))
  failed_names+=("terrain contrast")
else
  echo "PASS terrain contrast"
  pass=$((pass + 1))
fi

echo "== art prompts =="
# Same shape as the roster check above and for the same reason: docs/art/GENERATION_PLAN.md
# is generated from docs/art/STYLE_BIBLE.md + data/, so it goes stale silently the moment
# anyone adds a .tres or edits a prompt rule. scenes/_test_art_prompts.tscn (run in the
# loop above) checks that the plan is INTERNALLY correct; this checks that it is CURRENT,
# and that the generator is deterministic — two runs must be byte-identical, or --check
# itself would be meaningless. PYTHONIOENCODING for the same cp1250 reason as roster.py.
art_log="$LOG_DIR/art_prompts.log"
PYTHONIOENCODING=utf-8 python tools/gen_art_prompts.py --check >"$art_log" 2>&1
art_status=$?
if [ "$art_status" -ne 0 ]; then
  echo "FAIL art prompts (exit $art_status) — see $art_log"
  sed 's/^/  /' "$art_log"
  fail=$((fail + 1))
  failed_names+=("art prompts")
else
  echo "PASS art prompts"
  pass=$((pass + 1))
fi

echo "== art colors =="
# Doomscroll shipped amber/brown while its own .tres and STYLE_BIBLE.md both say green
# (found in live-gameplay review, 31.8.2026) — the art-on-disk-wins rule in
# distraction_animator.gd means `.tres` `color` only drives the glow halo, never the body
# pixels, so shipped art can drift from what the data/bible claim and nothing re-derives
# one from the other. This measures the shipped PNG's actual dominant hue for every
# distraction/defender/habit with real art and compares it against both. Known mismatches
# are logged in docs/art/ART_DEBT.md, which the script treats as its own allowlist (same
# "single source of truth" shape as the roster/terrain-contrast checks above) — only a
# NEW, undocumented mismatch fails the build.
art_colors_log="$LOG_DIR/art_colors.log"
PYTHONIOENCODING=utf-8 python tools/check_art_colors.py >"$art_colors_log" 2>&1
art_colors_status=$?
if [ "$art_colors_status" -ne 0 ]; then
  echo "FAIL art colors (exit $art_colors_status) — see $art_colors_log"
  grep "FAIL" "$art_colors_log" | sed 's/^/  /'
  fail=$((fail + 1))
  failed_names+=("art colors")
else
  echo "PASS art colors"
  pass=$((pass + 1))
fi

echo "== style failure modes =="
# STYLE_BIBLE.md §12d: three of direction A's six failure-mode tests (silhouette
# compactness, "five styles" colour-count cohesion, horde legibility) are measurable on
# PNGs instead of judged from a screenshot. Gates only files listed in the bible's
# <!-- gen:direction_a --> table (§12e) -- that table is EMPTY today (no direction-A
# master exists yet, §12f is still waiting on user approval), so a correct run gates
# ZERO files and says so explicitly. The whole current roster (every habit head, every
# distraction frame) predates direction A and would fail these gates by construction --
# gating it would leave verify.sh red until phase 1 finishes and stop it guarding
# anything else, so it is measured and printed as LEGACY instead, same convention as
# KNOWN_BROKEN_TESTS above and the allowlist in docs/art/ART_DEBT.md.
style_fm_log="$LOG_DIR/style_failure_modes.log"
PYTHONIOENCODING=utf-8 python tools/check_style_failure_modes.py >"$style_fm_log" 2>&1
style_fm_status=$?
if [ "$style_fm_status" -ne 0 ]; then
  echo "FAIL style failure modes (exit $style_fm_status) — see $style_fm_log"
  grep "FAIL" "$style_fm_log" | sed 's/^/  /'
  fail=$((fail + 1))
  failed_names+=("style failure modes")
else
  echo "PASS style failure modes"
  pass=$((pass + 1))
fi

echo
echo "== summary =="
echo "pass: $pass  fail: $fail  skip: $skip  known-broken: $known  flaky: $flaky  no-display: $nodisplay"
if [ "$fail" -ne 0 ]; then
  echo "failed:"
  for n in "${failed_names[@]}"; do
    echo "  - $n"
  done
  exit 1
fi
exit 0
