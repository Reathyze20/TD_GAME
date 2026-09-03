#!/usr/bin/env bash
set -uo pipefail
: "${GODOT:?nastav GODOT}"

last=""
while :; do
  INFO=$(python tools/next_task.py PATHFINDING.MD) || { echo "fronta hotová"; break; }
  IFS='|' read -r TASK MODEL NEEDS <<< "$INFO"
  if [ "$NEEDS" = "yes" ]; then
    echo "STOP na $TASK (Needs-me: yes) — čeká na tebe"
    break
  fi
  if [ "$TASK" = "$last" ]; then
    echo "ZACYKLENO: $TASK se nedokončil. Stop."
    break
  fi
  last="$TASK"
  ./run.sh main PATHFINDING.MD "$MODEL"
  rc=$?
  [ "$rc" -eq 2 ] && break
  [ "$rc" -eq 3 ] && break
  [ "$rc" -ne 0 ] && { echo "run.sh selhal (rc=$rc)"; break; }
done
