#!/usr/bin/env bash
set -euo pipefail

. "$(dirname "$0")/lib/testlib.sh"

setup_doctor_fixture() {
  local tmp="$1"
  create_basic_repo "$tmp/repo"
  export TRACE_FILE="$tmp/trace.log"
  write_common_stubs "$tmp/bin"
  export PATH="$tmp/bin:$PATH"
  export BEADSWAVE_SKILL_DIR="$SKILL_ROOT"
}

manifest_path_for() {
  local repo="$1"
  local bead_id="$2"
  printf '%s/.git/beadswave-state/%s.json\n' "$repo" "$bead_id"
}

write_manifest() {
  local repo="$1"
  local bead_id="$2"
  local content="$3"
  local path
  path="$(manifest_path_for "$repo" "$bead_id")"
  mkdir -p "$(dirname "$path")"
  printf '%s\n' "$content" > "$path"
}

test_doctor_repairs_merged_pr_open_bead() (
  set -euo pipefail
  local tmp output status
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  setup_doctor_fixture "$tmp"
  export BD_SHOW_JSON='[{"id":"mfcapp-123","status":"in_progress","external_refs":[{"ref":"gh-321"}],"labels":["stage:merging"]}]'
  export GH_PR_VIEW_MODE=custom
  export GH_PR_VIEW_JSON='{"number":321,"state":"MERGED","mergedAt":"2026-04-21T00:00:00Z","headRefName":"fix/mfcapp-123","headRefOid":"deadbeef","mergeCommit":{"oid":"deadbeef"},"autoMergeRequest":null,"statusCheckRollup":[]}'
  write_manifest "$tmp/repo" "mfcapp-123" '{"bead_id":"mfcapp-123","stage":"merging","branch":"fix/mfcapp-123","base_sha":"abc123","pr_number":321,"external_ref":"gh-321","hold_state":"auto-merge-ready"}'

  set +e
  output="$(cd "$tmp/repo" && "$DOCTOR_SCRIPT" --fix --json mfcapp-123 2>&1)"
  status=$?
  set -e

  assert_eq "0" "$status" "doctor should succeed when reconciling a merged open bead"
  assert_contains "$output" '"kind": "merged-pr-open-bead"'
  assert_contains "$output" '"auto_fixed": true'
  assert_file_contains "$TRACE_FILE" $'bd\tclose\tmfcapp-123'
  assert_file_contains "$(manifest_path_for "$tmp/repo" "mfcapp-123")" '"stage": "landed"'
)

test_doctor_reports_missing_manifest_for_target_bead() (
  set -euo pipefail
  local tmp output status
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  setup_doctor_fixture "$tmp"

  set +e
  output="$(cd "$tmp/repo" && "$DOCTOR_SCRIPT" --json mfcapp-123 2>&1)"
  status=$?
  set -e

  assert_eq "0" "$status" "doctor should treat missing manifests as findings, not hard failures"
  assert_contains "$output" '"kind": "missing-manifest"'
  assert_not_contains "$output" '"auto_fixed": true'
)

run_test "beadswave doctor repairs merged PRs whose beads stayed open" test_doctor_repairs_merged_pr_open_bead
run_test "beadswave doctor reports missing manifests for targeted beads" test_doctor_reports_missing_manifest_for_target_bead
