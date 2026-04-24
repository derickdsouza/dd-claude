#!/usr/bin/env bash
set -euo pipefail

. "$(dirname "$0")/lib/testlib.sh"

setup_merge_wait_fixture() {
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

test_merge_wait_marks_manifest_landed_after_merge() (
  set -euo pipefail
  local tmp output status
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  setup_merge_wait_fixture "$tmp"
  export BD_SHOW_JSON='[{"id":"mfcapp-123","status":"in_progress","external_refs":[{"ref":"gh-321"}],"labels":["stage:merging"]}]'
  export GH_PR_VIEW_MODE=custom
  export GH_PR_VIEW_JSON='{"state":"MERGED","mergedAt":"2026-04-21T00:00:00Z","mergeCommit":{"oid":"deadbeef"},"autoMergeRequest":null,"statusCheckRollup":[]}'
  write_manifest "$tmp/repo" "mfcapp-123" '{"bead_id":"mfcapp-123","stage":"merging","branch":"fix/mfcapp-123","base_sha":"abc123"}'

  set +e
  output="$(cd "$tmp/repo" && "$MERGE_WAIT_SCRIPT" mfcapp-123 --json 2>&1)"
  status=$?
  set -e

  assert_eq "0" "$status" "merge-wait should succeed when the PR is already merged"
  assert_contains "$output" '"state":"merged"'
  assert_file_contains "$TRACE_FILE" $'bd\tclose\tmfcapp-123'
  assert_file_contains "$(manifest_path_for "$tmp/repo" "mfcapp-123")" '"stage": "landed"'
  assert_file_contains "$(manifest_path_for "$tmp/repo" "mfcapp-123")" '"merge_commit": "deadbeef"'
)

test_merge_wait_records_timeout_in_manifest() (
  set -euo pipefail
  local tmp output status
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  setup_merge_wait_fixture "$tmp"
  export BD_SHOW_JSON='[{"id":"mfcapp-123","status":"in_progress","external_refs":[{"ref":"gh-321"}],"labels":["stage:merging"]}]'
  export GH_PR_VIEW_MODE=open
  write_manifest "$tmp/repo" "mfcapp-123" '{"bead_id":"mfcapp-123","stage":"merging","branch":"fix/mfcapp-123","base_sha":"abc123"}'

  set +e
  output="$(cd "$tmp/repo" && "$MERGE_WAIT_SCRIPT" mfcapp-123 --timeout 0 --poll 1 2>&1)"
  status=$?
  set -e

  assert_eq "2" "$status" "merge-wait should time out when timeout is zero"
  assert_contains "$output" "Timeout after 0s"
  assert_file_not_contains "$TRACE_FILE" $'bd\tclose\tmfcapp-123'
  assert_file_contains "$(manifest_path_for "$tmp/repo" "mfcapp-123")" '"last_successful_step": "merge-wait-timeout"'
  assert_file_contains "$(manifest_path_for "$tmp/repo" "mfcapp-123")" '"stage": "merging"'
  # Stuck beads should be queryable via `bd list --label merge-timeout`.
  assert_file_contains "$TRACE_FILE" $'bd\tupdate\tmfcapp-123\t--add-label\tmerge-timeout'
)

run_test "merge-wait marks the manifest landed after merge" test_merge_wait_marks_manifest_landed_after_merge
run_test "merge-wait records timeout state in the manifest" test_merge_wait_records_timeout_in_manifest
