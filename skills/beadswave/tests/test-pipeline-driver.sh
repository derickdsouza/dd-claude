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

write_trace_wrapper_with_stdout() {
  local path="$1"
  local label="$2"
  local stdout_text="$3"
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
printf '%s\n' '$stdout_text'
EOF
  chmod +x "$path"
}

setup_pipeline_driver_fixture() {
  local tmp="$1"
  create_basic_repo "$tmp/repo"
  mkdir -p "$tmp/repo/scripts"
  cd "$tmp/repo"
  git -c user.name=T -c user.email=t@t commit -q --allow-empty -m "init"
  git checkout -q -b fix/mfcapp-123
  cd - >/dev/null
  export TRACE_FILE="$tmp/trace.log"
  write_common_stubs "$tmp/bin"
  export PATH="$tmp/bin:$PATH"
  export BEADSWAVE_SKILL_DIR="$SKILL_ROOT"
  write_trace_wrapper "$tmp/repo/scripts/bd-ship.sh" "bd-ship-wrapper"
  write_trace_wrapper "$tmp/repo/scripts/merge-wait.sh" "merge-wait-wrapper"
  write_trace_wrapper "$tmp/repo/scripts/queue-hygiene.sh" "queue-hygiene-wrapper"
}

test_pipeline_driver_retries_shipping_stage_and_runs_cleanup() (
  set -euo pipefail
  local tmp output status
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  setup_pipeline_driver_fixture "$tmp"
  export BD_SHOW_JSON='[{"id":"mfcapp-123","status":"open","labels":["stage:shipping"]}]'

  set +e
  output="$(cd "$tmp/repo" && "$PIPELINE_DRIVER_SCRIPT" mfcapp-123 2>&1)"
  status=$?
  set -e

  assert_eq "0" "$status" "pipeline-driver should resume from stage:shipping"
  assert_contains "$output" "Stage: shipping"
  assert_file_contains "$TRACE_FILE" $'bd-ship-wrapper\tmfcapp-123\t--no-close'
  assert_file_contains "$TRACE_FILE" $'merge-wait-wrapper\tmfcapp-123\t--timeout\t1800'
  assert_file_contains "$TRACE_FILE" $'queue-hygiene-wrapper\t--phase\tafter\ mfcapp-123'
  assert_order "$TRACE_FILE" $'bd-ship-wrapper\tmfcapp-123\t--no-close' $'merge-wait-wrapper\tmfcapp-123\t--timeout\t1800' "shipping should happen before merge wait"
  assert_order "$TRACE_FILE" $'merge-wait-wrapper\tmfcapp-123\t--timeout\t1800' $'queue-hygiene-wrapper\t--phase\tafter\ mfcapp-123' "queue hygiene should run after merge wait"
)

test_pipeline_driver_runs_cleanup_for_closed_bead() (
  set -euo pipefail
  local tmp output status
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  setup_pipeline_driver_fixture "$tmp"
  export BD_SHOW_JSON='[{"id":"mfcapp-123","status":"closed","labels":["stage:landed"]}]'

  set +e
  output="$(cd "$tmp/repo" && "$PIPELINE_DRIVER_SCRIPT" mfcapp-123 2>&1)"
  status=$?
  set -e

  assert_eq "0" "$status" "pipeline-driver should still run cleanup for a closed bead"
  assert_contains "$output" "already closed; resuming cleanup only"
  assert_file_not_contains "$TRACE_FILE" "bd-ship-wrapper"
  assert_file_not_contains "$TRACE_FILE" "merge-wait-wrapper"
  assert_file_contains "$TRACE_FILE" $'queue-hygiene-wrapper\t--phase\tafter\ mfcapp-123'
)

test_pipeline_driver_skips_merge_wait_for_hold_prs() (
  set -euo pipefail
  local tmp output status
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  setup_pipeline_driver_fixture "$tmp"
  write_trace_wrapper_with_stdout "$tmp/repo/scripts/bd-ship.sh" "bd-ship-wrapper" "  PR is held for human review. Remove auto-merge:hold to queue it."
  export BD_SHOW_JSON='[{"id":"mfcapp-123","status":"open","labels":["stage:committed"]}]'

  set +e
  output="$(cd "$tmp/repo" && "$PIPELINE_DRIVER_SCRIPT" mfcapp-123 2>&1)"
  status=$?
  set -e

  assert_eq "0" "$status" "held PRs should exit cleanly without merge-wait timeout"
  assert_contains "$output" "Skipping merge-wait because the PR is intentionally held for review."
  assert_file_contains "$TRACE_FILE" $'bd-ship-wrapper\tmfcapp-123\t--no-close'
  assert_file_not_contains "$TRACE_FILE" "merge-wait-wrapper"
  assert_file_not_contains "$TRACE_FILE" "queue-hygiene-wrapper"
)

run_test "pipeline-driver retries stage:shipping before merge-wait" test_pipeline_driver_retries_shipping_stage_and_runs_cleanup
run_test "pipeline-driver still runs cleanup for closed beads" test_pipeline_driver_runs_cleanup_for_closed_bead
run_test "pipeline-driver skips merge-wait for hold PRs" test_pipeline_driver_skips_merge_wait_for_hold_prs
