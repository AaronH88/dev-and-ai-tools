# Dev and AI Tools

A collection of development automation tools centered around sandboxed Claude Code execution and multi-agent task orchestration.

## Overview

This repository provides:

1. **Claude Code Sandbox** — A secure, isolated Podman container for running Claude Code with filesystem and network isolation
2. **Agentic Task Orchestration** — A multi-agent workflow system where AI agents (Developer, Test Writer, Judge) collaborate to implement software projects
3. **Project Bootstrap Skills** — Custom Claude Code skills for scaffolding projects from requirements to executable workflows

## What's Inside

### 🔒 Claude Code Sandbox

A Podman-based wrapper (`tools/run-claude-sandbox.sh`) that runs Claude Code in an isolated container:

- **Filesystem isolation**: Only the current worktree is mounted — Claude cannot access files outside the project
- **Persistent authentication**: Auth tokens stored in `~/.claude-sandbox/auth/` (isolated from host `~/.claude`)
- **Network modes**: Unrestricted (default) or isolated to project's podman-compose services
- **Resource limits**: Configurable memory (default 4GB) and CPU (default 2 cores)
- **Unattended execution**: Runs with `--dangerously-skip-permissions` for full automation

### 🤖 Agentic Workflow System

An automated development loop where tasks flow through four stages:

1. **DEV** — Developer agent implements the task spec
2. **TEST** — Test Writer agent writes adversarial tests
3. **VERIFY** — Automated test suite execution
4. **JUDGE** — Judge agent reviews code quality on 5 dimensions (spec compliance, implementation quality, test quality, code reuse, slop detection)

Tasks that fail the Judge loop back with specific feedback. Tasks that pass advance to the next task. The build continues until all tasks are approved or a task becomes blocked after 3 attempts.

### 📋 Custom Skills

Three specialized skills for project automation:

- **project-bootstrap**: Transform requirements into complete architecture + task breakdown
- **agentic-scaffold**: Convert architecture docs into executable multi-agent workflows
- **deploy-update**: Safe production deployment with mandatory backup and verification

## Quick Start

### Prerequisites

- [Podman](https://podman.io/) installed
- Claude Code authentication (first run will prompt for browser login)

### Initial Setup

1. Create the auth directory:
   ```bash
   mkdir -p ~/.claude-sandbox/auth
   ```

2. Run the sandbox interactively to authenticate:
   ```bash
   tools/run-claude-sandbox.sh
   ```

   Claude will print a browser URL — open it and sign in. Tokens are saved and reused on future runs.

### Usage Examples

#### Interactive Mode

Drop into a live Claude Code session:
```bash
tools/run-claude-sandbox.sh
```

#### Agentic Mode (One-Shot Tasks)

Run a single task and exit:
```bash
# From a string:
tools/run-claude-sandbox.sh --task "implement pagination on /jobs endpoint"

# From a file:
tools/run-claude-sandbox.sh --task-file tasks/specs/task-1.1.md
```

#### Continue or Resume Sessions

```bash
# Continue the most recent session:
tools/run-claude-sandbox.sh --continue

# Resume a specific session:
tools/run-claude-sandbox.sh --resume abc123def456

# Pick a session interactively:
tools/run-claude-sandbox.sh --resume
```

#### Network Isolation

```bash
# Unrestricted (default) — can reach localhost:8000, localhost:5432, etc:
tools/run-claude-sandbox.sh --task "run the test suite"

# Isolated — only project's podman-compose services:
tools/run-claude-sandbox.sh --isolated --task "test the API integration"
```

#### Advanced Options

```bash
# Append additional context to system prompt:
tools/run-claude-sandbox.sh --task "implement auth" \
  --append-system-prompt-file tasks/ARCHITECTURE_REF.md

# Debug with shell access:
tools/run-claude-sandbox.sh --shell

# Execute a single command:
tools/run-claude-sandbox.sh --exec "make test"
```

## Automated Build Loop

For multi-task projects, the agentic workflow automates the entire build:

```bash
# Run tasks continuously until approved or blocked:
./loop.sh
```

The loop:
1. Runs `tools/run-claude-sandbox.sh --task-file tasks/RUN.md`
2. Checks `tasks/BUILD_STATUS.md`
3. Continues if status is `PENDING`, exits if `APPROVED` or `FAILED`

## Project Structure

```
.claude/
├── personas/              # Template persona files
│   ├── developer.md       # Implementation role
│   ├── judge.md          # Quality gatekeeper role
│   └── test_writer.md    # Adversarial testing role
├── skills/               # Custom Claude Code skills
│   ├── agentic-scaffold/
│   ├── deploy-update/
│   └── project-bootstrap/
├── templates/            # Templates for agentic workflow
│   ├── BUILD_STATUS.md
│   ├── RUN.md
│   ├── TASK_LIST.md
│   └── loop.sh
└── settings.local.json   # Claude settings

containers/
└── claude-sandbox/
    └── Containerfile     # Container definition (Node 22 + Python 3 + uv)

tools/
├── run-claude-sandbox.sh # Main sandbox wrapper script
└── README.md            # Detailed sandbox documentation

loop.sh                  # Automated build loop
```

## Creating a New Project with Agentic Workflow

### Step 1: Bootstrap from Requirements

Create a `docs/requirements.md` file with your project requirements, then:

```bash
tools/run-claude-sandbox.sh --task "Read .claude/skills/project-bootstrap/SKILL.md and bootstrap from docs/requirements.md"
```

This produces:
- `docs/ARCHITECTURE.md` — Complete technical design
- `docs/TASKS.md` — Ordered task breakdown with acceptance criteria

### Step 2: Review and Approve

Review both documents and make any corrections. These are the blueprints for your automated build.

### Step 3: Scaffold the Workflow

```bash
tools/run-claude-sandbox.sh --task "Read .claude/skills/agentic-scaffold/SKILL.md and scaffold from docs/TASKS.md and docs/ARCHITECTURE.md"
```

This produces:
- `tasks/specs/task-{id}.md` — Individual task specifications
- `tasks/TASK_LIST.md` — Master checklist with cursor tracking
- `tasks/personas/` — Agent role definitions
- `tasks/ARCHITECTURE_REF.md` — Condensed reference for agents
- `tasks/RUN.md` and `tasks/BUILD_STATUS.md` — Execution control files
- `loop.sh` — Executable build loop

### Step 4: Run the Build

One step at a time:
```bash
tools/run-claude-sandbox.sh --task-file tasks/RUN.md
```

Or fully automated:
```bash
./loop.sh
```

The system will:
1. Read the `→ NEXT:` cursor in `tasks/TASK_LIST.md`
2. Load the appropriate persona
3. Execute the current stage (DEV/TEST/VERIFY/JUDGE)
4. Update checkboxes and move the cursor
5. Repeat until approved or blocked

## How the Agentic Workflow Works

### Task Flow

Each task goes through four stages:

```
┌─────────┐     ┌──────────┐     ┌────────┐     ┌───────┐
│   DEV   │ --> │   TEST   │ --> │ VERIFY │ --> │ JUDGE │
│ persona │     │ persona  │     │  auto  │     │persona│
└─────────┘     └──────────┘     └────────┘     └───────┘
                                       │              │
                                       │              │
                                   FAIL│          FAIL│
                                       │              │
                                       └──────┬───────┘
                                              │
                                              ↓
                                    Loop back to DEV
                                    (with feedback)
```

- **DEV**: Implements exactly what's in the spec, commits with `git commit -m "dev: task {id}"`
- **TEST**: Writes adversarial tests to find gaps, commits with `git commit -m "test: task {id}"`
- **VERIFY**: Runs the test suite (command varies by scope: backend/frontend/both)
- **JUDGE**: Scores on 5 dimensions, writes verdict to `tasks/feedback/task-{id}-judge.md`

### Judge Scoring Dimensions

1. **Spec Compliance** — Are all acceptance criteria met? (Blocking if < 4/5)
2. **Implementation Quality** — Is the code simple and structurally sound? (Blocking if < 3/5)
3. **Test Quality** — Do tests meaningfully verify functionality? (Blocking if < 3/5)
4. **Code Reuse & Consistency** — Does it follow existing patterns? (Blocking if < 3/5)
5. **Slop Detection** — Is it free of AI-generated padding? (Blocking if < 3/5)

### Slop Detection

The Judge rejects implementations with:
- Comments that restate code
- Generic variable names (`result`, `data`, `response`, `temp`, `obj`)
- Pass-through functions
- Defensive null checks on things that cannot be null
- Trivially-passing tests (`assert True`)
- Unused imports/variables
- TODO/FIXME comments
- Code written to look thorough rather than be thorough

### Retry Logic

If the Judge returns `FAIL`:
1. All checkboxes for DEV/TEST/VERIFY/JUDGE are unchecked
2. Attempt counters increment
3. If any counter exceeds 3, the task is marked `[BLOCKED]` and the build stops
4. Otherwise, cursor moves back to DEV with feedback file reference updated
5. Developer reads the feedback and addresses all Required Fixes

## Configuration

Environment variables (set in `.env` or shell):

| Variable | Default | Description |
|----------|---------|-------------|
| `CLAUDE_SANDBOX_CONTAINERFILE` | (auto-detected) | Path to Containerfile relative to repo root |
| `CLAUDE_SANDBOX_IMAGE` | `localhost/claude-sandbox:latest` | Image name |
| `CLAUDE_SANDBOX_AUTH_DIR` | `~/.claude-sandbox/auth` | Auth token directory |
| `CLAUDE_SANDBOX_MEMORY` | `4g` | Memory limit |
| `CLAUDE_SANDBOX_CPUS` | `2` | CPU limit |

The sandbox script automatically loads all variables from `.env` and forwards them into the container.

## Portability

The sandbox system is project-agnostic. To use in a different project:

1. Copy `tools/run-claude-sandbox.sh` to your project
2. Copy `containers/claude-sandbox/Containerfile` to one of these locations:
   - `containers/claude-sandbox/Containerfile`
   - `.claude-sandbox/Containerfile`
   - `docker/claude-sandbox/Containerfile`
   - `Containerfile.claude-sandbox`
3. Ensure your project has a `.env` file (the script walks up from current directory to find it)
4. Run `mkdir -p ~/.claude-sandbox/auth && tools/run-claude-sandbox.sh` to authenticate

## Tips

- **First run**: Use interactive mode to test the sandbox before running automated tasks
- **Debugging**: Use `--shell` mode to debug container issues
- **Task specs**: Be specific in acceptance criteria — vague criteria lead to Judge failures
- **Personas are strict**: The Judge is designed to reject low-quality work by default
- **Feedback is specific**: Judge verdicts include file:line references for every Required Fix
- **View sessions**: Sessions are stored in the container's `~/.claude` directory (persisted via volume mount)

## License

This repository is for development tooling and automation. Adapt freely for your projects.
