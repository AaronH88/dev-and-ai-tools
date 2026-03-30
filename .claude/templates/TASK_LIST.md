# {Project Name} — Task List

## How This File Works

This file is the single source of truth for the agentic build loop.

Each time an agent is invoked it:
1. Reads the `→ NEXT:` cursor below to find its task
2. Reads the persona and spec listed in that task entry
3. Executes the task
4. Updates the checkbox for that entry `[ ]` → `[x]`
5. Advances the `→ NEXT:` cursor to the following entry
6. Exits

The judge is the only agent that can move the cursor backwards.
If the judge fails a task it unchecks the relevant entries,
resets the cursor, and writes feedback to a file for the developer to read.

Feedback files live in: `tasks/feedback/`
Persona files live in: `tasks/personas/`
Spec files live in: `tasks/specs/`

---

→ NEXT: Task 0.1 — DEV

---

{TASK ENTRIES GO HERE — one section per task, following the format below}

{EXAMPLE — replace with real tasks:}

{
## Task 0.1 — [Title]

- [ ] **DEV** — `persona: tasks/personas/developer.md` — attempt 1 of 3
  Read spec: `tasks/specs/task-0.1.md`
  If retrying, read feedback: _(none yet)_
  Implement the task. When done:
  - Run `git add -A && git commit -m "dev: task 0.1"`
  - Check this box
  - Set cursor to: `→ NEXT: Task 0.1 — TEST`

- [ ] **TEST** — `persona: tasks/personas/test_writer.md` — attempt 1 of 3
  Read spec: `tasks/specs/task-0.1.md`
  Read the diff: `git diff HEAD~1`
  Write tests for what the developer just built. When done:
  - Run `git add -A && git commit -m "test: task 0.1"`
  - Check this box
  - Set cursor to: `→ NEXT: Task 0.1 — VERIFY`

- [ ] **VERIFY** — attempt 1 of 3
  Run: `cd backend && python -m pytest -v 2>&1 | tee tasks/feedback/task-0.1-verify.txt`
  If exit code 0 (tests pass):
  - Check this box
  - Set cursor to: `→ NEXT: Task 0.1 — JUDGE`
  If exit code non-zero (tests fail):
  - Do NOT check this box
  - Uncheck DEV and TEST above (they must be redone)
  - Increment attempt numbers on DEV, TEST, VERIFY by 1
  - If attempt number would exceed 3: replace checkbox with `[BLOCKED]` and stop
  - Set cursor to: `→ NEXT: Task 0.1 — DEV`

- [ ] **JUDGE** — `persona: tasks/personas/judge.md` — attempt 1 of 3
  Read spec: `tasks/specs/task-0.1.md`
  Read diff: `git diff HEAD~2`
  Read verify output: `tasks/feedback/task-0.1-verify.txt`
  Write verdict to: `tasks/feedback/task-0.1-judge.md`
  Then read the verdict and act on it:

  If verdict is PASS or PASS_WITH_CONCERNS:
  - Check this box
  - Set cursor to: `→ NEXT: Task 1.1 — DEV`

  If verdict is FAIL:
  - Do NOT check this box
  - Uncheck DEV, TEST, VERIFY above
  - Increment attempt numbers on DEV, TEST, VERIFY, JUDGE by 1
  - If any attempt number would exceed 3: replace checkbox with `[BLOCKED]` and stop
  - Update the feedback reference on DEV: replace `_(none yet)_` with path to verdict file
  - Set cursor to: `→ NEXT: Task 0.1 — DEV`

  Feedback for DEV on retry: _(none yet)_

---
}

---

## Final Judge

- [ ] **FINAL JUDGE** — `persona: tasks/personas/judge.md`
  You are doing a final review of the entire project, not a single task.

  Read:
  - `tasks/ARCHITECTURE_REF.md` — what was planned
  - `git log --oneline` — what was actually built
  - All `tasks/feedback/*-judge.md` files — what concerns were raised during the build

  Write your full verdict to: `tasks/feedback/final-judge.md`

  You are looking for systemic issues that per-task judges may have missed:
  - Patterns that were inconsistent across phases
  - Concerns that appeared in multiple pass_with_concerns verdicts and were never resolved
  - Anything that would make this codebase hard to maintain or extend

  Then update `tasks/BUILD_STATUS.md` — overwrite the entire file with one of:

  If PASS:
  APPROVED

  If FAIL:
  FAILED — see tasks/feedback/final-judge.md
