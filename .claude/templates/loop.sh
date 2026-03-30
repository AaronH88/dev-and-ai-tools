#!/usr/bin/env bash

# Parse optional --model argument
MODEL_OVERRIDE=""
if [ "$1" = "--model" ] && [ -n "$2" ]; then
  MODEL_OVERRIDE="$2"
  echo "ℹ Model override: using $MODEL_OVERRIDE for all stages"
fi

while true; do
  # Determine which stage is next
  NEXT=$(grep "→ NEXT:" tasks/TASK_LIST.md | head -1)

  # Build command with optional model flag
  SANDBOX_CMD=(tools/run-claude-sandbox.sh --task-file tasks/RUN.md)

  if [ -n "$MODEL_OVERRIDE" ]; then
    # Use override if provided
    SANDBOX_CMD+=(--model "$MODEL_OVERRIDE")
  elif [[ "$NEXT" == *"JUDGE"* ]]; then
    # Use opus for JUDGE stage (better reasoning for code review)
    SANDBOX_CMD+=(--model opus)
    echo "ℹ Using Opus for Judge stage"
  fi

  "${SANDBOX_CMD[@]}" </dev/null || true

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