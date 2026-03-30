# Tools

This directory contains development automation tools for the Baby Tracker project, including an agentic task orchestration system and a sandboxed Claude Code environment.

## Overview

The tools in this directory support an AI-assisted development workflow where tasks are:
1. Specified in markdown files
2. Executed by AI agents (Developer, Test Writer, Judge) in isolated roles
3. Verified automatically via test suites
4. Reviewed for quality before approval

## Tools

### run-claude-sandbox.sh

A Podman-based sandbox wrapper for running Claude Code in an isolated, controlled environment.

#### Features

- **Filesystem isolation**: Only mounts the current worktree - Claude cannot access files outside the project
- **Persistent auth**: Tokens stored in `~/.claude-sandbox/auth/` (isolated from host `~/.claude`)
- **Network modes**:
  - Unrestricted: full host network access (default)
  - Isolated: only project's podman-compose services
- **Runs with `--dangerously-skip-permissions`**: Claude can read/write all files in the worktree
- **Resource limits**: Configurable memory (default 4GB) and CPU (default 2 cores)

#### Usage Modes

**Interactive mode** (default):
```bash
tools/run-claude-sandbox.sh
# Drops you into an interactive Claude Code session
```

**Agentic mode** (automated task execution):
```bash
tools/run-claude-sandbox.sh --task "implement pagination on /jobs endpoint"

# Or from a file:
tools/run-claude-sandbox.sh --task-file tasks/specs/task-1.1.md
```

**Continue previous session:**
```bash
tools/run-claude-sandbox.sh --continue
```

**Resume specific session:**
```bash
tools/run-claude-sandbox.sh --resume abc123def456
# Or pick interactively:
tools/run-claude-sandbox.sh --resume
```

**Shell mode** (debugging):
```bash
tools/run-claude-sandbox.sh --shell
# Drops into a bash shell inside the container
```

**Command execution:**
```bash
tools/run-claude-sandbox.sh --exec "make test"
# Runs a single command and exits
```

#### Network Isolation

**Unrestricted mode** (default):
```bash
tools/run-claude-sandbox.sh --task "..."
# Can access localhost:8000, localhost:5432, etc.
```

**Isolated mode** (only project services):
```bash
tools/run-claude-sandbox.sh --isolated --task "..."
# Can only reach containers in the project's podman-compose network
```

#### Advanced Options

**Custom system prompt:**
```bash
tools/run-claude-sandbox.sh --task "..." \
  --append-system-prompt-file tasks/ARCHITECTURE_REF.md
```

**Custom subagents:**
```bash
tools/run-claude-sandbox.sh --task "..." \
  --agents '{"explore": {"description": "Custom explorer"}}'
```

#### Configuration

Environment variable overrides (set in `.env` or shell):

- `CLAUDE_SANDBOX_CONTAINERFILE`: Path to Containerfile (default: auto-detect)
- `CLAUDE_SANDBOX_IMAGE`: Image name (default: `localhost/claude-sandbox:latest`)
- `CLAUDE_SANDBOX_AUTH_DIR`: Auth directory (default: `~/.claude-sandbox/auth`)
- `CLAUDE_SANDBOX_MEMORY`: Memory limit (default: `4g`)
- `CLAUDE_SANDBOX_CPUS`: CPU limit (default: `2`)

#### First-Time Setup

1. **Create auth directory:**
   ```bash
   mkdir -p ~/.claude-sandbox/auth
   ```

2. **Run the sandbox:**
   ```bash
   tools/run-claude-sandbox.sh
   ```

3. **Authenticate:**
   - Claude will print a browser URL
   - Open it and sign in
   - Tokens are saved to `~/.claude-sandbox/auth/` and reused on future runs

4. **The Containerfile** should be in one of these locations:
   - `containers/claude-sandbox/Containerfile`
   - `.claude-sandbox/Containerfile`
   - `docker/claude-sandbox/Containerfile`
   - `Containerfile.claude-sandbox`

