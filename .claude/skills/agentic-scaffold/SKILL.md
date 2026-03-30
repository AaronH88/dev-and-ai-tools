# Skill: Agentic Scaffold

## Purpose
Transform a task document into a complete agentic build loop — spec files,
TASK_LIST.md, personas, and execution scripts — ready to run with loop.sh.

## When to Use This Skill
After the project-bootstrap skill has produced docs/ARCHITECTURE.md and
docs/TASKS.md, and those documents have been reviewed and approved.

## Input
- `tasks_file` (string, required) — Path to the task document (e.g., `docs/TASKS.md`)
- `architecture_file` (string, required) — Path to the architecture document (e.g., `docs/ARCHITECTURE.md`)

## Process

Read {tasks_file} and {architecture_file} fully before producing any output.

---

### Step 1 — Create Folder Structure

Create these directories if they don't exist:
```
tasks/
tasks/specs/
tasks/feedback/
tasks/personas/
```

---

### Step 2 — Spec Files

For every task in {tasks_file}, create `tasks/specs/task-{id}.md`.

Each spec file must contain exactly:

```markdown
# Task {id} — {title}

## Phase
{phase number}

## Description
{full task description verbatim from {tasks_file}}

## Acceptance Criteria
{acceptance criteria verbatim from {tasks_file}}

## Verify Scope
{backend | frontend | both}
```

Rules:
- Copy descriptions and acceptance criteria verbatim — do not summarise
- Verify scope rules:
  - Backend-only tasks (no UI changes): backend
  - Frontend-only tasks (no API changes): frontend
  - Tasks touching both API and UI: both
  - Deployment tasks: backend
  - PWA / polish tasks: frontend
  - When unclear: both

---

### Step 3 — TASK_LIST.md

Copy the template from `.claude/templates/TASK_LIST.md`.

Replace the example task entries with real entries from {tasks_file}.
Every task gets exactly four entries in this order: DEV, TEST, VERIFY, JUDGE.

Entry format (copy this pattern exactly for every task):

```markdown
## Task {id} — {title}

- [ ] **DEV** — `persona: tasks/personas/developer.md` — attempt 1 of 3
  Read spec: `tasks/specs/task-{id}.md`
  If retrying, read feedback: _(none yet)_
  Implement the task. When done:
  - Run `git add -A && git commit -m "dev: task {id}"`
  - Check this box
  - Set cursor to: `→ NEXT: Task {id} — TEST`

- [ ] **TEST** — `persona: tasks/personas/test_writer.md` — attempt 1 of 3
  Read spec: `tasks/specs/task-{id}.md`
  Read the diff: `git diff HEAD~1`
  Write tests for what the developer just built. When done:
  - Run `git add -A && git commit -m "test: task {id}"`
  - Check this box
  - Set cursor to: `→ NEXT: Task {id} — VERIFY`

- [ ] **VERIFY** — attempt 1 of 3
  Run: `{verify_command} 2>&1 | tee tasks/feedback/task-{id}-verify.txt`
  If exit code 0 (tests pass):
  - Check this box
  - Set cursor to: `→ NEXT: Task {id} — JUDGE`
  If exit code non-zero (tests fail):
  - Do NOT check this box
  - Uncheck DEV and TEST above (they must be redone)
  - Increment attempt numbers on DEV, TEST, VERIFY by 1
  - If attempt number would exceed 3: replace checkbox with `[BLOCKED]` and stop
  - Set cursor to: `→ NEXT: Task {id} — DEV`

- [ ] **JUDGE** — `persona: tasks/personas/judge.md` — attempt 1 of 3
  Read spec: `tasks/specs/task-{id}.md`
  Read diff: `git diff HEAD~2` (covers dev + test commits)
  Read verify output: `tasks/feedback/task-{id}-verify.txt`
  Write verdict to: `tasks/feedback/task-{id}-judge.md`
  Then read the verdict and act on it:

  If verdict is PASS or PASS_WITH_CONCERNS:
  - Check this box
  - Set cursor to: `→ NEXT: Task {next_id} — DEV`

  If verdict is FAIL:
  - Do NOT check this box
  - Uncheck DEV, TEST, VERIFY above
  - Increment attempt numbers on DEV, TEST, VERIFY, JUDGE by 1
  - If any attempt number would exceed 3: replace checkbox with `[BLOCKED]` and stop
  - Update the feedback reference on DEV: replace `_(none yet)_` with path to verdict file
  - Set cursor to: `→ NEXT: Task {id} — DEV`

  Feedback for DEV on retry: _(none yet)_

---
```

VERIFY command by scope:
- `backend`: `cd backend && python -m pytest -v`
- `frontend`: `cd frontend && npm test -- --watchAll=false`
- `both`: `cd backend && python -m pytest -v 2>&1 | tee tasks/feedback/task-{id}-verify.txt && cd ../frontend && npm test -- --watchAll=false`

Note: for `both`, adjust the tee command so output from both test runs
goes to the same verify file.

Cursor rules:
- Each task's JUDGE PASS cursor points to the next task's DEV entry
- The very last task's JUDGE PASS cursor points to: `→ NEXT: FINAL JUDGE`
- The initial `→ NEXT:` cursor at the top of the file points to the first task DEV

The FINAL JUDGE entry is already in the template — do not modify it.
Insert all task entries between the header and the FINAL JUDGE section.

---

### Step 4 — Persona Files

Copy the three persona files verbatim from templates:
- `.claude/personas/developer.md` → `tasks/personas/developer.md`
- `.claude/personas/test_writer.md` → `tasks/personas/test_writer.md`
- `.claude/personas/judge.md` → `tasks/personas/judge.md`

Do not modify persona file content.

---

### Step 5 — Execution Files

Copy these files verbatim:
- `.claude/templates/RUN.md` → `tasks/RUN.md`
- `.claude/templates/BUILD_STATUS.md` → `tasks/BUILD_STATUS.md`
- `.claude/templates/loop.sh` → `loop.sh`

Make loop.sh executable:
```bash
chmod +x loop.sh
```

---

### Step 6 — ARCHITECTURE_REF.md

Produce `tasks/ARCHITECTURE_REF.md` — a condensed version of
{architecture_file} for use as agent context.

Rules:
- Maximum 200 lines
- Include: tech stack table, file/directory layout, key patterns and
  conventions, naming conventions, existing helpers to reuse
- Exclude: rationale prose, out of scope sections, lengthy descriptions
- Every agent invocation will read this file — keep it dense and useful,
  not comprehensive

---

### Step 7 — Validation

1. Count tasks in {tasks_file}
2. Count spec files in tasks/specs/
3. Count task sections in tasks/TASK_LIST.md (excluding FINAL JUDGE)
4. Confirm all three counts match
5. Confirm the last task JUDGE PASS cursor points to FINAL JUDGE
6. Confirm tasks/personas/ has developer.md, test_writer.md, judge.md
7. Confirm loop.sh is executable
8. Print output summary

## Output Summary Format

```
=== Agentic Scaffold Complete ===

Specs:          tasks/specs/          ({n} files)
Task list:      tasks/TASK_LIST.md    ({n} tasks)
Personas:       tasks/personas/       (developer, test_writer, judge)
Arch ref:       tasks/ARCHITECTURE_REF.md
Execution:      tasks/RUN.md, tasks/BUILD_STATUS.md, loop.sh

To run one step at a time:
  tools/run-claude-sandbox.sh --task-file tasks/RUN.md

To run automatically until complete or blocked:
  ./loop.sh
```

## Quality Rules

- All task IDs must be consistent across TASKS.md, specs/, and TASK_LIST.md
- The TASK_LIST.md cursor chain must be unbroken from first task to FINAL JUDGE
- No task entry may reference a spec file that doesn't exist
- Persona files must not be modified from the templates
- loop.sh and RUN.md must not be modified from the templates
