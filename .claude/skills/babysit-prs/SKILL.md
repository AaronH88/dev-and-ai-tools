# Babysit PRs

Monitor and maintain open pull requests. Checks merge health, CI status, review comments (including bot reviews), and takes action — fixing code, rebasing, and replying to reviewers.

Use standalone (`/babysit-prs org/repo#123 org/repo#456`) or in a loop (`/loop 15m /babysit-prs org/repo#123 org/repo#456`).

## Input

The skill receives PR references as arguments in the format `org/repo#number` (e.g., `automation-nexus/nexus-ui#935 automation-nexus/nexus#1166`). Full GitHub URLs are also accepted — extract `repo` and `number` from them. If no arguments are provided, ask the user which PRs to monitor.

## Repo directory mapping

This environment has local clones of the repos. Map repo names to local directories:

| Repo | Local directory |
|------|----------------|
| `automation-nexus/nexus` | `./nexus/` |
| `automation-nexus/nexus-ui` | `./nexus-ui/` |

## Running checks

**CRITICAL: Every iteration MUST run the check script for each PR.** Do not skip checks or use shortcut queries — the script covers all required checks.

For each PR, run:

```bash
.claude/skills/babysit-prs/check-pr.sh <repo> <number> [pr_author]
```

The script runs ALL checks in order:
1. **Merge health** — detects CONFLICTING, DIRTY, BEHIND
2. **CI status** — counts pass/fail/pending, extracts run IDs for failed checks
3. **Inline code comments** — finds unresolved threads (no reply from PR author)
4. **Review summaries** — flags CHANGES_REQUESTED reviews
5. **General PR comments** — groups bot comments by author with latest timestamps
6. **PR status summary** — state, reviewDecision, mergeStateStatus

The script exits with code 1 when action is needed. Read the output to determine what to do.

## Branch management (BEFORE any code changes)

**CRITICAL: Before making ANY code change or rebase, you MUST ensure you're on the correct branch AND pushing to the correct remote.**

### Detect the push remote

Not all PRs come from the fork. The head branch may live on `origin` (fork) or `upstream` (org repo). **Always check first:**

```bash
gh pr view <number> --repo <repo> --json headRefName,headRepositoryOwner \
  --jq '{branch: .headRefName, owner: .headRepositoryOwner.login}'
```

| `owner` matches | Remote to fetch/push |
|-----------------|---------------------|
| Fork owner (e.g. `AaronH88`) | `origin` |
| Upstream org (e.g. `automation-nexus`) | `upstream` |

Store the result — you'll need it for fetch, checkout, and push commands below.

### Worktree isolation (default)

Always use **git worktrees** for code changes. This avoids branch conflicts — especially when multiple babysitting loops run on different PRs in the same repo.

1. **Get the PR's branch name and remote** (see above).

2. **Create the worktree** from the repo's main checkout:
   ```bash
   cd ./nexus-ui/  # or ./nexus/ per the mapping table
   REMOTE=origin   # or upstream — based on detection above
   git fetch $REMOTE <branch> && git fetch upstream main
   git worktree add -b pr-<number>-fix .worktrees/nexus-ui-pr-<number> $REMOTE/<branch>
   ```

3. **Install dependencies** (worktrees don't share node_modules):
   ```bash
   (cd .worktrees/nexus-ui-pr-<number> && npm install)
   ```

4. **Run local checks from the worktree directory:**
   ```bash
   (cd .worktrees/nexus-ui-pr-<number> && npm run tsc && npm run lint && npm run format:check)
   ```

5. **Push using the local branch → remote branch mapping:**
   ```bash
   git push $REMOTE pr-<number>-fix:<branch>
   ```

6. **Return to workspace root** after finishing:
   ```bash
   cd /Users/ahetheri/pr-babysitting
   ```

7. **Cleanup** — remove the worktree after the PR merges:
   ```bash
   cd ./nexus-ui/
   git worktree remove .worktrees/nexus-ui-pr-<number>
   ```
   If the user asks to keep it, leave it until they say otherwise or the PR merges.

### Direct checkout (fallback)

Only use direct checkout when worktrees are impractical (e.g., the repo has no other active PR loops and the change is trivial):

1. **Navigate to the local repo and checkout:**
   ```bash
   cd ./nexus/  # or ./nexus-ui/ per the mapping table
   REMOTE=origin  # or upstream — based on detection above
   git fetch $REMOTE <branch> && git fetch upstream main
   git checkout <branch> 2>/dev/null || git checkout -b <branch> $REMOTE/<branch>
   ```

2. **Verify before proceeding:**
   ```bash
   git branch --show-current  # must match the PR's headRefName
   git log --oneline -1       # should match the PR's latest commit
   ```

3. **Return to workspace root** after finishing with a repo:
   ```bash
   cd /Users/ahetheri/pr-babysitting
   ```

## Local CI checks (BEFORE pushing)

**CRITICAL: After making code changes and before running `git push`, run the repo's local checks.** This catches TypeScript errors, lint violations, and formatting issues in one pass — avoiding multiple push-fix-push cycles.

### nexus-ui checks

From the `./nexus-ui/` directory:

```bash
npm run tsc              # TypeScript type check
npm run lint             # ESLint
npm run format:check     # Prettier formatting
```

If `format:check` fails, auto-fix and re-stage:
```bash
npm run format
git add -u
```

### nexus checks

From the `./nexus/` directory:

```bash
make format              # ruff format + pre-commit auto-fix
make lint                # linting checks
```

If `make format` modifies files, amend the commit or stage and commit the formatting fix before pushing.

### Handling local check failures

- Fix the issue, re-stage, and amend the commit (or create a new fixup commit).
- Re-run the failing check to confirm it passes.
- Only push once all local checks pass.

## Acting on results

### Merge health — ACTION: REBASE NEEDED

1. **Ensure correct branch** (see Branch management above)
2. `git fetch upstream main`
3. `git rebase upstream/main`
4. Resolve any conflicts:
   - If files were **deleted on main** and modified in our branch, check if our changes were already reverted/addressed. If so, `git rm <file>` and continue.
   - For content conflicts, examine both sides and merge appropriately.
5. `git rebase --continue` (repeat until done)
6. **Run local CI checks** (see above) to catch issues before pushing.
7. `git push --force-with-lease`
8. **Re-run check-pr.sh** to verify the rebase resolved the issue

### CI — ACTION: CI FAILURES DETECTED

The script outputs the failed check name, URL, and run ID. Use the run ID to get logs:

```bash
gh run view <run_id> --repo <repo> --log-failed
```

1. Diagnose the root cause.
2. **If it's in code we own** (not a pre-existing/infra failure):
   - **Ensure correct branch** (see Branch management above)
   - Fix it, commit, **run local CI checks**, and push.
   - **Re-run check-pr.sh** to verify.
3. **If it's a pre-existing failure** (flaky test that also fails on main, infra OOM, SonarCloud token issues): **re-run the failed jobs**, then move on.

To determine if a failure is pre-existing, check if the same test fails on main:
```bash
gh run list --repo <repo> --branch main --workflow "<workflow-name>" --limit 3
```

If pre-existing, re-trigger just the failed jobs:
```bash
gh run rerun <run_id> --repo <repo> --failed
```

### Comments — ACTION: UNRESOLVED COMMENTS

The script lists each unresolved thread with the comment ID. For each one:

- **Code change request** →
  1. **Ensure correct branch** (see Branch management above)
  2. Implement the fix, commit, **run local CI checks**, push.
  3. Reply **individually** to each comment:
     ```bash
     gh api repos/<repo>/pulls/<number>/comments/<comment_id>/replies -f body="Fixed in <commit-sha>: <brief explanation>"
     ```
- **Question** → Reply directly to the comment with a clear answer.
- **Nit/suggestion** → Implement unless it conflicts with project standards. Reply explaining what was done.

If reply fails (e.g., fork permissions), fall back to a general PR comment referencing each finding by `file:line`.

### Reviews — ACTION: CHANGES REQUESTED

Address the reviewer's concerns, push fixes, and reply to each point. The reviewer will need to re-approve.

## Feedback Loop — Skill Improvement

After completing all PR checks and actions for each iteration, run the feedback loop to extract reviewer learnings and improve existing skills. This creates a continuous improvement cycle: reviewers catch issues → feedback flows into skills → future work avoids those issues.

### When to run

- At the **end of each babysit cycle**, after all PRs have been checked and acted on
- **Skip** if every PR is clean with no new reviewer comments
- Only process **new feedback** since the last extraction (the script tracks this automatically)

### Step 1: Extract feedback

For each monitored PR, run:

```bash
.claude/skills/babysit-prs/extract-feedback.sh <repo> <number> [pr_author]
```

This outputs reviewer comments and reviews, filtered to only new items since the last extraction. If the output shows `(none)` for all sections, skip to the next PR.

### Step 2: Categorize feedback

For each comment — **including bot reviews** (e.g., `ai-security-reviewer-bot`, `sonarqubecloud`) — classify it:

| Category | Signal | Example |
|---|---|---|
| **coding-pattern** | "use X instead of Y", "always/never do Z" | "Use `useCallback` for handlers passed to children" |
| **testing** | "missing test", "test should cover", "add assertion" | "No test for the error state path" |
| **style-convention** | "rename to", "use this format", "naming" | "Constants should be UPPER_SNAKE_CASE" |
| **architecture** | "this belongs in X", "split into", "wrong layer" | "Validation logic should live in the service layer" |
| **security** | "validation missing", "access control", "injection risk" | "Add validation: project_id required before API call" |
| **process** | "PR should/shouldn't", "don't forget to", "always run" | "Run gen-contracts when changing API schemas" |
| **skip** | Praise, status-only bot output (e.g. SonarCloud pass/fail badge with no actionable finding), duplicate of already-captured pattern | "Looks good", Quality Gate Passed with no details |

**Bot feedback rules:**
- Treat bot findings with the same rigor as human reviewer comments — categorize and capture actionable patterns.
- **Security bot findings** (e.g., `ai-security-reviewer-bot`) often surface validation gaps, access control risks, or injection vectors. These are high-value patterns worth capturing even if the specific finding is a false positive — the underlying pattern may still be valid.
- **Quality gate bots** (e.g., `sonarqubecloud`) — only capture when they surface a specific, actionable pattern (e.g., "coverage on new code is 50%"). Skip bare pass/fail status badges.

### Step 3: Discover and match skills

Dynamically discover ALL current skills — **never hardcode skill names or paths**:

```bash
find .claude/skills -name 'SKILL.md' | sort
```

Read each discovered skill's first 30 lines to understand its domain and scope. Match each actionable feedback item to the most relevant skill based on content overlap. Skills may be added, renamed, or removed at any time — always discover fresh.

### Step 4: Update skills

Based on the match:

- **Existing manual skill matches** → Append the learning as a concrete, actionable rule to the relevant section. Frame it as guidance ("Always validate X before Y") not attribution ("A reviewer said to validate X"). **Never remove or rewrite existing content** — only add.
- **Existing auto skill matches** → Update its content, increment `match_count`, update `last_matched` in frontmatter.
- **No skill matches but pattern is reusable** → Create a new auto skill in `.claude/skills/auto/<slug>/SKILL.md`:
  ```yaml
  ---
  name: auto-<slug>
  description: <one-line description>
  auto_generated: true
  source: pr-feedback
  created: <YYYY-MM-DD>
  last_matched: <YYYY-MM-DD>
  match_count: 1
  ---
  ```
- **Contradicts existing skill** → Add a `> **Note (YYYY-MM-DD):** Reviewer feedback suggests ...` block flagging the contradiction. Do NOT silently override existing guidance.

### Step 5: Log to feedback journal

Append a summary to `.claude/state/pr-feedback/feedback-log.md`:

```markdown
## YYYY-MM-DD — repo#PR
- [category] "summary" → action (updated <skill-name> / created auto-<slug> / skipped)
```

**Recurring pattern detection**: Before logging, scan previous journal entries for the same category + similar feedback across **different PRs**. If a pattern appears 2+ times and hasn't been captured in a skill yet, escalate — update the most relevant skill immediately, even if individual occurrences seemed too minor.

### Feedback loop rules

- **Dynamic discovery only** — always `find` skills at runtime. Skills change between runs.
- **Additive to manual skills** — never remove or rewrite existing manual skill content.
- **Auto skills are fully managed** — create, update, or delete freely.
- **Actionable over exhaustive** — only capture feedback that changes future behavior.
- **Deduplicate** — check the journal before adding. Don't log the same pattern twice from the same PR.
- **One summary line** — after the loop completes, print exactly `[feedback-loop] <summary>` (e.g., `[feedback-loop] Updated frontend-coding-standards with 2 patterns, created auto-error-handling, skipped 3 items`).

## Rules

- **Run the check script every iteration** — never skip it or substitute a shortcut query.
- **Always verify you're on the correct branch** before making code changes.
- **Always return to workspace root** (`cd /Users/ahetheri/pr-babysitting`) after working in a repo.
- **Re-run check-pr.sh after pushing fixes** to verify the fix landed.
- **Skip items already addressed** in a previous loop iteration. Don't re-report unchanged status.
- **Only report if something changed** or needs attention.
- **Conventional commits** — match the repo's existing commit message style.
- **Don't block on non-actionable failures** — note them, move on.
- **Always rebase on upstream/main** — push to whichever remote owns the PR's head branch (detect with `headRepositoryOwner`).
- **Keep branches fresh** — even when the check script reports no merge conflict, proactively check if the branch is behind main (`git rev-list --count HEAD..upstream/main` after fetching). If behind, rebase and push to avoid drift.
