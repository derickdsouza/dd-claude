#!/usr/bin/env bash
# pipeline-driver.sh — Durable conveyor belt: ship → merge-wait → close → queue-hygiene.
#
# Runs the full automated pipeline for a bead after the agent has committed code:
#   1. bd-ship (rebase → gates → push → PR → queue)  [stage:shipping]
#   2. merge-wait (poll GitHub until merged)           [stage:merging → stage:landed]
#   3. Post-merge cleanup (queue hygiene)             [stage:landed]
#
# Idempotent: reads the current stage:* label and resumes from there.
# Safe to re-run at any point — completed stages are skipped.
#
# Usage:
#   pipeline-driver.sh <bead-id> [--timeout N] [--skip-merge-wait] [--json]
#
# Exit codes:
#   0   Pipeline completed (PR merged, bead closed, branch pruned)
#   1   Validation failure
#   2   bd-ship or merge-wait timeout
#   4   PR creation or merge handoff failure
#   6   Lint gate failed
#   7   Typecheck gate failed
#   20  Pre-ship hook failed
#   21  Rebase has conflicts
#   22  Merge conflicts detected during merge-wait
#   23  Post-merge queue hygiene failed
#   30+ Propagated from bd-ship or merge-wait

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
BEADSWAVE_RUNTIME="${BEADSWAVE_SKILL_DIR:-$HOME/.claude/skills/beadswave}/scripts/runtime.sh"

if [ -f "$BEADSWAVE_RUNTIME" ]; then
  # shellcheck disable=SC1090
  . "$BEADSWAVE_RUNTIME"
else
  echo "beadswave runtime missing at $BEADSWAVE_RUNTIME" >&2
  exit 1
fi

SKIP_MERGE_WAIT=false
JSON_OUTPUT=false
BEAD_ID=""
MERGE_TIMEOUT="${MERGE_WAIT_TIMEOUT:-1800}"
BD_SHIP_ARGS=()
HOLD_PR=false

usage() {
  cat <<EOF
Usage: pipeline-driver.sh <bead-id> [--timeout N] [--skip-merge-wait] [--json]

Options:
  --timeout N          Max seconds to wait for merge (default: 1800)
  --skip-merge-wait    Stop after bd-ship (do not wait for merge)
  --json               Output JSON result on stdout
  --branch <name>      Pass through to bd-ship
  --hold               Pass through to bd-ship
  -h, --help           Show this help

Pipeline stages (tracked via bd labels):
  stage:committed  →  stage:shipping  →  stage:merging  →  stage:landed
       (agent)           (bd-ship)         (merge-wait)      (prune+close)

Idempotent: resumes from the current stage. Re-run anytime.

Exit codes: propagated from bd-ship (1-21), merge-wait (2, 22), and queue hygiene (23).
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --timeout) MERGE_TIMEOUT="${2:?}"; shift 2 ;;
    --skip-merge-wait) SKIP_MERGE_WAIT=true; shift ;;
    --json) JSON_OUTPUT=true; shift ;;
    --branch|--hold) BD_SHIP_ARGS+=("$1" "${2:-}"); shift ${2:+2} ;;
    *) BEAD_ID="$1"; shift ;;
  esac
done

if [ -z "$BEAD_ID" ]; then
  usage
  exit 1
fi

RAW_BEAD_ID="$BEAD_ID"
if expanded_bead_id="$(beadswave_expand_bead_id "$BEAD_ID" "$REPO_ROOT" 2>/dev/null || true)"; then
  if [ -n "$expanded_bead_id" ]; then
    BEAD_ID="$expanded_bead_id"
  fi
fi
if [ "$RAW_BEAD_ID" != "$BEAD_ID" ]; then
  echo "  Resolved short bead id '$RAW_BEAD_ID' -> '$BEAD_ID'."
fi

BEAD_JSON=$(bd show "$BEAD_ID" --json 2>/dev/null || true)
if [ -z "$BEAD_JSON" ]; then
  echo "Bead '$BEAD_ID' not found." >&2
  exit 1
fi

LABELS=$(printf '%s' "$BEAD_JSON" | jq -r 'if type=="array" then .[0].labels else .labels end // [] | if type=="array" then .[] else . end | select(startswith("stage:"))' 2>/dev/null || true)
CURRENT_STAGE=$(printf '%s' "$LABELS" | head -1 || true)
BEAD_STATUS=$(printf '%s' "$BEAD_JSON" | jq -r 'if type=="array" then .[0].status else .status end // empty' 2>/dev/null)
CLEANUP_ONLY=false

if [ "$BEAD_STATUS" = "closed" ]; then
  CLEANUP_ONLY=true
  CURRENT_STAGE="stage:landed"
  echo "Bead '$BEAD_ID' is already closed; resuming cleanup only."
fi

echo "▶ Pipeline driver: $BEAD_ID (current stage: ${CURRENT_STAGE:-none})"

# ── Stage: shipping (bd-ship) ─────────────────────────────────────────
if [ "$CLEANUP_ONLY" = "false" ] && {
  [ -z "$CURRENT_STAGE" ] ||
  [ "$CURRENT_STAGE" = "stage:claimed" ] ||
  [ "$CURRENT_STAGE" = "stage:branched" ] ||
  [ "$CURRENT_STAGE" = "stage:committed" ] ||
  [ "$CURRENT_STAGE" = "stage:shipping" ];
}; then
  echo ""
  echo "═══ Stage: shipping (bd-ship) ═══"

  BD_SHIP="$(beadswave_resolve_bd_ship "$REPO_ROOT" 2>/dev/null)" || {
    BD_SHIP="bd-ship"
  }

  SHIP_LOG="$(beadswave_tmpfile pipeline-driver-ship)" || {
    echo "Could not allocate temp file for bd-ship output." >&2
    exit 1
  }

  if ! "$BD_SHIP" "$BEAD_ID" --no-close "${BD_SHIP_ARGS[@]}" >"$SHIP_LOG" 2>&1; then
    EXIT_CODE=$?
    cat "$SHIP_LOG"
    rm -f "$SHIP_LOG"
    echo "Pipeline halted: bd-ship exited $EXIT_CODE" >&2
    exit "$EXIT_CODE"
  fi
  cat "$SHIP_LOG"
  if grep -Fq "PR is held for human review." "$SHIP_LOG"; then
    HOLD_PR=true
  fi
  rm -f "$SHIP_LOG"

  echo "  bd-ship completed. Bead is at stage:merging."
else
  echo "  Skipping shipping stage (already at $CURRENT_STAGE)."
fi

# ── Stage: merging (merge-wait) ───────────────────────────────────────
if [ "$HOLD_PR" = "true" ]; then
  echo "  Skipping merge-wait because the PR is intentionally held for review."
  echo "Pipeline handed off: $BEAD_ID remains at stage:merging until review clears."
  exit 0
elif [ "$SKIP_MERGE_WAIT" = "false" ] && [ "$CURRENT_STAGE" != "stage:landed" ]; then
  MERGE_WAIT_SCRIPT="$(beadswave_resolve_merge_wait "$REPO_ROOT" 2>/dev/null || true)"
  if [ -z "$MERGE_WAIT_SCRIPT" ] || [ ! -x "$MERGE_WAIT_SCRIPT" ]; then
    echo "merge-wait.sh not found. Repair beadswave adoption before retrying." >&2
    exit 4
  fi

  echo ""
  echo "═══ Stage: merging (merge-wait) ═══"

  MERGE_WAIT_ARGS=("--timeout" "$MERGE_TIMEOUT")
  if [ "$JSON_OUTPUT" = "true" ]; then
    MERGE_WAIT_ARGS+=("--json")
  fi

  if ! "$MERGE_WAIT_SCRIPT" "$BEAD_ID" "${MERGE_WAIT_ARGS[@]}"; then
    EXIT_CODE=$?
    echo "Pipeline halted: merge-wait exited $EXIT_CODE" >&2
    exit "$EXIT_CODE"
  fi
elif [ "$CURRENT_STAGE" = "stage:landed" ]; then
  echo "  Skipping merge-wait (already landed)."
else
  echo "  Skipping merge-wait (--skip-merge-wait)."
fi

# ── Stage: landed (queue hygiene) ─────────────────────────────────────
echo ""
echo "═══ Stage: landed (cleanup) ═══"

QUEUE_HYGIENE_SCRIPT="$(beadswave_resolve_queue_hygiene "$REPO_ROOT" 2>/dev/null || true)"
if [ -z "$QUEUE_HYGIENE_SCRIPT" ] || [ ! -x "$QUEUE_HYGIENE_SCRIPT" ]; then
  echo "queue-hygiene.sh not found. Repair beadswave adoption before retrying." >&2
  exit 23
fi

if ! "$QUEUE_HYGIENE_SCRIPT" --phase "after $BEAD_ID"; then
  echo "  queue-hygiene failed after landing $BEAD_ID." >&2
  exit 23
fi

echo ""
echo "Pipeline complete: $BEAD_ID"
echo "  Stages: committed → shipping → merging → landed"

if [ "$JSON_OUTPUT" = "true" ]; then
  printf '{"bead":"%s","pipeline":"landed","ts":"%s"}\n' "$BEAD_ID" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
fi
