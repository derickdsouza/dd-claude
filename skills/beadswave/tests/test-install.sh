#!/usr/bin/env bash
set -euo pipefail

. "$(dirname "$0")/lib/testlib.sh"

create_install_adopted_repo() {
  local repo="$1"
  create_basic_repo "$repo"
  mkdir -p "$repo/.github/workflows" "$repo/.beadswave" "$repo/scripts"
  printf '# tracked\n' > "$repo/.github/workflows/auto-merge.yml"
  printf '{"templates":{}}\n' > "$repo/.beadswave/templates.lock.json"
}

test_check_rejects_stale_wrappers() (
  set -euo pipefail
  local tmp output status
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  create_install_adopted_repo "$tmp/repo"

  for path in \
    "$tmp/repo/scripts/bd-ship.sh" \
    "$tmp/repo/scripts/merge-wait.sh" \
    "$tmp/repo/scripts/pipeline-driver.sh" \
    "$tmp/repo/scripts/mass-ship.sh" \
    "$tmp/repo/scripts/monitor-prs.sh" \
    "$tmp/repo/scripts/queue-hygiene.sh" \
    "$tmp/repo/scripts/queue-drain.sh" \
    "$tmp/repo/scripts/bulk-approve-prs.sh" \
    "$tmp/repo/scripts/bd-lot-plan.sh" \
    "$tmp/repo/scripts/bd-lot-ship.sh" \
    "$tmp/repo/scripts/bd-circuit.sh" \
    "$tmp/repo/scripts/branch-prune.sh" \
    "$tmp/repo/scripts/safe-rebase.sh"
  do
    mkdir -p "$(dirname "$path")"
    printf '#!/usr/bin/env bash\necho stale\n' > "$path"
    chmod +x "$path"
  done

  set +e
  output="$(cd "$tmp/repo" && BEADSWAVE_SKILL="$SKILL_ROOT" "$INSTALL_SCRIPT" --check 2>&1)"
  status=$?
  set -e

  assert_eq "1" "$status" "stale wrappers should fail install --check"
  assert_eq "" "$output" "install --check should stay quiet on failure"
)

test_check_accepts_current_wrappers() (
  set -euo pipefail
  local tmp output status
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  create_install_adopted_repo "$tmp/repo"

  write_install_wrapper "$tmp/repo/scripts/bd-ship.sh" "references/templates/bd-ship.sh"
  write_install_wrapper "$tmp/repo/scripts/merge-wait.sh" "references/templates/merge-wait.sh"
  write_install_wrapper "$tmp/repo/scripts/pipeline-driver.sh" "references/templates/pipeline-driver.sh"
  write_install_wrapper "$tmp/repo/scripts/mass-ship.sh" "references/templates/mass-ship.sh"
  write_install_wrapper "$tmp/repo/scripts/monitor-prs.sh" "references/templates/monitor-prs.sh"
  write_install_wrapper "$tmp/repo/scripts/queue-hygiene.sh" "references/templates/queue-hygiene.sh"
  write_install_wrapper "$tmp/repo/scripts/queue-drain.sh" "references/templates/queue-drain.sh"
  write_install_wrapper "$tmp/repo/scripts/bulk-approve-prs.sh" "references/templates/bulk-approve-prs.sh"
  write_install_wrapper "$tmp/repo/scripts/bd-lot-plan.sh" "references/templates/bd-lot-plan.sh"
  write_install_wrapper "$tmp/repo/scripts/bd-lot-ship.sh" "references/templates/bd-lot-ship.sh"
  write_install_wrapper "$tmp/repo/scripts/bd-circuit.sh" "references/templates/bd-circuit.sh"
  write_install_wrapper "$tmp/repo/scripts/branch-prune.sh" "references/templates/branch-prune.sh"
  write_install_wrapper "$tmp/repo/scripts/safe-rebase.sh" "references/templates/safe-rebase.sh"

  set +e
  output="$(cd "$tmp/repo" && BEADSWAVE_SKILL="$SKILL_ROOT" "$INSTALL_SCRIPT" --check 2>&1)"
  status=$?
  set -e

  assert_eq "0" "$status" "current wrappers should pass install --check"
  assert_eq "" "$output" "install --check should stay quiet on success"
)

run_test "install --check rejects stale wrappers" test_check_rejects_stale_wrappers
run_test "install --check accepts current wrappers" test_check_accepts_current_wrappers
