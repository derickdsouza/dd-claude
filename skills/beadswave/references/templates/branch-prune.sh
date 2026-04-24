#!/usr/bin/env bash
# branch-prune.sh — remove local branches merged to main.
#
# After a PR is merged, the local branch still exists. Over time these
# accumulate. This script:
#   1. Syncs from origin
#   2. Finds branches whose commits are all on origin/main
#   3. Deletes each one
#
# Usage:
#   branch-prune.sh              # prune all merged branches
#   branch-prune.sh --dry-run    # show what would be pruned
#   branch-prune.sh --max 10     # prune at most 10 (default: unlimited)
#
# Exit codes:
#   0 — success (even if nothing to prune)
#   2 — usage error

set -euo pipefail

DRY_RUN=false
MAX_PRUNE=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run|-n) DRY_RUN=true; shift ;;
    --max)        MAX_PRUNE="${2:?--max needs a number}"; shift 2 ;;
    --help|-h)
      sed -n '2,/^$/{ s/^# //; s/^#//; p }' "$0"
      exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "error: not in a git repo" >&2; exit 1;
}
cd "$REPO_ROOT"

# ── Sync ───────────────────────────────────────────────────────────────
git fetch origin main --prune >/dev/null 2>&1 || git fetch --all --prune >/dev/null 2>&1 || true

# ── Discover merged branches ──────────────────────────────────────────
# Only consider fix/ branches (beadswave convention: one branch per bead).
MAP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/branch-prune.XXXXXX")"
trap 'rm -rf "$MAP_DIR"' EXIT

git branch --merged origin/main --list 'fix/*' > "$MAP_DIR/merged.txt"

MERGED_COUNT="$(grep -c . "$MAP_DIR/merged.txt" 2>/dev/null || echo 0)"
if [[ "$MERGED_COUNT" -eq 0 ]]; then
  echo "branch-prune: 0 merged branches to prune."
  exit 0
fi

echo "branch-prune: $MERGED_COUNT merged branch(es) found."

# ── Prune each merged branch ──────────────────────────────────────────
PRUNED=0
SKIPPED=0
while IFS= read -r line; do
  branch="${line##* }"  # strip leading whitespace/star

  # Cap check
  if [[ "$MAX_PRUNE" -gt 0 && "$PRUNED" -ge "$MAX_PRUNE" ]]; then
    echo "  max ($MAX_PRUNE) reached, stopping."
    break
  fi

  if $DRY_RUN; then
    echo "  [dry-run] would prune: $branch"
    PRUNED=$((PRUNED + 1))
    continue
  fi

  # Also remove any worktree associated with this branch
  WT_PATH="$(git worktree list --porcelain 2>/dev/null | { grep -A1 "^branch: refs/heads/${branch}$" || true; } | head -1 | sed 's/^worktree //')"
  if [ -n "$WT_PATH" ] && [ -d "$WT_PATH" ]; then
    git worktree remove --force "$WT_PATH" 2>/dev/null || true
  fi

  if git branch -d "$branch" 2>/dev/null; then
    PRUNED=$((PRUNED + 1))
    echo "  pruned: $branch"
  else
    SKIPPED=$((SKIPPED + 1))
    echo "  skipped: $branch"
  fi
done < "$MAP_DIR/merged.txt"

# ── Also clean up the git refs ────────────────────────────────────────
if ! $DRY_RUN; then
  git remote prune origin 2>/dev/null || true
  git worktree prune 2>/dev/null || true
fi

echo "branch-prune: $PRUNED pruned, $SKIPPED skipped, $MERGED_COUNT total."

# ── Health check ───────────────────────────────────────────────────────
REMAINING="$(git branch --list 'fix/*' | wc -l | tr -d ' ')"
if [[ "$REMAINING" -gt 50 ]]; then
  echo "warning: $REMAINING fix/ branches still present (>50). Consider running branch-prune again after pending merges complete."
fi
