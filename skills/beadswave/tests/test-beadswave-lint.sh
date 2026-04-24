#!/usr/bin/env bash
set -euo pipefail

. "$(dirname "$0")/lib/testlib.sh"

create_lint_ready_repo() {
  local repo="$1"
  create_basic_repo "$repo"
  mkdir -p "$repo/.github/workflows" "$repo/.beadswave" "$repo/scripts"
  printf '# tracked\n' > "$repo/.github/workflows/auto-merge.yml"

  write_install_wrapper "$repo/scripts/bd-ship.sh" "references/templates/bd-ship.sh"
  write_install_wrapper "$repo/scripts/mass-ship.sh" "references/templates/mass-ship.sh"
  write_install_wrapper "$repo/scripts/monitor-prs.sh" "references/templates/monitor-prs.sh"
  write_install_wrapper "$repo/scripts/queue-hygiene.sh" "references/templates/queue-hygiene.sh"
  write_install_wrapper "$repo/scripts/queue-drain.sh" "references/templates/queue-drain.sh"
  write_install_wrapper "$repo/scripts/bulk-approve-prs.sh" "references/templates/bulk-approve-prs.sh"
  write_install_wrapper "$repo/scripts/bd-lot-plan.sh" "references/templates/bd-lot-plan.sh"
  write_install_wrapper "$repo/scripts/bd-lot-ship.sh" "references/templates/bd-lot-ship.sh"
  write_install_wrapper "$repo/scripts/bd-circuit.sh" "references/templates/bd-circuit.sh"
  write_install_wrapper "$repo/scripts/branch-prune.sh" "references/templates/branch-prune.sh"
}

test_lint_accepts_runtime_backed_preship_hook() (
  set -euo pipefail
  local tmp output status
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  create_lint_ready_repo "$tmp/repo"

  cat > "$tmp/repo/.beadswave/pre-ship.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"
_BEADSWAVE_RUNTIME="${BEADSWAVE_SKILL_DIR:-$HOME/.claude/skills/beadswave}/scripts/runtime.sh"
# shellcheck disable=SC1090
. "$_BEADSWAVE_RUNTIME"
beadswave_run_gate "lint" "bun run lint"
EOF
  chmod +x "$tmp/repo/.beadswave/pre-ship.sh"

  set +e
  output="$(cd "$tmp/repo" && BEADSWAVE_SKILL="$SKILL_ROOT" "$LINT_SCRIPT" 2>&1)"
  status=$?
  set -e

  assert_eq "0" "$status" "runtime-backed pre-ship hook should pass lint"
  assert_contains "$output" ".beadswave/pre-ship.sh sources beadswave runtime"
  assert_contains "$output" ".beadswave/pre-ship.sh uses the shared gate runner"
)

test_lint_rejects_known_preship_antipatterns() (
  set -euo pipefail
  local tmp output status
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  create_lint_ready_repo "$tmp/repo"

  cat > "$tmp/repo/.beadswave/pre-ship.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
rm -f .git/*.lock 2>/dev/null || true
run_gate() {
  local out
  out="$(mktemp "${TMPDIR:-/tmp}/preship.XXXXXX.log")"
  : > "$out"
}
run_gate
EOF
  chmod +x "$tmp/repo/.beadswave/pre-ship.sh"

  set +e
  output="$(cd "$tmp/repo" && BEADSWAVE_SKILL="$SKILL_ROOT" "$LINT_SCRIPT" 2>&1)"
  status=$?
  set -e

  assert_eq "1" "$status" "known pre-ship anti-patterns should fail lint"
  assert_contains "$output" "redefines run_gate() instead of using beadswave_run_gate"
  assert_contains "$output" "handles git lock cleanup"
  assert_contains "$output" "uses a bespoke preship mktemp pattern"
)

run_test "beadswave lint accepts runtime-backed pre-ship hooks" test_lint_accepts_runtime_backed_preship_hook
run_test "beadswave lint rejects known pre-ship anti-patterns" test_lint_rejects_known_preship_antipatterns
