#!/usr/bin/env bash
# skill-quarantine.sh — build (if needed) and launch the skill-quarantine sandbox.
#
# Usage:
#   ./skill-quarantine.sh              # build image if missing, then start claude
#   ./skill-quarantine.sh --rebuild    # force a fresh docker build first
#   ./skill-quarantine.sh --check      # verify the sandbox isolation, then exit
#   ./skill-quarantine.sh --reset      # delete the sandbox's saved Claude login
#
# What the container can see of your machine: nothing except this repo's
# .claude/agents and .claude/commands directories, mounted READ-ONLY. Your
# home directory and projects are never mounted. Scanned repos live in an
# anonymous volume at /work that Docker deletes when the container exits.
# The only thing that persists between runs is a named volume holding the
# sandbox's own Claude Code login/settings (wipe it with --reset).

set -euo pipefail

IMAGE_NAME="${SKILL_QUARANTINE_IMAGE:-skill-quarantine}"
CLAUDE_HOME_VOLUME="skill-quarantine-claude-home"
REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
MODE="run"
FORCE_REBUILD=0

usage() {
  echo "Usage: $0 [--rebuild] [--check | --reset]" >&2
}

for arg in "$@"; do
  case "$arg" in
    --rebuild) FORCE_REBUILD=1 ;;
    --check) MODE="check" ;;
    --reset) MODE="reset" ;;
    -h|--help) usage; exit 0 ;;
    *)
      echo "Unknown argument: $arg" >&2
      usage
      exit 1
      ;;
  esac
done

if ! command -v docker >/dev/null 2>&1; then
  echo "Error: docker is not installed or not on PATH." >&2
  echo "Install Docker (e.g. Docker Desktop) and try again." >&2
  exit 1
fi

if ! docker info >/dev/null 2>&1; then
  echo "Error: the Docker daemon is not running. Start Docker Desktop (or dockerd) and try again." >&2
  exit 1
fi

# Git Bash / MSYS on Windows rewrites arguments that look like POSIX paths
# (/work -> C:/Program Files/Git/work), which breaks every container path
# below. Disable that, and hand Docker a native Windows path for the host
# side of the bind mounts instead.
HOST_ROOT="$REPO_ROOT"
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*)
    export MSYS_NO_PATHCONV=1
    HOST_ROOT="$(cd "$REPO_ROOT" && pwd -W)"
    ;;
esac

if [ "$MODE" = "reset" ]; then
  if docker volume inspect "$CLAUDE_HOME_VOLUME" >/dev/null 2>&1; then
    docker volume rm "$CLAUDE_HOME_VOLUME" >/dev/null
    echo "==> Deleted volume '$CLAUDE_HOME_VOLUME' (sandbox login and settings). You'll log in again next run."
  else
    echo "==> Volume '$CLAUDE_HOME_VOLUME' does not exist; nothing to reset."
  fi
  exit 0
fi

for required in "$REPO_ROOT/.claude/agents/skill-quarantine.md" "$REPO_ROOT/.claude/commands/skill-quarantine.md"; do
  if [ ! -f "$required" ]; then
    echo "Error: could not find $required" >&2
    exit 1
  fi
done

# Build the image if it doesn't exist yet, or if --rebuild was passed.
if [ "$FORCE_REBUILD" -eq 1 ]; then
  echo "==> --rebuild passed, forcing a fresh docker build..."
  docker build --no-cache -t "$IMAGE_NAME" "$REPO_ROOT"
elif ! docker image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
  echo "==> Image '$IMAGE_NAME' not found, building it now..."
  docker build -t "$IMAGE_NAME" "$REPO_ROOT"
else
  echo "==> Using existing image '$IMAGE_NAME' (run with --rebuild to force a fresh build)."
fi

# The sandbox. Every flag here is load-bearing — see README "Security model".
#   --rm                      container filesystem and /work volume deleted on exit
#   --cap-drop=ALL            no Linux capabilities (no raw sockets, chown, mount, ...)
#   no-new-privileges         setuid binaries can't escalate
#   --pids-limit / --memory   a fork bomb or runaway install can't take down the host
#   /work                     anonymous volume: scanned code never touches the host disk
#   agents/commands  :ro      the tool's own instructions can't be rewritten by a skill
#   named volume              only the sandbox's Claude login persists between runs
DOCKER_ARGS=(
  --rm
  --cap-drop=ALL
  --security-opt no-new-privileges
  --pids-limit 1024
  --memory 4g
  --mount type=volume,target=/work
  --mount type=volume,source="$CLAUDE_HOME_VOLUME",target=/home/sandbox/.claude
  --mount type=bind,source="$HOST_ROOT/.claude/agents",target=/home/sandbox/.claude/agents,readonly
  --mount type=bind,source="$HOST_ROOT/.claude/commands",target=/home/sandbox/.claude/commands,readonly
  -w /work
)

if [ "$MODE" = "check" ]; then
  echo "==> Checking sandbox isolation..."
  # Runs the probe inside a container launched with the exact same flags as
  # a real session. Each line is PASS/FAIL; any FAIL makes this exit non-zero.
  docker run "${DOCKER_ARGS[@]}" "$IMAGE_NAME" '
    fails=0
    pass() { echo "  PASS  $1"; }
    fail() { echo "  FAIL  $1"; fails=$((fails + 1)); }

    [ "$(id -u)" != "0" ] && pass "runs as non-root user ($(id -un))" || fail "running as root"

    grep -q "^CapEff:[[:space:]]*0*$" /proc/self/status \
      && pass "all Linux capabilities dropped" || fail "process still has capabilities"

    grep -q "^NoNewPrivs:[[:space:]]*1" /proc/self/status \
      && pass "no-new-privileges is set" || fail "no-new-privileges is not set"

    # Every bind mount (anything not a Docker volume or a kernel pseudo-fs)
    # must be one of our two read-only config dirs.
    while read -r _ _ _ _ mnt opts _; do
      case "$mnt" in
        /home/sandbox/.claude/agents|/home/sandbox/.claude/commands)
          case ",$opts," in
            *,ro,*) pass "$mnt is mounted read-only" ;;
            *) fail "$mnt is writable" ;;
          esac ;;
      esac
    done < /proc/self/mountinfo

    unexpected=$(awk "{print \$5}" /proc/self/mountinfo | grep -Ev "^/(proc|sys|dev)(/|$)|^/$|^/etc/(hosts|hostname|resolv\.conf)$|^/work$|^/home/sandbox/\.claude(/agents|/commands)?$" || true)
    [ -z "$unexpected" ] && pass "no other host paths mounted" || fail "unexpected mounts: $unexpected"

    touch /home/sandbox/.claude/agents/.probe 2>/dev/null \
      && fail "agent instructions are writable" || pass "agent instructions cannot be modified"

    touch /work/.probe 2>/dev/null && rm -f /work/.probe \
      && pass "/work is writable (ephemeral scan area)" || fail "/work is not writable"

    [ -f /home/sandbox/.claude/agents/skill-quarantine.md ] && [ -f /home/sandbox/.claude/commands/skill-quarantine.md ] \
      && pass "skill-quarantine agent and command are loaded" || fail "agent or command missing"

    for tool in git gitleaks semgrep pip-audit npm claude; do
      command -v "$tool" >/dev/null && pass "$tool is installed" || fail "$tool is missing"
    done

    echo
    if [ "$fails" -eq 0 ]; then
      echo "All checks passed."
    else
      echo "$fails check(s) FAILED - do not vet skills until this is fixed."
      exit 1
    fi
  '
  exit $?
fi

echo "==> Launching sandbox. Working directory inside the container is /work"
echo "    (temporary; deleted when you exit). Your home directory and other"
echo "    projects are NOT mounted or visible."
echo

exec docker run -it "${DOCKER_ARGS[@]}" "$IMAGE_NAME" "claude"
