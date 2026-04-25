#!/usr/bin/env bash
# queue-hygiene.sh — Refresh main, prune merged branches, and repair
# queue state before/after a bead or batch ship.
#
# Usage:
#   queue-hygiene.sh [--phase <name>] [--prune-max N] [--stuck N]
#                    [--no-fetch] [--no-prune] [--no-monitor]
#
# Exit codes:
#   0   Hygiene completed
#   2   Usage or runtime bootstrap error
#   3   Repo state is unsafe (dirty tracked changes or mid-merge/rebase/cherry-pick)
#   4   Could not refresh origin/main
#   5   branch-prune failed
#   6   monitor-prs failed
#   7   queue-hygiene lock could not be acquired
#   8   stale stage:shipping bead found (ship process died mid-flight)

set -uo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
BEADSWAVE_RUNTIME="${BEADSWAVE_SKILL_DIR:-$HOME/.claude/skills/beadswave}/scripts/runtime.sh"

if [ ! -f "$BEADSWAVE_RUNTIME" ]; then
  echo "beadswave runtime missing at $BEADSWAVE_RUNTIME" >&2
  exit 2
fi

# shellcheck disable=SC1090
. "$BEADSWAVE_RUNTIME"

BEADSWAVE_STAGE_MACHINE="${BEADSWAVE_SKILL_DIR:-$HOME/.claude/skills/beadswave}/scripts/stage_machine.sh"
if [ -f "$BEADSWAVE_STAGE_MACHINE" ]; then
  # shellcheck disable=SC1090
  . "$BEADSWAVE_STAGE_MACHINE"
fi

PHASE=""
RUN_FETCH=1
RUN_PRUNE=1
RUN_MONITOR=1
PRUNE_MAX="${BEADSWAVE_QUEUE_HYGIENE_PRUNE_MAX:-25}"
MONITOR_STUCK_MINUTES="${BEADSWAVE_QUEUE_HYGIENE_MONITOR_STUCK_MINUTES:-30}"
BRANCH_PRUNE_WRAPPER="$REPO_ROOT/scripts/branch-prune.sh"
MONITOR_PRS_WRAPPER="$REPO_ROOT/scripts/monitor-prs.sh"
LOCK_DIR="$(beadswave_lock_dir "$REPO_ROOT" queue-hygiene)"

usage() {
  cat <<EOF
Usage: queue-hygiene.sh [--phase <name>] [--prune-max N] [--stuck N]
                        [--no-fetch] [--no-prune] [--no-monitor]

Options:
  --phase <name>    Prefix progress output with a phase label.
  --prune-max N     Max merged branches to prune in one pass. Default: $PRUNE_MAX
  --stuck N         Treat PRs idle for N minutes as stuck. Default: $MONITOR_STUCK_MINUTES
  --no-fetch        Skip refreshing origin/main.
  --no-prune        Skip scripts/branch-prune.sh.
  --no-monitor      Skip scripts/monitor-prs.sh --orphans --resolve-conflicts.
  -h, --help        Show this help.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --phase) PHASE="${2:-}"; shift 2 ;;
    --prune-max) PRUNE_MAX="${2:-}"; shift 2 ;;
    --stuck) MONITOR_STUCK_MINUTES="${2:-}"; shift 2 ;;
    --no-fetch) RUN_FETCH=0; shift ;;
    --no-prune) RUN_PRUNE=0; shift ;;
    --no-monitor) RUN_MONITOR=0; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

say() {
  if [ -n "$PHASE" ]; then
    echo "  [$PHASE] $*"
  else
    echo "$*"
  fi
}

warn() {
  if [ -n "$PHASE" ]; then
    echo "  [$PHASE] warning: $*" >&2
  else
    echo "warning: $*" >&2
  fi
}

ATTEMPTS=0
until beadswave_lock_acquire "$LOCK_DIR"; do
  ATTEMPTS=$((ATTEMPTS + 1))
  if [ "$ATTEMPTS" -ge 15 ]; then
    warn "another queue-hygiene run is still holding $LOCK_DIR"
    exit 7
  fi
  sleep 1
done
trap 'beadswave_lock_release "$LOCK_DIR"' EXIT

if ! beadswave_require_clean_worktree "$REPO_ROOT" "queue-hygiene"; then
  exit 3
fi

# ── Check for stale worktree bootstrap ───────────────────────────────────────
# If setup-dev.sh was run and a fingerprint exists, verify it is still fresh.
# A stale bootstrap (lockfile changed, node_modules gone, .env missing) causes
# subtle test / lint / typecheck failures that look like code bugs. Warn early.
if [ -f "$REPO_ROOT/.beadswave/bootstrap.fingerprint" ]; then
  beadswave_check_bootstrap_fingerprint "$REPO_ROOT" --warn-only || true
fi

# ── Check for stale in-flight beads (stage:shipping stuck > 30 min) ──
# stage:shipping is a transient state — it should never persist > 30 min.
# If found, the ship process died mid-flight. Block allocation until repaired.
STALE_SHIPPING_MINUTES="${BEADSWAVE_STALE_SHIPPING_MINUTES:-30}"
STALE_SHIPPING=$(bd list --status=in_progress --label "stage:shipping" --json -n 0 2>/dev/null \
  | python3 -c "
import json, sys
from datetime import datetime, timedelta, timezone
try:
    beads = json.load(sys.stdin)
    cutoff = datetime.now(timezone.utc) - timedelta(minutes=int('$STALE_SHIPPING_MINUTES'))
    stale = []
    for b in beads:
        updated = b.get('updated_at', '')
        if updated:
            try:
                dt = datetime.fromisoformat(updated.replace('Z','+00:00'))
                if dt < cutoff:
                    stale.append(b['id'])
            except Exception:
                stale.append(b['id'])
    print(len(stale))
    if stale:
        import sys as _sys
        print('\n'.join(stale), file=_sys.stderr)
except Exception:
    print(0)
" 2>/tmp/bw_stale_shipping.txt || true)

if [ "${STALE_SHIPPING:-0}" -gt 0 ]; then
  # bd-ship installs an EXIT trap that clears stage:shipping on every
  # abnormal exit, so any bead still carrying the label after
  # STALE_SHIPPING_MINUTES is definitively orphaned (not mid-ship). Auto-heal
  # by clearing the label — hard-failing here used to block /waves preflight
  # and force manual label surgery. Set BEADSWAVE_STALE_SHIPPING_MODE=block
  # to restore the old fail-closed behavior.
  local_mode="${BEADSWAVE_STALE_SHIPPING_MODE:-heal}"
  warn "Found ${STALE_SHIPPING} bead(s) stuck in stage:shipping > ${STALE_SHIPPING_MINUTES}min:"
  cat /tmp/bw_stale_shipping.txt >&2 2>/dev/null || true
  if [ "$local_mode" = "block" ]; then
    warn "BEADSWAVE_STALE_SHIPPING_MODE=block — refusing to auto-heal."
    warn "Re-run bd-ship for each stuck bead, or remove 'stage:shipping' label manually."
    exit 8
  fi
  while IFS= read -r stale_id; do
    [ -n "$stale_id" ] || continue
    bead_rollback "$stale_id" >/dev/null 2>&1 || true
    say "auto-healed stale stage:shipping on $stale_id"
  done </tmp/bw_stale_shipping.txt
fi
rm -f /tmp/bw_stale_shipping.txt

if [ "$RUN_FETCH" = "1" ]; then
  say "refreshing origin/main"
  if ! beadswave_fetch_origin_main "$REPO_ROOT"; then
    warn "could not refresh origin/main"
    exit 4
  fi
fi

if [ "$RUN_PRUNE" = "1" ]; then
  if [ -x "$BRANCH_PRUNE_WRAPPER" ]; then
    say "pruning merged branches"
    if ! "$BRANCH_PRUNE_WRAPPER" --max "$PRUNE_MAX" >/dev/null 2>&1; then
      warn "branch-prune reported a problem"
      exit 5
    fi
  else
    warn "scripts/branch-prune.sh not installed; skipping prune pass"
  fi
fi

if [ "$RUN_MONITOR" = "1" ]; then
  if [ -x "$MONITOR_PRS_WRAPPER" ]; then
    say "repairing orphaned/stuck/conflicting PRs"
    if ! "$MONITOR_PRS_WRAPPER" --orphans --resolve-conflicts --stuck "$MONITOR_STUCK_MINUTES" >/dev/null 2>&1; then
      warn "monitor-prs reported a problem"
      exit 6
    fi
  else
    warn "scripts/monitor-prs.sh not installed; skipping PR repair pass"
  fi
fi

# ── Manifest garbage collection ─────────────────────────────────────────
# Sweep .git/beadswave-state/*.json for closed beads whose manifest file
# is older than BEADSWAVE_MANIFEST_GC_DAYS (default 7). Keeps the state
# directory bounded over hundreds of ships. Open/in-progress beads are
# never touched regardless of mtime — the manifest is still authoritative
# for pipeline-driver recovery.
MANIFEST_DIR="$REPO_ROOT/.git/beadswave-state"
if [ -d "$MANIFEST_DIR" ]; then
  GC_DAYS="${BEADSWAVE_MANIFEST_GC_DAYS:-7}"
  CLOSED_IDS_FILE="$(mktemp)"
  bd list --status=closed --json -n 0 2>/dev/null \
    | jq -r '(if type=="array" then . else [.] end)[] | .id' \
    > "$CLOSED_IDS_FILE" 2>/dev/null || true
  REMOVED=0
  while IFS= read -r closed_id; do
    [ -n "$closed_id" ] || continue
    manifest="$MANIFEST_DIR/$closed_id.json"
    [ -f "$manifest" ] || continue
    # Only GC files older than the window — recently-landed beads keep
    # their manifests around long enough for the doctor to reconcile.
    if find "$manifest" -mtime +"$GC_DAYS" -print 2>/dev/null | grep -q .; then
      rm -f "$manifest"
      REMOVED=$((REMOVED + 1))
    fi
  done < "$CLOSED_IDS_FILE"
  rm -f "$CLOSED_IDS_FILE"
  if [ "$REMOVED" -gt 0 ]; then
    say "garbage-collected $REMOVED stale manifest(s) for closed beads"
  fi
fi

exit 0
