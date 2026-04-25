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

test_queue_hygiene_auto_heals_stale_shipping_labels() (
  set -euo pipefail
  local tmp output status
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  setup_queue_hygiene_fixture "$tmp"
  # One bead stuck in stage:shipping for 2 hours — orphaned by an earlier
  # crashed ship. Queue-hygiene should auto-heal it, not hard-fail.
  export BD_LIST_JSON='[{"id":"mfcapp-stale","status":"in_progress","updated_at":"2020-01-01T00:00:00Z","labels":["stage:shipping"]}]'
  # bead_rollback reads the current stage via `bd show` before transitioning;
  # the shared fake-bd shim returns BD_SHOW_JSON for any id.
  export BD_SHOW_JSON='[{"id":"mfcapp-stale","status":"in_progress","labels":["stage:shipping"]}]'

  set +e
  output="$(cd "$tmp/repo" && "$QUEUE_HYGIENE_SCRIPT" --phase preflight 2>&1)"
  status=$?
  set -e

  assert_eq "0" "$status" "queue-hygiene should heal stale stage:shipping and succeed"
  assert_contains "$output" "auto-healed stale stage:shipping on mfcapp-stale"
  assert_file_contains "$TRACE_FILE" $'bd\tupdate\tmfcapp-stale\t--remove-label\tstage:shipping'
)

test_queue_hygiene_respects_block_mode_for_stale_shipping() (
  set -euo pipefail
  local tmp output status
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  setup_queue_hygiene_fixture "$tmp"
  export BD_LIST_JSON='[{"id":"mfcapp-stale","status":"in_progress","updated_at":"2020-01-01T00:00:00Z","labels":["stage:shipping"]}]'

  set +e
  output="$(cd "$tmp/repo" && BEADSWAVE_STALE_SHIPPING_MODE=block "$QUEUE_HYGIENE_SCRIPT" --phase preflight 2>&1)"
  status=$?
  set -e

  assert_eq "8" "$status" "block mode should preserve fail-closed behavior"
  assert_contains "$output" "refusing to auto-heal"
  assert_file_not_contains "$TRACE_FILE" $'bd\tupdate\tmfcapp-stale\t--remove-label\tstage:shipping'
)

test_queue_hygiene_gcs_closed_bead_manifests() (
  set -euo pipefail
  local tmp output status closed_manifest open_manifest
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  setup_queue_hygiene_fixture "$tmp"
  # Two manifests: one for an open bead (keep), one for a closed bead
  # whose file is older than the GC window (delete).
  mkdir -p "$tmp/repo/.git/beadswave-state"
  closed_manifest="$tmp/repo/.git/beadswave-state/mfcapp-closed.json"
  open_manifest="$tmp/repo/.git/beadswave-state/mfcapp-open.json"
  printf '%s\n' '{"bead_id":"mfcapp-closed","stage":"landed"}' > "$closed_manifest"
  printf '%s\n' '{"bead_id":"mfcapp-open","stage":"merging"}' > "$open_manifest"
  # Backdate the closed manifest beyond the 7-day default window
  touch -t 202001010000 "$closed_manifest"
  # GC queries `bd list --status=closed`; return mfcapp-closed so the
  # manifest sweep knows which files are safe to remove.
  export BD_LIST_JSON='[{"id":"mfcapp-closed","status":"closed"}]'

  set +e
  output="$(cd "$tmp/repo" && "$QUEUE_HYGIENE_SCRIPT" --phase preflight 2>&1)"
  status=$?
  set -e

  assert_eq "0" "$status" "queue-hygiene should succeed while GC'ing stale manifests"
  assert_contains "$output" "garbage-collected 1 stale manifest"
  [ ! -f "$closed_manifest" ] || fail "closed bead manifest should have been removed"
  [ -f "$open_manifest" ] || fail "open bead manifest should have been preserved"
)

run_test "queue-hygiene runs prune and monitor passes" test_queue_hygiene_runs_prune_and_monitor
run_test "queue-hygiene garbage-collects manifests for old closed beads" test_queue_hygiene_gcs_closed_bead_manifests
run_test "queue-hygiene fails closed on dirty tracked changes" test_queue_hygiene_fails_closed_on_dirty_tracked_changes
run_test "queue-hygiene auto-heals stale stage:shipping labels" test_queue_hygiene_auto_heals_stale_shipping_labels
run_test "queue-hygiene respects block mode for stale stage:shipping" test_queue_hygiene_respects_block_mode_for_stale_shipping
