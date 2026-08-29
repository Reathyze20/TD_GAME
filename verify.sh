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
)
ROSTER_KNOWN_STALE=1

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
  timeout "$TIMEOUT_S" "$GODOT" --headless --path . --main-scene "res://$scene" >"$log" 2>&1
  status=$?

  if [ "$status" -eq 124 ]; then
    # A timeout is never baselined, known-broken or not — a hang is always news.
    echo "FAIL $name (timeout after ${TIMEOUT_S}s) — see $log"
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
