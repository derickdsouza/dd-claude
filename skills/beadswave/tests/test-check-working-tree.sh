#!/usr/bin/env bash
set -euo pipefail

. "$(dirname "$0")/lib/testlib.sh"

test_noop_when_isolation_disabled() (
  set -euo pipefail
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  create_basic_repo "$tmp/repo"
  export TRACE_FILE="$tmp/trace.log"
  write_common_stubs "$tmp/bin"
  export PATH="$tmp/bin:$PATH"
  . "$CHECK_WORKTREE_SCRIPT"
  unset PRESHIP_ISOLATE

  local output status
  set +e
  output="$(cd "$tmp/repo" && beadswave_check_working_tree "fix/target" 2>&1)"
  status=$?
  set -e

  assert_eq "0" "$status" "isolation-disabled call should be a no-op"
  assert_eq "" "$output" "isolation-disabled call should not print anything"
)

test_detects_uncommitted_changes() (
  set -euo pipefail
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  create_basic_repo "$tmp/repo"
  mkdir -p "$tmp/repo/src"
  printf 'dirty\n' > "$tmp/repo/src/a.ts"
  cd "$tmp/repo" && git add -A && git -c user.name=T -c user.email=t@t commit -m "seed" -q
  printf 'changed\n' > "$tmp/repo/src/a.ts"
  export TRACE_FILE="$tmp/trace.log"
  write_common_stubs "$tmp/bin"
  export PATH="$tmp/bin:$PATH"
  export PRESHIP_ISOLATE=1
  . "$CHECK_WORKTREE_SCRIPT"

  local output status
  set +e
  output="$(cd "$tmp/repo" && beadswave_check_working_tree "fix/target" 2>&1)"
  status=$?
  set -e

  assert_eq "1" "$status" "uncommitted changes should abort isolation"
  assert_contains "$output" "uncommitted file(s)"
  assert_contains "$output" "src/a.ts"
)

test_detects_staged_changes() (
  set -euo pipefail
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  create_basic_repo "$tmp/repo"
  printf 'seed\n' > "$tmp/repo/README.md"
  cd "$tmp/repo" && git add -A && git -c user.name=T -c user.email=t@t commit -m "seed" -q
  mkdir -p "$tmp/repo/src"
  printf 'new\n' > "$tmp/repo/src/new.ts"
  cd "$tmp/repo" && git add src/new.ts
  export TRACE_FILE="$tmp/trace.log"
  write_common_stubs "$tmp/bin"
  export PATH="$tmp/bin:$PATH"
  export PRESHIP_ISOLATE=1
  . "$CHECK_WORKTREE_SCRIPT"

  local output status
  set +e
  output="$(cd "$tmp/repo" && beadswave_check_working_tree "fix/target" 2>&1)"
  status=$?
  set -e

  assert_eq "1" "$status" "staged changes should abort isolation"
  assert_contains "$output" "uncommitted file(s)"
  assert_contains "$output" "src/new.ts"
)

test_passes_for_clean_workspace() (
  set -euo pipefail
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  create_basic_repo "$tmp/repo"
  printf 'seed\n' > "$tmp/repo/README.md"
  cd "$tmp/repo" && git add -A && git -c user.name=T -c user.email=t@t commit -m "seed" -q
  export TRACE_FILE="$tmp/trace.log"
  write_common_stubs "$tmp/bin"
  export PATH="$tmp/bin:$PATH"
  export PRESHIP_ISOLATE=1
  . "$CHECK_WORKTREE_SCRIPT"

  local output status
  set +e
  output="$(cd "$tmp/repo" && beadswave_check_working_tree "fix/target" 2>&1)"
  status=$?
  set -e

  assert_eq "0" "$status" "clean workspace should pass"
  assert_eq "" "$output" "clean workspace should stay quiet"
)

test_detects_in_progress_git_operation() (
  set -euo pipefail
  local tmp git_dir output status
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  create_basic_repo "$tmp/repo"
  printf 'seed\n' > "$tmp/repo/README.md"
  cd "$tmp/repo" && git add -A && git -c user.name=T -c user.email=t@t commit -m "seed" -q
  git_dir="$(cd "$tmp/repo" && git rev-parse --git-dir)"
  : > "$tmp/repo/$git_dir/CHERRY_PICK_HEAD"
  export TRACE_FILE="$tmp/trace.log"
  write_common_stubs "$tmp/bin"
  export PATH="$tmp/bin:$PATH"
  export PRESHIP_ISOLATE=1
  . "$CHECK_WORKTREE_SCRIPT"

  set +e
  output="$(cd "$tmp/repo" && beadswave_check_working_tree "fix/target" 2>&1)"
  status=$?
  set -e

  assert_eq "1" "$status" "in-progress git operations should abort isolation"
  assert_contains "$output" "mid-cherry-pick"
)

run_test "check-working-tree no-op when disabled" test_noop_when_isolation_disabled
run_test "check-working-tree detects uncommitted changes" test_detects_uncommitted_changes
run_test "check-working-tree detects staged changes" test_detects_staged_changes
run_test "check-working-tree passes clean workspace" test_passes_for_clean_workspace
run_test "check-working-tree detects in-progress git operations" test_detects_in_progress_git_operation
