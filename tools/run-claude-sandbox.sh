#!/usr/bin/env bash
# Run Claude Code inside a Podman sandbox container with --dangerously-skip-permissions
#
# The container mounts only the current worktree — Claude cannot access anything
# outside it. Auth tokens are persisted in ~/.claude-sandbox/auth on the host.
#
# MODES:
#   (no flag)                  Interactive: drop into a live Claude Code session
#   --task "do something"      Agentic: Claude runs the task unattended then exits
#   --task-file <path>         Agentic: task is read from a file in the worktree
#   --shell                    Debug: plain bash shell inside the container
#   --exec "make test"         Command: run a single command and exit
#
# SESSION:
#   --continue                 Resume the most recent Claude Code session
#   --resume [session-id]      Pick a session interactively or resume a specific session ID
#
# COMPOSABLE FLAGS:
#   --append-system-prompt-file <path>   Append additional system prompt from file
#   --agents <json>                      Define custom subagents (JSON passed through)
#
# NETWORK:
#   (no flag)                  Unrestricted: can reach all local services
#   --isolated                 Restricted: only this worktree's podman-compose services
#
# EXAMPLES:
#   tools/run-claude-sandbox.sh
#   tools/run-claude-sandbox.sh --task "add pagination to the /jobs endpoint"
#   tools/run-claude-sandbox.sh --task-file tasks/implement-auth.md
#   tools/run-claude-sandbox.sh --continue
#   tools/run-claude-sandbox.sh --continue --task "now write the tests"
#   tools/run-claude-sandbox.sh --resume
#   tools/run-claude-sandbox.sh --resume abc123def456
#   tools/run-claude-sandbox.sh --task "..." --append-system-prompt-file tasks/AGENT_CONTEXT.md
#   tools/run-claude-sandbox.sh --shell
#   tools/run-claude-sandbox.sh --exec "make test"
#   tools/run-claude-sandbox.sh --isolated --task "fix the flaky test in test_jobs.py"
#
# CONFIGURATION (environment variable overrides):
#   CLAUDE_SANDBOX_CONTAINERFILE  Containerfile path relative to repo root
#   CLAUDE_SANDBOX_IMAGE          Sandbox image name (default: localhost/claude-sandbox:latest)
#   CLAUDE_SANDBOX_AUTH_DIR       Auth token directory (default: ~/.claude-sandbox/auth)
#   CLAUDE_SANDBOX_MEMORY         Memory limit (default: 4g)
#   CLAUDE_SANDBOX_CPUS           CPU limit (default: 2)
#
# PORTABILITY:
#   This script is self-contained and project-agnostic. To use in a new project:
#   1. Copy this script to tools/run-claude-sandbox.sh and chmod +x
#   2. Copy the Containerfile to one of the supported locations (searched in order):
#        containers/claude-sandbox/Containerfile
#        .claude-sandbox/Containerfile
#        docker/claude-sandbox/Containerfile
#        Containerfile.claude-sandbox
#   3. Ensure your project has a .env file with PODMAN_PROJECT set
#   All variables from .env are forwarded into the container automatically.
#
# FIRST RUN (auth setup):
#   mkdir -p ~/.claude-sandbox/auth
#   tools/run-claude-sandbox.sh
#   # Claude Code will print a browser URL — open it to authenticate
#   # Tokens are saved to ~/.claude-sandbox/auth and reused on future runs

set -euo pipefail

# ── Constants (all overridable via environment variables) ──────────────────────
SANDBOX_IMAGE="${CLAUDE_SANDBOX_IMAGE:-localhost/claude-sandbox:latest}"
CONTAINER_WORKDIR="/workspace"
MEMORY_LIMIT="${CLAUDE_SANDBOX_MEMORY:-4g}"
CPU_LIMIT="${CLAUDE_SANDBOX_CPUS:-2}"
AUTH_DIR="${CLAUDE_SANDBOX_AUTH_DIR:-${HOME}/.claude-sandbox/auth}"
CONTAINERFILE_PATH="${CLAUDE_SANDBOX_CONTAINERFILE:-}"

# ── Colors ─────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()    { echo -e "${BLUE}ℹ${NC} $1"; }
success() { echo -e "${GREEN}✓${NC} $1"; }
warning() { echo -e "${YELLOW}⚠${NC} $1"; }
error()   { echo -e "${RED}✗${NC} $1" >&2; }
die()     { error "$1"; exit 1; }

# ── Argument parsing ───────────────────────────────────────────────────────────
ISOLATED=false
MODE="interactive"
TASK=""
TASK_FILE=""
EXEC_CMD=""
SESSION_FLAG=""
SESSION_ID=""
APPEND_SYSTEM_PROMPT_FILE=""
AGENTS_JSON=""

while [ $# -gt 0 ]; do
    case "$1" in
        --isolated)
            ISOLATED=true
            shift
            ;;
        --task)
            [ $# -lt 2 ] && die "--task requires a value"
            MODE="agentic"
            TASK="$2"
            shift 2
            ;;
        --task-file)
            [ $# -lt 2 ] && die "--task-file requires a path"
            MODE="agentic-file"
            TASK_FILE="$2"
            shift 2
            ;;
        --continue)
            [ -n "$SESSION_FLAG" ] && die "--continue and --resume are mutually exclusive"
            SESSION_FLAG="continue"
            shift
            ;;
        --resume)
            [ -n "$SESSION_FLAG" ] && die "--continue and --resume are mutually exclusive"
            SESSION_FLAG="resume"
            if [ $# -gt 1 ] && [[ ! "$2" =~ ^-- ]]; then
                SESSION_ID="$2"
                shift 2
            else
                shift
            fi
            ;;
        --append-system-prompt-file)
            [ $# -lt 2 ] && die "--append-system-prompt-file requires a path"
            APPEND_SYSTEM_PROMPT_FILE="$2"
            shift 2
            ;;
        --agents)
            [ $# -lt 2 ] && die "--agents requires JSON"
            AGENTS_JSON="$2"
            shift 2
            ;;
        --shell)
            MODE="shell"
            shift
            ;;
        --exec)
            [ $# -lt 2 ] && die "--exec requires a command"
            MODE="exec"
            EXEC_CMD="$2"
            shift 2
            ;;
        --help|-h)
            sed -n '2,65p' "$0" | grep '^#' | sed 's/^# \?//'
            exit 0
            ;;
        *)
            die "Unknown argument: $1. Use --help for usage."
            ;;
    esac
done

# ── Validate environment ───────────────────────────────────────────────────────
if ! command -v podman &>/dev/null; then
    die "podman not found. Please install Podman."
fi

if [ ! -d "$AUTH_DIR" ]; then
    info "Creating Claude auth directory: $AUTH_DIR"
    mkdir -p "$AUTH_DIR"
fi

# ── Find .env — walk up from current dir to git root ──────────────────────────
ENV_FILE=""
WORKTREE_ROOT=""
SEARCH_DIR="$(pwd)"
GIT_ROOT=""

if git rev-parse --git-dir &>/dev/null 2>&1; then
    GIT_ROOT=$(git rev-parse --show-toplevel)
fi

while [ "$SEARCH_DIR" != "/" ]; do
    if [ -f "$SEARCH_DIR/.env" ]; then
        ENV_FILE="$SEARCH_DIR/.env"
        WORKTREE_ROOT="$SEARCH_DIR"
        break
    fi
    [ "$SEARCH_DIR" = "$GIT_ROOT" ] && break
    SEARCH_DIR="$(dirname "$SEARCH_DIR")"
done

[ -n "$ENV_FILE" ] || die "No .env file found. Run this script from inside a project or worktree directory."

info "Using .env:    $ENV_FILE"
info "Worktree root: $WORKTREE_ROOT"

# Load .env into the current shell so we can read PODMAN_PROJECT and slot vars.
# All vars are also forwarded into the container wholesale via --env-file.
if [ -f "$ENV_FILE" ]; then
    set -a
    while IFS= read -r line; do
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$line" ]] && continue
        [[ "$line" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]] && eval "export ${line%%#*}"
    done < "$ENV_FILE"
    set +a
fi

# Only these two are needed by the script itself — everything else goes via --env-file
NEXUS_SLOT="${NEXUS_SLOT:-0}"
PODMAN_PROJECT="${PODMAN_PROJECT:-$(basename "$WORKTREE_ROOT")}"

# ── Resolve --append-system-prompt-file ───────────────────────────────────────
if [ -n "$APPEND_SYSTEM_PROMPT_FILE" ]; then
    if [ ! "${APPEND_SYSTEM_PROMPT_FILE:0:1}" = "/" ]; then
        APPEND_SYSTEM_PROMPT_FILE="${WORKTREE_ROOT}/${APPEND_SYSTEM_PROMPT_FILE}"
    fi
    [ -f "$APPEND_SYSTEM_PROMPT_FILE" ] || \
        die "System prompt file not found: $APPEND_SYSTEM_PROMPT_FILE"
    case "$APPEND_SYSTEM_PROMPT_FILE" in
        "$WORKTREE_ROOT"/*) ;;
        *) die "System prompt file must be inside the worktree: $APPEND_SYSTEM_PROMPT_FILE" ;;
    esac
    info "System prompt file: $APPEND_SYSTEM_PROMPT_FILE"
fi

# ── Resolve --task-file ────────────────────────────────────────────────────────
if [ "$MODE" = "agentic-file" ]; then
    if [ ! "${TASK_FILE:0:1}" = "/" ]; then
        TASK_FILE="${WORKTREE_ROOT}/${TASK_FILE}"
    fi
    [ -f "$TASK_FILE" ] || die "Task file not found: $TASK_FILE"
    TASK="$(cat "$TASK_FILE")"
    MODE="agentic"
    info "Task loaded from: $TASK_FILE"
fi

# ── Find repo root and Containerfile ──────────────────────────────────────────
REPO_ROOT=""
if git rev-parse --git-dir &>/dev/null 2>&1; then
    REPO_ROOT=$(git rev-parse --show-toplevel)
fi

# Candidate repo roots — the git root, plus two levels up to handle worktrees
# that live at <repo>/worktrees/<branch>/ where git root is the worktree itself
REPO_CANDIDATES=("$REPO_ROOT")
if [ -n "$WORKTREE_ROOT" ]; then
    REPO_CANDIDATES+=(
        "$(dirname "$(dirname "$WORKTREE_ROOT")")"
        "$(dirname "$WORKTREE_ROOT")"
    )
fi

CONTAINERFILE_SEARCH_PATHS=(
    "containers/claude-sandbox/Containerfile"
    ".claude-sandbox/Containerfile"
    "docker/claude-sandbox/Containerfile"
    "Containerfile.claude-sandbox"
)

FOUND_CONTAINERFILE=""

if [ -n "$CONTAINERFILE_PATH" ]; then
    # Explicit override — validate it exists somewhere in our candidate roots
    for root in "${REPO_CANDIDATES[@]}"; do
        [ -z "$root" ] && continue
        if [ -f "$root/$CONTAINERFILE_PATH" ]; then
            FOUND_CONTAINERFILE="$root/$CONTAINERFILE_PATH"
            REPO_ROOT="$root"
            break
        fi
    done
    [ -n "$FOUND_CONTAINERFILE" ] || \
        die "Containerfile not found at CLAUDE_SANDBOX_CONTAINERFILE=$CONTAINERFILE_PATH"
else
    # Search well-known locations across all candidate roots
    for root in "${REPO_CANDIDATES[@]}"; do
        [ -z "$root" ] && continue
        for candidate in "${CONTAINERFILE_SEARCH_PATHS[@]}"; do
            if [ -f "$root/$candidate" ]; then
                FOUND_CONTAINERFILE="$root/$candidate"
                CONTAINERFILE_PATH="$candidate"
                REPO_ROOT="$root"
                break 2
            fi
        done
    done
    [ -n "$FOUND_CONTAINERFILE" ] || die \
"Cannot find Claude sandbox Containerfile. Set CLAUDE_SANDBOX_CONTAINERFILE or place it at:
  containers/claude-sandbox/Containerfile
  .claude-sandbox/Containerfile
  docker/claude-sandbox/Containerfile
  Containerfile.claude-sandbox"
fi

info "Containerfile: $FOUND_CONTAINERFILE"

# ── Build image if needed ──────────────────────────────────────────────────────
if ! podman image exists "$SANDBOX_IMAGE" 2>/dev/null; then
    info "Sandbox image not found, building (this takes a few minutes)..."
    podman build \
        -t "$SANDBOX_IMAGE" \
        -f "$FOUND_CONTAINERFILE" \
        "$REPO_ROOT" \
        || die "Failed to build sandbox image"
    success "Sandbox image built: $SANDBOX_IMAGE"
else
    info "Using existing sandbox image: $SANDBOX_IMAGE"
fi

# ── Network configuration ──────────────────────────────────────────────────────
NETWORK_ARGS=()

if [ "$ISOLATED" = true ]; then
    COMPOSE_NETWORK="${PODMAN_PROJECT}_default"
    if ! podman network exists "$COMPOSE_NETWORK" 2>/dev/null; then
        die "Network '$COMPOSE_NETWORK' not found. Run 'make services-run' in this worktree first."
    fi
    NETWORK_ARGS+=(--network "$COMPOSE_NETWORK")
    info "Isolated mode: connected to network '$COMPOSE_NETWORK'"
    info "  Services reachable by container name on this network"
else
    NETWORK_ARGS+=(--network host)
    info "Unrestricted mode: host network access (ports sourced from .env)"
fi

# ── Determine container command ────────────────────────────────────────────────
CONTAINER_CMD=()
TTY_FLAG="--tty"
INTERACTIVE_FLAG="--interactive"

if [ "$MODE" = "interactive" ] || [ "$MODE" = "agentic" ]; then
    CONTAINER_CMD=(claude --dangerously-skip-permissions)

    if [ "$SESSION_FLAG" = "continue" ]; then
        CONTAINER_CMD+=(-c)
    elif [ "$SESSION_FLAG" = "resume" ]; then
        if [ -n "$SESSION_ID" ]; then
            CONTAINER_CMD+=(--resume "$SESSION_ID")
        else
            CONTAINER_CMD+=(--resume)
        fi
    fi

    if [ "$MODE" = "agentic" ]; then
        CONTAINER_CMD+=(-p "$TASK")
        TTY_FLAG=""
        INTERACTIVE_FLAG=""
    fi

    if [ -n "$APPEND_SYSTEM_PROMPT_FILE" ]; then
        RELATIVE_PATH="${APPEND_SYSTEM_PROMPT_FILE#"$WORKTREE_ROOT"/}"
        CONTAINER_CMD+=(--append-system-prompt-file "${CONTAINER_WORKDIR}/${RELATIVE_PATH}")
    fi

    if [ -n "$AGENTS_JSON" ]; then
        CONTAINER_CMD+=(--agents "$AGENTS_JSON")
    fi

elif [ "$MODE" = "shell" ]; then
    CONTAINER_CMD=(/bin/bash)

elif [ "$MODE" = "exec" ]; then
    CONTAINER_CMD=(/bin/bash -c "$EXEC_CMD")
    TTY_FLAG=""
    INTERACTIVE_FLAG=""
fi

# ── Print summary ──────────────────────────────────────────────────────────────
CONTAINER_NAME="claude-sandbox-slot${NEXUS_SLOT}-$$"

SESSION_MODE="new"
if [ "$SESSION_FLAG" = "continue" ]; then
    SESSION_MODE="continue (last session)"
elif [ "$SESSION_FLAG" = "resume" ]; then
    if [ -n "$SESSION_ID" ]; then
        SESSION_MODE="resume ($SESSION_ID)"
    else
        SESSION_MODE="resume (interactive picker)"
    fi
fi

echo ""
echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  Launching Claude Code sandbox${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo ""
echo "  Worktree:  $WORKTREE_ROOT"
echo "  Project:   $PODMAN_PROJECT  (slot ${NEXUS_SLOT})"
echo "  Mode:      $MODE"
echo "  Session:   $SESSION_MODE"
echo "  Isolated:  $ISOLATED"
echo "  Container: $CONTAINER_NAME"
echo "  Memory:    $MEMORY_LIMIT  |  CPUs: $CPU_LIMIT"
if [ -n "$APPEND_SYSTEM_PROMPT_FILE" ]; then
    echo "  Sys prompt: ${APPEND_SYSTEM_PROMPT_FILE#"$WORKTREE_ROOT"/}"
fi
if [ -n "$AGENTS_JSON" ]; then
    echo "  Agents:    $(echo "$AGENTS_JSON" | head -c 60)..."
fi
if [ "$MODE" = "agentic" ]; then
    echo ""
    echo "  Task:"
    echo "$TASK" | head -5 | sed 's/^/    /'
    [ "$(echo "$TASK" | wc -l)" -gt 5 ] && echo "    ..."
fi
echo ""

if [ "$MODE" = "interactive" ] || [ "$MODE" = "agentic" ]; then
    warning "Claude Code is running with --dangerously-skip-permissions"
    warning "It can read and modify all files in the mounted worktree."
    echo ""
fi

# ── Run ────────────────────────────────────────────────────────────────────────
podman run \
    --rm \
    ${INTERACTIVE_FLAG:+--interactive} \
    ${TTY_FLAG:+--tty} \
    --name "$CONTAINER_NAME" \
    \
    `# Mount only the worktree — nothing else from the host filesystem` \
    --volume "${WORKTREE_ROOT}:${CONTAINER_WORKDIR}:z" \
    --workdir "$CONTAINER_WORKDIR" \
    \
    `# Persistent auth — survives container restarts, isolated from host ~/.claude` \
    --volume "${AUTH_DIR}:/home/node/.claude:z" \
    \
    `# Forward all project env vars — no hardcoded variable names` \
    --env-file "${ENV_FILE}" \
    \
    `# Resource limits` \
    --memory "$MEMORY_LIMIT" \
    --cpus "$CPU_LIMIT" \
    \
    `# Security: drop all capabilities, no privilege escalation` \
    --cap-drop ALL \
    --security-opt no-new-privileges \
    \
    `# Network` \
    "${NETWORK_ARGS[@]}" \
    \
    "$SANDBOX_IMAGE" \
    "${CONTAINER_CMD[@]}"
