#!/usr/bin/env bash
# check-working-tree.sh — beadswave helper for workspace isolation.
#
# Pre-ship gates (lint/typecheck/tests/build) run over the *working tree*.
# Uncommitted changes from unrelated work can poison gate scope: your bead's
# branch shows clean, but the gate fails on files from unrelated changes.
#
# This helper is opt-in. Project pre-ship hooks may source it and call
# `beadswave_check_working_tree` early. When PRESHIP_ISOLATE=1 and uncommitted
# changes are present, it aborts with a message pointing at the real cause.
#
# Usage in a pre-ship hook:
#   if [[ -f "${BEADSWAVE_SKILL_DIR:-$HOME/.claude/skills/beadswave}/scripts/check-working-tree.sh" ]]; then
#     # shellcheck disable=SC1091
#     . "${BEADSWAVE_SKILL_DIR:-$HOME/.claude/skills/beadswave}/scripts/check-working-tree.sh"
#     beadswave_check_working_tree "<target-branch>" || exit 1
#   fi
#
# Defaults to no-op (PRESHIP_ISOLATE unset) so behaviour is unchanged for
# repos that don't need isolation.

beadswave_check_working_tree() {
  local target_branch="${1:-}"
  local repo_root
  local runtime_path
  repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  runtime_path="${BEADSWAVE_SKILL_DIR:-$HOME/.claude/skills/beadswave}/scripts/runtime.sh"

  if ! declare -F beadswave_require_clean_worktree >/dev/null 2>&1; then
    if [[ -f "$runtime_path" ]]; then
      # shellcheck disable=SC1090
      . "$runtime_path"
    else
      echo "beadswave runtime missing at $runtime_path" >&2
      return 1
    fi
  fi

  [[ "${PRESHIP_ISOLATE:-0}" = "1" ]] || return 0

  if ! beadswave_require_clean_worktree "$repo_root" "bd-ship preflight"; then
    echo "  uncommitted file(s) are contaminating the working tree." >&2
    echo "  Pre-ship gates run against the whole working tree." >&2
    echo "  If unrelated changes are present, lint/typecheck/tests can fail for the wrong reason." >&2
    echo "  Options:" >&2
    echo "    1. Commit or discard unrelated changes before shipping" >&2
    echo "    2. Ship from a clean worktree dedicated to this bead" >&2
    echo "  Then re-run bd-ship." >&2
    return 1
  fi

  return 0
}
