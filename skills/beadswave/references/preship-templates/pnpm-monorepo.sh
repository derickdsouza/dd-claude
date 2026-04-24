#!/usr/bin/env bash
# .beadswave/pre-ship.sh — pnpm workspace / monorepo starter template.
#
# Mirrors a common CI job set for pnpm + TS projects. Customize by:
# - adding tsgo / tsc dual-pass if you hit TS version drift
# - adding trufflehog / semgrep if your CI runs SAST gates
# - splitting test:unit / test:integration by workspace
# - adding drizzle/prisma migration drift checks for DB-backed services

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

# Optional: abort early if uncommitted changes in the working tree.
# bd-ship sets PRESHIP_ISOLATE=1 by default. Set PRESHIP_ISOLATE=0 only if you
# intentionally want legacy non-isolated behaviour.
_BEADSWAVE_CHECK="${BEADSWAVE_SKILL_DIR:-$HOME/.claude/skills/beadswave}/scripts/check-working-tree.sh"
if [[ -f "$_BEADSWAVE_CHECK" ]]; then
  # shellcheck disable=SC1090
  . "$_BEADSWAVE_CHECK"
  beadswave_check_working_tree || exit 1
fi

_BEADSWAVE_RUNTIME="${BEADSWAVE_SKILL_DIR:-$HOME/.claude/skills/beadswave}/scripts/runtime.sh"
if [[ -f "$_BEADSWAVE_RUNTIME" ]]; then
  # shellcheck disable=SC1090
  . "$_BEADSWAVE_RUNTIME"
else
  echo "✗ beadswave runtime missing at $_BEADSWAVE_RUNTIME" >&2
  exit 1
fi

export NODE_OPTIONS="${NODE_OPTIONS:-} --max_old_space_size=6144"

# Prune stale logs from previous failed runs (>1 day old).
find "${TMPDIR:-/tmp}" -maxdepth 1 -name 'preship.*' -mtime +1 -delete 2>/dev/null || true

echo "▶ Pre-ship gates (pnpm workspace)"

beadswave_run_gate "lint (all workspaces)"      "pnpm -r lint" || exit 1
beadswave_run_gate "typecheck (all workspaces)" "pnpm -r typecheck" || exit 1
beadswave_run_gate "pnpm audit"                 "pnpm audit --prod" || exit 1
beadswave_run_gate "tests (all workspaces)"     "pnpm -r test" || exit 1
beadswave_run_gate "build (all workspaces)"     "pnpm -r build" || exit 1

# ── Optional SAST gates (uncomment + install trufflehog / semgrep first) ──
# trufflehog --since-commit needs origin/main fetched — without this it
# fails with "unknown revision" on fresh clones and worktrees.
# git fetch --no-tags --quiet origin main 2>/dev/null || true
# beadswave_run_gate "trufflehog (diff vs main)" \
#   "trufflehog git file://. --since-commit origin/main --only-verified --fail" || exit 1
# beadswave_run_gate "semgrep (src)" \
#   "semgrep --config p/typescript --error --severity ERROR \
#      --exclude='**/__tests__/**' --exclude='**/*.test.ts' ." || exit 1

echo "✓ Pre-ship gates passed"
