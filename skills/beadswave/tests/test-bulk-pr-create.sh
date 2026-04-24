#!/usr/bin/env bash
set -euo pipefail

. "$(dirname "$0")/lib/testlib.sh"

BULK_PR_CREATE_SCRIPT="$SKILL_ROOT/references/templates/bulk-pr-create.sh"

write_bulk_pr_create_gh_stub() {
  local path="$1"
  mkdir -p "$(dirname "$path")"
  cat > "$path" <<'EOF'
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

if [[ "${1:-}" == "pr" && "${2:-}" == "list" ]]; then
  head_branch=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --head)
        head_branch="${2:-}"
        shift 2
        ;;
      *)
        shift
        ;;
    esac
  done
  if [[ "$head_branch" == "fix/existing" ]]; then
    printf '1\n'
  else
    printf '0\n'
  fi
  exit 0
fi

if [[ "${1:-}" == "pr" && "${2:-}" == "create" ]]; then
  printf 'https://github.com/example/repo/pull/41\n'
  exit 0
fi

if [[ "${1:-}" == "pr" && "${2:-}" == "comment" ]]; then
  exit 0
fi

if [[ "${1:-}" == "pr" && "${2:-}" == "merge" ]]; then
  exit 0
fi

exit 0
EOF
  chmod +x "$path"
}

setup_bulk_pr_create_fixture() {
  local tmp="$1"
  create_basic_repo "$tmp/repo"
  export TRACE_FILE="$tmp/trace.log"
  export BEADSWAVE_SKILL_DIR="$SKILL_ROOT"
  mkdir -p "$tmp/bin"
  write_bulk_pr_create_gh_stub "$tmp/bin/gh"
  export PATH="$tmp/bin:$PATH"
}

test_bulk_pr_create_creates_pr_and_requests_auto_merge() (
  set -euo pipefail
  local tmp branches output status
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  setup_bulk_pr_create_fixture "$tmp"

  branches="$tmp/branches.txt"
  printf 'fix/new\nfix/existing\n' > "$branches"

  set +e
  output="$(cd "$tmp/repo" && "$BULK_PR_CREATE_SCRIPT" "$branches" 2>&1)"
  status=$?
  set -e

  assert_eq "0" "$status" "bulk-pr-create should succeed with one created and one skipped branch"
  assert_contains "$output" "CREATED #41: fix/new"
  assert_contains "$output" "SKIP (existing PR): fix/existing"
  assert_contains "$output" "Created: 1"
  assert_contains "$output" "Skipped: 1"
  assert_file_contains "$TRACE_FILE" $'gh\tpr\tcreate\t--head\tfix/new\t--base\tmain'
  assert_file_not_contains "$TRACE_FILE" $'gh\tpr\tcreate\t--head\tfix/existing'
)

run_test "bulk-pr-create creates PRs and requests auto-merge" test_bulk_pr_create_creates_pr_and_requests_auto_merge
