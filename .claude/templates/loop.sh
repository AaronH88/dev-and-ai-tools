#!/usr/bin/env bash

while true; do
  tools/run-claude-sandbox.sh --task-file tasks/RUN.md </dev/null || true

  STATUS=$(cat tasks/BUILD_STATUS.md | tr -d '[:space:]')

  if [ "$STATUS" = "APPROVED" ]; then
    echo "✓ Build approved by final judge."
    break
  fi

  if [[ "$STATUS" == FAILED* ]]; then
    echo "✗ Final judge failed — see tasks/feedback/final-judge.md"
    break
  fi

  NEXT=$(grep "→ NEXT:" tasks/TASK_LIST.md | head -1)
  echo "Next: $NEXT"
done