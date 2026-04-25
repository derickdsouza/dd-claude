#!/usr/bin/env bash
# merge-wait.sh — Poll GitHub until a bead's PR is merged.
#
# Reads the PR number from the bead's external-ref (gh-<n>).
# Loops until: PR merged, PR has conflicts (fail), or timeout.
#
# Usage:
#   merge-wait.sh <bead-id> [--timeout N] [--poll N] [--json]
#
# Pipeline stages:
#   On entry: expects stage:merging label on the bead
#   On merge: sets stage:landed, closes the bead
#   On conflict: exits 22, leaves bead at stage:merging
#
# Exit codes:
#   0   PR merged successfully
#   1   Validation failure (bad bead ID, no PR, not in merging stage)
#   2   Timeout waiting for merge
#   3   PR was closed/merged with conflicts or in an unexpected state
#   22  PR has merge conflicts that need manual resolution

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
BEADSWAVE_RUNTIME="${BEADSWAVE_SKILL_DIR:-$HOME/.claude/skills/beadswave}/scripts/runtime.sh"
BEADSWAVE_STAGE_MACHINE="${BEADSWAVE_SKILL_DIR:-$HOME/.claude/skills/beadswave}/scripts/stage_machine.sh"

if [ -f "$BEADSWAVE_RUNTIME" ]; then
  # shellcheck disable=SC1090
  . "$BEADSWAVE_RUNTIME"
else
  echo "beadswave runtime missing at $BEADSWAVE_RUNTIME" >&2
  exit 1
fi

if [ -f "$BEADSWAVE_STAGE_MACHINE" ]; then
  # shellcheck disable=SC1090
  . "$BEADSWAVE_STAGE_MACHINE"
else
  echo "beadswave stage_machine missing at $BEADSWAVE_STAGE_MACHINE" >&2
  exit 1
fi

# Tell stage_machine's role-based porcelain that we're the merge path.
export BEADSWAVE_STAGE_ROLE=merge

TIMEOUT="${MERGE_WAIT_TIMEOUT:-1800}"
POLL_INTERVAL="${MERGE_WAIT_POLL:-30}"
JSON_OUTPUT=false
BEAD_ID=""

usage() {
  cat <<EOF
Usage: merge-wait.sh <bead-id> [--timeout N] [--poll N] [--json]

Options:
  --timeout N   Max seconds to wait for merge (default: 1800 = 30 min)
  --poll N      Poll interval in seconds (default: 30)
  --json        Output JSON result on stdout
  -h, --help    Show this help

Env:
  MERGE_WAIT_TIMEOUT   Default timeout in seconds (default: 1800)
  MERGE_WAIT_POLL      Default poll interval in seconds (default: 30)

Pipeline stages:
  Expects: stage:merging label on the bead
  Success: sets stage:landed, closes bead
  Failure: leaves bead at stage:merging

Exit codes:
  0   PR merged successfully
  1   Validation failure
  2   Timeout
  3   Unexpected PR state
  22  Merge conflict
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --timeout) TIMEOUT="${2:?}"; shift 2 ;;
    --poll)    POLL_INTERVAL="${2:?}"; shift 2 ;;
    --json)    JSON_OUTPUT=true; shift ;;
    -*)        echo "Unknown option: $1" >&2; exit 1 ;;
    *)         BEAD_ID="$1"; shift ;;
  esac
done

if [ -z "$BEAD_ID" ]; then
  usage
  exit 1
fi

# Update a bead's state manifest at .git/beadswave-state/<id>.json.
# Usage: update_manifest <bead_id> <jq-filter>
# Silent no-op if the manifest is missing or jq fails — this is advisory
# state, not load-bearing.
update_manifest() {
  local bead_id="$1"; shift
  # Delegate to the runtime's per-bead-locked helper so concurrent writers
  # (e.g. monitor-prs auto-heal racing a live merge-wait poll) cannot
  # clobber each other's updates. Failure is still a silent no-op — this
  # is advisory state.
  beadswave_update_manifest_locked "$REPO_ROOT" "$bead_id" "$@" 2>/dev/null || true
}

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

BEAD_STATUS=$(printf '%s' "$BEAD_JSON" | jq -r 'if type=="array" then .[0].status else .status end // empty' 2>/dev/null)
if [ "$BEAD_STATUS" = "closed" ]; then
  echo "Bead '$BEAD_ID' is already closed."
  exit 0
fi

EXTERNAL_REF=$(printf '%s' "$BEAD_JSON" | jq -r 'if type=="array" then .[0].external_refs[0].ref else .external_refs[0].ref end // empty' 2>/dev/null || true)
if [ -z "$EXTERNAL_REF" ] || [[ "$EXTERNAL_REF" != gh-* ]]; then
  echo "Bead '$BEAD_ID' has no PR external-ref (expected gh-<n>)." >&2
  exit 1
fi

PR_NUMBER="${EXTERNAL_REF#gh-}"
echo "▶ Waiting for PR #$PR_NUMBER to merge (bead $BEAD_ID, timeout ${TIMEOUT}s)..."

START_TS=$(date +%s)
RESULT_STATE=""
RESULT_DETAIL=""

while true; do
  NOW_TS=$(date +%s)
  ELAPSED=$(( NOW_TS - START_TS ))

  if [ "$ELAPSED" -ge "$TIMEOUT" ]; then
    echo "Timeout after ${TIMEOUT}s — PR #$PR_NUMBER is still not merged." >&2
    echo "  Re-run merge-wait.sh with a longer timeout, or check PR status manually." >&2
    # Tag the bead so `bd list --label merge-timeout` surfaces stuck beads
    # for triage by /bw-monitor or the operator. stage:merging is preserved
    # — the bead is still in the merge phase, just not progressing.
    bd update "$BEAD_ID" --add-label merge-timeout >/dev/null 2>&1 || true
    update_manifest "$BEAD_ID" '. + {last_successful_step: "merge-wait-timeout"}'
    exit 2
  fi

  PR_JSON=$(gh pr view "$PR_NUMBER" --json state,mergedAt,mergeCommit,autoMergeRequest,statusCheckRollup 2>/dev/null || true)
  if [ -z "$PR_JSON" ]; then
    echo "  Could not read PR #$PR_NUMBER — retrying in ${POLL_INTERVAL}s..."
    sleep "$POLL_INTERVAL"
    continue
  fi

  PR_STATE=$(printf '%s' "$PR_JSON" | jq -r '.state // empty' 2>/dev/null)
  MERGED_AT=$(printf '%s' "$PR_JSON" | jq -r '.mergedAt // empty' 2>/dev/null)

  if [ "$PR_STATE" = "MERGED" ] || { [ -n "$MERGED_AT" ] && [ "$MERGED_AT" != "null" ]; }; then
    RESULT_STATE="merged"
    RESULT_DETAIL="PR #$PR_NUMBER merged at $(printf '%s' "$PR_JSON" | jq -r '.mergedAt' 2>/dev/null)"
    break
  fi

  if [ "$PR_STATE" = "CLOSED" ]; then
    RESULT_STATE="closed"
    RESULT_DETAIL="PR #$PR_NUMBER was closed without merging"
    break
  fi

  # Check for merge conflicts via check runs
  CONFLICTING=$(printf '%s' "$PR_JSON" | jq -r '
    [.statusCheckRollup // [] | .[] | select(.conclusion == "failure" and (.name | test("conflict|rebase|merge"; "i")))] | length
  ' 2>/dev/null || echo "0")

  if [ "$CONFLICTING" -gt 0 ]; then
    echo "  PR #$PR_NUMBER has merge conflicts." >&2
    echo "  Rebase the branch and re-run bd-ship." >&2
    exit 22
  fi

  REMAINING=$(( TIMEOUT - ELAPSED ))
  echo "  PR #$PR_NUMBER state=$PR_STATE — waiting (${REMAINING}s remaining)..."

  sleep "$POLL_INTERVAL"
done

if [ "$RESULT_STATE" = "merged" ]; then
  echo "  $RESULT_DETAIL"

  # ── Merge reachability verification ────────────────────────────────────────
  # Before closing the bead, confirm the merge commit is actually reachable from
  # origin/main. This catches squash-merges that lost provenance, force-pushes
  # that replaced the merge, or branch-name collisions that tricked the poll.
  # Failure is warn-only — the PR is already merged on GitHub's side and there
  # is nothing useful to block here, but the operator should investigate.
  MERGE_COMMIT=$(printf '%s' "$PR_JSON" | jq -r '.mergeCommit.oid // empty' 2>/dev/null || true)
  if [ -n "$MERGE_COMMIT" ] && [ "$MERGE_COMMIT" != "null" ]; then
    echo "  Verifying merge commit $MERGE_COMMIT is reachable from origin/main..."
    # Fetch to ensure we have the latest origin/main ref
    git fetch origin main --quiet 2>/dev/null || true
    if git merge-base --is-ancestor "$MERGE_COMMIT" "origin/main" 2>/dev/null; then
      echo "  ✓ Merge commit confirmed reachable from origin/main."
    else
      echo "  warning: merge commit $MERGE_COMMIT is NOT reachable from origin/main." >&2
      echo "    This may indicate a squash-merge, force-push, or stale local fetch." >&2
      echo "    Verify manually: git fetch origin main && git log origin/main | grep $MERGE_COMMIT" >&2
      echo "    Proceeding to close bead (reachability check is advisory)." >&2
    fi
  else
    echo "  (No merge commit SHA available — skipping reachability check.)"
  fi

  # merging/review-hold → landed via the stage machine (LAND event).
  # stage_machine owns the stage:* label transition and the .stage field;
  # it also removes stage:review-hold if the bead went through a hold.
  bead_advance "$BEAD_ID" >/dev/null 2>&1 || true
  bd update "$BEAD_ID" --remove-label merge-timeout >/dev/null 2>&1 || true

  MERGE_COMMIT_JSON="${MERGE_COMMIT:-}"
  if [ -n "$MERGE_COMMIT_JSON" ] && [ "$MERGE_COMMIT_JSON" != "null" ]; then
    update_manifest "$BEAD_ID" \
      --arg mc "$MERGE_COMMIT_JSON" \
      '. + {merge_commit: $mc, last_successful_step: "merge-wait-landed"}'
  else
    update_manifest "$BEAD_ID" \
      '. + {last_successful_step: "merge-wait-landed"}'
  fi

  if [ "$BEAD_STATUS" != "closed" ]; then
    echo "▶ Closing bead..."
    bd close "$BEAD_ID" -r "Merged via PR #$PR_NUMBER" >/dev/null 2>&1 || {
      echo "  Warning: failed to close bead '$BEAD_ID'" >&2
    }
  fi

  if [ "$JSON_OUTPUT" = "true" ]; then
    printf '{"bead":"%s","pr":%s,"state":"%s","detail":"%s"}\n' "$BEAD_ID" "$PR_NUMBER" "$RESULT_STATE" "$RESULT_DETAIL"
  fi

  echo "  Stage: stage:landed"
  exit 0
fi

echo "  $RESULT_DETAIL" >&2
if [ "$RESULT_STATE" = "closed" ]; then
  # PR was closed without merging — usually a manual abandon. Roll the bead
  # back to branched (clears stage:merging) so queue-hygiene doesn't re-flag
  # it as stale, and tag with pr-closed-unmerged for triage.
  bead_rollback "$BEAD_ID" >/dev/null 2>&1 || true
  bd update "$BEAD_ID" --add-label pr-closed-unmerged >/dev/null 2>&1 || true
  update_manifest "$BEAD_ID" '. + {last_successful_step: "merge-wait-closed-unmerged"}'
fi
exit 3
