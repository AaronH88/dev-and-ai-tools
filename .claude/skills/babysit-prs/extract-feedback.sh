#!/usr/bin/env bash
# Extract review feedback from a GitHub PR for skill improvement analysis.
# Usage: extract-feedback.sh <org/repo> <pr_number> [pr_author]
#
# Outputs reviewer comments and reviews, filtered to only new feedback
# since the last extraction. State is tracked per-PR in .claude/state/pr-feedback/.
set -euo pipefail

REPO="${1:?Usage: extract-feedback.sh <org/repo> <pr_number> [pr_author]}"
PR="${2:?Usage: extract-feedback.sh <org/repo> <pr_number> [pr_author]}"
AUTHOR="${3:-}"

PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo ".")
STATE_DIR="${PROJECT_ROOT}/.claude/state/pr-feedback"
STATE_FILE="${STATE_DIR}/${REPO//\//-}-${PR}.json"

mkdir -p "$STATE_DIR"

# Get PR author if not provided
if [[ -z "$AUTHOR" ]]; then
  AUTHOR=$(gh pr view "$PR" --repo "$REPO" --json author --jq '.author.login' 2>/dev/null) || AUTHOR=""
fi

# Read last extraction timestamp
SINCE=""
if [[ -f "$STATE_FILE" ]]; then
  SINCE=$(python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    print(json.load(f).get('last_extracted', ''))
" "$STATE_FILE" 2>/dev/null) || SINCE=""
fi

echo "=== PR FEEDBACK: ${REPO}#${PR} ==="
echo "Author: ${AUTHOR:-unknown}"
[[ -n "$SINCE" ]] && echo "New feedback since: $SINCE" || echo "First extraction — showing all reviewer feedback"
echo ""

# --- Inline review comments (code-level feedback from reviewers) ---
echo "--- INLINE REVIEW COMMENTS ---"
gh api "repos/${REPO}/pulls/${PR}/comments" --paginate 2>/dev/null | python3 -c "
import sys, json
data = json.load(sys.stdin)
author = '$AUTHOR'
since = '$SINCE'
count = 0
for c in data:
    user = c.get('user', {}).get('login', '')
    if user == author:
        continue
    created = c.get('created_at', '')
    if since and created <= since:
        continue
    path = c.get('path', '?')
    line = c.get('line') or c.get('original_line') or '?'
    body = c.get('body', '').strip()
    if not body:
        continue
    count += 1
    print(f'  [{user}] {path}:{line}')
    for bline in body.split('\n'):
        print(f'    {bline}')
    print()
if count == 0:
    print('  (none)')
" 2>/dev/null || echo "  (error reading comments)"

# --- Reviews with body text (approval/changes-requested/commented) ---
echo "--- REVIEWS ---"
gh api "repos/${REPO}/pulls/${PR}/reviews" --paginate 2>/dev/null | python3 -c "
import sys, json
data = json.load(sys.stdin)
author = '$AUTHOR'
since = '$SINCE'
count = 0
for r in data:
    if r.get('state') == 'PENDING':
        continue
    user = r.get('user', {}).get('login', '')
    if user == author:
        continue
    submitted = r.get('submitted_at', '')
    if since and submitted <= since:
        continue
    body = r.get('body', '').strip()
    if not body and r.get('state') == 'APPROVED':
        continue
    state = r.get('state', '?')
    count += 1
    print(f'  [{user}] {state} ({submitted})')
    if body:
        for bline in body.split('\n'):
            print(f'    {bline}')
    print()
if count == 0:
    print('  (none)')
" 2>/dev/null || echo "  (error reading reviews)"

# --- General PR comments (exclude bots and PR author) ---
echo "--- GENERAL COMMENTS ---"
gh api "repos/${REPO}/issues/${PR}/comments" --paginate 2>/dev/null | python3 -c "
import sys, json
data = json.load(sys.stdin)
author = '$AUTHOR'
since = '$SINCE'
count = 0
for c in data:
    user = c.get('user', {}).get('login', '')
    if user == author:
        continue
    if user.endswith('[bot]'):
        continue
    created = c.get('created_at', '')
    if since and created <= since:
        continue
    body = c.get('body', '').strip()
    if not body:
        continue
    count += 1
    print(f'  [{user}]')
    for bline in body[:500].split('\n'):
        print(f'    {bline}')
    print()
if count == 0:
    print('  (none)')
" 2>/dev/null || echo "  (error reading comments)"

echo ""
echo "=== END FEEDBACK ==="

# Update extraction timestamp
python3 -c "
import json, datetime, sys
state_file = sys.argv[1]
try:
    with open(state_file) as f:
        data = json.load(f)
except:
    data = {}
data['last_extracted'] = datetime.datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ')
data['repo'] = '$REPO'
data['pr'] = int('$PR')
with open(state_file, 'w') as f:
    json.dump(data, f, indent=2)
" "$STATE_FILE"
