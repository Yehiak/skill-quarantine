#!/usr/bin/env bash
# run-vetter.sh — build (if needed) and launch the skill-vetter sandbox.
#
# Usage:
#   ./run-vetter.sh              # build image if missing, then run
#   ./run-vetter.sh --rebuild    # force a fresh docker build first
#
# What this does NOT do: it never mounts your home directory or any real
# project into the container. The only host path mounted is ./scratch,
# which this script creates if missing. Everything else lives in a named
# Docker volume scoped to this tool, or is wiped when the container exits.

set -euo pipefail

IMAGE_NAME="claude-vetter"
REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
SCRATCH_DIR="$REPO_ROOT/scratch"
AGENT_SRC="$REPO_ROOT/.claude/agents/skill-vetter.md"
COMMANDS_SRC_DIR="$REPO_ROOT/.claude/commands"
CLAUDE_HOME_VOLUME="skill-vetter-claude-home"
FORCE_REBUILD=0

for arg in "$@"; do
  case "$arg" in
    --rebuild)
      FORCE_REBUILD=1
      ;;
    *)
      echo "Unknown argument: $arg" >&2
      echo "Usage: $0 [--rebuild]" >&2
      exit 1
      ;;
  esac
done

if ! command -v docker >/dev/null 2>&1; then
  echo "Error: docker is not installed or not on PATH." >&2
  echo "Install Docker (e.g. Docker Desktop) and try again." >&2
  exit 1
fi

# Build the image if it doesn't exist yet, or if --rebuild was passed.
if [ "$FORCE_REBUILD" -eq 1 ]; then
  echo "==> --rebuild passed, forcing a fresh docker build..."
  docker build --no-cache -t "$IMAGE_NAME" "$(dirname "$0")"
elif ! docker image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
  echo "==> Image '$IMAGE_NAME' not found, building it now..."
  docker build -t "$IMAGE_NAME" "$(dirname "$0")"
else
  echo "==> Using existing image '$IMAGE_NAME' (run with --rebuild to force a fresh build)."
fi

# Set up the scratch directory that gets bind-mounted into the container as
# /work. This is the ONLY host path the container ever sees.
mkdir -p "$SCRATCH_DIR/.claude/agents" "$SCRATCH_DIR/.claude/commands"

if [ ! -f "$AGENT_SRC" ]; then
  echo "Error: could not find $AGENT_SRC" >&2
  exit 1
fi
cp "$AGENT_SRC" "$SCRATCH_DIR/.claude/agents/skill-vetter.md"

# Sync slash commands (e.g. /vet) into the sandbox too.
if [ -d "$COMMANDS_SRC_DIR" ]; then
  cp "$COMMANDS_SRC_DIR"/*.md "$SCRATCH_DIR/.claude/commands/" 2>/dev/null || true
fi

echo "==> Launching sandbox. Working directory inside the container is /work,"
echo "    bind-mounted from: $SCRATCH_DIR"
echo "    Your home directory and other projects are NOT mounted or visible."
echo

# --cap-drop=ALL / no-new-privileges: strip capabilities, block privilege
# escalation. --rm: container FS discarded on exit. The named volume holds
# only the sandbox's own Claude Code login, persisted across runs.
# ./scratch is the ONLY host bind mount — never $HOME, never a real project.
docker run \
  --rm \
  -it \
  --cap-drop=ALL \
  --security-opt no-new-privileges \
  --mount type=bind,source="$SCRATCH_DIR",target=/work \
  --mount type=volume,source="$CLAUDE_HOME_VOLUME",target=/home/vetter/.claude \
  -w /work \
  "$IMAGE_NAME" \
  "claude"
