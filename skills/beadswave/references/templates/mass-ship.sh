#!/usr/bin/env bash
# mass-ship.sh — Ship many beads in one batch via bd-ship.
#
# Usage:
#   mass-ship [--auto] [--from N] [--to N] [--dry-run] [BRANCHES...]
#
# Modes:
#   --auto      Auto-discover branches from `git branch`, skip those that
#               already have an open PR or a commit matching <suffix>) on
#               origin/main. Default if no BRANCHES given.
#   BRANCHES    Explicit list of branch names (positional). Overrides --auto.
#
# Options:
#   --from N         1-indexed start of slice (inclusive). Default: 1.
#   --to   N         1-indexed end of slice (inclusive). Default: end.
#   --dry-run        Print the ship plan without running bd-ship.
#   --hold           Pass --hold to bd-ship (force auto-merge:hold on every PR).
#   --rate-limit N   Sleep N seconds between PRs to avoid saturating GitHub
#                    Actions runner concurrency. Default: 90 (sized for the
#                    Team plan's 60-slot ceiling with a 7-job CI pipeline).
#                    Set to 0 to disable. Override via PRESHIP_RATE_LIMIT env.
#   -h, --help       Show this help.
#
# Behavior:
#   For each branch:
#     1. Refresh origin/main, prune merged local branches, repair stuck PRs.
#     2. Derive BEAD_ID by taking the suffix after the last `-`.
#     3. Skip if a PR with head=branch is already open.
#     4. Reopen the bead if it was closed (bd-ship refuses closed beads).
#     5. Run bd-ship.
#     6. Run the queue/workspace hygiene pass again before the next branch.
#   Serial only — bd-ship mutates the git workspace and cannot run in parallel.
#
# Exit codes:
#   0   All branches shipped (or skipped as already-PR'd)
#   1   Argument error
#   2   bd-ship not found
#   >0  Number of failures

set -uo pipefail

usage() {
  sed -n '2,/^$/p' "$0" | sed 's/^# \?//'
  exit 0
}

# ──────────────────────────────────────────────────────────────
# Resolve bd-ship — prefer repo-local script, fall back to PATH
# ──────────────────────────────────────────────────────────────
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
BEADSWAVE_RUNTIME="${BEADSWAVE_SKILL_DIR:-$HOME/.claude/skills/beadswave}/scripts/runtime.sh"
if [ -f "$BEADSWAVE_RUNTIME" ]; then
  # shellcheck disable=SC1090
  . "$BEADSWAVE_RUNTIME"
fi
BD_SHIP=""
if command -v beadswave_resolve_bd_ship >/dev/null 2>&1; then
  BD_SHIP="$(beadswave_resolve_bd_ship "$REPO_ROOT" 2>/dev/null || true)"
elif [ -x "${REPO_ROOT}/scripts/bd-ship.sh" ]; then
  BD_SHIP="${REPO_ROOT}/scripts/bd-ship.sh"
elif command -v bd-ship >/dev/null 2>&1; then
  BD_SHIP="$(command -v bd-ship)"
fi
if [ -z "$BD_SHIP" ]; then
  echo "bd-ship not found (looked in ${REPO_ROOT}/scripts/bd-ship.sh and PATH)" >&2
  exit 2
fi

BRANCH_PRUNE_WRAPPER="${REPO_ROOT}/scripts/branch-prune.sh"
MONITOR_PRS_WRAPPER="${REPO_ROOT}/scripts/monitor-prs.sh"
QUEUE_HYGIENE_WRAPPER="${REPO_ROOT}/scripts/queue-hygiene.sh"
QUEUE_HYGIENE="${BEADSWAVE_MASS_SHIP_QUEUE_HYGIENE:-1}"
PRUNE_MAX="${BEADSWAVE_MASS_SHIP_PRUNE_MAX:-25}"
MONITOR_STUCK_MINUTES="${BEADSWAVE_MASS_SHIP_MONITOR_STUCK_MINUTES:-30}"

AUTO=false
DRY_RUN=false
HOLD_FLAG=""
FROM=1
TO=0
RATE_LIMIT="${PRESHIP_RATE_LIMIT:-90}"
declare -a BRANCHES=()

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)    usage ;;
    --auto)       AUTO=true; shift ;;
    --dry-run)    DRY_RUN=true; shift ;;
    --skip-tests) echo "ERROR: --skip-tests is no longer supported. Pre-ship checks are mandatory." >&2; exit 1 ;;
    --hold)       HOLD_FLAG="--hold"; shift ;;
    --from)       FROM="$2"; shift 2 ;;
    --to)         TO="$2"; shift 2 ;;
    --rate-limit) RATE_LIMIT="$2"; shift 2 ;;
    --)           shift; BRANCHES+=("$@"); break ;;
    -*)           echo "Unknown option: $1" >&2; exit 1 ;;
    *)            BRANCHES+=("$1"); shift ;;
  esac
done

# Default to --auto if no explicit branches
if [ ${#BRANCHES[@]} -eq 0 ]; then AUTO=true; fi

run_queue_hygiene() {
  local phase="$1"
  local status=0
  [ "$QUEUE_HYGIENE" = "1" ] || return 0

  if [ -x "$QUEUE_HYGIENE_WRAPPER" ]; then
    "$QUEUE_HYGIENE_WRAPPER" --phase "$phase" --prune-max "$PRUNE_MAX" --stuck "$MONITOR_STUCK_MINUTES"
    return $?
  fi

  echo "  [$phase] refreshing origin/main"
  if command -v beadswave_fetch_origin_main >/dev/null 2>&1; then
    beadswave_fetch_origin_main "$REPO_ROOT" || {
      echo "  [$phase] warning: could not refresh origin/main" >&2
    }
  elif ! git fetch origin main --prune >/dev/null 2>&1 && ! git fetch origin --prune >/dev/null 2>&1; then
    echo "  [$phase] warning: could not refresh origin/main" >&2
  fi

  if [ -x "$BRANCH_PRUNE_WRAPPER" ]; then
    echo "  [$phase] pruning merged branches"
    if ! "$BRANCH_PRUNE_WRAPPER" --max "$PRUNE_MAX" >/dev/null 2>&1; then
      echo "  [$phase] warning: branch-prune reported a problem" >&2
    fi
  fi

  if [ -x "$MONITOR_PRS_WRAPPER" ]; then
    echo "  [$phase] repairing orphaned/stuck/conflicting PRs"
    if ! "$MONITOR_PRS_WRAPPER" --orphans --resolve-conflicts --stuck "$MONITOR_STUCK_MINUTES" >/dev/null 2>&1; then
      echo "  [$phase] warning: monitor-prs reported a problem" >&2
    fi
  fi

  return 0
}

if [ "$AUTO" = "true" ] && [ ${#BRANCHES[@]} -eq 0 ]; then
  if ! run_queue_hygiene "preflight"; then
    echo "mass-ship stopped during queue hygiene preflight." >&2
    exit 1
  fi

  # Discover fix/* branches
  git fetch origin main --prune >/dev/null 2>&1 || true
  mapfile -t DISCOVERED < <(git branch --list 'fix/*' --format='%(refname:short)' | sort -u)

  MAIN_RECENT=$(git log origin/main --oneline -200 2>/dev/null || true)

  for b in "${DISCOVERED[@]}"; do
    if gh pr list --state open --head "$b" --json number --jq '.[0].number // empty' 2>/dev/null | grep -q .; then
      continue
    fi
    suffix="${b##*-}"
    if echo "$MAIN_RECENT" | grep -q "$suffix)"; then
      continue
    fi
    BRANCHES+=("$b")
  done
fi

TOTAL=${#BRANCHES[@]}
if [ "$TOTAL" -eq 0 ]; then
  echo "No branches to ship."
  exit 0
fi

PROJECT_PREFIX="$(beadswave_project_prefix "$REPO_ROOT" 2>/dev/null || basename "$REPO_ROOT")"

# Apply --from / --to slicing (1-indexed, inclusive)
[ "$TO" -le 0 ] && TO="$TOTAL"
if [ "$FROM" -lt 1 ] || [ "$FROM" -gt "$TOTAL" ]; then
  echo "--from out of range: $FROM (total $TOTAL)" >&2
  exit 1
fi

# Build the slice
declare -a SLICE=()
for (( i=FROM-1; i<TO && i<TOTAL; i++ )); do SLICE+=("${BRANCHES[$i]}"); done
SLICE_LEN=${#SLICE[@]}

echo "▶ Plan: ship $SLICE_LEN branch(es) (from $FROM to $((FROM+SLICE_LEN-1)) of $TOTAL discovered)"
for b in "${SLICE[@]}"; do
  suffix="${b##*-}"
  echo "    ${PROJECT_PREFIX}-$suffix  ($b)"
done | head -30
[ "$SLICE_LEN" -gt 30 ] && echo "    ... and $((SLICE_LEN-30)) more"

if [ "$DRY_RUN" = "true" ]; then
  echo "(dry-run; no changes)"
  exit 0
fi

# ──────────────────────────────────────────────────────────────
# Run the ship loop
# ──────────────────────────────────────────────────────────────
FAILURES=0
SKIPPED=0
SHIPPED=0
START_TS=$(date +%s)

for (( i=0; i<SLICE_LEN; i++ )); do
  b="${SLICE[$i]}"
  suffix="${b##*-}"
  n=$((i+1))

  if command -v beadswave_expand_bead_id >/dev/null 2>&1 && bead="$(beadswave_expand_bead_id "$suffix" "$REPO_ROOT" 2>/dev/null || true)"; then
    bead="${bead:-${PROJECT_PREFIX}-${suffix}}"
  else
    bead="${PROJECT_PREFIX}-${suffix}"
  fi

  echo "=== [$n/$SLICE_LEN] $bead ($b) ==="

  if ! run_queue_hygiene "before $bead"; then
    echo "  ✗ queue hygiene failed before $bead; stopping batch." >&2
    FAILURES=$((FAILURES+1))
    break
  fi

  # Idempotent: skip if PR already exists
  if gh pr list --state open --head "$b" --json number --jq '.[0].number // empty' 2>/dev/null | grep -q .; then
    pr_num=$(gh pr list --state open --head "$b" --json number --jq '.[0].number')
    echo "  ↪ PR #$pr_num already exists, skipping"
    SKIPPED=$((SKIPPED+1))
    if ! run_queue_hygiene "after skip $bead"; then
      echo "  ✗ queue hygiene failed after skip $bead; stopping batch." >&2
      FAILURES=$((FAILURES+1))
      break
    fi
    continue
  fi

  bd update "$bead" --status open >/dev/null 2>&1 || true

  if "$BD_SHIP" "$bead" --branch "$b" $HOLD_FLAG; then
    SHIPPED=$((SHIPPED+1))
  else
    rc=$?
    echo "  ✗ FAILED (rc=$rc)"
    FAILURES=$((FAILURES+1))
  fi

  if ! run_queue_hygiene "after $bead"; then
    echo "  ✗ queue hygiene failed after $bead; stopping batch." >&2
    FAILURES=$((FAILURES+1))
    break
  fi

  # Rate-limit between ships to avoid saturating GitHub Actions runner pool.
  # Skip the sleep after the final ship.
  if [ "$RATE_LIMIT" -gt 0 ] && [ "$n" -lt "$SLICE_LEN" ]; then
    echo "  ⏱  rate-limit: sleeping ${RATE_LIMIT}s before next ship"
    sleep "$RATE_LIMIT"
  fi
done

ELAPSED=$(( $(date +%s) - START_TS ))
echo
echo "=== Summary ==="
echo "  shipped:  $SHIPPED"
echo "  skipped:  $SKIPPED  (already had open PR)"
echo "  failures: $FAILURES"
echo "  elapsed:  ${ELAPSED}s"

exit "$FAILURES"
