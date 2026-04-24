#!/usr/bin/env bash
set -euo pipefail

. "$(dirname "$0")/lib/testlib.sh"

write_bulk_approve_gh_stub() {
  local bin_dir="$1"
  mkdir -p "$bin_dir"
  cat > "$bin_dir/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
trace="${TRACE_FILE:?}"
{
  printf 'gh'
  for arg in "$@"; do
    printf '\t%q' "$arg"
  done
  printf '\n'
} >> "$trace"

cmd="${1:-}"
case "$cmd" in
  repo)
    printf '%s\n' "${GH_REPO_VIEW:-owner/repo}"
    ;;
  auth)
    sub="${2:-}"
    case "$sub" in
      status)
        printf 'Logged in to github.com account %s\n' "${GH_USER_A:-user-a}"
        printf 'Logged in to github.com account %s\n' "${GH_USER_B:-user-b}"
        ;;
      switch)
        exit 0
        ;;
      *)
        echo "unexpected gh auth subcommand: $sub" >&2
        exit 99
        ;;
    esac
    ;;
  pr)
    sub="${2:-}"
    case "$sub" in
      list)
        printf '%s\n' "${GH_PR_LIST:-}"
        ;;
      review)
        pr_num="${3:-}"
        fail_var="GH_PR_${pr_num}_REVIEW_EXIT"
        exit "${!fail_var:-0}"
        ;;
      *)
        echo "unexpected gh pr subcommand: $sub" >&2
        exit 99
        ;;
    esac
    ;;
  api)
    endpoint="${2:-}"
    pr_num="$(printf '%s' "$endpoint" | sed -E 's#.*pulls/([0-9]+).*#\1#')"
    case "$endpoint" in
      */pulls/*/commits)
        var_name="GH_PR_${pr_num}_LAST_PUSHER"
        printf '%s\n' "${!var_name:-unknown}"
        ;;
      */pulls/*/reviews)
        var_name="GH_PR_${pr_num}_APPROVALS"
        printf '%s\n' "${!var_name:-}"
        ;;
      */pulls/*)
        var_name="GH_PR_${pr_num}_OPENER"
        printf '%s\n' "${!var_name:-unknown}"
        ;;
      *)
        echo "unexpected gh api endpoint: $endpoint" >&2
        exit 99
        ;;
    esac
    ;;
  *)
    echo "unexpected gh command: $cmd" >&2
    exit 99
    ;;
esac
EOF
  chmod +x "$bin_dir/gh"
}

setup_bulk_approve_fixture() {
  local tmp="$1"
  export TRACE_FILE="$tmp/trace.log"
  write_bulk_approve_gh_stub "$tmp/bin"
  export PATH="$tmp/bin:$PATH"
  export GH_REPO_VIEW="owner/repo"
  export GH_USER_A="user-a"
  export GH_USER_B="user-b"
}

test_approves_with_non_last_pusher_account() (
  set -euo pipefail
  local tmp output status
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  setup_bulk_approve_fixture "$tmp"
  export GH_PR_LIST='11'
  export GH_PR_11_OPENER='user-a'
  export GH_PR_11_LAST_PUSHER='user-a'
  export GH_PR_11_APPROVALS=''

  set +e
  output="$("$BULK_APPROVE_SCRIPT" 2>&1)"
  status=$?
  set -e

  assert_eq "0" "$status" "eligible PR should be approved"
  assert_contains "$output" "PR #11: opener=user-a last pusher=user-a -> approving as user-b"
  assert_file_contains "$TRACE_FILE" $'gh\tauth\tswitch\t--user\tuser-b'
  assert_file_contains "$TRACE_FILE" $'gh\tpr\treview\t11\t--approve'
)

test_skips_impossible_self_approval_case() (
  set -euo pipefail
  local tmp output status
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  setup_bulk_approve_fixture "$tmp"
  export GH_PR_LIST='12'
  export GH_PR_12_OPENER='user-b'
  export GH_PR_12_LAST_PUSHER='user-a'
  export GH_PR_12_APPROVALS=''

  set +e
  output="$("$BULK_APPROVE_SCRIPT" 2>&1)"
  status=$?
  set -e

  assert_eq "0" "$status" "impossible self-approval should be skipped, not fail"
  assert_contains "$output" "two-account approval would require self-approval"
  assert_file_not_contains "$TRACE_FILE" $'gh\tpr\treview\t12\t--approve'
)

test_skips_when_last_pusher_outside_config() (
  set -euo pipefail
  local tmp output status
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  setup_bulk_approve_fixture "$tmp"
  export GH_PR_LIST='13'
  export GH_PR_13_OPENER='user-a'
  export GH_PR_13_LAST_PUSHER='outside-user'
  export GH_PR_13_APPROVALS=''

  set +e
  output="$("$BULK_APPROVE_SCRIPT" 2>&1)"
  status=$?
  set -e

  assert_eq "0" "$status" "outside-config last pusher should be skipped"
  assert_contains "$output" "last pusher 'outside-user' is outside configured accounts"
  assert_file_not_contains "$TRACE_FILE" $'gh\tpr\treview\t13\t--approve'
)

test_skips_when_correct_approver_already_approved() (
  set -euo pipefail
  local tmp output status
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  setup_bulk_approve_fixture "$tmp"
  export GH_PR_LIST='14'
  export GH_PR_14_OPENER='user-a'
  export GH_PR_14_LAST_PUSHER='user-a'
  export GH_PR_14_APPROVALS='user-b'

  set +e
  output="$("$BULK_APPROVE_SCRIPT" 2>&1)"
  status=$?
  set -e

  assert_eq "0" "$status" "already-approved PR should be skipped"
  assert_contains "$output" "already approved by user-b"
  assert_file_not_contains "$TRACE_FILE" $'gh\tpr\treview\t14\t--approve'
)

run_test "bulk-approve approves with non-last-pusher account" test_approves_with_non_last_pusher_account
run_test "bulk-approve skips impossible self-approval" test_skips_impossible_self_approval_case
run_test "bulk-approve skips outside-config last pushers" test_skips_when_last_pusher_outside_config
run_test "bulk-approve skips when correct approver already approved" test_skips_when_correct_approver_already_approved
