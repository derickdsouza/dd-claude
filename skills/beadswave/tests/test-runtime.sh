#!/usr/bin/env bash
set -euo pipefail

. "$(dirname "$0")/lib/testlib.sh"

test_session_key_prefers_explicit_agent_slot() (
  set -euo pipefail
  export BEADSWAVE_AGENT_SLOT='agent slot/alpha'
  export CLAUDE_SESSION_ID='session-123'
  # shellcheck disable=SC1090
  . "$RUNTIME_SCRIPT"

  local key
  key="$(beadswave_session_key)"
  assert_eq "agent_slot_alpha" "$key" "explicit agent slot should win and be sanitized"
)

test_session_key_falls_back_to_tty() (
  set -euo pipefail
  unset BEADSWAVE_AGENT_SLOT CLAUDE_SESSION_ID CODEX_SESSION_ID CMUX_SESSION_ID TERM_SESSION_ID KITTY_WINDOW_ID WEZTERM_PANE TMUX_PANE WINDOWID
  export BEADSWAVE_TTY_OVERRIDE='/dev/ttys012'
  # shellcheck disable=SC1090
  . "$RUNTIME_SCRIPT"

  local key
  key="$(beadswave_session_key)"
  assert_eq "dev_ttys012" "$key" "tty fallback should produce a stable sanitized key"
)

test_resolve_bd_ship_prefers_repo_wrapper() (
  set -euo pipefail
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  create_basic_repo "$tmp/repo"
  mkdir -p "$tmp/repo/scripts" "$tmp/bin"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$tmp/repo/scripts/bd-ship.sh"
  chmod +x "$tmp/repo/scripts/bd-ship.sh"
  printf '#!/usr/bin/env bash\necho PATH_BD_SHIP\n' > "$tmp/bin/bd-ship"
  chmod +x "$tmp/bin/bd-ship"
  export PATH="$tmp/bin:$PATH"
  # shellcheck disable=SC1090
  . "$RUNTIME_SCRIPT"

  local repo_root
  repo_root="$(cd "$tmp/repo" && pwd -P)"
  local resolved
  resolved="$(cd "$tmp/repo" && beadswave_resolve_bd_ship)"
  assert_eq "$repo_root/scripts/bd-ship.sh" "$resolved" "repo wrapper should beat PATH bd-ship"
)

test_resolve_bd_ship_falls_back_to_path() (
  set -euo pipefail
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  create_basic_repo "$tmp/repo"
  mkdir -p "$tmp/bin"
  printf '#!/usr/bin/env bash\necho PATH_BD_SHIP\n' > "$tmp/bin/bd-ship"
  chmod +x "$tmp/bin/bd-ship"
  export PATH="$tmp/bin:$PATH"
  # shellcheck disable=SC1090
  . "$RUNTIME_SCRIPT"

  local resolved
  resolved="$(cd "$tmp/repo" && beadswave_resolve_bd_ship)"
  assert_eq "$tmp/bin/bd-ship" "$resolved" "PATH bd-ship should be used when no repo wrapper exists"
)

test_resolve_pipeline_driver_prefers_repo_wrapper() (
  set -euo pipefail
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  create_basic_repo "$tmp/repo"
  mkdir -p "$tmp/repo/scripts"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$tmp/repo/scripts/pipeline-driver.sh"
  chmod +x "$tmp/repo/scripts/pipeline-driver.sh"
  # shellcheck disable=SC1090
  . "$RUNTIME_SCRIPT"

  local repo_root resolved
  repo_root="$(cd "$tmp/repo" && pwd -P)"
  resolved="$(cd "$tmp/repo" && beadswave_resolve_pipeline_driver)"
  assert_eq "$repo_root/scripts/pipeline-driver.sh" "$resolved" "repo pipeline-driver wrapper should win"
)

test_resolve_merge_wait_falls_back_to_skill_template() (
  set -euo pipefail
  local tmp resolved
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  create_basic_repo "$tmp/repo"
  # shellcheck disable=SC1090
  . "$RUNTIME_SCRIPT"

  resolved="$(cd "$tmp/repo" && beadswave_resolve_merge_wait)"
  assert_eq "$MERGE_WAIT_SCRIPT" "$resolved" "merge-wait should fall back to the skill template when no repo wrapper exists"
)

test_tmpfile_returns_unique_paths() (
  set -euo pipefail
  # shellcheck disable=SC1090
  . "$RUNTIME_SCRIPT"

  local one two
  one="$(beadswave_tmpfile preship)"
  two="$(beadswave_tmpfile preship)"

  [[ -f "$one" ]] || fail "first tmpfile was not created"
  [[ -f "$two" ]] || fail "second tmpfile was not created"
  [[ "$one" != "$two" ]] || fail "tmpfile helper returned the same path twice"
  assert_contains "$(basename "$one")" "preship." "tmpfile should preserve the requested prefix"
  rm -f "$one" "$two"
)

test_agent_name_helpers_round_trip() (
  set -euo pipefail
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  create_basic_repo "$tmp/repo"
  export BEADSWAVE_AGENT_SLOT='agent/session-42'
  # shellcheck disable=SC1090
  . "$RUNTIME_SCRIPT"

  beadswave_write_agent_name "gamma" "$tmp/repo"

  local agent_name
  agent_name="$(beadswave_read_agent_name "$tmp/repo")"
  assert_eq "gamma" "$agent_name" "agent helper should round-trip the agent name"
  [[ -f "$tmp/repo/.beads/.agent-agent_session-42" ]] || fail "agent helper should write the session-keyed file"
)

test_recent_agent_names_filters_stale_files() (
  set -euo pipefail
  local tmp recent
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  create_basic_repo "$tmp/repo"
  mkdir -p "$tmp/repo/.beads"
  printf 'alpha\n' > "$tmp/repo/.beads/.agent-fresh"
  printf 'beta\n' > "$tmp/repo/.beads/.agent-stale"
  python3 - "$tmp/repo/.beads/.agent-stale" <<'PY'
import os
import sys
import time

path = sys.argv[1]
old = time.time() - (5 * 60 * 60)
os.utime(path, (old, old))
PY
  # shellcheck disable=SC1090
  . "$RUNTIME_SCRIPT"

  recent="$(beadswave_recent_agent_names "$tmp/repo" 60)"
  assert_contains "$recent" "alpha" "recent agent helper should include fresh sessions"
  assert_not_contains "$recent" "beta" "recent agent helper should ignore stale sessions"
)

test_clear_git_locks_removes_top_level_locks() (
  set -euo pipefail
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  create_basic_repo "$tmp/repo"
  # shellcheck disable=SC1090
  . "$RUNTIME_SCRIPT"

  : > "$tmp/repo/.git/index.lock"
  : > "$tmp/repo/.git/HEAD.lock"

  beadswave_clear_git_locks "$tmp/repo"

  [[ ! -e "$tmp/repo/.git/index.lock" ]] || fail "index.lock should be removed"
  [[ ! -e "$tmp/repo/.git/HEAD.lock" ]] || fail "HEAD.lock should be removed"
)

test_lock_helpers_use_lock_directories() (
  set -euo pipefail
  local tmp lock_dir
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  create_basic_repo "$tmp/repo"
  # shellcheck disable=SC1090
  . "$RUNTIME_SCRIPT"

  lock_dir="$(beadswave_lock_dir "$tmp/repo" queue-hygiene)"
  beadswave_lock_acquire "$lock_dir" || fail "first lock acquisition should succeed"
  if beadswave_lock_acquire "$lock_dir"; then
    fail "second lock acquisition should fail while the lock directory exists"
  fi
  [[ -d "$lock_dir" ]] || fail "lock directory should exist after acquire"
  beadswave_lock_release "$lock_dir"
  [[ ! -e "$lock_dir" ]] || fail "lock directory should be removed after release"
)

test_project_prefix_prefers_bd_issue_prefix() (
  set -euo pipefail
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  create_basic_repo "$tmp/repo"
  export TRACE_FILE="$tmp/trace.log"
  write_common_stubs "$tmp/bin"
  export PATH="$tmp/bin:$PATH"
  export BD_LIST_JSON='[{"id":"portfolio-manager-oivqp.4"}]'
  # shellcheck disable=SC1090
  . "$RUNTIME_SCRIPT"

  local prefix
  prefix="$(cd "$tmp/repo" && beadswave_project_prefix)"
  assert_eq "portfolio-manager" "$prefix" "project prefix should come from live bead ids when available"
)

test_expand_bead_id_qualifies_short_ids() (
  set -euo pipefail
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  create_basic_repo "$tmp/repo"
  export TRACE_FILE="$tmp/trace.log"
  write_common_stubs "$tmp/bin"
  export PATH="$tmp/bin:$PATH"
  export BD_LIST_JSON='[{"id":"portfolio-manager-oivqp.4"}]'
  export BD_SHOW_MATCH_ID='portfolio-manager-oivqp.4'
  export BD_SHOW_JSON='[{"id":"portfolio-manager-oivqp.4","status":"open"}]'
  # shellcheck disable=SC1090
  . "$RUNTIME_SCRIPT"

  local expanded
  expanded="$(cd "$tmp/repo" && beadswave_expand_bead_id oivqp.4)"
  assert_eq "portfolio-manager-oivqp.4" "$expanded" "short bead ids should be expanded with the project prefix"
)

test_request_pr_auto_merge_retries_methods() (
  set -euo pipefail
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  create_basic_repo "$tmp/repo"
  export TRACE_FILE="$tmp/trace.log"
  write_common_stubs "$tmp/bin"
  export PATH="$tmp/bin:$PATH"
  export GH_PR_MERGE_FAIL_METHODS='--squash'
  export GH_PR_MERGE_FAIL_OUTPUT='squash disabled'
  # shellcheck disable=SC1090
  . "$RUNTIME_SCRIPT"

  local method
  method="$(beadswave_request_pr_auto_merge 321)"
  assert_eq "--merge" "$method" "auto-merge helper should fall through to the next method"
  assert_order "$TRACE_FILE" $'gh\tpr\tmerge\t321\t--squash\t--auto\t--delete-branch' $'gh\tpr\tmerge\t321\t--merge\t--auto\t--delete-branch' "merge helper should retry with the next method"
)

run_test "runtime session key prefers explicit agent slot" test_session_key_prefers_explicit_agent_slot
run_test "runtime session key falls back to tty" test_session_key_falls_back_to_tty
run_test "runtime resolves repo-local bd-ship first" test_resolve_bd_ship_prefers_repo_wrapper
run_test "runtime resolves PATH bd-ship as fallback" test_resolve_bd_ship_falls_back_to_path
run_test "runtime resolves repo-local pipeline-driver first" test_resolve_pipeline_driver_prefers_repo_wrapper
run_test "runtime resolves merge-wait from the skill template" test_resolve_merge_wait_falls_back_to_skill_template
run_test "runtime tmpfile helper returns unique files" test_tmpfile_returns_unique_paths
run_test "runtime agent-name helpers round-trip session state" test_agent_name_helpers_round_trip
run_test "runtime recent-agent helper filters stale sessions" test_recent_agent_names_filters_stale_files
run_test "runtime clears top-level git lock files safely" test_clear_git_locks_removes_top_level_locks
run_test "runtime lock helpers use lock directories" test_lock_helpers_use_lock_directories
run_test "runtime derives project prefix from bead ids" test_project_prefix_prefers_bd_issue_prefix
run_test "runtime expands short bead ids" test_expand_bead_id_qualifies_short_ids
run_test "runtime retries GitHub auto-merge methods" test_request_pr_auto_merge_retries_methods
