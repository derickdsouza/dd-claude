#!/usr/bin/env bash
# .beadswave/pre-ship.sh — Bun single-app starter template.
#
# For Bun projects WITHOUT a workspaces array in package.json.
# If your repo has workspaces, use bun-monorepo.sh instead (install.sh picks
# automatically based on `workspaces` in package.json).
#
# Customize by:
# - swapping `bun run` commands to match your package.json scripts
# - enabling the bundle-size gate (see check-bundle-size.sh template)
# - adding drizzle/prisma migration drift checks for DB-backed apps

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

echo "▶ Pre-ship gates (bun single-app)"

beadswave_run_gate "lint"       "bun run lint" || exit 1
beadswave_run_gate "typecheck"  "bun run typecheck" || exit 1
beadswave_run_gate "bun audit"  "bun audit" || exit 1
beadswave_run_gate "tests"      "bun run test" || exit 1
beadswave_run_gate "build"      "bun run build" || exit 1

# Optional: enforce a bundle size budget. Copy
# $SKILL/references/templates/check-bundle-size.sh → scripts/ and uncomment:
# beadswave_run_gate "bundle size" "BUNDLE_SIZE_BUDGET_KB=1100 scripts/check-bundle-size.sh" || exit 1

echo "✓ Pre-ship gates passed"
