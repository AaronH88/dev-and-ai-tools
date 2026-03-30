# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Purpose

This is a development and AI tools repository containing:
- **Claude Code Sandbox**: A Podman-based isolated execution environment for running Claude Code safely
- **Agentic Task Orchestration**: A multi-agent workflow system (Developer → Test Writer → Judge) for automated software development
- **Project Bootstrap Skills**: Custom skills for scaffolding and managing AI-assisted development workflows

## Architecture Overview

### Sandboxed Execution Environment

The repository provides `tools/run-claude-sandbox.sh`, a wrapper script that:
- Runs Claude Code inside a Podman container with filesystem isolation
- Mounts only the current worktree (Claude cannot access files outside the project)
- Persists auth tokens in `~/.claude-sandbox/auth/` (isolated from host `~/.claude`)
- Supports network isolation modes (unrestricted or isolated to podman-compose services)
- Runs with `--dangerously-skip-permissions` inside the container for unattended automation
- Resource limits: 4GB memory, 2 CPUs (configurable via environment variables)

### Agentic Workflow System

Tasks flow through a four-stage cycle:
1. **DEV** (Developer persona) — Implements the task spec
2. **TEST** (Test Writer persona) — Writes tests for the implementation
3. **VERIFY** — Runs test suite to confirm functionality
4. **JUDGE** (Judge persona) — Reviews code quality and decides PASS/FAIL

Tasks are defined in:
- `tasks/specs/task-{id}.md` — Individual task specifications
- `tasks/TASK_LIST.md` — Master checklist with `→ NEXT:` cursor tracking current task
- `tasks/RUN.md` — Entry point that reads TASK_LIST and executes the next task
- `tasks/BUILD_STATUS.md` — Tracks overall build state (PENDING/APPROVED/FAILED)

The `loop.sh` script runs `tools/run-claude-sandbox.sh --task-file tasks/RUN.md` repeatedly until the build is approved or blocked.

### Persona System

Each stage uses a different persona file that defines the agent's role, mandate, and constraints:
- `tasks/personas/developer.md` — Focus on implementing exactly what's in the spec, no more/less
- `tasks/personas/test_writer.md` — Adversarial testing to find gaps the developer missed
- `tasks/personas/judge.md` — Gatekeeping role that scores implementations on 5 dimensions and blocks low-quality work

## Key Commands

### Running the Sandbox

**Interactive mode** (manual Claude Code session):
```bash
tools/run-claude-sandbox.sh
```

**Agentic mode** (automated task execution):
```bash
# From a string:
tools/run-claude-sandbox.sh --task "implement pagination on /jobs endpoint"

# From a file:
tools/run-claude-sandbox.sh --task-file tasks/RUN.md
```

**Continue/resume sessions**:
```bash
# Continue last session:
tools/run-claude-sandbox.sh --continue

# Resume a specific session:
tools/run-claude-sandbox.sh --resume abc123def456

# Pick a session interactively:
tools/run-claude-sandbox.sh --resume
```

**Network isolation**:
```bash
# Unrestricted (default) — can reach localhost:8000, localhost:5432, etc:
tools/run-claude-sandbox.sh --task "..."

# Isolated — can only reach project's podman-compose services:
tools/run-claude-sandbox.sh --isolated --task "..."
```

**Advanced options**:
```bash
# Append system prompt from a file:
tools/run-claude-sandbox.sh --task "..." \
  --append-system-prompt-file tasks/ARCHITECTURE_REF.md

# Custom subagents (JSON):
tools/run-claude-sandbox.sh --task "..." \
  --agents '{"explore": {"description": "Custom explorer"}}'

# Shell mode (debugging):
tools/run-claude-sandbox.sh --shell

# Execute a single command:
tools/run-claude-sandbox.sh --exec "make test"
```

### Automated Build Loop

```bash
# Run tasks continuously until approved or blocked:
./loop.sh

# One step at a time:
tools/run-claude-sandbox.sh --task-file tasks/RUN.md
```

## Available Skills

The repository includes three custom skills in `.claude/skills/`:

### 1. project-bootstrap

**Purpose**: Transform requirements into architecture + task breakdown

**When to use**: Starting a new software project from requirements

**Input**: Path to requirements file (defaults to `docs/requirements.md`)

**Outputs**:
- `docs/ARCHITECTURE.md` — Complete technical design with tech stack, data models, API design, deployment architecture
- `docs/TASKS.md` — Ordered task breakdown with phases, descriptions, acceptance criteria, and verify scopes

**Usage**:
```bash
tools/run-claude-sandbox.sh --task "Read .claude/skills/project-bootstrap/SKILL.md and bootstrap from docs/requirements.md"
```

### 2. agentic-scaffold

**Purpose**: Convert ARCHITECTURE.md + TASKS.md into executable agentic workflow

**When to use**: After project-bootstrap produces approved documentation

**Input**:
- `tasks_file` — Path to task document (e.g., `docs/TASKS.md`)
- `architecture_file` — Path to architecture document (e.g., `docs/ARCHITECTURE.md`)

**Outputs**:
- `tasks/specs/task-{id}.md` — One spec file per task
- `tasks/TASK_LIST.md` — Master checklist with DEV/TEST/VERIFY/JUDGE entries for each task
- `tasks/personas/` — Copies of developer.md, test_writer.md, judge.md
- `tasks/ARCHITECTURE_REF.md` — Condensed architecture reference for agents (<200 lines)
- `tasks/RUN.md`, `tasks/BUILD_STATUS.md` — Execution control files
- `loop.sh` — Executable loop script

**Usage**:
```bash
tools/run-claude-sandbox.sh --task "Read .claude/skills/agentic-scaffold/SKILL.md and scaffold from docs/TASKS.md and docs/ARCHITECTURE.md"
```

### 3. deploy-update

**Purpose**: Safely update a deployed application (backup → pull → deploy → verify)

**When to use**: Deploying changes to a production instance with live data

**Assumptions**:
- App deployed on Linux server (LXC/VM/bare metal)
- Repo cloned at known path with `deploy/update.sh` and `deploy/backup.sh` scripts
- Service managed by systemd

**Workflow**: Backup (mandatory) → Check current state → Pull latest → Run update script → Verify service/API/data integrity

## File Structure

```
.claude/
  personas/          # Template persona files (copied to tasks/personas/)
    developer.md
    judge.md
    test_writer.md
  skills/            # Custom Claude Code skills
    agentic-scaffold/
    deploy-update/
    project-bootstrap/
  templates/         # Templates for agentic workflow
    BUILD_STATUS.md
    RUN.md
    TASK_LIST.md
    loop.sh
  settings.local.json  # Claude settings (MCP servers)

containers/
  claude-sandbox/
    Containerfile    # Container definition for sandboxed Claude environment

tools/
  run-claude-sandbox.sh  # Main wrapper script for running Claude in Podman
  README.md             # Detailed documentation for the sandbox

loop.sh              # Automated build loop (runs RUN.md until approved/blocked)
```

## Configuration

Environment variables (set in `.env` or shell):
- `CLAUDE_SANDBOX_CONTAINERFILE` — Path to Containerfile (auto-detected if not set)
- `CLAUDE_SANDBOX_IMAGE` — Image name (default: `localhost/claude-sandbox:latest`)
- `CLAUDE_SANDBOX_AUTH_DIR` — Auth token directory (default: `~/.claude-sandbox/auth`)
- `CLAUDE_SANDBOX_MEMORY` — Memory limit (default: `4g`)
- `CLAUDE_SANDBOX_CPUS` — CPU limit (default: `2`)

The sandbox script automatically loads all variables from `.env` and forwards them into the container via `--env-file`.

## Portability

The sandbox system is project-agnostic. To use in a new project:
1. Copy `tools/run-claude-sandbox.sh` to the new project
2. Copy `containers/claude-sandbox/Containerfile` to one of these locations:
   - `containers/claude-sandbox/Containerfile`
   - `.claude-sandbox/Containerfile`
   - `docker/claude-sandbox/Containerfile`
   - `Containerfile.claude-sandbox`
3. Ensure the project has a `.env` file (script walks up from current directory to find it)
4. First run: `mkdir -p ~/.claude-sandbox/auth && tools/run-claude-sandbox.sh` to authenticate

## Key Patterns

### Task Specifications

Each task spec in `tasks/specs/task-{id}.md` follows a fixed format:
```markdown
# Task {id} — {title}

## Phase
{phase number}

## Description
{full description}

## Acceptance Criteria
{testable criteria}

## Verify Scope
backend | frontend | both
```

The verify scope determines which test command runs in the VERIFY stage.

### TASK_LIST.md Cursor

The file uses a `→ NEXT:` cursor to track the current task. Each task entry:
1. Lists the specific persona file to use
2. Specifies which files to read (specs, feedback, diffs)
3. Defines the exact actions to take and git commit format
4. Updates the cursor to point to the next step on completion

### Judge Verdicts

Judge output must begin with YAML frontmatter:
```yaml
---
task: "task_id"
iteration: n
role_under_review: developer | test_writer | both
verdict: pass | fail | pass_with_concerns
retry_target: developer | test_writer | both
loop_back: true | false
---
```

Followed by:
- Scorecard (5 dimensions rated 1-5, marked blocking/non-blocking)
- Verdict summary (2-3 sentences, direct and unencouraging)
- Required fixes (if loop_back: true)
- Concerns (non-blocking issues for final review)

### Slop Detection

The Judge persona is trained to detect AI-generated "slop":
- Comments that restate code
- Generic variable names (`result`, `data`, `response`, `temp`, `obj`, `val`)
- Pass-through functions
- Defensive null checks on things that cannot be null
- Trivially-passing tests (`assert True`)
- Docstrings on self-explanatory functions
- Unused imports/variables
- TODO/FIXME comments in submitted code
- Code written to look thorough rather than be thorough

Pervasive slop (score < 3 on dimension 5) is blocking.

## Working with This Repository

When modifying or extending this repository:
- Test sandbox changes with `--shell` mode first before running automated tasks
- The personas are designed to be strict — they enforce quality by default
- The TASK_LIST.md format is rigid by design — agents expect exact patterns
- Skills are meant to be composed: bootstrap → scaffold → loop
- The containerfile uses Node 22 + Python 3 + uv package manager
- The sandbox runs as the `node` user (uid 1000), not root
