# Aaron's PR Review Style

Skill for reviewing GitHub PRs with critical, inline findings posted directly to the PR.

## When to use

When the user asks to "do a code review" or "review" a GitHub PR URL.

## Scripts

This skill includes three shell scripts in this directory:

- **`fetch-pr-context.sh <owner/repo> <pr-number>`** — Fetches metadata, diff, file list, existing reviews, HEAD SHA, and the PR branch in one call. Saves diff to `/tmp/pr-<number>-diff.txt` and prints everything to stdout.
- **`post-pr-review.sh <owner/repo> <pr-number> <review-json-file>`** — Posts all comments as a single bulk review. This is the **primary** posting method. The JSON file must contain `commit_id`, `event`, `body`, and `comments` array.
- **`post-pr-comment.sh <owner/repo> <pr-number> <sha> <file> <line> <body>`** — **Fallback only.** Posts a single inline comment. Use this if the bulk review script fails (e.g., line resolution error on one comment). Set `START_LINE` env var for multi-line ranges.

## Process

### 1. Fetch PR context

Run the fetch script:

```bash
bash .claude/skills/aarons_pr_review_style/fetch-pr-context.sh <owner/repo> <pr-number>
```

This gives you everything: metadata, diff on disk, file list, existing reviews, HEAD SHA, and a local `pr-<number>` branch for line lookups.

### 2. Read the full diff

Read `/tmp/pr-<number>-diff.txt` in full. For large diffs (2000+ lines), paginate with offset/limit. Never skip files — every changed file gets reviewed.

### 3. Analyze for findings

Think deeply about each change. Look for these categories in priority order:

**Race conditions & concurrency**
- TOCTOU (time-of-check-time-of-use) bugs
- Split-brain / dual-source-of-truth (two places read the same config independently — they will drift)
- Missing conditional updates (e.g., overwriting CANCELLED with COMPLETED)
- Implicit ordering dependencies between operations

**Correctness**
- Behavioral changes not documented as breaking (e.g., "no breaking changes" but approval nodes can no longer wait indefinitely)
- Tests deleted without replacement — if validation moved to a different layer, the new layer needs tests
- Stale TODOs from the very PR that claims to fix the thing the TODO references
- Detached ORM objects returned from closed sessions (works today, breaks when someone accesses a relationship)

**Validation & security**
- Missing bounds (no max on retry count, no max on timeout — unbounded user input on public endpoints)
- Content-Length checks without actual body size enforcement
- User-controlled values in error messages or log fields

**Design & maintainability**
- Copy-pasted logic that will drift (same schema in 6 files, same constant in 3 places)
- Unnecessary overhead (SELECT FOR UPDATE when a plain UPDATE suffices)
- Hardcoded values that mirror a config source (hardcoded timeout defaults that must stay in sync with a catalog)
- Per-call allocations that should be ClassVar/module-level constants

**Missing coverage**
- New code paths with no corresponding test (approval fallback_decision + continue_on_failure path)
- Fragile test assertions (asserting calendar day instead of timedelta)

### 4. Classify findings by severity

- **Critical**: Will cause data loss, security bypass, or silent incorrect behavior in production. The PR should not merge without addressing these.
- **Significant**: Design issue, missing validation, or correctness gap that will bite eventually. Should be addressed or explicitly deferred with a tracked issue.
- **Minor**: Style, naming, unnecessary overhead, fragile tests, missing comments. Nice to fix but not blocking.

### 5. Find exact line numbers

The fetch script outputs which lookup method is available. Use the matching command:

**If lookup is `git`** (local remote found):
```bash
git show pr-<number>:<filepath> | grep -n "<pattern>"
```

**If lookup is `api`** (no local remote — e.g., reviewing a different repo):
```bash
gh api "repos/<owner/repo>/contents/<filepath>?ref=<sha>" --jq '.content' | base64 -d | grep -n "<pattern>"
```

Verify the target line is within a diff hunk — GitHub rejects comments on lines outside the diff.

### 6. Post as a bulk review

Write all findings to a JSON file at `/tmp/pr-<number>-review.json`:

```json
{
  "commit_id": "<sha>",
  "event": "COMMENT",
  "body": "## Code Review\n\nSummary of findings...",
  "comments": [
    {"path": "src/foo.py", "line": 42, "side": "RIGHT", "body": "**Significant: ...**\n\nDetails..."},
    {"path": "src/bar.py", "line": 10, "side": "RIGHT", "body": "**Minor: ...**\n\nDetails..."}
  ]
}
```

Then post with the bulk script:

```bash
bash .claude/skills/aarons_pr_review_style/post-pr-review.sh \
  <owner/repo> <pr-number> /tmp/pr-<number>-review.json
```

This groups all comments under a single review with a summary header. If the bulk post fails (line resolution error), fall back to posting individually with `post-pr-comment.sh`.

**Important**: The `commit_id` must match the current PR HEAD. Get it from the fetch script output or `gh api repos/<owner/repo>/pulls/<number> --jq '.head.sha'`.

### 7. Clean up

```bash
rm /tmp/pr-<number>-*.txt
git branch -D pr-<number>
```

### 8. Summarize to user

End with a short summary listing what was posted, grouped by severity with one-line descriptions:

> Done. Posted 5 inline comments on PR #1215:
> - **Significant**: Cycle detection hardcodes iterate port — future feedback ports will false-positive
> - **Significant**: trigger["id"] access relies on implicit ordering with schema validation
> - **Minor**: _build_validator() at import time crashes app on malformed schemas

## Comment format

Each comment body follows this structure:

```
**<Severity>: <One-line title that states the problem>**

<2-4 sentences explaining the issue, what goes wrong, and under what conditions.>

<Optional: concrete code suggestion or alternatives.>
```

Do NOT include:
- Generic praise ("nice refactor!")
- Nitpicks about formatting, import ordering, or comment style (unless the user asks)
- Findings already covered by other reviewers
- Suggestions that add complexity without fixing a real issue

## What NOT to review

- Auto-generated files (api_client, uv.lock) — scan for unexpected changes but don't comment on generated code style
- JSON schema formatting changes (array-per-line vs inline) — these are formatter output, not design decisions
- Test boilerplate changes (removing `timeout=300` from constructors after a field was removed) — mechanical, correct by inspection

## User preferences

- When the user says "be critical" — focus on real issues, don't soften language, don't pad with compliments
- When the user says "show me what you're going to post first" — list remaining findings in the chat BEFORE posting, let the user filter
- When the user says "only major" or "only critical" — skip Minor findings entirely
- Default to posting all severity levels unless told otherwise
