#!/usr/bin/env bash
# .beadswave/pre-ship.sh — Go modules starter template.
#
# Gates covered: gofmt, go vet, staticcheck, govulncheck, go test.
# Customize by:
# - adding golangci-lint ./... if your CI uses the aggregated linter
# - adding goreleaser check for binary-release repos
# - adding a -race test pass for concurrency-heavy services

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

echo "▶ Pre-ship gates (go modules)"

beadswave_run_gate "gofmt"       "test -z \"\$(gofmt -l .)\"" || exit 1
beadswave_run_gate "go vet"      "go vet ./..." || exit 1
beadswave_run_gate "staticcheck" "staticcheck ./..." || exit 1
beadswave_run_gate "govulncheck" "govulncheck ./..." || exit 1
beadswave_run_gate "go test"     "go test ./..." || exit 1
beadswave_run_gate "go build"    "go build ./..." || exit 1

echo "✓ Pre-ship gates passed"
