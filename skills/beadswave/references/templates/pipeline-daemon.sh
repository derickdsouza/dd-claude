#!/usr/bin/env bash
# pipeline-daemon.sh — Fire-and-forget daemon that auto-drives committed beads
# through the conveyor belt.
#
# Watches for beads with stage:committed label and runs pipeline-driver.sh
# for each one. Reports only irreconcilable failures.
#
# Usage:
#   pipeline-daemon.sh [--interval N] [--max-concurrent N] [--once]
#
# Options:
#   --interval N        Poll interval in seconds (default: 30)
#   --max-concurrent N  Max concurrent pipeline-driver processes (default: 3)
#   --once              Run one pass and exit (for cron mode)
#   --json              Output JSON status

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
BEADSWAVE_RUNTIME="${BEADSWAVE_SKILL_DIR:-$HOME/.claude/skills/beadswave}/scripts/runtime.sh"

if [ -f "$BEADSWAVE_RUNTIME" ]; then
  # shellcheck disable=SC1090
  . "$BEADSWAVE_RUNTIME"
fi

INTERVAL="${PIPELINE_DAEMON_INTERVAL:-30}"
MAX_CONCURRENT="${PIPELINE_DAEMON_MAX_CONCURRENT:-3}"
ONCE=false
JSON_OUTPUT=false
PIDS_DIR=""

cleanup() {
  if [ -n "$PIDS_DIR" ] && [ -d "$PIDS_DIR" ]; then
    rm -rf "$PIDS_DIR"
  fi
}
trap cleanup EXIT

usage() {
  cat <<EOF
Usage: pipeline-daemon.sh [--interval N] [--max-concurrent N] [--once] [--json]

Options:
  --interval N        Poll interval in seconds (default: 30)
  --max-concurrent N  Max concurrent pipeline-driver processes (default: 3)
  --once              Single pass then exit (for cron)
  --json              Output JSON status
  -h, --help          Show this help

Env:
  PIPELINE_DAEMON_INTERVAL      Poll interval (default: 30)
  PIPELINE_DAEMON_MAX_CONCURRENT  Max parallel pipelines (default: 3)

The daemon polls bd for stage:committed beads and runs pipeline-driver.sh
for each one. Only reports irreconcilable failures. Normal operation is silent.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --interval) INTERVAL="${2:?}"; shift 2 ;;
    --max-concurrent) MAX_CONCURRENT="${2:?}"; shift 2 ;;
    --once) ONCE=true; shift ;;
    --json) JSON_OUTPUT=true; shift ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

PIDS_DIR="$(mktemp -d "${TMPDIR:-/tmp}/pipeline-daemon-pids.XXXXXX")"

DRIVER="${BEADSWAVE_SKILL_DIR:-$HOME/.claude/skills/beadswave}/references/templates/pipeline-driver.sh"
if [ ! -x "$DRIVER" ]; then
  REPO_DRIVER="$REPO_ROOT/scripts/pipeline-driver.sh"
  if [ -x "$REPO_DRIVER" ]; then
    DRIVER="$REPO_DRIVER"
  else
    echo "pipeline-driver.sh not found. Install beadswave templates first." >&2
    exit 1
  fi
fi

count_running() {
  local count=0
  for pidfile in "$PIDS_DIR"/*.pid; do
    [ -f "$pidfile" ] || continue
    local pid
    pid=$(cat "$pidfile" 2>/dev/null || true)
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      count=$((count + 1))
    else
      rm -f "$pidfile"
    fi
  done
  echo "$count"
}

reap_finished() {
  for pidfile in "$PIDS_DIR"/*.pid; do
    [ -f "$pidfile" ] || continue
    local pid bead_id
    pid=$(cat "$pidfile" 2>/dev/null || true)
    bead_id=$(basename "$pidfile" .pid)
    if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then
      wait "$pid" 2>/dev/null
      local exit_code=$?
      rm -f "$pidfile"
      if [ "$exit_code" -ne 0 ]; then
        echo "[$(date +%H:%M:%S)] FAILED: $bead_id (pipeline-driver exited $exit_code)" >&2
        echo "  Re-run manually: pipeline-driver.sh $bead_id" >&2
      fi
    fi
  done
}

run_pass() {
  reap_finished

  local running
  running=$(count_running)

  local committed_json
  committed_json=$(bd list --label stage:committed --json -n 0 2>/dev/null || echo "[]")

  local count
  count=$(printf '%s' "$committed_json" | jq 'length' 2>/dev/null || echo "0")

  if [ "$count" -eq 0 ]; then
    return 0
  fi

  local ids
  ids=$(printf '%s' "$committed_json" | jq -r '.[].id // (if type=="array" then .[].[].id else empty end)' 2>/dev/null || true)

  while IFS= read -r bead_id; do
    [ -z "$bead_id" ] && continue
    running=$(count_running)
    if [ "$running" -ge "$MAX_CONCURRENT" ]; then
      break
    fi

    # Skip if already being processed
    [ -f "$PIDS_DIR/${bead_id}.pid" ] && continue

    echo "[$(date +%H:%M:%S)] Driving: $bead_id"

    "$DRIVER" "$bead_id" >/dev/null 2>"${PIDS_DIR}/${bead_id}.log" &
    local pid=$!
    echo "$pid" > "$PIDS_DIR/${bead_id}.pid"

    sleep 2
  done <<< "$ids"
}

echo "Pipeline daemon started (interval: ${INTERVAL}s, max concurrent: ${MAX_CONCURRENT})"
echo "  Repo: $REPO_ROOT"
echo "  Driver: $DRIVER"
echo ""

while true; do
  run_pass

  if [ "$ONCE" = "true" ]; then
    # Wait for all running to finish
    sleep 5
    reap_finished
    break
  fi

  sleep "$INTERVAL"
done

echo "Pipeline daemon finished."
