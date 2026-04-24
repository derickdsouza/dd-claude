#!/usr/bin/env bash
# queue-drain.sh — Throttled requeue for infra-failed auto-merge PRs.
#
# Context: when mass-ship creates PRs faster than GitHub Actions can provision
# runners, some runs die in 2-3s with zero steps (conclusion=failure, 0 steps
# executed). These are NOT real test/lint failures — they're runner-quota
# exhaustion. This script detects that pattern and re-requests those runs
# while respecting an in-flight concurrency ceiling.
#
# Designed for single-shot operation. Wire to /loop for recurring execution:
#   /loop 60s scripts/queue-drain.sh
#
# Usage:
#   queue-drain [options]
#
# Options:
#   --label LABEL         PR label to consider. Default: auto-merge
#   --max-concurrent N    Ceiling on in-flight runs. Default: 15
#   --max-per-pass M      Cap on reruns issued per invocation. Default: 5
#   --stale-seconds S     Runtime threshold for infra-fail detection. Default: 15
#   --workflow NAME       Only consider checks from this workflow. Default: CI/CD Pipeline
#   --dry-run             Print the rerun plan without calling `gh run rerun`
#   --json                Emit JSON summary on stdout
#   --watch INTERVAL      Loop internally with adaptive pacing
#   -h, --help
#
# Exit codes:
#   0   No-op, or reruns issued successfully
#   1   At least one rerun failed
#   2   Argument error
#   3   Throttled (at or above --max-concurrent; no action taken)

set -uo pipefail

LABEL_FILTER="auto-merge"
MAX_CONCURRENT=15
MAX_PER_PASS=5
STALE_SECONDS=15
WORKFLOW_NAME="CI/CD Pipeline"
DRY_RUN=false
JSON_OUT=false
WATCH_INTERVAL=""

while [ $# -gt 0 ]; do
  case "$1" in
    --label)          LABEL_FILTER="$2"; shift 2 ;;
    --max-concurrent) MAX_CONCURRENT="$2"; shift 2 ;;
    --max-per-pass)   MAX_PER_PASS="$2"; shift 2 ;;
    --stale-seconds)  STALE_SECONDS="$2"; shift 2 ;;
    --workflow)       WORKFLOW_NAME="$2"; shift 2 ;;
    --dry-run)        DRY_RUN=true; shift ;;
    --json)           JSON_OUT=true; shift ;;
    --watch)          WATCH_INTERVAL="$2"; shift 2 ;;
    -h|--help)        sed -n '2,/^$/p' "$0" | sed 's/^# \?//'; exit 0 ;;
    *)                echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

command -v gh >/dev/null 2>&1 || { echo "gh CLI required" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "jq required" >&2; exit 2; }

# ──────────────────────────────────────────────────────────────
# One pass: count in-flight runs, find infra-fails, issue reruns
# ──────────────────────────────────────────────────────────────
run_one_pass() {
  # 1. In-flight ceiling check — count runs across ALL workflows.
  local in_flight
  in_flight=$(gh api "repos/:owner/:repo/actions/runs?status=in_progress&per_page=100" \
                --jq '.workflow_runs | length' 2>/dev/null || echo 0)
  local queued
  queued=$(gh api "repos/:owner/:repo/actions/runs?status=queued&per_page=100" \
             --jq '.workflow_runs | length' 2>/dev/null || echo 0)
  local busy=$((in_flight + queued))

  local budget=$((MAX_CONCURRENT - busy))
  [ "$budget" -gt "$MAX_PER_PASS" ] && budget="$MAX_PER_PASS"

  # 2. Candidate discovery — PRs labeled, with an infra-fail run on $WORKFLOW_NAME.
  # Signature: all matching-workflow checks concluded FAILURE AND every one
  # of them finished within $STALE_SECONDS of its start (runner never got past
  # provisioning). Real test failures take >30s per check.
  local candidates_json
  candidates_json=$(gh pr list --state open --limit 100 --label "$LABEL_FILTER" \
    --json number,statusCheckRollup 2>/dev/null \
    | jq --argjson stale "$STALE_SECONDS" --arg workflow "$WORKFLOW_NAME" '
        [ .[] |
          ( [.statusCheckRollup[] | select(.__typename=="CheckRun" and .workflowName==$workflow and .conclusion!="SKIPPED")] ) as $runs
          | select(($runs | length) > 0)
          | select(all($runs[]; .conclusion=="FAILURE"))
          | select(all($runs[]; ((.completedAt | fromdate) - (.startedAt | fromdate)) < $stale))
          | ($runs | sort_by(.completedAt) | last) as $sample
          | { n: .number,
              run_url: $sample.detailsUrl,
              duration: (($sample.completedAt | fromdate) - ($sample.startedAt | fromdate)),
              job_count: ($runs | length) }
        ]
    ')

  local n_candidates
  n_candidates=$(echo "$candidates_json" | jq 'length')

  # 3. Emit summary + maybe throttle.
  if [ "$JSON_OUT" = "true" ]; then
    echo "$candidates_json" | jq \
      --argjson in_flight "$in_flight" \
      --argjson queued "$queued" \
      --argjson budget "$budget" \
      --argjson max "$MAX_CONCURRENT" '
        { in_flight: $in_flight, queued: $queued, busy: ($in_flight+$queued),
          max_concurrent: $max, budget: $budget, candidates: . }
      '
  else
    echo "▶ queue-drain: in-flight=$in_flight queued=$queued busy=$busy ceiling=$MAX_CONCURRENT budget=$budget candidates=$n_candidates"
  fi

  if [ "$budget" -le 0 ]; then
    [ "$JSON_OUT" = "true" ] || echo "  throttled — at/above concurrency ceiling, no action"
    return 3
  fi

  if [ "$n_candidates" -eq 0 ]; then
    [ "$JSON_OUT" = "true" ] || echo "  no infra-fail candidates"
    return 0
  fi

  # 4. Rerun up to $budget candidates (oldest-first to clear backlog).
  local issued=0 failed=0
  while read -r pr_line; do
    [ "$issued" -ge "$budget" ] && break
    local pr_n run_id
    pr_n=$(echo "$pr_line" | jq -r '.n')
    run_id=$(echo "$pr_line" | jq -r '.run_url' | grep -oE '/runs/[0-9]+/' | tr -dc 0-9)
    [ -z "$run_id" ] && { echo "  ∿ PR#$pr_n: could not extract run_id, skipping" >&2; continue; }

    if [ "$DRY_RUN" = "true" ]; then
      echo "  (dry-run) would rerun PR#$pr_n run=$run_id"
      issued=$((issued+1))
      continue
    fi

    if gh run rerun "$run_id" --failed >/dev/null 2>&1; then
      [ "$JSON_OUT" = "true" ] || echo "  ✓ PR#$pr_n rerun issued (run=$run_id)"
      issued=$((issued+1))
    else
      [ "$JSON_OUT" = "true" ] || echo "  ✗ PR#$pr_n rerun failed (run=$run_id)"
      failed=$((failed+1))
    fi
  done < <(echo "$candidates_json" | jq -c '.[]')

  [ "$JSON_OUT" = "true" ] || echo "  issued=$issued failed=$failed"
  [ "$failed" -gt 0 ] && return 1 || return 0
}

# ──────────────────────────────────────────────────────────────
# Watch mode — loop with adaptive pacing
# ──────────────────────────────────────────────────────────────
if [ -n "$WATCH_INTERVAL" ]; then
  echo "▶ queue-drain watch mode — base interval ${WATCH_INTERVAL}s (adaptive)"
  while :; do
    run_one_pass
    rc=$?
    # Adaptive sleep:
    #   3 (throttled)       → sleep longer, let runners drain
    #   0 (no candidates)   → sleep longer, nothing to do
    #   0/1 (reruns issued) → sleep base interval
    case "$rc" in
      3) sleep $((WATCH_INTERVAL * 3)) ;;
      0) sleep $((WATCH_INTERVAL * 2)) ;;
      *) sleep "$WATCH_INTERVAL" ;;
    esac
  done
fi

run_one_pass
