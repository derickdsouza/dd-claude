#!/usr/bin/env bash
# Shared runtime helpers for beadswave commands, prompts, and starter templates.

beadswave_sanitize_key() {
  printf '%s' "$1" | sed -E 's/[^A-Za-z0-9._-]+/_/g; s/^_+//; s/_+$//'
}

beadswave_session_key() {
  local candidate
  for candidate in \
    "${BEADSWAVE_AGENT_SLOT:-}" \
    "${CLAUDE_SESSION_ID:-}" \
    "${CODEX_SESSION_ID:-}" \
    "${CMUX_SESSION_ID:-}" \
    "${TERM_SESSION_ID:-}" \
    "${KITTY_WINDOW_ID:-}" \
    "${WEZTERM_PANE:-}" \
    "${TMUX_PANE:-}" \
    "${WINDOWID:-}"
  do
    if [[ -n "$candidate" ]]; then
      beadswave_sanitize_key "$candidate"
      return 0
    fi
  done

  if [[ -n "${BEADSWAVE_TTY_OVERRIDE:-}" ]]; then
    candidate="$BEADSWAVE_TTY_OVERRIDE"
  else
    candidate="$(tty 2>/dev/null || true)"
  fi
  if [[ -n "$candidate" && "$candidate" != "not a tty" ]]; then
    beadswave_sanitize_key "$candidate"
    return 0
  fi

  if [[ -n "${PPID:-}" ]]; then
    printf 'ppid-%s\n' "$(beadswave_sanitize_key "$PPID")"
    return 0
  fi
  printf 'pid-%s\n' "$(beadswave_sanitize_key "$$")"
}

beadswave_agent_file() {
  local repo_root="${1:-}"
  if [[ -z "$repo_root" ]]; then
    repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  fi
  printf '%s/.beads/.agent-%s\n' "$repo_root" "$(beadswave_session_key)"
}

beadswave_read_agent_name() {
  local repo_root="${1:-}"
  local agent_file=""
  agent_file="$(beadswave_agent_file "$repo_root")"
  [[ -f "$agent_file" ]] || return 1
  sed -n '1p' "$agent_file"
}

beadswave_write_agent_name() {
  local agent_name="${1:-}"
  local repo_root="${2:-}"
  local agent_file=""

  [[ -n "$agent_name" ]] || return 1
  agent_file="$(beadswave_agent_file "$repo_root")"
  mkdir -p "$(dirname "$agent_file")"
  printf '%s\n' "$agent_name" > "$agent_file"
}

beadswave_recent_agent_names() {
  local repo_root="${1:-}"
  local fresh_minutes="${2:-240}"

  if [[ -z "$repo_root" ]]; then
    repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  fi

  python3 - "$repo_root" "$fresh_minutes" <<'PY'
import glob
import os
import sys
import time

repo_root = sys.argv[1]
try:
    fresh_minutes = int(sys.argv[2] or "240")
except ValueError:
    fresh_minutes = 240

cutoff = time.time() - (fresh_minutes * 60)
seen = set()

for path in sorted(glob.glob(os.path.join(repo_root, ".beads", ".agent-*"))):
    try:
        if os.path.getmtime(path) < cutoff:
            continue
        with open(path, encoding="utf-8") as handle:
            agent_name = handle.readline().strip()
    except OSError:
        continue
    if not agent_name or agent_name in seen:
        continue
    seen.add(agent_name)
    print(agent_name)
PY
}

beadswave_project_prefix() {
  local repo_root="${1:-}"
  local sample_id=""
  if [[ -z "$repo_root" ]]; then
    repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  fi

  if [[ -n "${BEADSWAVE_PROJECT_PREFIX:-}" ]]; then
    printf '%s\n' "$BEADSWAVE_PROJECT_PREFIX"
    return 0
  fi

  if command -v bd >/dev/null 2>&1; then
    sample_id="$(bd list -n 1 --json 2>/dev/null | python3 -c '
import json
import sys

try:
    payload = json.load(sys.stdin)
except Exception:
    sys.exit(0)

if isinstance(payload, list):
    payload = payload[0] if payload else {}

issue_id = payload.get("id", "")
if issue_id:
    print(issue_id)
' 2>/dev/null || true)"
    if [[ -n "$sample_id" && "$sample_id" == *-* ]]; then
      printf '%s\n' "${sample_id%-*}"
      return 0
    fi
  fi

  basename "$repo_root"
}

beadswave_expand_bead_id() {
  local raw_id="${1:-}"
  local repo_root="${2:-}"
  local candidate=""

  [[ -n "$raw_id" ]] || return 1
  if [[ -z "$repo_root" ]]; then
    repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  fi

  if [[ "$raw_id" == *-* ]]; then
    printf '%s\n' "$raw_id"
    return 0
  fi

  candidate="$(beadswave_project_prefix "$repo_root")-$raw_id"

  if command -v bd >/dev/null 2>&1; then
    if bd show "$candidate" --json >/dev/null 2>&1; then
      printf '%s\n' "$candidate"
      return 0
    fi
    if bd show "$raw_id" --json >/dev/null 2>&1; then
      printf '%s\n' "$raw_id"
      return 0
    fi
    return 1
  fi

  printf '%s\n' "$candidate"
}

beadswave_resolve_bd_ship() {
  local repo_root="${1:-}"
  if [[ -z "$repo_root" ]]; then
    repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  fi

  if [[ -x "$repo_root/scripts/bd-ship.sh" ]]; then
    printf '%s/scripts/bd-ship.sh\n' "$repo_root"
    return 0
  fi
  if command -v bd-ship >/dev/null 2>&1; then
    command -v bd-ship
    return 0
  fi
  return 1
}

beadswave_resolve_pipeline_driver() {
  local repo_root="${1:-}"
  local skill_dir="${BEADSWAVE_SKILL_DIR:-$HOME/.claude/skills/beadswave}"
  if [[ -z "$repo_root" ]]; then
    repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  fi

  if [[ -x "$repo_root/scripts/pipeline-driver.sh" ]]; then
    printf '%s/scripts/pipeline-driver.sh\n' "$repo_root"
    return 0
  fi
  if [[ -x "$skill_dir/references/templates/pipeline-driver.sh" ]]; then
    printf '%s/references/templates/pipeline-driver.sh\n' "$skill_dir"
    return 0
  fi
  return 1
}

beadswave_resolve_merge_wait() {
  local repo_root="${1:-}"
  local skill_dir="${BEADSWAVE_SKILL_DIR:-$HOME/.claude/skills/beadswave}"
  if [[ -z "$repo_root" ]]; then
    repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  fi

  if [[ -x "$repo_root/scripts/merge-wait.sh" ]]; then
    printf '%s/scripts/merge-wait.sh\n' "$repo_root"
    return 0
  fi
  if [[ -x "$skill_dir/references/templates/merge-wait.sh" ]]; then
    printf '%s/references/templates/merge-wait.sh\n' "$skill_dir"
    return 0
  fi
  return 1
}

beadswave_resolve_queue_hygiene() {
  local repo_root="${1:-}"
  local skill_dir="${BEADSWAVE_SKILL_DIR:-$HOME/.claude/skills/beadswave}"
  if [[ -z "$repo_root" ]]; then
    repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  fi

  if [[ -x "$repo_root/scripts/queue-hygiene.sh" ]]; then
    printf '%s/scripts/queue-hygiene.sh\n' "$repo_root"
    return 0
  fi
  if [[ -x "$skill_dir/references/templates/queue-hygiene.sh" ]]; then
    printf '%s/references/templates/queue-hygiene.sh\n' "$skill_dir"
    return 0
  fi
  return 1
}

beadswave_resolve_doctor() {
  local repo_root="${1:-}"
  local skill_dir="${BEADSWAVE_SKILL_DIR:-$HOME/.claude/skills/beadswave}"
  if [[ -z "$repo_root" ]]; then
    repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  fi

  if [[ -x "$repo_root/scripts/beadswave-doctor.sh" ]]; then
    printf '%s/scripts/beadswave-doctor.sh\n' "$repo_root"
    return 0
  fi
  if [[ -x "$skill_dir/references/templates/beadswave-doctor.sh" ]]; then
    printf '%s/references/templates/beadswave-doctor.sh\n' "$skill_dir"
    return 0
  fi
  return 1
}

beadswave_state_dir() {
  local repo_root="${1:-}"
  if [[ -z "$repo_root" ]]; then
    repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  fi
  printf '%s/.git/beadswave-state\n' "$repo_root"
}

beadswave_manifest_key() {
  local bead_id="${1:-}"
  [[ -n "$bead_id" ]] || return 1
  beadswave_sanitize_key "$bead_id"
}

beadswave_manifest_path() {
  local bead_id="${1:-}"
  local repo_root="${2:-}"
  [[ -n "$bead_id" ]] || return 1
  if [[ -z "$repo_root" ]]; then
    repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  fi
  printf '%s/%s.json\n' "$(beadswave_state_dir "$repo_root")" "$(beadswave_manifest_key "$bead_id")"
}

beadswave_manifest_read() {
  local bead_id="${1:-}"
  local repo_root="${2:-}"
  local path=""
  path="$(beadswave_manifest_path "$bead_id" "$repo_root")" || return 1
  if [[ -f "$path" ]]; then
    cat "$path"
  else
    printf '{}\n'
  fi
}

beadswave_manifest_write() {
  local bead_id="${1:-}"
  local repo_root="${2:-}"
  local path state_dir tmp
  [[ -n "$bead_id" ]] || return 1
  if [[ -z "$repo_root" ]]; then
    repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  fi

  state_dir="$(beadswave_state_dir "$repo_root")"
  path="$(beadswave_manifest_path "$bead_id" "$repo_root")" || return 1
  mkdir -p "$state_dir"
  tmp="$(beadswave_tmpfile beadswave-manifest)" || return 1

  python3 - "$path" "$bead_id" >"$tmp" <<'PY'
import json
import os
import sys
from datetime import datetime, timezone

path = sys.argv[1]
bead_id = sys.argv[2]

try:
    patch = json.load(sys.stdin)
except Exception as exc:
    raise SystemExit(f"invalid manifest patch: {exc}")

current = {}
if os.path.exists(path):
    try:
        with open(path, encoding="utf-8") as handle:
            current = json.load(handle) or {}
    except Exception:
        current = {}

if not isinstance(current, dict):
    current = {}
if not isinstance(patch, dict):
    raise SystemExit("manifest patch must be a JSON object")

for key, value in patch.items():
    if value is None:
        current.pop(key, None)
    else:
        current[key] = value

current["bead_id"] = bead_id
current["updated_at"] = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
print(json.dumps(current, indent=2, sort_keys=True))
PY
  mv "$tmp" "$path"
}

beadswave_manifest_patch() {
  local bead_id="${1:-}"
  local repo_root="${2:-}"
  local patch_json="${3:-}"
  [[ -n "$bead_id" && -n "$patch_json" ]] || return 1
  printf '%s' "$patch_json" | beadswave_manifest_write "$bead_id" "$repo_root"
}

beadswave_manifest_get() {
  local bead_id="${1:-}"
  local repo_root="${2:-}"
  local field="${3:-}"
  local path=""
  [[ -n "$bead_id" && -n "$field" ]] || return 1
  path="$(beadswave_manifest_path "$bead_id" "$repo_root")" || return 1
  if [[ ! -f "$path" ]]; then
    return 1
  fi
  python3 - "$path" "$field" <<'PY'
import json
import sys

path = sys.argv[1]
field = sys.argv[2]

with open(path, encoding="utf-8") as handle:
    payload = json.load(handle)

value = payload
for part in field.split("."):
    if not isinstance(value, dict) or part not in value:
        raise SystemExit(1)
    value = value[part]

if isinstance(value, (dict, list)):
    print(json.dumps(value, sort_keys=True))
elif value is None:
    print("null")
else:
    print(value)
PY
}

beadswave_manifest_remove() {
  local bead_id="${1:-}"
  local repo_root="${2:-}"
  local path=""
  path="$(beadswave_manifest_path "$bead_id" "$repo_root")" || return 1
  rm -f "$path"
}

beadswave_ref_sha() {
  local repo_root="${1:-}"
  local ref_name="${2:-}"
  [[ -n "$ref_name" ]] || return 1
  if [[ -z "$repo_root" ]]; then
    repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  fi
  (
    cd "$repo_root" &&
    git rev-parse "$ref_name" 2>/dev/null
  )
}

beadswave_merge_base() {
  local repo_root="${1:-}"
  local left_ref="${2:-}"
  local right_ref="${3:-}"
  [[ -n "$left_ref" && -n "$right_ref" ]] || return 1
  if [[ -z "$repo_root" ]]; then
    repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  fi
  (
    cd "$repo_root" &&
    git merge-base "$left_ref" "$right_ref" 2>/dev/null
  )
}

beadswave_diff_name_only() {
  local repo_root="${1:-}"
  local range="${2:-}"
  [[ -n "$range" ]] || return 1
  if [[ -z "$repo_root" ]]; then
    repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  fi
  (
    cd "$repo_root" &&
    git diff --name-only "$range" 2>/dev/null
  ) || true
}

beadswave_count_commits() {
  local repo_root="${1:-}"
  local range="${2:-}"
  [[ -n "$range" ]] || return 1
  if [[ -z "$repo_root" ]]; then
    repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  fi
  (
    cd "$repo_root" &&
    git rev-list --count "$range" 2>/dev/null
  ) || true
}

beadswave_intersect_paths() {
  local left_file="${1:-}"
  local right_file="${2:-}"
  [[ -n "$left_file" && -n "$right_file" ]] || return 1
  python3 - "$left_file" "$right_file" <<'PY'
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    left = {line.strip() for line in handle if line.strip()}
with open(sys.argv[2], encoding="utf-8") as handle:
    right = {line.strip() for line in handle if line.strip()}

for path in sorted(left & right):
    print(path)
PY
}

beadswave_git_dir() {
  local repo_root="${1:-}"
  local git_dir=""
  if [[ -z "$repo_root" ]]; then
    repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  fi

  git_dir="$(
    cd "$repo_root" &&
    git rev-parse --git-dir 2>/dev/null
  )" || return 1

  case "$git_dir" in
    /*) printf '%s\n' "$git_dir" ;;
    *) printf '%s/%s\n' "$repo_root" "$git_dir" ;;
  esac
}

beadswave_git_operation_state() {
  local repo_root="${1:-}"
  local git_dir=""
  if [[ -z "$repo_root" ]]; then
    repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  fi

  git_dir="$(beadswave_git_dir "$repo_root")" || return 0

  if [[ -d "$git_dir/rebase-merge" || -d "$git_dir/rebase-apply" ]]; then
    printf 'rebase\n'
    return 0
  fi
  if [[ -f "$git_dir/CHERRY_PICK_HEAD" ]]; then
    printf 'cherry-pick\n'
    return 0
  fi
  if [[ -f "$git_dir/REVERT_HEAD" ]]; then
    printf 'revert\n'
    return 0
  fi
  if [[ -f "$git_dir/MERGE_HEAD" ]]; then
    printf 'merge\n'
    return 0
  fi
  if [[ -f "$git_dir/BISECT_LOG" ]]; then
    printf 'bisect\n'
    return 0
  fi
  if [[ -f "$git_dir/AM_HEAD" ]]; then
    printf 'am\n'
    return 0
  fi
  return 1
}

beadswave_dirty_paths() {
  local repo_root="${1:-}"
  if [[ -z "$repo_root" ]]; then
    repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  fi

  # System-owned lock files: machine-local artifacts produced by the skill
  # or the Claude Code harness, never part of user work. Filtered out so
  # they don't block queue-hygiene / bd-ship. Extend via
  # BEADSWAVE_DIRTY_IGNORE (newline- or colon-separated glob-free paths).
  local ignore_regex='^(\.beadswave/templates\.lock\.json(\.tmp)?|\.claude/scheduled_tasks\.lock|\.beads/auto-pr\.log)$'
  local extra="${BEADSWAVE_DIRTY_IGNORE:-}"
  if [[ -n "$extra" ]]; then
    local IFS=$'\n:'
    local p
    for p in $extra; do
      [[ -z "$p" ]] && continue
      local escaped
      escaped="$(printf '%s' "$p" | sed 's/[.[\*^$()+?{|]/\\&/g')"
      ignore_regex="${ignore_regex%\$}|^${escaped}\$"
    done
  fi

  {
    (
      cd "$repo_root" &&
      git diff --name-only --ignore-submodules=all 2>/dev/null
    ) || true
    (
      cd "$repo_root" &&
      git diff --cached --name-only --ignore-submodules=all 2>/dev/null
    ) || true
  } | sed '/^$/d' | sort -u | { grep -Ev "$ignore_regex" || true; }
  # Trailing `|| true` keeps an empty grep (exit 1) from tripping `set -e`.
}

beadswave_require_clean_worktree() {
  local repo_root="${1:-}"
  local reason="${2:-operation}"
  local max_paths="${3:-10}"
  local op_state=""
  local dirty_paths=""

  if [[ -z "$repo_root" ]]; then
    repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  fi

  op_state="$(beadswave_git_operation_state "$repo_root" 2>/dev/null || true)"
  if [[ -n "$op_state" ]]; then
    echo "✗ Refusing to continue $reason while git is mid-$op_state." >&2
    echo "  Finish or abort the $op_state before retrying." >&2
    return 1
  fi

  dirty_paths="$(beadswave_dirty_paths "$repo_root" 2>/dev/null || true)"
  if [[ -z "$dirty_paths" ]]; then
    return 0
  fi

  local count
  count="$(printf '%s\n' "$dirty_paths" | wc -l | tr -d ' ')"
  echo "✗ Refusing to continue $reason with $count uncommitted path(s) in the worktree." >&2
  echo "  Paths (first $max_paths):" >&2
  printf '%s\n' "$dirty_paths" | head -"$max_paths" | sed 's/^/    /' >&2
  echo "  Commit, discard, or move the unrelated changes before retrying." >&2
  return 1
}

beadswave_clear_git_locks() {
  local repo_root="${1:-}"
  if [[ -z "$repo_root" ]]; then
    repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  fi
  [[ -d "$repo_root/.git" ]] || return 0

  find "$repo_root/.git" -maxdepth 1 -type f -name '*.lock' -exec rm -f -- {} + 2>/dev/null || true
}

beadswave_lock_dir() {
  local repo_root="${1:-}"
  local lock_name="${2:-waves}"
  if [[ -z "$repo_root" ]]; then
    repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  fi
  printf '%s/.beads/.%s.lockdir\n' "$repo_root" "$lock_name"
}

beadswave_lock_acquire() {
  local lock_dir="${1:-}"
  [[ -n "$lock_dir" ]] || return 1
  mkdir -p "$(dirname "$lock_dir")"
  mkdir "$lock_dir" 2>/dev/null
}

beadswave_lock_release() {
  local lock_dir="${1:-}"
  [[ -n "$lock_dir" ]] || return 0
  rmdir "$lock_dir" 2>/dev/null || true
}

beadswave_worktree_dir() {
  local repo_root="${1:-}"
  local agent="${2:-}"
  [[ -n "$agent" ]] || return 1
  if [[ -z "$repo_root" ]]; then
    repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  fi
  # If we're already inside a worktree, resolve to the main repo's parent.
  local common_dir main_root
  common_dir="$(cd "$repo_root" && git rev-parse --git-common-dir 2>/dev/null)"
  if [[ -n "$common_dir" ]]; then
    main_root="$(cd "$repo_root" && cd "$common_dir/.." && pwd)"
  else
    main_root="$repo_root"
  fi
  printf '%s/%s-%s-worktree\n' "$(dirname "$main_root")" "$(basename "$main_root")" "$agent"
}

beadswave_ensure_worktree() {
  # Create (or report) an isolated worktree for this agent.
  # Echoes the worktree path on success.
  local repo_root="${1:-}"
  local agent="${2:-}"
  local base_ref="${3:-origin/main}"
  [[ -n "$agent" ]] || return 1
  if [[ -z "$repo_root" ]]; then
    repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  fi
  local wt branch
  wt="$(beadswave_worktree_dir "$repo_root" "$agent")"
  branch="drain/$agent"

  if [[ -d "$wt/.git" || -f "$wt/.git" ]]; then
    printf '%s\n' "$wt"
    return 0
  fi

  (cd "$repo_root" && git fetch origin main --prune >/dev/null 2>&1) || true

  # Use existing drain/<agent> branch if present; else create from base_ref.
  if (cd "$repo_root" && git show-ref --verify --quiet "refs/heads/$branch"); then
    (cd "$repo_root" && git worktree add "$wt" "$branch" >/dev/null 2>&1) || return 1
  else
    (cd "$repo_root" && git worktree add -b "$branch" "$wt" "$base_ref" >/dev/null 2>&1) || return 1
  fi
  printf '%s\n' "$wt"
}

beadswave_remove_worktree() {
  local repo_root="${1:-}"
  local agent="${2:-}"
  [[ -n "$agent" ]] || return 1
  if [[ -z "$repo_root" ]]; then
    repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  fi
  local wt
  wt="$(beadswave_worktree_dir "$repo_root" "$agent")"
  [[ -d "$wt" ]] || return 0
  (cd "$repo_root" && git worktree remove "$wt" --force >/dev/null 2>&1) || true
}

beadswave_assert_branch_free_here() {
  # Fail (return 1) if <branch> is checked out in a worktree other than the
  # current one. Used by bd-ship before rebase and by /drain before branch
  # creation to fail fast with a clear error instead of hitting git's cryptic
  # "fatal: '<branch>' is already used by worktree at ..." mid-operation.
  local repo_root="${1:-}"
  local branch="${2:-}"
  [[ -n "$branch" ]] || return 1
  if [[ -z "$repo_root" ]]; then
    repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  fi
  local here_abs
  here_abs="$(cd "$repo_root" && pwd -P)"
  local owner=""
  local wt_abs=""
  local wt_branch=""
  # git worktree list --porcelain emits blocks of "worktree <path>\nHEAD ...\nbranch refs/heads/<name>\n\n"
  while IFS= read -r line; do
    case "$line" in
      "worktree "*)
        wt_abs="$(cd "${line#worktree }" 2>/dev/null && pwd -P)" || wt_abs="${line#worktree }"
        wt_branch=""
        ;;
      "branch refs/heads/"*)
        wt_branch="${line#branch refs/heads/}"
        if [[ "$wt_branch" == "$branch" && "$wt_abs" != "$here_abs" ]]; then
          owner="$wt_abs"
          break
        fi
        ;;
      "")
        wt_abs=""
        wt_branch=""
        ;;
    esac
  done < <(cd "$repo_root" && git worktree list --porcelain 2>/dev/null)

  if [[ -n "$owner" ]]; then
    echo "✗ Branch '$branch' is already checked out in worktree: $owner" >&2
    echo "  Resolve by one of:" >&2
    echo "    - ship from that worktree instead: cd $owner" >&2
    echo "    - free the branch there: (cd $owner && git switch --detach)" >&2
    echo "    - remove that worktree if stale: git worktree remove --force $owner" >&2
    return 1
  fi
  return 0
}

beadswave_fetch_origin_main() {
  local repo_root="${1:-}"
  if [[ -z "$repo_root" ]]; then
    repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  fi

  (
    cd "$repo_root" &&
    git fetch origin main --prune >/dev/null 2>&1
  ) || (
    cd "$repo_root" &&
    git fetch origin --prune >/dev/null 2>&1
  )
}

beadswave_tmpfile() {
  local prefix="${1:-beadswave}"
  local dir="${TMPDIR:-/tmp}"
  local out=""

  rm -f "$dir/${prefix}.XXXXXX" "$dir/${prefix}.XXXXXX.log" 2>/dev/null || true

  out="$(mktemp "${dir}/${prefix}.XXXXXX" 2>/dev/null || true)"
  if [[ -n "$out" ]]; then
    printf '%s\n' "$out"
    return 0
  fi

  out="$(mktemp 2>/dev/null || true)"
  if [[ -n "$out" ]]; then
    printf '%s\n' "$out"
    return 0
  fi

  return 1
}

beadswave_append_issue_note() {
  local issue_id="${1:-}"
  local note_text="${2:-}"

  [[ -n "$issue_id" && -n "$note_text" ]] || return 1

  if bd note "$issue_id" "$note_text" >/dev/null 2>&1; then
    return 0
  fi

  bd update "$issue_id" --append-notes "$note_text" >/dev/null
}

beadswave_reset_issue_open() {
  local issue_id="${1:-}"
  [[ -n "$issue_id" ]] || return 1
  bd update "$issue_id" --assignee "" --status open >/dev/null
}

beadswave_run_gate() {
  local name="$1"
  local cmd="$2"
  printf '  ▶ %-40s' "$name"

  local out
  out="$(beadswave_tmpfile preship)" || {
    echo " ✗"
    echo "  mktemp failed for pre-ship gate output" >&2
    return 1
  }

  if bash -c "$cmd" >"$out" 2>&1; then
    echo " ✓"
    rm -f "$out"
    return 0
  fi

  echo " ✗"
  echo "  --- $name: last 80 lines ---" >&2
  tail -80 "$out" >&2
  echo "  --- full log: $out ---" >&2
  return 1
}

beadswave_pr_merge_methods() {
  case "${BEADSWAVE_GH_PR_MERGE_METHOD:-}" in
    "")
      printf '%s\n' --squash --merge --rebase
      ;;
    squash)
      printf '%s\n' --squash
      ;;
    merge)
      printf '%s\n' --merge
      ;;
    rebase)
      printf '%s\n' --rebase
      ;;
    *)
      echo "Invalid BEADSWAVE_GH_PR_MERGE_METHOD='${BEADSWAVE_GH_PR_MERGE_METHOD}'. Use squash, merge, or rebase." >&2
      return 1
      ;;
  esac
}

beadswave_request_pr_auto_merge() {
  local pr_number="${1:-}"
  local head_sha="${2:-}"
  local merge_flag=""
  local output=""
  local args=()
  local last_output=""

  [[ -n "$pr_number" ]] || return 1

  while IFS= read -r merge_flag; do
    [[ -n "$merge_flag" ]] || continue
    args=(pr merge "$pr_number" "$merge_flag" --auto --delete-branch)
    if [[ -n "$head_sha" ]]; then
      args+=(--match-head-commit "$head_sha")
    fi

    if output="$(gh "${args[@]}" 2>&1)"; then
      printf '%s\n' "$merge_flag"
      return 0
    fi

    if [[ "$output" == *"unstable status"* ]] || [[ "$output" == *"already enabled"* ]] || [[ "$output" == *"Auto merge is already enabled"* ]]; then
      printf '%s\n' "$merge_flag"
      return 0
    fi

    last_output="$output"
  done < <(beadswave_pr_merge_methods)

  if [[ -n "$last_output" ]]; then
    printf '%s\n' "$last_output" >&2
  fi
  return 1
}

# ── Bootstrap fingerprint helpers ─────────────────────────────────────────────
# A bootstrap fingerprint records what was set up in a worktree and when, so
# queue-hygiene and drain can warn when the worktree is stale (lockfile changed,
# node_modules missing, .env absent, etc.) before allowing a new bead to start.
#
# Fingerprint file: <repo_root>/.beadswave/bootstrap.fingerprint
# Format (one key=value per line):
#   bootstrapped_at=<epoch>
#   lockfile_hash=<sha256 of the primary lockfile, or "none">
#   node_modules_present=<0|1>
#   env_present=<0|1>
#   agent=<agent-name>

_beadswave_primary_lockfile() {
  local repo="$1"
  for f in bun.lockb package-lock.json yarn.lock pnpm-lock.yaml Cargo.lock go.sum; do
    if [[ -f "$repo/$f" ]]; then
      printf '%s/%s' "$repo" "$f"
      return 0
    fi
  done
}

beadswave_write_bootstrap_fingerprint() {
  local repo="${1:?repo root required}"
  local agent="${2:-}"
  local fp_dir="$repo/.beadswave"
  local fp_file="$fp_dir/bootstrap.fingerprint"
  mkdir -p "$fp_dir"

  local lockfile_hash="none"
  local lockfile
  lockfile="$(_beadswave_primary_lockfile "$repo")"
  if [[ -n "$lockfile" ]]; then
    lockfile_hash="$(shasum -a 256 "$lockfile" 2>/dev/null | awk '{print $1}' || echo "none")"
  fi

  local nm_present=0
  [[ -d "$repo/node_modules" ]] && nm_present=1

  local env_present=0
  for ef in .env .env.local .env.development .env.development.local; do
    [[ -f "$repo/$ef" ]] && env_present=1 && break
  done

  {
    printf 'bootstrapped_at=%s\n' "$(date +%s)"
    printf 'lockfile_hash=%s\n' "$lockfile_hash"
    printf 'node_modules_present=%s\n' "$nm_present"
    printf 'env_present=%s\n' "$env_present"
    printf 'agent=%s\n' "${agent:-}"
  } > "$fp_file"
}

beadswave_check_bootstrap_fingerprint() {
  # Usage: beadswave_check_bootstrap_fingerprint <repo> [--warn-only]
  # Returns 0 if fingerprint is fresh, 1 if stale or missing.
  # Prints a warning line to stderr if stale (always) or missing (if --warn-only).
  local repo="${1:?repo root required}"
  local warn_only=0
  [[ "${2:-}" == "--warn-only" ]] && warn_only=1

  local fp_file="$repo/.beadswave/bootstrap.fingerprint"

  if [[ ! -f "$fp_file" ]]; then
    echo "  warning: no bootstrap fingerprint found — run scripts/setup-dev.sh first" >&2
    return 1
  fi

  # Read stored values
  local stored_lockfile_hash stored_nm stored_env
  stored_lockfile_hash=$(grep '^lockfile_hash=' "$fp_file" | cut -d= -f2)
  stored_nm=$(grep '^node_modules_present=' "$fp_file" | cut -d= -f2)
  stored_env=$(grep '^env_present=' "$fp_file" | cut -d= -f2)

  local stale_reasons=()

  # Check if lockfile changed since bootstrap
  local current_lockfile_hash="none"
  local lockfile
  lockfile="$(_beadswave_primary_lockfile "$repo")"
  if [[ -n "$lockfile" ]]; then
    current_lockfile_hash="$(shasum -a 256 "$lockfile" 2>/dev/null | awk '{print $1}' || echo "none")"
  fi
  if [[ "$current_lockfile_hash" != "$stored_lockfile_hash" ]]; then
    stale_reasons+=("lockfile changed since last bootstrap")
  fi

  # Check node_modules presence
  local nm_present=0
  [[ -d "$repo/node_modules" ]] && nm_present=1
  if [[ "$stored_nm" == "1" && "$nm_present" == "0" ]]; then
    stale_reasons+=("node_modules was present at bootstrap but is now missing")
  fi

  # Check .env presence
  local env_present=0
  for ef in .env .env.local .env.development .env.development.local; do
    [[ -f "$repo/$ef" ]] && env_present=1 && break
  done
  if [[ "$stored_env" == "1" && "$env_present" == "0" ]]; then
    stale_reasons+=(".env file was present at bootstrap but is now missing")
  fi

  if [[ "${#stale_reasons[@]}" -gt 0 ]]; then
    echo "  warning: worktree bootstrap is stale:" >&2
    for reason in "${stale_reasons[@]}"; do
      echo "    - $reason" >&2
    done
    echo "    Re-run scripts/setup-dev.sh to refresh the bootstrap." >&2
    return 1
  fi

  return 0
}
