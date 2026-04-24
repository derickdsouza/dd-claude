#!/usr/bin/env bash
set -euo pipefail

. "$(dirname "$0")/lib/testlib.sh"

setup_monitor_fixture() {
  local tmp="$1"
  create_basic_repo "$tmp/repo"
  export TRACE_FILE="$tmp/trace.log"
  write_common_stubs "$tmp/bin"
  export PATH="$tmp/bin:$PATH"
  export BEADSWAVE_SKILL_DIR="$SKILL_ROOT"
}

test_orphans_repairs_stuck_labeled_prs_missing_auto_merge() (
  set -euo pipefail
  local tmp output status
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  setup_monitor_fixture "$tmp"
  export GH_PR_LIST_AUTO_MERGE_JSON='[{"n":1522,"title":"fix(metrics): stuck merge handoff","branch":"fix/stuck-1522","labels":["auto-merge"],"updated":"2026-04-20T00:00:00Z","checks":[{"name":"gate","conclusion":"SUCCESS"}]}]'
  export GH_PR_LIST_ORPHAN_JSON='[]'
  export GH_PR_VIEW_MODE=custom
  export GH_PR_VIEW_JSON='{"state":"OPEN","mergedAt":null,"autoMergeRequest":null,"comments":[]}'

  set +e
  output="$(cd "$tmp/repo" && "$MONITOR_PRS_SCRIPT" --orphans --stuck 1 2>&1)"
  status=$?
  set -e

  assert_eq "0" "$status" "repairing a stuck labeled PR should not mark monitor-prs as failing"
  assert_contains "$output" "Scanning for stuck labeled PRs missing merge handoff"
  assert_contains "$output" "Repairing #1522"
  assert_file_contains "$TRACE_FILE" $'gh\tpr\tmerge\t1522\t--squash\t--auto\t--delete-branch'
)

test_orphans_respects_custom_label_env() (
  set -euo pipefail
  local tmp output status
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  setup_monitor_fixture "$tmp"
  # No PRs carry the default auto-merge label in this repo — this shop
  # uses 'ship-it'. Without configurability, the scan silently finds
  # nothing and crashed handoffs never get repaired.
  export GH_PR_LIST_AUTO_MERGE_JSON='[]'
  export GH_PR_LIST_ORPHAN_JSON='[]'
  export GH_PR_LIST_LABEL_MATCH_LABEL='ship-it'
  export GH_PR_LIST_LABEL_MATCH_JSON='[{"number":9090,"title":"fix(orders): stuck custom-label handoff","headRefName":"fix/orders-9090"}]'
  export GH_PR_VIEW_MODE=custom
  export GH_PR_VIEW_JSON='{"state":"OPEN","mergedAt":null,"autoMergeRequest":null,"comments":[]}'

  set +e
  output="$(cd "$tmp/repo" && BEADSWAVE_ORPHAN_LABEL=ship-it "$MONITOR_PRS_SCRIPT" --orphans --stuck 1 2>&1)"
  status=$?
  set -e

  assert_eq "0" "$status" "custom orphan label should drive the scan without failing"
  assert_contains "$output" "Repairing #9090"
  assert_file_contains "$TRACE_FILE" $'gh\tpr\tmerge\t9090\t--squash\t--auto\t--delete-branch'
)

run_test "monitor-prs repairs stuck labeled PRs missing auto-merge handoff" test_orphans_repairs_stuck_labeled_prs_missing_auto_merge
run_test "monitor-prs orphan scan honors BEADSWAVE_ORPHAN_LABEL" test_orphans_respects_custom_label_env
