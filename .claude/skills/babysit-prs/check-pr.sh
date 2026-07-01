#!/usr/bin/env bash
# check-pr.sh — Run all babysit-prs checks for a single PR.
#
# Usage: ./check-pr.sh <repo> <number> [pr_author]
#   e.g.: ./check-pr.sh automation-nexus/nexus-ui 947
#   e.g.: ./check-pr.sh automation-nexus/nexus-ui 947 AaronH88
#
# Outputs structured blocks that Claude can parse and act on.
# Exit code 0 = all clean, 1 = action needed.

set -euo pipefail

REPO="${1:?Usage: check-pr.sh <repo> <number> [pr_author]}"
PR_NUMBER="${2:?Usage: check-pr.sh <repo> <number> [pr_author]}"
PR_AUTHOR="${3:-AaronH88}"

ACTION_NEEDED=0

echo "========================================"
echo "PR: ${REPO}#${PR_NUMBER}"
echo "========================================"

# ── 1. Merge health ──────────────────────────────────────────────────────
echo ""
echo "── 1. MERGE HEALTH ──"
MERGE_JSON=$(gh pr view "$PR_NUMBER" --repo "$REPO" --json mergeStateStatus,mergeable,state 2>&1) || true
echo "$MERGE_JSON" | python3 -c "
import sys, json
d = json.load(sys.stdin)
status = d.get('mergeStateStatus','UNKNOWN')
mergeable = d.get('mergeable','UNKNOWN')
state = d.get('state','UNKNOWN')
print(f'  state: {state}')
print(f'  mergeable: {mergeable}')
print(f'  mergeStateStatus: {status}')
if status in ('DIRTY',) or mergeable == 'CONFLICTING':
    print('  ACTION: REBASE NEEDED — has conflicts')
    sys.exit(2)
elif status == 'BEHIND':
    print('  ACTION: REBASE NEEDED — behind main')
    sys.exit(2)
elif status in ('CLEAN', 'BLOCKED', 'UNKNOWN'):
    print('  OK: no merge action needed')
" || ACTION_NEEDED=1

# ── 2. CI status ─────────────────────────────────────────────────────────
echo ""
echo "── 2. CI STATUS ──"
CI_OUTPUT=$(gh pr checks "$PR_NUMBER" --repo "$REPO" 2>&1) || true

# Count pass/fail/pending
PASS_COUNT=$(echo "$CI_OUTPUT" | grep -c "	pass	" || true)
FAIL_COUNT=$(echo "$CI_OUTPUT" | grep -c "	fail	" || true)
PENDING_COUNT=$(echo "$CI_OUTPUT" | grep -c "	pending	" || true)
SKIP_COUNT=$(echo "$CI_OUTPUT" | grep -c "	skipping	" || true)

echo "  pass: $PASS_COUNT  fail: $FAIL_COUNT  pending: $PENDING_COUNT  skipping: $SKIP_COUNT"

if [ "$FAIL_COUNT" -gt 0 ]; then
    echo "  ACTION: CI FAILURES DETECTED"
    echo "  Failed checks:"
    echo "$CI_OUTPUT" | grep "	fail	" | while IFS= read -r line; do
        NAME=$(echo "$line" | cut -f1)
        URL=$(echo "$line" | cut -f4)
        # Extract run ID from URL for gh run view --log-failed
        RUN_ID=$(echo "$URL" | grep -oE 'runs/[0-9]+' | head -1 | cut -d/ -f2 || true)
        echo "    - $NAME"
        echo "      url: $URL"
        if [ -n "$RUN_ID" ]; then
            echo "      run_id: $RUN_ID  (use: gh run view $RUN_ID --repo $REPO --log-failed)"
        fi
    done
    ACTION_NEEDED=1
elif [ "$PENDING_COUNT" -gt 0 ]; then
    echo "  INFO: CI still running"
else
    echo "  OK: all checks passing"
fi

# ── 3a. Inline code comments (with reply-thread detection) ───────────────
echo ""
echo "── 3a. INLINE CODE COMMENTS ──"

# Fetch ALL inline comments with pagination.
# --paginate can produce multiple JSON arrays concatenated without commas.
# Use jq -s 'add // []' to merge them into a single array.
ALL_INLINE=$(gh api "repos/${REPO}/pulls/${PR_NUMBER}/comments" --paginate 2>&1 \
  | jq -s 'add // [] | [.[] | {
      id: .id,
      author: .user.login,
      path: (.path | split("/")[-1]),
      created_at: .created_at,
      body_preview: (.body | split("\n")[0][:120]),
      in_reply_to: .in_reply_to_id
    }]' 2>&1) || true

# Use python to find unresolved threads (top-level comments with no reply from PR author)
echo "$ALL_INLINE" | python3 -c "
import sys, json

pr_author = '${PR_AUTHOR}'

try:
    comments = json.load(sys.stdin)
except (json.JSONDecodeError, ValueError):
    print('  ERROR: failed to parse inline comments')
    sys.exit(0)

if not isinstance(comments, list):
    print('  ERROR: unexpected comment format')
    sys.exit(0)

# Build sets: top-level comment IDs from others, and IDs that PR author replied to
top_level = {}
replied_to = set()

for c in comments:
    if c['in_reply_to'] is None and c['author'] != pr_author:
        top_level[c['id']] = c
    if c['in_reply_to'] is not None and c['author'] == pr_author:
        replied_to.add(c['in_reply_to'])

resolved = {cid: c for cid, c in top_level.items() if cid in replied_to}
unresolved = {cid: c for cid, c in top_level.items() if cid not in replied_to}

print(f'  Total threads: {len(top_level)}  Resolved: {len(resolved)}  Unresolved: {len(unresolved)}')

if unresolved:
    print('  ACTION: UNRESOLVED COMMENTS')
    for c in sorted(unresolved.values(), key=lambda x: x['created_at']):
        print(f'    [{c[\"created_at\"]}] {c[\"author\"]} on {c[\"path\"]} (id:{c[\"id\"]})')
        print(f'      {c[\"body_preview\"]}')
    sys.exit(2)
else:
    print('  OK: all comment threads resolved')
" || ACTION_NEEDED=1

# ── 3b. Review summaries ─────────────────────────────────────────────────
echo ""
echo "── 3b. REVIEW SUMMARIES ──"
REVIEWS=$(gh api "repos/${REPO}/pulls/${PR_NUMBER}/reviews" --jq "
  [.[] | select(.user.login != \"${PR_AUTHOR}\") | {
    author: .user.login,
    state: .state,
    submitted_at: .submitted_at
  }]
" 2>&1) || true

echo "$REVIEWS" | python3 -c "
import sys, json

reviews = json.load(sys.stdin)

# Only care about actionable states
changes_requested = [r for r in reviews if r['state'] == 'CHANGES_REQUESTED']
approved = [r for r in reviews if r['state'] == 'APPROVED']
commented = [r for r in reviews if r['state'] == 'COMMENTED']

print(f'  Approved: {len(approved)}  Changes requested: {len(changes_requested)}  Commented: {len(commented)}')

if changes_requested:
    print('  ACTION: CHANGES REQUESTED')
    for r in changes_requested:
        print(f'    [{r[\"submitted_at\"]}] {r[\"author\"]}: {r[\"state\"]}')
    sys.exit(2)
elif approved:
    for r in approved:
        print(f'    [{r[\"submitted_at\"]}] {r[\"author\"]}: APPROVED')
    print('  OK: has approval(s)')
else:
    print('  INFO: no approvals or change requests yet')
" || ACTION_NEEDED=1

# ── 3c. General PR comments (bots) ───────────────────────────────────────
echo ""
echo "── 3c. GENERAL PR COMMENTS ──"
PR_COMMENTS=$(gh pr view "$PR_NUMBER" --repo "$REPO" --json comments --jq "
  [.comments[] | select(.author.login != \"${PR_AUTHOR}\") | {
    author: .author.login,
    createdAt: .createdAt,
    body_preview: (.body | split(\"\n\")[0][:120])
  }]
" 2>&1) || true

echo "$PR_COMMENTS" | python3 -c "
import sys, json

comments = json.load(sys.stdin)

# Categorise by bot type for easier scanning
bots = {}
for c in comments:
    author = c['author']
    bots.setdefault(author, []).append(c)

print(f'  Total comments: {len(comments)} from {len(bots)} author(s)')
for author, entries in bots.items():
    latest = max(entries, key=lambda x: x['createdAt'])
    print(f'    {author} ({len(entries)} comments, latest: {latest[\"createdAt\"]})')
    print(f'      {latest[\"body_preview\"]}')
"

# ── 4. PR status summary ─────────────────────────────────────────────────
echo ""
echo "── 4. PR STATUS SUMMARY ──"
gh pr view "$PR_NUMBER" --repo "$REPO" --json state,reviewDecision,mergeStateStatus,title,headRefName --jq '
  "  title: \(.title)",
  "  branch: \(.headRefName)",
  "  state: \(.state)",
  "  reviewDecision: \(.reviewDecision)",
  "  mergeStateStatus: \(.mergeStateStatus)"
'

echo ""
echo "── RESULT ──"
if [ "$ACTION_NEEDED" -eq 1 ]; then
    echo "  ⚠️  ACTION NEEDED"
else
    echo "  ✅ ALL CLEAR"
fi

exit $ACTION_NEEDED
