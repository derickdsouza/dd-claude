#!/usr/bin/env bash

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL_ROOT="$(cd "$TESTS_DIR/.." && pwd)"

CHECK_WORKTREE_SCRIPT="$SKILL_ROOT/scripts/check-working-tree.sh"
RUNTIME_SCRIPT="$SKILL_ROOT/scripts/runtime.sh"
BD_SHIP_SCRIPT="$SKILL_ROOT/references/templates/bd-ship.sh"
BULK_APPROVE_SCRIPT="$SKILL_ROOT/references/templates/bulk-approve-prs.sh"
INSTALL_SCRIPT="$SKILL_ROOT/references/templates/install.sh"
LINT_SCRIPT="$SKILL_ROOT/references/templates/beadswave-lint.sh"
BRANCH_PRUNE_SCRIPT="$SKILL_ROOT/references/templates/branch-prune.sh"
MONITOR_PRS_SCRIPT="$SKILL_ROOT/references/templates/monitor-prs.sh"
SETUP_DEV_SCRIPT="$SKILL_ROOT/references/templates/setup-dev.sh"
MASS_SHIP_SCRIPT="$SKILL_ROOT/references/templates/mass-ship.sh"
QUEUE_HYGIENE_SCRIPT="$SKILL_ROOT/references/templates/queue-hygiene.sh"
PIPELINE_DRIVER_SCRIPT="$SKILL_ROOT/references/templates/pipeline-driver.sh"
MERGE_WAIT_SCRIPT="$SKILL_ROOT/references/templates/merge-wait.sh"
DOCTOR_SCRIPT="$SKILL_ROOT/references/templates/beadswave-doctor.sh"

fail() {
  echo "not ok - $*" >&2
  exit 1
}

pass() {
  echo "ok - $*"
}

run_test() {
  local name="$1"
  local fn="$2"
  echo "-- $name"
  "$fn"
  pass "$name"
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  local message="${3:-expected '$expected' but got '$actual'}"
  [[ "$actual" == "$expected" ]] || fail "$message"
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local message="${3:-expected output to contain '$needle'}"
  [[ "$haystack" == *"$needle"* ]] || fail "$message"
}

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  local message="${3:-expected output not to contain '$needle'}"
  [[ "$haystack" != *"$needle"* ]] || fail "$message"
}

assert_file_contains() {
  local file="$1"
  local needle="$2"
  local message="${3:-expected '$file' to contain '$needle'}"
  grep -Fq -- "$needle" "$file" || fail "$message"
}

assert_file_not_contains() {
  local file="$1"
  local needle="$2"
  local message="${3:-expected '$file' not to contain '$needle'}"
  if [[ -f "$file" ]] && grep -Fq -- "$needle" "$file"; then
    fail "$message"
  fi
}

assert_order() {
  local file="$1"
  local first="$2"
  local second="$3"
  local message="${4:-expected '$first' before '$second'}"
  local first_line
  local second_line
  first_line=$(grep -nF -- "$first" "$file" | head -n 1 | cut -d: -f1 || true)
  second_line=$(grep -nF -- "$second" "$file" | head -n 1 | cut -d: -f1 || true)
  [[ -n "$first_line" ]] || fail "$message (missing '$first')"
  [[ -n "$second_line" ]] || fail "$message (missing '$second')"
  (( first_line < second_line )) || fail "$message"
}

create_basic_repo() {
  local repo="$1"
  mkdir -p "$repo"
  git init -q "$repo"
  mkdir -p "$repo/.beads/prompts"
  printf 'Create a PR for this bead.\n' > "$repo/.beads/prompts/create-pr.md"
  : > "$repo/.beads/auto-pr.log"
}

write_install_wrapper() {
  local path="$1"
  local target_rel="$2"
  mkdir -p "$(dirname "$path")"
  cat > "$path" <<EOF
#!/usr/bin/env bash
set -euo pipefail
TARGET="$target_rel"
exec "\$TARGET" "\$@"
EOF
  chmod +x "$path"
}

write_trace_exec_wrapper() {
  local path="$1"
  local label="$2"
  local target="$3"
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
exec "$target" "\$@"
EOF
  chmod +x "$path"
}

write_common_stubs() {
  local bin_dir="$1"
  mkdir -p "$bin_dir"

  cat > "$bin_dir/bd" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
trace="${TRACE_FILE:?}"
cmd="${1:-}"
if [[ $# -gt 0 ]]; then
  shift
fi
{
  printf 'bd'
  [[ -n "$cmd" ]] && printf '\t%q' "$cmd"
  for arg in "$@"; do
    printf '\t%q' "$arg"
  done
  printf '\n'
} >> "$trace"
  case "$cmd" in
  show)
    requested="${1:-}"
    if [[ -n "${BD_SHOW_MATCH_ID:-}" && "$requested" != "$BD_SHOW_MATCH_ID" ]]; then
      exit 1
    fi
    if [[ -n "${BD_SHOW_JSON:-}" ]]; then
      printf '%s\n' "$BD_SHOW_JSON"
    else
      printf '%s\n' '[{"id":"bd-123","status":"open"}]'
    fi
    ;;
  create)
    if [[ -n "${BD_CREATE_JSON:-}" ]]; then
      printf '%s\n' "$BD_CREATE_JSON"
    else
      printf '%s\n' '{"id":"bd-sub"}'
    fi
    ;;
  update)
    exit "${BD_UPDATE_EXIT_CODE:-0}"
    ;;
  close)
    exit "${BD_CLOSE_EXIT_CODE:-0}"
    ;;
  list)
    if [[ -n "${BD_LIST_JSON:-}" ]]; then
      printf '%s\n' "$BD_LIST_JSON"
    else
      printf '%s\n' '[{"id":"demo-bd-12345"}]'
    fi
    ;;
  *)
    echo "unexpected bd command: $cmd" >&2
    exit 99
    ;;
esac
EOF
  chmod +x "$bin_dir/bd"

  cat > "$bin_dir/bun" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
trace="${TRACE_FILE:?}"
{
  printf 'bun'
  for arg in "$@"; do
    printf '\t%q' "$arg"
  done
  printf '\n'
} >> "$trace"
case "$*" in
  "run lint") exit "${BUN_LINT_EXIT_CODE:-0}" ;;
  "run typecheck") exit "${BUN_TYPECHECK_EXIT_CODE:-0}" ;;
  "run test --run") exit "${BUN_TEST_EXIT_CODE:-0}" ;;
  "test") exit "${BUN_TEST_EXIT_CODE:-0}" ;;
  *) exit 0 ;;
esac
EOF
  chmod +x "$bin_dir/bun"

  cat > "$bin_dir/claude" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
trace="${TRACE_FILE:?}"
{
  printf 'claude'
  for arg in "$@"; do
    printf '\t%q' "$arg"
  done
  printf '\n'
} >> "$trace"
cat >/dev/null
case "${CLAUDE_MODE:-success}" in
  success)
    printf 'PR_NUMBER=%s\n' "${CLAUDE_PR_NUMBER:-321}"
    printf 'PR_LABEL=%s\n' "${CLAUDE_PR_LABEL:-auto-merge}"
    ;;
  missing_pr)
    printf 'PR_LABEL=%s\n' "${CLAUDE_PR_LABEL:-auto-merge}"
    ;;
  fail)
    echo "claude failed" >&2
    exit 1
    ;;
  *)
    echo "unexpected CLAUDE_MODE: ${CLAUDE_MODE}" >&2
    exit 99
    ;;
esac
EOF
  chmod +x "$bin_dir/claude"

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
if [[ "${1:-}" == "pr" && "${2:-}" == "comment" ]]; then
  exit "${GH_PR_COMMENT_EXIT_CODE:-0}"
fi
if [[ "${1:-}" == "pr" && "${2:-}" == "view" ]]; then
  case "${GH_PR_VIEW_MODE:-open}" in
    merged)
      printf '%s\n' '{"state":"MERGED","mergedAt":"2026-04-21T00:00:00Z","autoMergeRequest":null}'
      ;;
    auto)
      printf '%s\n' '{"state":"OPEN","mergedAt":null,"autoMergeRequest":{"enabledAt":"2026-04-21T00:00:00Z"}}'
      ;;
    open)
      printf '%s\n' '{"state":"OPEN","mergedAt":null,"autoMergeRequest":null}'
      ;;
    custom)
      # Note: ${VAR:-{}} parses as default of "{" plus literal "}", which
      # appends a spurious closing brace. Use a quoted default to avoid it.
      printf '%s\n' "${GH_PR_VIEW_JSON:-"{}"}"
      ;;
    *)
      echo "unexpected GH_PR_VIEW_MODE: ${GH_PR_VIEW_MODE}" >&2
      exit 99
      ;;
  esac
  exit 0
fi
if [[ "${1:-}" == "pr" && "${2:-}" == "list" ]]; then
  if [[ " $* " == *" --label auto-merge "* && -n "${GH_PR_LIST_AUTO_MERGE_JSON:-}" ]]; then
    printf '%s\n' "$GH_PR_LIST_AUTO_MERGE_JSON"
    exit 0
  fi
  # Generic label match: tests can set GH_PR_LIST_LABEL_MATCH_LABEL=<label>
  # and GH_PR_LIST_LABEL_MATCH_JSON=<json> to stub a non-default orphan label.
  if [[ -n "${GH_PR_LIST_LABEL_MATCH_LABEL:-}" \
        && " $* " == *" --label ${GH_PR_LIST_LABEL_MATCH_LABEL} "* \
        && -n "${GH_PR_LIST_LABEL_MATCH_JSON:-}" ]]; then
    printf '%s\n' "$GH_PR_LIST_LABEL_MATCH_JSON"
    exit 0
  fi
  if [[ -n "${GH_PR_LIST_ORPHAN_JSON:-}" ]]; then
    printf '%s\n' "$GH_PR_LIST_ORPHAN_JSON"
    exit 0
  fi
  if [[ -n "${GH_PR_LIST_JSON:-}" ]]; then
    printf '%s\n' "$GH_PR_LIST_JSON"
    exit 0
  fi
  exit 0
fi
if [[ "${1:-}" == "pr" && "${2:-}" == "merge" ]]; then
  merge_method=""
  for arg in "$@"; do
    case "$arg" in
      --squash|--merge|--rebase)
        merge_method="$arg"
        ;;
    esac
  done
  if [[ -n "${GH_PR_MERGE_UNSTABLE_METHODS:-}" && " ${GH_PR_MERGE_UNSTABLE_METHODS} " == *" ${merge_method} "* ]]; then
    echo "GraphQL: Pull request Pull request is in unstable status (enablePullRequestAutoMerge)" >&2
    exit 1
  fi
  if [[ -n "${GH_PR_MERGE_FAIL_METHODS:-}" && " ${GH_PR_MERGE_FAIL_METHODS} " == *" ${merge_method} "* ]]; then
    if [[ -n "${GH_PR_MERGE_FAIL_OUTPUT:-}" ]]; then
      printf '%s\n' "${GH_PR_MERGE_FAIL_OUTPUT}" >&2
    fi
    exit "${GH_PR_MERGE_FAIL_EXIT_CODE:-1}"
  fi
  exit "${GH_PR_MERGE_EXIT_CODE:-0}"
fi
exit 0
EOF
  chmod +x "$bin_dir/gh"

  cat > "$bin_dir/timeout" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
trace="${TRACE_FILE:?}"
{
  printf 'timeout'
  for arg in "$@"; do
    printf '\t%q' "$arg"
  done
  printf '\n'
} >> "$trace"
shift
exec "$@"
EOF
  chmod +x "$bin_dir/timeout"

  cat > "$bin_dir/gtimeout" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
trace="${TRACE_FILE:?}"
{
  printf 'gtimeout'
  for arg in "$@"; do
    printf '\t%q' "$arg"
  done
  printf '\n'
} >> "$trace"
shift
exec "$@"
EOF
  chmod +x "$bin_dir/gtimeout"
}
