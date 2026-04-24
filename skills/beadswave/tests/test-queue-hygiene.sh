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

setup_queue_hygiene_fixture() {
  local tmp="$1"
  git init -q --bare "$tmp/remote.git"
  create_basic_repo "$tmp/repo"
  mkdir -p "$tmp/repo/scripts"
  cd "$tmp/repo"
  git -c user.name=T -c user.email=t@t commit -q --allow-empty -m "init"
  git remote add origin "$tmp/remote.git"
  git push -q -u origin main 2>/dev/null || true
  cd - >/dev/null
  export TRACE_FILE="$tmp/trace.log"
  write_common_stubs "$tmp/bin"
  export PATH="$tmp/bin:$PATH"
  export BEADSWAVE_SKILL_DIR="$SKILL_ROOT"
  write_trace_wrapper "$tmp/repo/scripts/branch-prune.sh" "branch-prune-wrapper"
  write_trace_wrapper "$tmp/repo/scripts/monitor-prs.sh" "monitor-prs-wrapper"
}

test_queue_hygiene_runs_prune_and_monitor() (
  set -euo pipefail
  local tmp output status
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  setup_queue_hygiene_fixture "$tmp"

  set +e
  output="$(cd "$tmp/repo" && "$QUEUE_HYGIENE_SCRIPT" --phase preflight --prune-max 11 --stuck 7 2>&1)"
  status=$?
  set -e

  assert_eq "0" "$status" "queue-hygiene should succeed with healthy stubs"
  assert_contains "$output" "[preflight] refreshing origin/main"
  assert_contains "$output" "[preflight] pruning merged branches"
  assert_contains "$output" "[preflight] repairing orphaned/stuck/conflicting PRs"
  assert_file_contains "$TRACE_FILE" $'branch-prune-wrapper\t--max\t11'
  assert_file_contains "$TRACE_FILE" $'monitor-prs-wrapper\t--orphans\t--resolve-conflicts\t--stuck\t7'
  assert_order "$TRACE_FILE" $'branch-prune-wrapper\t--max\t11' $'monitor-prs-wrapper\t--orphans\t--resolve-conflicts\t--stuck\t7' "queue hygiene should prune before monitoring"
)

test_queue_hygiene_fails_closed_on_dirty_tracked_changes() (
  set -euo pipefail
  local tmp output status
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  setup_queue_hygiene_fixture "$tmp"
  printf 'seed\n' > "$tmp/repo/README.md"
  cd "$tmp/repo" && git add -A && git -c user.name=T -c user.email=t@t commit -m "seed" -q
  printf 'dirty\n' > "$tmp/repo/README.md"

  set +e
  output="$(cd "$tmp/repo" && "$QUEUE_HYGIENE_SCRIPT" --phase preflight 2>&1)"
  status=$?
  set -e

  assert_eq "3" "$status" "queue-hygiene should fail closed on tracked dirty state"
  assert_contains "$output" "Refusing to continue queue-hygiene"
  assert_file_not_contains "$TRACE_FILE" $'branch-prune-wrapper'
  assert_file_not_contains "$TRACE_FILE" $'monitor-prs-wrapper'
)

run_test "queue-hygiene runs prune and monitor passes" test_queue_hygiene_runs_prune_and_monitor
run_test "queue-hygiene fails closed on dirty tracked changes" test_queue_hygiene_fails_closed_on_dirty_tracked_changes
