#!/usr/bin/env bash
set -euo pipefail

. "$(dirname "$0")/lib/testlib.sh"

setup_bd_ship_fixture() {
  local tmp="$1"
  git init -q --bare "$tmp/remote.git"
  create_basic_repo "$tmp/repo"
  cd "$tmp/repo"
  git -c user.name=T -c user.email=t@t commit -q --allow-empty -m "init"
  git remote add origin "$tmp/remote.git"
  git push -q -u origin main 2>/dev/null || true
  git checkout -q -b fix/mfcapp-123
  git checkout -q -b fix/metrics-oivqp1
  git checkout -q main
  cd - >/dev/null
  printf '{}' > "$tmp/repo/bun.lock"
  printf '{ "scripts": { "test": "vitest run" } }\n' > "$tmp/repo/package.json"
  export TRACE_FILE="$tmp/trace.log"
  write_common_stubs "$tmp/bin"
  export PATH="$tmp/bin:$PATH"
  export BEADSWAVE_SKILL_DIR="$SKILL_ROOT"
  export PRESHIP_ISOLATE=0
  export MERGIFY_QUEUE_TIMEOUT_SECONDS=0
  export GH_PR_VIEW_MODE=auto
  # Fixture beads have no scope: label; skip the scope gate so the test
  # exercising the gate under test (not the scope gate) runs to completion.
  export BEADSWAVE_SKIP_SCOPE_CHECK=1
  export BEADSWAVE_SKIP_FAILURE_BUDGET=1
}

test_gate_failure_creates_current_preship_subissue() (
  set -euo pipefail
  local tmp output status
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  setup_bd_ship_fixture "$tmp"
  export BD_SHOW_JSON='[{"id":"mfcapp-123","status":"in_progress"}]'

  set +e
  output="$(cd "$tmp/repo" && LINT_CMD='echo lint exploded >&2; exit 1' TYPECHECK_CMD='' TEST_CMD='' "$BD_SHIP_SCRIPT" mfcapp-123 --branch fix/mfcapp-123 2>&1)"
  status=$?
  set -e

  assert_eq "6" "$status" "lint failure should return the lint gate exit code"
  assert_contains "$output" "lint gate failed"
  assert_file_contains "$TRACE_FILE" $'bd\tcreate\t--parent\tmfcapp-123'
  assert_file_contains "$TRACE_FILE" $'\t--title\tpreship-fail:'
  assert_file_contains "$TRACE_FILE" $'\t--description\t'
  assert_file_contains "$TRACE_FILE" $'\t--labels\tpreship-fail'
  assert_file_contains "$TRACE_FILE" $'\t--json'
  assert_file_not_contains "$TRACE_FILE" "--body"
  assert_file_not_contains "$TRACE_FILE" $'bd\tclose\tmfcapp-123'
)

test_happy_path_uses_repo_test_script_and_closes_after_merge() (
  set -euo pipefail
  local tmp output status
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  setup_bd_ship_fixture "$tmp"
  export BD_SHOW_JSON='[{"id":"mfcapp-123","status":"in_progress"}]'
  export CLAUDE_MODE=success
  export CLAUDE_PR_NUMBER=321
  export CLAUDE_PR_LABEL=auto-merge
  export GH_PR_VIEW_MODE=merged

  set +e
  output="$(cd "$tmp/repo" && "$BD_SHIP_SCRIPT" mfcapp-123 --branch fix/mfcapp-123 2>&1)"
  status=$?
  set -e

  assert_eq "0" "$status" "happy path should succeed"
  assert_contains "$output" "PR #321 created"
  assert_contains "$output" "Pushing branch"
  assert_file_contains "$TRACE_FILE" $'bun\trun\tlint'
  assert_file_contains "$TRACE_FILE" $'bun\trun\ttypecheck'
  assert_file_contains "$TRACE_FILE" $'bun\trun\ttest\t--run'
  assert_file_not_contains "$TRACE_FILE" $'bun\ttest'
  assert_order "$TRACE_FILE" $'bun\trun\tlint' $'claude\t-p\t--dangerously-skip-permissions' "gates should happen before PR creation"
  assert_order "$TRACE_FILE" $'claude\t-p\t--dangerously-skip-permissions' $'bd\tclose\tmfcapp-123' "bead close must happen after PR creation"
  assert_order "$TRACE_FILE" $'bd\tupdate\tmfcapp-123\t--external-ref\tgh-321\t--add-label\tshipped-via-pr' $'bd\tclose\tmfcapp-123' "provenance must be attached before close"
  assert_file_contains "$tmp/repo/.beads/auto-pr.log" '"pr":321'
)

test_hold_pr_reports_human_review_message() (
  set -euo pipefail
  local tmp output status
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  setup_bd_ship_fixture "$tmp"
  export BD_SHOW_JSON='[{"id":"mfcapp-123","status":"in_progress"}]'
  export CLAUDE_MODE=success
  export CLAUDE_PR_NUMBER=321
  export CLAUDE_PR_LABEL=auto-merge:hold
  export GH_PR_VIEW_MODE=open

  set +e
  output="$(cd "$tmp/repo" && "$BD_SHIP_SCRIPT" mfcapp-123 --branch fix/mfcapp-123 2>&1)"
  status=$?
  set -e

  assert_eq "0" "$status" "hold PRs should still ship successfully"
  assert_contains "$output" "PR is held for human review"
  assert_contains "$output" "Approve the PR to trigger merge"
  assert_contains "$output" "Leaving bead open at stage:merging until PR #321 is actually merged."
  assert_file_not_contains "$TRACE_FILE" $'gh\tpr\tmerge'
  assert_file_not_contains "$TRACE_FILE" $'bd\tclose\tmfcapp-123'
)

test_merge_handoff_failure_keeps_bead_open() (
  set -euo pipefail
  local tmp output status
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  setup_bd_ship_fixture "$tmp"
  export BD_SHOW_JSON='[{"id":"mfcapp-123","status":"in_progress"}]'
  export CLAUDE_MODE=success
  export CLAUDE_PR_NUMBER=321
  export CLAUDE_PR_LABEL=auto-merge
  export GH_PR_VIEW_MODE=open
  export GH_PR_MERGE_EXIT_CODE=1

  set +e
  output="$(cd "$tmp/repo" && "$BD_SHIP_SCRIPT" mfcapp-123 --branch fix/mfcapp-123 2>&1)"
  status=$?
  set -e

  assert_eq "4" "$status" "merge handoff failure should leave the bead open"
  assert_file_not_contains "$TRACE_FILE" $'bd\tclose\tmfcapp-123'
)

test_rejects_support_file_diff_by_default() (
  set -euo pipefail
  local tmp output status
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  setup_bd_ship_fixture "$tmp"
  export BD_SHOW_JSON='[{"id":"mfcapp-123","status":"in_progress"}]'
  cd "$tmp/repo"
  git checkout -q fix/mfcapp-123
  mkdir -p src
  printf 'x\n' > ".beads/.agent-alpha"
  printf 'x\n' > "src/a.ts"
  git add -A && git -c user.name=T -c user.email=t@t commit -q -m "add support files"
  cd - >/dev/null

  set +e
  output="$(cd "$tmp/repo" && "$BD_SHIP_SCRIPT" mfcapp-123 2>&1)"
  status=$?
  set -e

  assert_eq "1" "$status" "support/session file diffs should fail closed"
  assert_contains "$output" "Refusing to ship session-state files in this bead diff"
  assert_contains "$output" ".beads/.agent-alpha"
  assert_file_not_contains "$TRACE_FILE" $'git\tpush\t-u\torigin'
  assert_file_not_contains "$TRACE_FILE" $'bd\tclose\tmfcapp-123'
)

test_pr_creation_failure_never_closes_bead() (
  set -euo pipefail
  local tmp output status
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  setup_bd_ship_fixture "$tmp"
  export BD_SHOW_JSON='[{"id":"mfcapp-123","status":"in_progress"}]'
  export CLAUDE_MODE=missing_pr

  set +e
  output="$(cd "$tmp/repo" && "$BD_SHIP_SCRIPT" mfcapp-123 --branch fix/mfcapp-123 2>&1)"
  status=$?
  set -e

  assert_eq "4" "$status" "missing PR metadata should fail PR creation"
  assert_contains "$output" "did not return a PR number"
  assert_file_not_contains "$TRACE_FILE" $'bd\tclose\tmfcapp-123'
)

test_short_bead_id_resolves_to_project_prefix() (
  set -euo pipefail
  local tmp output status
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  setup_bd_ship_fixture "$tmp"
  export BD_LIST_JSON='[{"id":"portfolio-manager-oivqp.1"}]'
  export BD_SHOW_MATCH_ID='portfolio-manager-oivqp.1'
  export BD_SHOW_JSON='[{"id":"portfolio-manager-oivqp.1","status":"in_progress"}]'
  export CLAUDE_MODE=success
  export CLAUDE_PR_NUMBER=654
  export CLAUDE_PR_LABEL=auto-merge
  export GH_PR_VIEW_MODE=merged

  set +e
  output="$(cd "$tmp/repo" && "$BD_SHIP_SCRIPT" oivqp.1 --branch fix/metrics-oivqp1 2>&1)"
  status=$?
  set -e

  assert_eq "0" "$status" "short bead ids should resolve before shipping"
  assert_contains "$output" "Resolved short bead id 'oivqp.1' -> 'portfolio-manager-oivqp.1'."
  assert_file_contains "$TRACE_FILE" $'bd\tshow\tportfolio-manager-oivqp.1\t--json'
  assert_file_contains "$TRACE_FILE" $'bd\tclose\tportfolio-manager-oivqp.1'
)

test_rebase_aborts_when_branch_checked_out_in_sibling_worktree() (
  set -euo pipefail
  local tmp output status
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  setup_bd_ship_fixture "$tmp"
  export BD_SHOW_JSON='[{"id":"mfcapp-123","status":"in_progress"}]'
  # Force a behind-origin state so the rebase branch actually runs.
  (
    cd "$tmp/repo"
    git -c user.name=T -c user.email=t@t commit -q --allow-empty -m "advance main"
    git push -q origin main
    git reset -q --hard HEAD^
    git checkout -q fix/mfcapp-123
    git -c user.name=T -c user.email=t@t commit -q --allow-empty -m "bead work"
    git checkout -q main
    # Sibling worktree now owns fix/mfcapp-123.
    git worktree add -q "$tmp/sibling" fix/mfcapp-123 >/dev/null 2>&1
  )

  set +e
  output="$(cd "$tmp/repo" && "$BD_SHIP_SCRIPT" mfcapp-123 --branch fix/mfcapp-123 2>&1)"
  status=$?
  set -e

  assert_eq "23" "$status" "worktree collision should exit 23"
  assert_contains "$output" "already checked out in worktree"
  assert_contains "$output" "$tmp/sibling"
  assert_file_not_contains "$TRACE_FILE" $'bd\tcreate\t--parent\tmfcapp-123'
)

test_rebase_conflict_clears_stage_shipping_label() (
  set -euo pipefail
  local tmp output status
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  setup_bd_ship_fixture "$tmp"
  export BD_SHOW_JSON='[{"id":"mfcapp-123","status":"in_progress"}]'

  # Create a genuine rebase conflict: main and fix/mfcapp-123 both modify
  # the same line of the same file, off a shared parent.
  (
    cd "$tmp/repo"
    git checkout -q main
    printf 'shared\n' > conflicted.txt
    git add conflicted.txt
    git -c user.name=T -c user.email=t@t commit -q -m "seed conflicted.txt"
    git push -q origin main

    git checkout -q fix/mfcapp-123
    git reset -q --hard main
    printf 'branch-version\n' > conflicted.txt
    git add conflicted.txt
    git -c user.name=T -c user.email=t@t commit -q -m "bead changes conflicted.txt"

    git checkout -q main
    printf 'main-version\n' > conflicted.txt
    git add conflicted.txt
    git -c user.name=T -c user.email=t@t commit -q -m "main changes conflicted.txt"
    git push -q origin main
  )

  set +e
  output="$(cd "$tmp/repo" && "$BD_SHIP_SCRIPT" mfcapp-123 --branch fix/mfcapp-123 2>&1)"
  status=$?
  set -e

  assert_eq "21" "$status" "rebase conflict should exit 21"
  assert_contains "$output" "Rebase on origin/main has conflicts"
  assert_file_contains "$TRACE_FILE" $'bd\tupdate\tmfcapp-123\t--add-label\tstage:shipping'
  assert_file_contains "$TRACE_FILE" $'bd\tupdate\tmfcapp-123\t--remove-label\tstage:shipping'
  assert_file_not_contains "$TRACE_FILE" $'bd\tclose\tmfcapp-123'
)

run_test "bd-ship creates current preship sub-issue" test_gate_failure_creates_current_preship_subissue
run_test "bd-ship happy path uses repo test script and closes after merge" test_happy_path_uses_repo_test_script_and_closes_after_merge
run_test "bd-ship reports hold PRs as waiting on human review" test_hold_pr_reports_human_review_message
run_test "bd-ship keeps bead open when merge handoff fails" test_merge_handoff_failure_keeps_bead_open
run_test "bd-ship rejects support/session file diffs by default" test_rejects_support_file_diff_by_default
run_test "bd-ship leaves bead open when PR creation fails" test_pr_creation_failure_never_closes_bead
run_test "bd-ship resolves short bead ids before shipping" test_short_bead_id_resolves_to_project_prefix
run_test "bd-ship aborts when feature branch is in a sibling worktree" test_rebase_aborts_when_branch_checked_out_in_sibling_worktree
run_test "bd-ship clears stage:shipping label on rebase conflict" test_rebase_conflict_clears_stage_shipping_label
