# Dev and AI Tools

A collection of development automation tools for AI-assisted software development. Write requirements, let AI agents build it.

## My Development Workflow

This is how I build software with this toolkit:

### Step 1: Write Requirements

Create `docs/requirements.md` describing what I want to build:
- Features and functionality
- User stories or use cases
- Technical constraints or preferences
- Any other context

### Step 2: Generate Architecture and Tasks

Run the `project-bootstrap` skill to transform requirements into concrete plans:

```bash
tools/run-claude-sandbox.sh --task "Read .claude/skills/project-bootstrap/SKILL.md and bootstrap from docs/requirements.md"
```

This produces:
- `docs/ARCHITECTURE.md` — Complete technical design (tech stack, data models, API design, deployment architecture)
- `docs/TASKS.md` — Ordered task breakdown with acceptance criteria and verify scopes

I review both documents and make any corrections before proceeding.

### Step 3: Scaffold the Agentic Workflow

Run the `agentic-scaffold` skill to convert the plans into an executable workflow:

```bash
tools/run-claude-sandbox.sh --task "Read .claude/skills/agentic-scaffold/SKILL.md and scaffold from docs/TASKS.md and docs/ARCHITECTURE.md"
```

This creates:
- `tasks/specs/task-{id}.md` — Individual task specifications
- `tasks/TASK_LIST.md` — Master checklist with cursor tracking
- `tasks/personas/` — Agent role definitions (Developer, Test Writer, Judge)
- `tasks/ARCHITECTURE_REF.md` — Condensed architecture reference
- `loop.sh` — Automated build loop script

### Step 4: Run the Build Loop

Execute the automated build process:

```bash
./loop.sh
```

The loop runs continuously, executing each task through four stages:

```
┌─────────┐     ┌──────────┐     ┌────────┐     ┌───────┐
│   DEV   │ --> │   TEST   │ --> │ VERIFY │ --> │ JUDGE │
│ persona │     │ persona  │     │  auto  │     │persona│
└─────────┘     └──────────┘     └────────┘     └───────┘
     ↑                                  │              │
     │                              FAIL│          FAIL│
     │                                  │              │
     └──────────────────────────────────┴──────────────┘
                    Loop back with feedback
```

- **DEV**: Implements the task spec
- **TEST**: Writes adversarial tests
- **VERIFY**: Runs the test suite
- **JUDGE**: Scores code quality on 5 dimensions

Tasks that fail loop back with specific feedback. Tasks that pass advance to the next task. The build continues until all tasks are approved or a task becomes blocked after 3 retry attempts.

The loop exits when `tasks/BUILD_STATUS.md` shows either:
- `APPROVED` — All tasks passed, build is complete
- `FAILED` — A task was blocked after 3 attempts or the final judge rejected the build

### Step 5: Review and Push

When the build completes successfully, I push to git for review:

```bash
git push
```

All implementation commits, test commits, and judge verdicts are in the git history, making it easy to review what was built and why.

---

## What's Inside

This repository provides three main components:

### 🔒 Claude Code Sandbox

A Podman-based wrapper (`tools/run-claude-sandbox.sh`) that runs Claude Code in an isolated container:

- **Filesystem isolation**: Only the current worktree is mounted — Claude cannot access files outside the project
- **Persistent authentication**: Auth tokens stored in `~/.claude-sandbox/auth/` (isolated from host `~/.claude`)
- **Network modes**: Unrestricted (default) or isolated to project's podman-compose services
- **Resource limits**: Configurable memory (default 4GB) and CPU (default 2 cores)
- **Unattended execution**: Runs with `--dangerously-skip-permissions` for full automation

### 🤖 Agentic Workflow System

An automated development loop where tasks flow through four stages with three specialized AI personas:

**Developer Persona**
- Implements exactly what's in the spec, no more/less
- Follows architecture and existing patterns
- Self-reviews before committing
- Commits with `git commit -m "dev: task {id}"`

**Test Writer Persona**
- Writes adversarial tests to find gaps the developer missed
- Covers all acceptance criteria and failure paths
- Tests behavior through public interfaces
- Commits with `git commit -m "test: task {id}"`

**Judge Persona**
- Scores on 5 dimensions (spec compliance, implementation quality, test quality, code reuse, slop detection)
- Rejects low-quality work with specific Required Fixes
- Not helpful, not encouraging — a strict gatekeeper against technical debt
- Writes verdicts to `tasks/feedback/task-{id}-judge.md`

### 📋 Custom Skills

Three specialized skills for project automation:

- **project-bootstrap**: Transform requirements into complete architecture + task breakdown
- **agentic-scaffold**: Convert architecture docs into executable multi-agent workflows
- **deploy-update**: Safe production deployment with mandatory backup and verification

---

## Initial Setup

### Prerequisites

- [Podman](https://podman.io/) installed
- Claude Code authentication

### First Time Setup

1. Create the auth directory:
   ```bash
   mkdir -p ~/.claude-sandbox/auth
   ```

2. Run the sandbox interactively to authenticate:
   ```bash
   tools/run-claude-sandbox.sh
   ```

   Claude will print a browser URL — open it and sign in. Tokens are saved and reused on future runs.

3. Copy the environment template:
   ```bash
   cp .env.example .env
   ```

   Edit `.env` if you need to customize resource limits or paths (defaults work for most cases).

---

## Sandbox Usage Reference

The sandbox wrapper (`tools/run-claude-sandbox.sh`) supports various modes beyond the automated workflow.

### Interactive Mode

Drop into a live Claude Code session:
```bash
tools/run-claude-sandbox.sh
```

### One-Shot Tasks

Run a single task and exit:
```bash
# From a string:
tools/run-claude-sandbox.sh --task "implement pagination on /jobs endpoint"

# From a file:
tools/run-claude-sandbox.sh --task-file tasks/specs/task-1.1.md
```

### Session Management

```bash
# Continue the most recent session:
tools/run-claude-sandbox.sh --continue

# Resume a specific session:
tools/run-claude-sandbox.sh --resume abc123def456

# Pick a session interactively:
tools/run-claude-sandbox.sh --resume
```

### Network Isolation

```bash
# Unrestricted (default) — can reach localhost:8000, localhost:5432, etc:
tools/run-claude-sandbox.sh --task "run the test suite"

# Isolated — only project's podman-compose services:
tools/run-claude-sandbox.sh --isolated --task "test the API integration"
```

### Advanced Options

```bash
# Append additional context to system prompt:
tools/run-claude-sandbox.sh --task "implement auth" \
  --append-system-prompt-file tasks/ARCHITECTURE_REF.md

# Debug with shell access:
tools/run-claude-sandbox.sh --shell

# Execute a single command:
tools/run-claude-sandbox.sh --exec "make test"
```

---

## How the Judge Works

The Judge persona scores each task on 5 dimensions, rating 1–5 and marking each as blocking or non-blocking:

### 1. Spec Compliance
Does the implementation meet every acceptance criterion?
- **Blocking if score < 4/5**

### 2. Implementation Quality
Is the code simple, readable, and structurally sound?
- **Blocking if score < 3/5**

### 3. Test Quality
Do the tests meaningfully verify functionality?
- **Blocking if score < 3/5**

### 4. Code Reuse & Consistency
Does it follow existing patterns and use existing helpers?
- **Blocking if score < 3/5**

### 5. Slop Detection
Is it free of AI-generated padding and noise?
- **Blocking if score < 3/5**

### Slop Indicators

The Judge rejects implementations with:
- Comments that restate code
- Generic variable names (`result`, `data`, `response`, `temp`, `obj`)
- Pass-through functions that just call one other function
- Defensive null checks on things that cannot be null
- Trivially-passing tests (`assert True`, `assert x is not None`)
- Docstrings on self-explanatory functions
- Unused imports or variables
- TODO/FIXME comments in submitted code
- Code written to look thorough rather than be thorough

### Retry Logic

If the Judge returns `FAIL`:
1. All checkboxes for DEV/TEST/VERIFY/JUDGE are unchecked
2. Attempt counters increment
3. If any counter exceeds 3, the task is marked `[BLOCKED]` and the build stops
4. Otherwise, cursor moves back to DEV with feedback file reference updated
5. Developer reads the feedback and addresses all Required Fixes

---

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
.env.example            # Environment configuration template
```

---

## Configuration

Environment variables (set in `.env`):

| Variable | Default | Description |
|----------|---------|-------------|
| `PODMAN_PROJECT` | (basename of worktree) | Project identifier for container/network naming |
| `NEXUS_SLOT` | `0` | Slot number for parallel sandbox instances |
| `CLAUDE_SANDBOX_IMAGE` | `localhost/claude-sandbox:latest` | Container image name |
| `CLAUDE_SANDBOX_CONTAINERFILE` | (auto-detected) | Path to Containerfile |
| `CLAUDE_SANDBOX_AUTH_DIR` | `~/.claude-sandbox/auth` | Auth token directory |
| `CLAUDE_SANDBOX_MEMORY` | `4g` | Memory limit |
| `CLAUDE_SANDBOX_CPUS` | `2` | CPU limit |

All variables from `.env` are automatically forwarded into the container.

---

## Portability

The sandbox system is project-agnostic. To use in a different project:

1. Copy `tools/run-claude-sandbox.sh` to your project
2. Copy `containers/claude-sandbox/Containerfile` to one of these locations:
   - `containers/claude-sandbox/Containerfile`
   - `.claude-sandbox/Containerfile`
   - `docker/claude-sandbox/Containerfile`
   - `Containerfile.claude-sandbox`
3. Ensure your project has a `.env` file with at least `PODMAN_PROJECT` set
4. Run `mkdir -p ~/.claude-sandbox/auth && tools/run-claude-sandbox.sh` to authenticate

The skills (project-bootstrap, agentic-scaffold) can be copied to any project's `.claude/skills/` directory.

---

## Tips

- **Spec quality matters**: Specific acceptance criteria in `docs/requirements.md` lead to better task breakdowns and fewer Judge failures
- **Review before scaffolding**: Fix any issues in `docs/ARCHITECTURE.md` and `docs/TASKS.md` before running agentic-scaffold — changing them after requires re-scaffolding
- **Let it run**: The loop is designed to run unattended — resist the urge to intervene mid-task
- **Judge feedback is specific**: Failed tasks get file:line references for every Required Fix
- **Three strikes**: After 3 failed attempts, a task is marked `[BLOCKED]` and you need to manually investigate
- **Git history tells the story**: Each task creates 2-4 commits (dev, test, sometimes retry iterations) — use `git log` to see what happened

---

## License

This repository is for development tooling and automation. Adapt freely for your projects.
