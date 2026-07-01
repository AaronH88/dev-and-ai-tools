#!/usr/bin/env bash
# Fetch all PR context needed for a code review.
# Usage: fetch-pr-context.sh <owner/repo> <pr-number>
#
# Creates /tmp/pr-<number>-diff.txt and prints structured context to stdout.
#
# For line number lookups, the script tries two strategies:
# 1. git fetch (if a local remote matches the repo) → git show pr-<number>:<file>
# 2. gh api fallback (any repo) → fetch-pr-file.sh <owner/repo> <pr-number> <sha> <file>

set -euo pipefail

REPO="${1:?Usage: fetch-pr-context.sh <owner/repo> <pr-number>}"
PR="${2:?Usage: fetch-pr-context.sh <owner/repo> <pr-number>}"

DIFF_FILE="/tmp/pr-${PR}-diff.txt"

echo "=== PR #${PR} — Fetching context ==="

# --- Metadata ---
echo ""
echo "--- Metadata ---"
gh pr view "$PR" --repo "$REPO" \
  --json title,body,state,baseRefName,headRefName,additions,deletions,changedFiles,author,url

# --- Diff ---
echo ""
echo "--- Diff ---"
gh pr diff "$PR" --repo "$REPO" > "$DIFF_FILE"
LINES=$(wc -l < "$DIFF_FILE")
echo "Saved ${LINES} lines to ${DIFF_FILE}"

# --- Changed files ---
echo ""
echo "--- Changed files ---"
gh api "repos/${REPO}/pulls/${PR}/files" --paginate --jq '.[].filename'

# --- Existing reviews (summary) ---
echo ""
echo "--- Existing reviews ---"
gh pr view "$PR" --repo "$REPO" --json reviews \
  --jq '.reviews[] | "\(.author.login): \(.state) (\(.submittedAt[:10]))"'

# --- HEAD SHA ---
echo ""
echo "--- HEAD SHA ---"
HEAD_SHA=$(gh api "repos/${REPO}/pulls/${PR}" --jq '.head.sha')
echo "$HEAD_SHA"

# --- Fetch branch for line number lookups ---
echo ""
echo "--- Fetching PR branch ---"

# Strategy 1: Try git fetch if we have a matching remote
REMOTE=""
if git rev-parse --git-dir >/dev/null 2>&1; then
  for r in $(git remote 2>/dev/null); do
    REMOTE_URL=$(git remote get-url "$r" 2>/dev/null || true)
    if echo "$REMOTE_URL" | grep -qi "${REPO}"; then
      REMOTE="$r"
      break
    fi
  done
fi

LOOKUP_METHOD=""
if [ -n "$REMOTE" ]; then
  if git fetch "$REMOTE" "pull/${PR}/head:pr-${PR}" 2>&1; then
    LOOKUP_METHOD="git"
    echo "Branch pr-${PR} available for: git show pr-${PR}:<filepath>"
  else
    echo "WARN: git fetch failed, falling back to gh api"
  fi
fi

# Strategy 2: Fall back to gh api for file content
if [ -z "$LOOKUP_METHOD" ]; then
  LOOKUP_METHOD="api"
  echo "Using gh api for file lookups (no local remote for ${REPO})"
  echo "To view a file: gh api repos/${REPO}/contents/<filepath>?ref=${HEAD_SHA} --jq '.content' | base64 -d"
fi

echo ""
echo "=== Context ready ==="
echo "  Diff:       ${DIFF_FILE}"
echo "  HEAD SHA:   ${HEAD_SHA}"
echo "  Lookup:     ${LOOKUP_METHOD}"
if [ "$LOOKUP_METHOD" = "git" ]; then
  echo "  File cmd:   git show pr-${PR}:<filepath>"
else
  echo "  File cmd:   gh api repos/${REPO}/contents/<filepath>?ref=${HEAD_SHA} --jq '.content' | base64 -d"
fi
echo "==="
