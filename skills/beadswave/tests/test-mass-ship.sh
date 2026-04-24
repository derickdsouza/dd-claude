#!/usr/bin/env bash
set -euo pipefail

. "$(dirname "$0")/lib/testlib.sh"

write_trace_wrapper() {
  local path="$1"
  local label="$2"
  mkdir -p "$(dirname "$path")"
  cat > "$path" <<EOF
#!/usr/bin/env bash
set -euo pipefail
trace="\${TRACE_FILE:?}"
{
  printf '%s' '$label'
  for arg in "\$@"; do
    printf '\t%q' "\$arg"
  done
  printf '\n'
} >> "\$trace"
EOF
  chmod +x "$path"
}

setup_mass_ship_fixture() {
  local tmp="$1"
  git init -q --bare "$tmp/remote.git"
  create_basic_repo "$tmp/repo"
  mkdir -p "$tmp/repo/scripts"
  cd "$tmp/repo"
  git -c user.name=T -c user.email=t@t commit -q --allow-empty -m "init"
  git remote add origin "$tmp/remote.git"
  git push -q -u origin main 2>/dev/null || true
  git checkout -q -b fix/demo-a
  git checkout -q -b fix/demo-b
  git checkout -q main
  cd - >/dev/null
  export TRACE_FILE="$tmp/trace.log"
  write_common_stubs "$tmp/bin"
  export PATH="$tmp/bin:$PATH"
  export BEADSWAVE_SKILL_DIR="$SKILL_ROOT"
  export PRESHIP_RATE_LIMIT=0
  export BEADSWAVE_MASS_SHIP_MONITOR_STUCK_MINUTES=5
  export BD_LIST_JSON='[{"id":"portfolio-manager-demo"}]'
  write_trace_wrapper "$tmp/repo/scripts/bd-ship.sh" "bd-ship-wrapper"
  write_trace_wrapper "$tmp/repo/scripts/branch-prune.sh" "branch-prune-wrapper"
  write_trace_wrapper "$tmp/repo/scripts/monitor-prs.sh" "monitor-prs-wrapper"
  write_trace_exec_wrapper "$tmp/repo/scripts/queue-hygiene.sh" "queue-hygiene-wrapper" "$QUEUE_HYGIENE_SCRIPT"
}

test_mass_ship_auto_mode_runs_queue_hygiene_between_beads() (
  set -euo pipefail
  local tmp output status
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  setup_mass_ship_fixture "$tmp"

  set +e
  output="$(cd "$tmp/repo" && "$MASS_SHIP_SCRIPT" --auto --rate-limit 0 2>&1)"
  status=$?
  set -e

  assert_eq "0" "$status" "mass-ship should succeed with healthy stubs"
  assert_contains "$output" "[preflight] refreshing origin/main"
  assert_contains "$output" "[preflight] pruning merged branches"
  assert_contains "$output" "[after portfolio-manager-a] repairing orphaned/stuck/conflicting PRs"
  assert_file_contains "$TRACE_FILE" $'queue-hygiene-wrapper\t--phase\tpreflight\t--prune-max\t25\t--stuck\t5'
  assert_file_contains "$TRACE_FILE" $'branch-prune-wrapper\t--max\t25'
  assert_file_contains "$TRACE_FILE" $'monitor-prs-wrapper\t--orphans\t--resolve-conflicts\t--stuck\t5'
  assert_file_contains "$TRACE_FILE" $'bd-ship-wrapper\tportfolio-manager-a\t--branch\tfix/demo-a'
  assert_file_contains "$TRACE_FILE" $'bd-ship-wrapper\tportfolio-manager-b\t--branch\tfix/demo-b'
  assert_order "$TRACE_FILE" $'queue-hygiene-wrapper\t--phase\tbefore\ portfolio-manager-a\t--prune-max\t25\t--stuck\t5' $'bd-ship-wrapper\tportfolio-manager-a\t--branch\tfix/demo-a' "queue hygiene should run before the first ship"
  assert_order "$TRACE_FILE" $'bd-ship-wrapper\tportfolio-manager-a\t--branch\tfix/demo-a' $'bd-ship-wrapper\tportfolio-manager-b\t--branch\tfix/demo-b' "ships should remain serial"
)

run_test "mass-ship auto mode runs queue hygiene between beads" test_mass_ship_auto_mode_runs_queue_hygiene_between_beads
