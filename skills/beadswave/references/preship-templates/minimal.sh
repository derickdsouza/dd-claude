#!/usr/bin/env bash
# .beadswave/pre-ship.sh — starter template (minimal / unknown stack).
#
# Gates added here run before canonical lint/typecheck/test in bd-ship.
# Replace this stub with repo-specific gates. See references in the
# beadswave SKILL.md (portfolio-manager's 14-gate suite is a good exemplar).
#
# Convention: exit 0 on pass, non-zero on fail (aborts ship with code 20).

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

echo "▶ Pre-ship gates (stub — customize me)"
echo "  (no gates configured — see https://github.com/anthropics/claude-skills/tree/main/beadswave for examples)"
echo "  (custom gates should use beadswave_run_gate from scripts/runtime.sh)"
echo "✓ Pre-ship stub passed"
