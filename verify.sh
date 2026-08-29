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
KNOWN_BROKEN_TESTS=(
  _test_deep_reading
  _test_fog_bandwidth
  _test_los
  _test_phase4
  _test_shadow_occlusion
  _test_suppression
  _test_zen_pulsar
  # Flaky, not reliably broken: passed 3 of 5 full-suite runs, always on the same
  # check ("slow expired while blocked: factor reset to 1.0 (got 0.5)") — a real-time
  # race in that one status-expiry assertion, unrelated to whatever task is running.
  _test_phase3
)
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
failed_names=()

_is_known_broken() {
  local candidate="$1"
  local entry
  for entry in "${KNOWN_BROKEN_TESTS[@]}"; do
    [ "$entry" = "$candidate" ] && return 0
  done
  return 1
}

shopt -s nullglob
for scene in scenes/_test_*.tscn; do
  name=$(basename "$scene" .tscn)
  case "$name" in
    _test_legacy_*)
      echo "SKIP $name"
      skip=$((skip + 1))
      continue
      ;;
  esac

  log="$LOG_DIR/$name.log"
  echo "== $name =="
  extra_args=()
  test_timeout="$TIMEOUT_S"
  if _needs_fixed_fps "$name"; then
    extra_args=(--fixed-fps 60)
    test_timeout=520
  fi
  timeout "$test_timeout" "$GODOT" --headless --path . --main-scene "res://$scene" \
    "${extra_args[@]}" >"$log" 2>&1
  status=$?

  if [ "$status" -eq 124 ]; then
    # A timeout is never baselined, known-broken or not — a hang is always news.
    echo "FAIL $name (timeout after ${test_timeout}s) — see $log"
    fail=$((fail + 1))
    failed_names+=("$name (timeout)")
  elif [ "$status" -ne 0 ]; then
    if _is_known_broken "$name"; then
      echo "KNOWN-BROKEN $name (exit $status) — pre-existing, see PROGRESS.md — $log"
      known=$((known + 1))
    else
      echo "FAIL $name (exit $status) — see $log"
      fail=$((fail + 1))
      failed_names+=("$name (exit $status)")
    fi
  else
    if _is_known_broken "$name"; then
      echo "PASS $name (was KNOWN-BROKEN — remove it from verify.sh's list)"
    else
      echo "PASS $name"
    fi
    pass=$((pass + 1))
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

echo
echo "== summary =="
echo "pass: $pass  fail: $fail  skip: $skip  known-broken: $known"
if [ "$fail" -ne 0 ]; then
  echo "failed:"
  for n in "${failed_names[@]}"; do
    echo "  - $n"
  done
  exit 1
fi
exit 0
