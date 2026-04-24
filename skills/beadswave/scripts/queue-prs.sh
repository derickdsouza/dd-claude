#!/usr/bin/env bash
# beadswave/scripts/queue-prs.sh — reusable PR auto-merge helper.
#
# Adds the `auto-merge` label and posts `` for each named
# branch's open PR. Intended to be called from a repo's
# `.beadswave/pre-ship.sh` AFTER all gates pass, closing the gap where
# re-runs of pre-ship against existing PRs don't chain into the merge
# queue (bd-ship.sh only queues freshly-created PRs).
#
# Usage:
#   queue-prs.sh verify <branch>[,<branch>...]   — preflight: each branch
#       must have an open PR resolvable via `gh pr view`. Exits 2 on any
#       miss. Run this BEFORE the gate set so typos fail fast.
#
#   queue-prs.sh queue  <branch>[,<branch>...]   — for each branch, skip
#       if already `auto-merge`-labelled, else add the label and post
#       ``. Idempotent (safe to re-run).
#
# Note:
#   `queue_conditions` alone does NOT auto-queue matching PRs — only the
#   explicit `` comment does. This helper posts it.

set -euo pipefail

BEADSWAVE_RUNTIME="${BEADSWAVE_SKILL_DIR:-$HOME/.claude/skills/beadswave}/scripts/runtime.sh"
if [[ -f "$BEADSWAVE_RUNTIME" ]]; then
  # shellcheck disable=SC1090
  . "$BEADSWAVE_RUNTIME"
fi

_die() { echo "queue-prs.sh: $*" >&2; exit 2; }

_split_branches() {
  local raw="$1"
  local -a out=()
  IFS=',' read -r -a _arr <<< "$raw"
  for b in "${_arr[@]}"; do
    b="${b// /}"  # trim spaces
    [[ -n "$b" ]] && out+=("$b")
  done
  printf '%s\n' "${out[@]}"
}

cmd_verify() {
  local branches="${1:-}"
  [[ -z "$branches" ]] && _die "verify: no branches provided"
  local ok=1
  while IFS= read -r b; do
    [[ -z "$b" ]] && continue
    if ! gh pr view "$b" --json number >/dev/null 2>&1; then
      echo "  ✗ $b — no open PR" >&2
      ok=0
    fi
  done < <(_split_branches "$branches")
  [[ "$ok" == "1" ]] || exit 2
}

cmd_queue() {
  local branches="${1:-}"
  [[ -z "$branches" ]] && _die "queue: no branches provided"
  local fail=0
  while IFS= read -r b; do
    [[ -z "$b" ]] && continue
    local pr
    pr="$(gh pr view "$b" --json number -q .number 2>/dev/null || true)"
    if [[ -z "$pr" ]]; then
      echo "  ✗ $b — PR not found (did it close?); skipping" >&2
      fail=1; continue
    fi
    if gh pr view "$pr" --json labels -q '.labels[].name' 2>/dev/null \
         | grep -qx 'auto-merge'; then
      echo "  = PR #$pr ($b) — already auto-merge; skipping"
      continue
    fi
    if gh pr edit "$pr" --add-label auto-merge >/dev/null 2>&1; then
      echo "  + PR #$pr ($b) — label auto-merge"
    else
      echo "  ✗ PR #$pr ($b) — failed to add label" >&2
      fail=1; continue
    fi
    if gh pr comment "$pr" --body "" >/dev/null 2>&1; then
      echo "  + PR #$pr ($b) —  posted"
    else
      echo "  ✗ PR #$pr ($b) — failed to post queue comment" >&2
      fail=1
    fi
    if command -v beadswave_request_pr_auto_merge >/dev/null 2>&1; then
      if beadswave_request_pr_auto_merge "$pr" "" >/dev/null 2>&1; then
        echo "  + PR #$pr ($b) — GitHub auto-merge requested"
      else
        echo "  ✗ PR #$pr ($b) — failed to request GitHub auto-merge" >&2
        fail=1
      fi
    fi
  done < <(_split_branches "$branches")
  return $fail
}

case "${1:-}" in
  verify) shift; cmd_verify "${1:-}" ;;
  queue)  shift; cmd_queue  "${1:-}" ;;
  ""|-h|--help)
    sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'
    exit 0 ;;
  *)
    _die "unknown subcommand: $1 (expected: verify, queue)" ;;
esac
