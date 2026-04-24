#!/usr/bin/env bash
set -euo pipefail

. "$(dirname "$0")/lib/testlib.sh"

setup_branch_prune_fixture() {
  local tmp="$1"
  mkdir -p "$tmp"
  git init -q --bare "$tmp/remote.git"

  local repo="$tmp/repo"
  mkdir -p "$repo"
  git init -q -b main "$repo"
  git -C "$repo" config user.name "Test User"
  git -C "$repo" config user.email "test@example.com"
  printf 'seed\n' > "$repo/README.md"
  git -C "$repo" add README.md
  git -C "$repo" commit -q -m "seed"
  git -C "$repo" remote add origin "$tmp/remote.git"
  git -C "$repo" push -q -u origin main
  git -C "$repo" branch fix/one
  git -C "$repo" branch fix/two

  export TRACE_FILE="$tmp/trace.log"
  write_common_stubs "$tmp/bin"
  export PATH="$tmp/bin:$PATH"
  export BEADSWAVE_SKILL_DIR="$SKILL_ROOT"
}

test_branch_prune_removes_merged_branches() (
  set -euo pipefail
  local tmp output status
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  setup_branch_prune_fixture "$tmp"

  set +e
  output="$(cd "$tmp/repo" && "$BRANCH_PRUNE_SCRIPT" 2>&1)"
  status=$?
  set -e

  assert_eq "0" "$status" "branch-prune should succeed"
  assert_contains "$output" "pruned: fix/one"
  assert_contains "$output" "pruned: fix/two"
  assert_contains "$output" "branch-prune: 2 pruned"
)

run_test "branch-prune removes merged branches" test_branch_prune_removes_merged_branches
