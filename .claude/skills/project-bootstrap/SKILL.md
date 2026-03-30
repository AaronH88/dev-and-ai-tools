# Skill: Project Bootstrap

## Purpose
Transform a requirements document or brainstorm notes into a complete
architecture document and task breakdown, ready to be handed to the
agentic-scaffold skill.

## When to Use This Skill
When starting a new software project and you have any of:
- A requirements document
- Brainstorm notes
- A rough description of what needs to be built
- A conversation summary of features and decisions

## Input
The user will provide a path to a requirements file, or paste requirements
directly. If no input is specified, look for `docs/requirements.md`.

## Process

Read the input requirements fully before producing any output.
Understand the complete scope before making architecture decisions.

---

### Step 1 — Architecture Document

Produce `docs/ARCHITECTURE.md`.

The document must cover every section below. Do not leave placeholder
sections — if something is unknown, make a reasonable decision and note
it as an assumption.

Required sections:

**Overview**
- What is this project
- Who uses it and how
- Core goals and non-goals

**Tech Stack**
- Every technology chosen with a one-line rationale
- Present as a table: Layer | Technology | Rationale

**System Architecture**
- How the pieces fit together
- ASCII diagram showing components and data flow

**Data Models**
- Every entity with all fields, types, and relationships
- Foreign keys and constraints stated explicitly

**API Design** (if applicable)
- Base path and conventions
- Every endpoint grouped by resource
- Method, path, description, request/response shape

**Frontend Structure** (if applicable)
- Directory layout
- Page and component breakdown
- State management approach

**Deployment Architecture**
- Where it runs and how
- Process management
- Data persistence strategy
- Backup approach

**Non-Functional Requirements**
- Performance expectations
- Security considerations
- Accessibility or device requirements

**Out of Scope (v1)**
- Explicit list of things not being built now

---

### Step 2 — Task Document

Produce `docs/TASKS.md`.

Break the architecture into discrete, implementable tasks.

Rules:
- Group tasks into phases that represent logical build stages
  (e.g. Phase 0 Setup, Phase 1 Backend Foundation, Phase 2 Frontend)
- Each task must be implementable in a single focused Claude Code session
- Each task must have explicit, verifiable acceptance criteria
  — acceptance criteria must be testable, not subjective
- Tasks must be strictly ordered — each one builds on previous tasks
- A developer reading only the task spec must have everything they need
- Use numeric IDs: 0.1, 1.1, 1.2, 2.1 etc.
- Include verify_scope per task: backend | frontend | both

Task document format:

```
## Phase 1 — [Phase Name]

### Task 1.1 — [Title]

[Full description of what to build]

**Acceptance criteria:** [List of specific, testable criteria]

**verify_scope:** backend | frontend | both
```

---

### Step 3 — Validation

Before finishing:
1. Read docs/ARCHITECTURE.md — does it have all required sections?
2. Read docs/TASKS.md — does every task have acceptance criteria?
3. Are tasks ordered correctly (no task depends on a later task)?
4. Print the output summary below

## Output Summary Format

```
=== Project Bootstrap Complete ===

Architecture: docs/ARCHITECTURE.md
  Sections: [list section headings]

Tasks: docs/TASKS.md
  [n] phases
  [n] total tasks

Next step:
  Review both documents and make any corrections.
  Then run the agentic scaffold skill:

  tools/run-claude-sandbox.sh --task "Read .claude/skills/agentic-scaffold/SKILL.md and scaffold this project from docs/TASKS.md"
```

## Quality Rules

- No placeholders or TODO sections in output files
- No references to example projects used during development
- Every task must be specific enough that a developer can implement it
  without asking questions
- Architecture decisions must be specific — "use FastAPI because X"
  not "use a web framework"
- Acceptance criteria must be verifiable by running code or tests,
  not by reading it
