#!/usr/bin/env bash
# Post a bulk PR review with inline comments from a JSON file.
# Usage: post-pr-review.sh <owner/repo> <pr-number> <review-json-file>
#
# The JSON file must have this structure:
# {
#   "commit_id": "<sha>",
#   "event": "COMMENT",
#   "body": "Review summary text",
#   "comments": [
#     {"path": "src/foo.py", "line": 42, "side": "RIGHT", "body": "Comment text"},
#     ...
#   ]
# }
#
# Prints the review URL on success. On failure, prints the error and exits 1
# so the caller can fall back to posting comments individually.

set -euo pipefail

REPO="${1:?Usage: post-pr-review.sh <owner/repo> <pr-number> <review-json-file>}"
PR="${2:?}"
REVIEW_FILE="${3:?}"

if [ ! -f "$REVIEW_FILE" ]; then
  echo "ERROR: Review file not found: $REVIEW_FILE" >&2
  exit 1
fi

RESULT=$(gh api "repos/${REPO}/pulls/${PR}/reviews" --method POST --input "$REVIEW_FILE" 2>&1)

URL=$(echo "$RESULT" | jq -r '.html_url // empty' 2>/dev/null || true)
if [ -n "$URL" ]; then
  COMMENT_COUNT=$(jq '.comments | length' "$REVIEW_FILE")
  echo "Review posted with ${COMMENT_COUNT} inline comments: ${URL}"
else
  echo "ERROR: Bulk review failed" >&2
  echo "$RESULT" >&2
  exit 1
fi
