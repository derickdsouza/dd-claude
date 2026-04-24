#!/usr/bin/env bash
# .beadswave/pre-ship.sh — Python / Poetry starter template.
#
# Gates covered: ruff (lint+format), pyright (types), pytest, bandit (SAST).
# Customize by:
# - swapping pyright → mypy if your team prefers
# - adding safety / pip-audit for dependency CVE scanning
# - adding alembic/yoyo migration drift checks for DB-backed services
# - adding mkdocs build if you ship docs from the repo

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

# Prune stale logs from previous failed runs (>1 day old).
find "${TMPDIR:-/tmp}" -maxdepth 1 -name 'preship.*' -mtime +1 -delete 2>/dev/null || true

echo "▶ Pre-ship gates (python / poetry)"

beadswave_run_gate "ruff lint"     "poetry run ruff check ." || exit 1
beadswave_run_gate "ruff format"   "poetry run ruff format --check ." || exit 1
beadswave_run_gate "pyright"       "poetry run pyright" || exit 1
beadswave_run_gate "bandit (SAST)" "poetry run bandit -q -r . -c pyproject.toml || poetry run bandit -q -r ." || exit 1
beadswave_run_gate "pytest"        "poetry run pytest -q" || exit 1

echo "✓ Pre-ship gates passed"
