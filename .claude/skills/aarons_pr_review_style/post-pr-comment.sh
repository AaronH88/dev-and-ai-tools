#!/usr/bin/env bash
# Post an inline review comment on a GitHub PR.
# Usage: post-pr-comment.sh <owner/repo> <pr-number> <commit-sha> <file-path> <line> <body>
#
# Optional env vars:
#   START_LINE  — set for multi-line comments (range: START_LINE..LINE)
#
# Prints the comment URL on success, or an error message on failure.

set -euo pipefail

REPO="${1:?Usage: post-pr-comment.sh <owner/repo> <pr-number> <sha> <file> <line> <body>}"
PR="${2:?}"
SHA="${3:?}"
FILE_PATH="${4:?}"
LINE="${5:?}"
BODY="${6:?}"

ARGS=(
  --method POST
  --field commit_id="$SHA"
  --field path="$FILE_PATH"
  --field line="$LINE"
  --field side="RIGHT"
  --field body="$BODY"
)

if [ -n "${START_LINE:-}" ]; then
  ARGS+=(--field start_line="$START_LINE" --field start_side="RIGHT")
fi

RESULT=$(gh api "repos/${REPO}/pulls/${PR}/comments" "${ARGS[@]}" 2>&1)

# Try to extract the HTML URL; fall back to printing the raw result
URL=$(echo "$RESULT" | jq -r '.html_url // empty' 2>/dev/null || true)
if [ -n "$URL" ]; then
  echo "$URL"
else
  echo "ERROR: Failed to post comment" >&2
  echo "$RESULT" >&2
  exit 1
fi
