#!/usr/bin/env bash
# safe-rebase.sh — Rebase the current branch onto a target while preserving
# beads state. Works around the failure mode where rebasing commits that touch
# `.beads/*.jsonl` (or Dolt binary files) loses or corrupts beads records.
#
# Strategy: copy .beads/ aside (not `git stash`, since stash-pop conflicts on
# append-only JSONL mangle the event ordering), run the rebase, then replace
# .beads/ with the pre-rebase copy and add a single "restore" commit if needed.
#
# Usage:
#   scripts/safe-rebase.sh              # rebase onto origin/main (default)
#   scripts/safe-rebase.sh origin/dev   # rebase onto another ref
#
# Exit codes:
#   0  rebase succeeded (with or without beads restore commit)
#   1  rebase failed — beads/.git fully restored, tree back at original HEAD
#   2  precondition failure (dirty tree, not a git repo, etc.)

set -euo pipefail

TARGET="${1:-origin/main}"
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"

if [[ -z "$REPO_ROOT" ]]; then
  echo "safe-rebase: not inside a git repository" >&2
  exit 2
fi

cd "$REPO_ROOT"

BEADS_DIR="$REPO_ROOT/.beads"
ORIGINAL_HEAD="$(git rev-parse HEAD)"
ORIGINAL_BRANCH="$(git symbolic-ref --short HEAD 2>/dev/null || echo "")"

if [[ ! -d "$BEADS_DIR" ]]; then
  echo "safe-rebase: no .beads/ found — running plain rebase"
  exec git rebase "$TARGET"
fi

if [[ -n "$(git status --porcelain)" ]]; then
  echo "safe-rebase: working tree is dirty" >&2
  echo "  Commit, stash, or discard changes outside .beads/ before rebasing." >&2
  exit 2
fi

BACKUP="$(mktemp -d -t beads-backup.XXXXXX)"
echo "→ Backing up .beads/ → $BACKUP"
cp -a "$BEADS_DIR/." "$BACKUP/"

# If the rebase blows up, get back to a clean state no matter what.
restore_and_fail() {
  local rc=$?
  echo "✗ safe-rebase: rebase failed (rc=$rc) — rolling back" >&2
  git rebase --abort 2>/dev/null || true
  if [[ -n "$ORIGINAL_BRANCH" ]]; then
    git checkout -q "$ORIGINAL_BRANCH" 2>/dev/null || true
  fi
  git reset --hard "$ORIGINAL_HEAD" 2>/dev/null || true
  rm -rf "$BEADS_DIR"
  mkdir -p "$BEADS_DIR"
  cp -a "$BACKUP/." "$BEADS_DIR/"
  rm -rf "$BACKUP"
  exit 1
}
trap restore_and_fail ERR INT TERM

echo "→ Fetching $TARGET"
if [[ "$TARGET" == origin/* ]]; then
  git fetch origin "${TARGET#origin/}" --prune >/dev/null 2>&1 || true
fi

echo "→ Rebasing onto $TARGET"
git rebase "$TARGET"

# Past the danger zone — rebase completed.
trap - ERR INT TERM

echo "→ Restoring .beads/ from pre-rebase backup"
rm -rf "$BEADS_DIR"
mkdir -p "$BEADS_DIR"
cp -a "$BACKUP/." "$BEADS_DIR/"

git add .beads
if ! git diff --cached --quiet; then
  echo "→ Creating restore commit for .beads/"
  git commit -m "chore(beads): restore state after rebase onto $TARGET" --no-verify
else
  echo "→ .beads/ already matches post-rebase state — no restore commit needed"
fi

rm -rf "$BACKUP"
echo "✓ safe-rebase complete (target=$TARGET, beads preserved)"
