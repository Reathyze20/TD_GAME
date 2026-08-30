#!/usr/bin/env bash
set -uo pipefail
: "${GODOT:?nastav GODOT na cestu ke console buildu}"
BRANCH="$1"; QUEUE="$2"
mkdir -p .dev

git checkout "$BRANCH" || exit 1

INFO=$(python tools/next_task.py "$QUEUE") || { echo "Fronta $QUEUE hotová."; exit 0; }
IFS='|' read -r TASK MODEL NEEDS_ME <<< "$INFO"

if [ "$NEEDS_ME" = "yes" ]; then
  echo "STOP: $TASK vyžaduje tvoji přítomnost. Fronta $QUEUE pozastavena."
  exit 0
fi

echo ">>> $TASK  (model: $MODEL)"
claude -p "Přečti $QUEUE a PROGRESS.md. Pracuj VÝHRADNĚ na úkolu $TASK, na ničem jiném. \
Po dokončení spusť ./verify.sh, commitni, přepiš u $TASK 'Status: todo' na 'Status: done' \
a připiš řádek do PROGRESS.md. Pak skonči." \
  --model "$MODEL" \
  --permission-mode dontAsk \
  --output-format stream-json --verbose \
  --max-turns 80 --max-budget-usd 15 \
  >> ".dev/agent-${BRANCH}-${TASK}-$(date +%s).log" 2>&1

git push origin "$BRANCH"