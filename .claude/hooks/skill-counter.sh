#!/usr/bin/env bash
# UserPromptSubmit hook: counts prompts per session and injects a skill
# review directive every N prompts (default 5, configurable via
# SKILL_REVIEW_INTERVAL env var).
#
# The review directive tells Claude to review the FULL session conversation
# (both user prompts and its own responses/discoveries) and create, update,
# or remove auto-generated skills in .claude/skills/auto/.
set -euo pipefail

INPUT=$(cat)

PROMPT=$(printf '%s' "$INPUT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(d.get('input', ''))
" 2>/dev/null) || exit 0

# Skip system/command prompts and slash commands
[[ "$PROMPT" == "<command-name>"* ]] && exit 0
[[ "$PROMPT" == "<local-command"* ]] && exit 0
[[ "$PROMPT" == "/"* ]] && exit 0
[[ -z "$PROMPT" ]] && exit 0

SESSION_ID="${CLAUDE_SESSION_ID:-$$}"
COUNTER_FILE="/tmp/claude-skillmgr-${SESSION_ID}.json"
LOCK_FILE="/tmp/claude-skillmgr-${SESSION_ID}-reviewing"
INTERVAL="${SKILL_REVIEW_INTERVAL:-5}"

# Skip if a review is already pending (prevent double-injection).
# Stale lock files (>10 min) are removed — they indicate a session ended mid-review.
if [[ -f "$LOCK_FILE" ]]; then
  LOCK_AGE=$(( $(date +%s) - $(stat -f %m "$LOCK_FILE" 2>/dev/null || stat -c %Y "$LOCK_FILE" 2>/dev/null || echo 0) ))
  if [[ "$LOCK_AGE" -gt 600 ]]; then
    rm -f "$LOCK_FILE"
  else
    exit 0
  fi
fi

# Read or initialize counter
if [[ -f "$COUNTER_FILE" ]]; then
  COUNT=$(python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    print(json.load(f).get('count', 0))
" "$COUNTER_FILE" 2>/dev/null) || COUNT=0
else
  COUNT=0
fi

COUNT=$((COUNT + 1))

if [[ "$COUNT" -lt "$INTERVAL" ]]; then
  # Not yet at threshold — update counter and exit silently
  python3 -c "
import json, sys
with open(sys.argv[1], 'w') as f:
    json.dump({'count': int(sys.argv[2])}, f)
" "$COUNTER_FILE" "$COUNT"
  exit 0
fi

# Threshold reached — reset counter and create lock
python3 -c "
import json, sys
with open(sys.argv[1], 'w') as f:
    json.dump({'count': 0}, f)
" "$COUNTER_FILE"
touch "$LOCK_FILE"

# Find project root for skill paths
PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || PROJECT_ROOT="."
AUTO_DIR="${PROJECT_ROOT}/.claude/skills/auto"

cat <<'REVIEW_DIRECTIVE'
[SKILL REVIEW] After completing the user's request above, perform a background skill review.

Review the ENTIRE conversation so far in this session — your own responses, discoveries,
error resolutions, tool outputs, and approaches that worked, not just the user's prompts.

Look for:
- Workflows or multi-step processes you figured out during this session
- Domain knowledge you discovered (project structure, API patterns, config quirks)
- Error resolution paths — problems you hit and how you solved them
- Corrections the user made to your approach
- Non-obvious patterns or conventions specific to this codebase
- Approaches that worked well and should be reused

Then:
1. Read all skills in .claude/skills/auto/ (if directory has any SKILL.md files)
2. Compare what you learned against ALL existing skills (manual in .claude/skills/ AND auto)
3. Take action:

ACTIONS (pick one or more):
- CREATE: New reusable learning not covered by any existing skill. Write to .claude/skills/auto/<slug>/SKILL.md with this frontmatter:
  ---
  name: auto-<slug>
  description: <one-line description>
  auto_generated: true
  created: <today's date YYYY-MM-DD>
  last_matched: <today's date YYYY-MM-DD>
  match_count: 1
  ---
- UPDATE: Existing auto skill needs improvement based on new learnings. Edit its SKILL.md and increment match_count.
- DELETE: Auto skill is stale (last_matched > 30 days old), too narrow (only one specific scenario), or duplicates a manual skill. Remove its entire directory.
- NOTHING: No actionable patterns found. Skip.

RULES:
- Only create skills for REUSABLE learnings — things likely to help in future sessions
- Do NOT create skills for one-off questions, trivial operations, or things already covered by manual skills
- NEVER touch skills outside .claude/skills/auto/
- After completing the review, remove the lock file: rm /tmp/claude-skillmgr-SESSION_ID-reviewing
- Print exactly one summary line prefixed with [skill-manager]
- If in doubt about whether something is worth a skill, err on the side of creating — cleanup will prune later
REVIEW_DIRECTIVE

# Inject the actual session ID into the lock file removal instruction
echo "(Lock file to remove: ${LOCK_FILE})"
