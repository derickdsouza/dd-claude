#!/bin/bash
# Stale Process Monitor
# Kills orphaned node/vitest processes that have been running longer than 10 minutes.
# Designed to be launched once per Claude Code session via SessionStart hook.

INTERVAL=300  # Check every 5 minutes
MAX_AGE_SECONDS=600  # Kill processes older than 10 minutes
LOG="$HOME/.claude/logs/stale-monitor.log"
PIDFILE="$HOME/.claude/scripts/.stale-monitor.pid"

# Prevent duplicate monitors
if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
  exit 0
fi
echo $$ > "$PIDFILE"

cleanup() {
  rm -f "$PIDFILE"
  exit 0
}
trap cleanup EXIT INT TERM

while true; do
  now=$(date +%s)

  # Find node processes running vitest that exceed MAX_AGE_SECONDS
  while IFS= read -r line; do
    pid=$(echo "$line" | awk '{print $2}')
    elapsed=$(echo "$line" | awk '{print $3}')

    if [ -n "$pid" ] && [ "$elapsed" -gt "$MAX_AGE_SECONDS" ] 2>/dev/null; then
      echo "$(date '+%Y-%m-%d %H:%M:%S') Killing stale process PID=$pid (elapsed=${elapsed}s)" >> "$LOG"
      kill "$pid" 2>/dev/null
      sleep 1
      kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null
    fi
  done < <(ps -eo ppid,pid,etimes,command 2>/dev/null | grep -E 'node.*vitest|vitest.*node' | grep -v grep | awk '{print $1, $2, $3}')

  sleep "$INTERVAL"
done
