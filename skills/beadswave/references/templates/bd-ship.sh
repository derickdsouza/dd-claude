#!/usr/bin/env bash
# bd-ship.sh — Push the current branch, create the PR, and only close the bead
# when the PR is already merged during this invocation.
#
# Usage:
#   bd-ship <bead-id> [--branch <name>] [--hold]
#   bd-ship adopt <pr-number>
#
# Flow (gates run in order; non-zero exit on any failure):
#   1. Kill switch (.auto-merge-disabled file present)
#   2. Validate bead exists and is open
#   2a. Gate: claim check — bead must be in_progress (BEADSWAVE_SKIP_CLAIM_CHECK=1 to override)
#   2b. Gate: failure budget — block if preship-fail count >= BEADSWAVE_FAILURE_BUDGET (default 3)
#   2c. Gate: scope declaration — block if scope:unknown or no scope: label (BEADSWAVE_SKIP_SCOPE_CHECK=1)
#   3. Resolve current git branch (or --branch override)
#   4. Abort early on uncommitted changes
#   5. Gate: pre-ship hook (.beadswave/pre-ship.sh if executable) — MANDATORY
#   6. Gate: lint       — MANDATORY  (override LINT_CMD env var)
#   7. Gate: typecheck  — MANDATORY  (override TYPECHECK_CMD env var)
#   8. Gate: tests      — MANDATORY  (override TEST_CMD env var)
#   9. git push
#  10. Spawn `claude -p` with .beads/prompts/create-pr.md to create the PR
#  11. Tag PR provenance on the bead
#  12. Reject accidental beadswave/session-support file diffs unless explicitly allowed
#  13. Merge the PR via gh pr merge (or queue via Mergify in legacy mode)
#  14. Close the bead only if the PR is already merged now; otherwise leave it
#      open at stage:merging for merge-wait / pipeline-driver
#  15. Append one line to .beads/auto-pr.log
#
# PRE-SHIP CHECKS ARE MANDATORY. On gate failure, a sub-issue is created under the
# parent bead with label "preship-fail". The worker must fix the sub-issue and
# re-run bd-ship until all gates pass. There are no --skip-* flags.
#
# See beadswave skill `references/ship-pipeline.md` for full architecture.

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
LOG_FILE="${REPO_ROOT}/.beads/auto-pr.log"
KILL_SWITCH="${REPO_ROOT}/.ship-paused"
PROMPT_FILE="${REPO_ROOT}/.beads/prompts/create-pr.md"
BEADSWAVE_RUNTIME="${BEADSWAVE_SKILL_DIR:-$HOME/.claude/skills/beadswave}/scripts/runtime.sh"

if [ -f "$BEADSWAVE_RUNTIME" ]; then
  # shellcheck disable=SC1090
  . "$BEADSWAVE_RUNTIME"
else
  echo "beadswave runtime missing at $BEADSWAVE_RUNTIME" >&2
  exit 1
fi

mkdir -p "$(dirname "$LOG_FILE")"

# ──────────────────────────────────────────────────────────────
# Stack detection + per-repo config
#
# Gate commands resolve in this precedence (high wins):
#   1. Env vars at invocation  (LINT_CMD=... bd-ship ...)
#   2. .beadswave.env in repo root  (sourced as shell)
#   3. Stack defaults auto-detected from lockfile
#
# Empty commands ("") are treated as "skip this gate" — a Rust repo
# with no typecheck script can set TYPECHECK_CMD="" in .beadswave.env.
# ──────────────────────────────────────────────────────────────
_ENV_LINT_CMD="${LINT_CMD:-}"
_ENV_TYPECHECK_CMD="${TYPECHECK_CMD:-}"
_ENV_TEST_CMD="${TEST_CMD:-}"
unset LINT_CMD TYPECHECK_CMD TEST_CMD

STACK=""
DEFAULT_LINT_CMD=""
DEFAULT_TYPECHECK_CMD=""
DEFAULT_TEST_CMD=""

package_json_has_script() {
  local script_name="$1"
  [ -f "$REPO_ROOT/package.json" ] || return 1
  python3 - "$REPO_ROOT/package.json" "$script_name" <<'PY' >/dev/null 2>&1
import json
import sys

package_json = sys.argv[1]
script_name = sys.argv[2]

try:
    with open(package_json) as handle:
        pkg = json.load(handle)
except Exception:
    sys.exit(1)

scripts = pkg.get("scripts") or {}
sys.exit(0 if script_name in scripts else 1)
PY
}

if [ -f "$REPO_ROOT/bun.lock" ] || [ -f "$REPO_ROOT/bun.lockb" ]; then
  STACK="bun"
  DEFAULT_LINT_CMD="bun run lint"
  DEFAULT_TYPECHECK_CMD="bun run typecheck"
  if package_json_has_script test; then
    DEFAULT_TEST_CMD="bun run test --run"
  else
    DEFAULT_TEST_CMD="bun test"
  fi
elif [ -f "$REPO_ROOT/pnpm-lock.yaml" ]; then
  STACK="pnpm"
  DEFAULT_LINT_CMD="pnpm lint"
  DEFAULT_TYPECHECK_CMD="pnpm typecheck"
  DEFAULT_TEST_CMD="pnpm test"
elif [ -f "$REPO_ROOT/yarn.lock" ]; then
  STACK="yarn"
  DEFAULT_LINT_CMD="yarn lint"
  DEFAULT_TYPECHECK_CMD="yarn typecheck"
  DEFAULT_TEST_CMD="yarn test"
elif [ -f "$REPO_ROOT/package.json" ]; then
  STACK="npm"
  DEFAULT_LINT_CMD="npm run lint"
  DEFAULT_TYPECHECK_CMD="npm run typecheck"
  DEFAULT_TEST_CMD="npm test"
elif [ -f "$REPO_ROOT/Cargo.toml" ]; then
  STACK="rust"
  DEFAULT_LINT_CMD="cargo clippy --all-targets -- -D warnings"
  DEFAULT_TYPECHECK_CMD="cargo check --all-targets"
  DEFAULT_TEST_CMD="cargo test"
elif [ -f "$REPO_ROOT/pyproject.toml" ] || [ -f "$REPO_ROOT/requirements.txt" ]; then
  STACK="python"
  DEFAULT_LINT_CMD="ruff check ."
  DEFAULT_TYPECHECK_CMD="mypy ."
  DEFAULT_TEST_CMD="pytest"
elif [ -f "$REPO_ROOT/go.mod" ]; then
  STACK="go"
  DEFAULT_LINT_CMD="golangci-lint run"
  DEFAULT_TYPECHECK_CMD="go vet ./..."
  DEFAULT_TEST_CMD="go test ./..."
else
  STACK="unknown"
fi

if [ -f "$REPO_ROOT/.beadswave.env" ]; then
  # shellcheck disable=SC1091
  . "$REPO_ROOT/.beadswave.env"
fi

LINT_CMD="${_ENV_LINT_CMD:-${LINT_CMD:-$DEFAULT_LINT_CMD}}"
TYPECHECK_CMD="${_ENV_TYPECHECK_CMD:-${TYPECHECK_CMD:-$DEFAULT_TYPECHECK_CMD}}"
TEST_CMD="${_ENV_TEST_CMD:-${TEST_CMD:-$DEFAULT_TEST_CMD}}"

FORCE_HOLD=false
NO_CLOSE=false
BRANCH_OVERRIDE=""
BEAD_ID=""

PRESHIP_HOOK="${BEADSWAVE_PRESHIP_HOOK:-${REPO_ROOT}/.beadswave/pre-ship.sh}"
BEADSWAVE_ALLOW_SUPPORT_FILE_DIFF="${BEADSWAVE_ALLOW_SUPPORT_FILE_DIFF:-0}"

usage() {
  cat <<EOF
Usage: bd-ship <bead-id> [--branch <name>] [--hold]
       bd-ship adopt <pr-number>

Options:
  --branch <name>    Override branch auto-detection (default: current git branch)
  --hold             Force HOLD=true (prompt still decides risk paragraph)
  --no-close         Skip closing the bead (for pipeline-driver use — merge-wait closes after merge)
  -h, --help         Show this help

Env:
  LINT_CMD           Command to run lint      (default: auto-detected from stack)
  TYPECHECK_CMD      Command to run typecheck (default: auto-detected from stack)
  TEST_CMD           Command to run tests     (default: auto-detected from stack)
  BEADSWAVE_GH_PR_MERGE_METHOD
                     Merge method for direct merge. One of:
                     squash, merge, rebase. Default: merge.
  BEADSWAVE_MERGE_STRATEGY
                     Merge strategy: "direct" (default).
                     Direct: bd-ship merges immediately via gh pr merge.
  BEADS_ACTOR        Override user name in auto-pr.log entries (default: \$USER)
  BEADSWAVE_ALLOW_SUPPORT_FILE_DIFF
                     Set to 1 only for intentional workflow/bootstrap PRs that
                     modify .beadswave/, .githooks/, or .beads/ support files.

Stack defaults (auto-detected from lockfile in repo root):
  bun.lock / bun.lockb  → bun run lint / bun run typecheck / bun run test --run (if package.json has a test script) else bun test
  pnpm-lock.yaml        → pnpm lint / pnpm typecheck / pnpm test
  yarn.lock             → yarn lint / yarn typecheck / yarn test
  package.json (npm)    → npm run lint / npm run typecheck / npm test
  Cargo.toml            → cargo clippy / cargo check / cargo test
  pyproject.toml        → ruff check . / mypy . / pytest
  go.mod                → golangci-lint run / go vet / go test

Per-repo override: create .beadswave.env in repo root; it is sourced as shell
and may set LINT_CMD / TYPECHECK_CMD / TEST_CMD. Set a command to "" (empty)
to disable that gate for the whole repo.

Precedence (high wins): env var at invocation > .beadswave.env > stack default

PRESHIP_ISOLATE defaults to 1 for bd-ship. Set PRESHIP_ISOLATE=0 only if you
intentionally need legacy non-isolated behaviour and accept the scope risk.

PRE-SHIP CHECKS ARE MANDATORY. On gate failure a sub-issue is created under
the parent bead with label "preship-fail". Fix the sub-issue and re-run bd-ship.
There are no --skip-* flags — the only path to shipping is through all gates green.

Exit codes:
  0   Shipped successfully (PR created)
  1   Validation failure (bead unknown, already closed, non-isolated workspace, branch mismatch)
  2   Tests failed
  3   Push failed
  4   PR creation failed
  5   Kill switch active (.ship-paused present)
  6   Lint failed
  7   Typecheck failed
  20  Pre-ship hook (.beadswave/pre-ship.sh) failed
  21  Rebase on origin/main has conflicts
EOF
}

log_event() {
  local ts
  ts=$(date '+%Y-%m-%dT%H:%M:%S%z')
  local actor="${BEADS_ACTOR:-${USER:-unknown}}"
  printf '{"ts":"%s","bead":"%s","branch":"%s","pr":%s,"label":"%s","actor":"%s"}\n' \
    "$ts" "$BEAD_ID" "$1" "$2" "$3" "$actor" >> "$LOG_FILE"
}

create_preship_subissue() {
  local gate_name="$1"
  local output_file="$2"
  local title="preship-fail: ${gate_name} gate failed for bead ${BEAD_ID}"
  local body="${gate_name} gate failed during bd-ship. See output below. Fix this sub-issue, then re-run bd-ship."
  if [ -f "$output_file" ]; then
    local summary
    summary=$(tail -40 "$output_file" 2>/dev/null || true)
    body="${body}"$'\n\n'"--- last 40 lines of ${gate_name} output ---"$'\n```'$'\n'"${summary}"$'\n```'
  fi
  local create_json
  local sub_id
  create_json=$(bd create \
    --parent "$BEAD_ID" \
    --title "$title" \
    --description "$body" \
    --labels preship-fail \
    --json 2>/dev/null || true)
  sub_id=$(printf '%s' "$create_json" | jq -r 'if type=="array" then .[0].id else .id end // empty' 2>/dev/null || true)
  if [ -n "$sub_id" ]; then
    echo "  Sub-issue created: $sub_id (label: preship-fail)" >&2
  else
    echo "  Warning: could not auto-create sub-issue. Manually create one under $BEAD_ID." >&2
  fi
}

resolve_branch() {
  local current
  current="$(git branch --show-current 2>/dev/null || true)"
  if [ -n "$current" ] && [ "$current" != "main" ] && [ "$current" != "master" ]; then
    printf '%s\n' "$current"
    return 0
  fi

  echo "Not on a feature branch (current: ${current:-detached HEAD}). Pass --branch <name>." >&2
  return 1
}

rebase_on_main() {
  local rebase_log
  rebase_log="$(beadswave_tmpfile bd-ship-rebase)" || {
    echo "✗ Could not allocate temp file for rebase output" >&2
    exit 21
  }

  beadswave_fetch_origin_main "$REPO_ROOT"

  local behind
  behind="$(git rev-list --right-only --count origin/main..."$BRANCH" 2>/dev/null || echo "0")"
  if [ "$behind" -eq 0 ]; then
    rm -f "$rebase_log"
    echo "  Branch is up-to-date with origin/main (0 commits behind)"
    return 0
  fi
  echo "  Branch is $behind commit(s) behind origin/main — rebasing..."

  # Fail fast if $BRANCH is checked out in a sibling worktree — otherwise
  # `git rebase origin/main "$BRANCH"` would emit a cryptic
  # "fatal: '$BRANCH' is already used by worktree at ..." deep in the rebase.
  if ! beadswave_assert_branch_free_here "$REPO_ROOT" "$BRANCH"; then
    rm -f "$rebase_log"
    echo "✗ Cannot rebase '$BRANCH' — owned by another worktree. Not shipping." >&2
    exit 23
  fi

  beadswave_clear_git_locks "$REPO_ROOT"

  # Preserve .beads/ across the rebase — rebasing commits that touch
  # `.beads/*.jsonl` (or Dolt binary files) can lose or corrupt state.
  local beads_backup=""
  if [ -d "$REPO_ROOT/.beads" ]; then
    beads_backup="$(mktemp -d -t beads-preship.XXXXXX)"
    cp -a "$REPO_ROOT/.beads/." "$beads_backup/"
  fi

  if ! git rebase origin/main "$BRANCH" >"$rebase_log" 2>&1; then
    git rebase --abort 2>/dev/null || true
    if [ -n "$beads_backup" ]; then
      rm -rf "$REPO_ROOT/.beads"
      mkdir -p "$REPO_ROOT/.beads"
      cp -a "$beads_backup/." "$REPO_ROOT/.beads/"
      rm -rf "$beads_backup"
    fi
    echo "✗ Rebase on origin/main has conflicts — not shipping." >&2
    echo "--- rebase output ---" >&2
    cat "$rebase_log" >&2
    create_preship_subissue "rebase" "$rebase_log"
    exit 21
  fi

  if [ -n "$beads_backup" ]; then
    rm -rf "$REPO_ROOT/.beads"
    mkdir -p "$REPO_ROOT/.beads"
    cp -a "$beads_backup/." "$REPO_ROOT/.beads/"
    rm -rf "$beads_backup"
    if ! git -C "$REPO_ROOT" diff --quiet -- .beads; then
      git -C "$REPO_ROOT" add .beads
      git -C "$REPO_ROOT" commit -m "chore(beads): restore state after rebase onto origin/main" --no-verify >/dev/null
      echo "  .beads/ restored post-rebase (appended restore commit)"
    fi
  fi

  rm -f "$rebase_log"
  echo "  Rebase successful — branch is on latest origin/main"
}

normalize_queue_settings() {
  case "$MERGIFY_QUEUE_TIMEOUT_SECONDS" in
    ''|*[!0-9]*)
      MERGIFY_QUEUE_TIMEOUT_SECONDS=300
      ;;
  esac
  case "$MERGIFY_QUEUE_POLL_SECONDS" in
    ''|*[!0-9]*)
      MERGIFY_QUEUE_POLL_SECONDS=15
      ;;
  esac
  if [ "$MERGIFY_QUEUE_TIMEOUT_SECONDS" -gt 0 ] && [ "$MERGIFY_QUEUE_POLL_SECONDS" -le 0 ]; then
    MERGIFY_QUEUE_POLL_SECONDS=1
  fi
}

pr_handoff_state() {
  local pr_number="$1"
  local pr_json state merged_at auto_merge_present
  pr_json="$(gh pr view "$pr_number" --json state,mergedAt,autoMergeRequest 2>/dev/null || true)"
  if [ -z "$pr_json" ]; then
    printf 'unknown\n'
    return 0
  fi

  state="$(printf '%s' "$pr_json" | jq -r '.state // empty' 2>/dev/null || true)"
  merged_at="$(printf '%s' "$pr_json" | jq -r '.mergedAt // empty' 2>/dev/null || true)"
  auto_merge_present="$(printf '%s' "$pr_json" | jq -r 'if .autoMergeRequest then "yes" else "no" end' 2>/dev/null || true)"

  if [ "$state" != "OPEN" ] || { [ -n "$merged_at" ] && [ "$merged_at" != "null" ]; }; then
    printf 'closed\n'
  elif [ "$auto_merge_present" = "yes" ]; then
    printf 'auto\n'
  else
    printf 'open\n'
  fi
}

enable_github_merge_fallback() {
  local pr_number="$1"
  local head_sha merge_note
  head_sha="$(git rev-parse "$BRANCH" 2>/dev/null || true)"
  if merge_note="$(beadswave_request_pr_auto_merge "$pr_number" "$head_sha" 2>&1)"; then
    echo "  Activated GitHub auto-merge / merge-queue fallback (${merge_note})."
    return 0
  fi
  echo "  Warning: GitHub auto-merge / merge-queue fallback failed." >&2
  if [ -n "$merge_note" ]; then
    printf '  %s\n' "$merge_note" >&2
  fi
  return 1
}

branch_changed_paths() {
  if git show-ref --verify --quiet "refs/heads/$BRANCH"; then
    git diff --name-only origin/main..."$BRANCH" 2>/dev/null || true
  fi
}

reject_forbidden_support_paths() {
  local paths path session_paths support_paths
  paths="$(branch_changed_paths)"
  [ -n "$paths" ] || return 0

  while IFS= read -r path; do
    [ -n "$path" ] || continue
    case "$path" in
      .beads/.agent-*|.beads/.waves.lockdir|.beads/.waves.lockdir/*|.beads/auto-pr.log)
        session_paths+="${path}"$'\n'
        ;;
      .beads/prompts/create-pr.md)
        ;;
      .beads/*|.beadswave/*|.githooks/*)
        support_paths+="${path}"$'\n'
        ;;
    esac
  done <<EOF
$paths
EOF

  if [ -n "${session_paths:-}" ]; then
    echo "✗ Refusing to ship session-state files in this bead diff:" >&2
    printf '%s' "$session_paths" | sed 's/^/    /' >&2
    echo "  Remove these from the branch before shipping." >&2
    return 1
  fi

  if [ -n "${support_paths:-}" ] && [ "$BEADSWAVE_ALLOW_SUPPORT_FILE_DIFF" != "1" ]; then
    echo "✗ Refusing to ship beadswave/workflow support files in this bead diff:" >&2
    printf '%s' "$support_paths" | sed 's/^/    /' >&2
    echo "  These files are commonly pulled in accidentally by broad git add." >&2
    echo "  If this is an intentional workflow/bootstrap change, re-run with BEADSWAVE_ALLOW_SUPPORT_FILE_DIFF=1." >&2
    return 1
  fi

  return 0
}

ensure_merge_handoff() {
  if [ "${HOLD:-false}" = "true" ]; then
    echo "  Skipped merge (HOLD=true — requires human review)."
    return 0
  fi

  echo "  Merge strategy: direct merge"
  local merge_method="${BEADSWAVE_GH_PR_MERGE_METHOD:-merge}"
  local merge_output

  if merge_output="$(gh pr merge "$PR_NUMBER" --"$merge_method" --delete-branch 2>&1)"; then
    echo "  Merged PR #$PR_NUMBER via direct $merge_method."
    return 0
  fi

  if echo "$merge_output" | grep -q "already merged"; then
    echo "  PR #$PR_NUMBER was already merged."
    return 0
  fi

  for method in squash merge rebase; do
    if [ "$method" != "$merge_method" ]; then
      if merge_output="$(gh pr merge "$PR_NUMBER" --"$method" --delete-branch 2>&1)"; then
        echo "  Merged PR #$PR_NUMBER via fallback $method."
        return 0
      fi
    fi
  done

  echo "  Error: all merge methods failed for PR #$PR_NUMBER." >&2
  echo "  $merge_output" >&2
  return 1
}

# ──────────────────────────────────────────────────────────────
# adopt subcommand: retroactively trigger direct merge for an existing open PR
# Usage: bd-ship adopt <pr-number>
# ──────────────────────────────────────────────────────────────
if [ "${1:-}" = "adopt" ]; then
  shift
  if [ $# -eq 0 ] || [ -z "$1" ]; then
    echo "Usage: bd-ship adopt <pr-number>" >&2
    exit 1
  fi
  ADOPT_PR="$1"
  shift

  ADOPT_JSON=$(gh pr view "$ADOPT_PR" --json number,state,title,headRefName 2>/dev/null || true)
  if [ -z "$ADOPT_JSON" ]; then
    echo "PR #$ADOPT_PR not found." >&2
    exit 4
  fi
  ADOPT_STATE=$(echo "$ADOPT_JSON" | jq -r '.state // empty')
  if [ "$ADOPT_STATE" != "OPEN" ]; then
    echo "PR #$ADOPT_PR is not open (state: $ADOPT_STATE)." >&2
    exit 4
  fi

  ADOPT_TITLE=$(echo "$ADOPT_JSON" | jq -r '.title')
  ADOPT_BRANCH=$(echo "$ADOPT_JSON" | jq -r '.headRefName')
  echo "Adopting PR #$ADOPT_PR: ${ADOPT_TITLE}"

  PR_NUMBER="$ADOPT_PR"
  HOLD=false
  BRANCH="$ADOPT_BRANCH"
  BEAD_ID="adopt"

  if ! ensure_merge_handoff; then
    echo "  Warning: merge handoff not fully established. PR may need manual merge." >&2
  fi

  log_event "$BRANCH" "$ADOPT_PR" "adopted"
  echo "PR #$ADOPT_PR adopted."
  exit 0
fi

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --branch)
      BRANCH_OVERRIDE="$2"
      shift 2
      ;;
    --hold)
      FORCE_HOLD=true
      shift
      ;;
    --no-close)
      NO_CLOSE=true
      shift
      ;;
    --skip-preship|--skip-lint|--skip-typecheck|--skip-tests)
      echo "ERROR: $1 is no longer supported. Pre-ship checks are mandatory — fix failures instead of skipping them." >&2
      exit 1
      ;;
    --)
      shift
      break
      ;;
    -*)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
    *)
      BEAD_ID="$1"
      shift
      ;;
  esac
done

if [ -z "$BEAD_ID" ]; then
  usage
  exit 1
fi

RAW_BEAD_ID="$BEAD_ID"
if expanded_bead_id="$(beadswave_expand_bead_id "$BEAD_ID" "$REPO_ROOT" 2>/dev/null || true)"; then
  if [ -n "$expanded_bead_id" ]; then
    BEAD_ID="$expanded_bead_id"
  fi
fi
if [ "$RAW_BEAD_ID" != "$BEAD_ID" ]; then
  echo "  Resolved short bead id '$RAW_BEAD_ID' -> '$BEAD_ID'."
fi

if [ -f "$KILL_SWITCH" ]; then
  echo "Shipping is paused (.ship-paused file present)." >&2
  echo "Remove the file to re-enable shipping." >&2
  exit 5
fi

BEAD_JSON_FILE="$(beadswave_tmpfile bd-ship-show)" || {
  echo "Could not allocate a temp file for bead metadata." >&2
  exit 1
}
trap 'rm -f "$BEAD_JSON_FILE"' EXIT

if ! bd show "$BEAD_ID" --json > "$BEAD_JSON_FILE" 2>/dev/null; then
  echo "Bead '$BEAD_ID' not found." >&2
  if [ "$RAW_BEAD_ID" = "$BEAD_ID" ] && [[ "$RAW_BEAD_ID" != *-* ]]; then
    echo "  Try the fully-qualified bead id '$(beadswave_project_prefix "$REPO_ROOT")-$RAW_BEAD_ID'." >&2
  fi
  exit 1
fi

BEAD_STATUS=$(jq -r 'if type=="array" then .[0].status else .status end // empty' "$BEAD_JSON_FILE")
if [ "$BEAD_STATUS" = "closed" ]; then
  echo "Bead '$BEAD_ID' is already closed." >&2
  exit 1
fi

# Enforce: bead must be in_progress before shipping. An open bead means it was
# never claimed via /drain or /bw-work, which are the only sanctioned entry points.
# Use BEADSWAVE_SKIP_CLAIM_CHECK=1 only for pipeline-driver internal calls that
# manage claim state themselves.
if [ "${BEADSWAVE_SKIP_CLAIM_CHECK:-0}" != "1" ] && [ "$BEAD_STATUS" != "in_progress" ]; then
  echo "✗ Bead '$BEAD_ID' has status '$BEAD_STATUS' — must be 'in_progress' to ship." >&2
  echo "  Claim it first via /drain or /bw-work, which set the bead in_progress." >&2
  echo "  Quick claim: bd update $BEAD_ID --claim" >&2
  exit 1
fi

# ── Failure budget gate ───────────────────────────────────────────────
# Count preship-fail child beads. If the budget is exhausted, require human
# intervention before allowing another automatic ship attempt.
BEADSWAVE_FAILURE_BUDGET="${BEADSWAVE_FAILURE_BUDGET:-3}"
if [ "${BEADSWAVE_SKIP_FAILURE_BUDGET:-0}" != "1" ]; then
  FAIL_COUNT=$(bd list --parent "$BEAD_ID" --label preship-fail --json -n 0 2>/dev/null \
    | python3 -c "import json,sys; ds=json.load(sys.stdin); print(len(ds))" 2>/dev/null || echo "0")
  if [ "${FAIL_COUNT:-0}" -ge "$BEADSWAVE_FAILURE_BUDGET" ]; then
    echo "✗ Bead '$BEAD_ID' has exhausted its failure budget ($FAIL_COUNT / $BEADSWAVE_FAILURE_BUDGET preship-fail sub-issues)." >&2
    echo "  Investigate and close the preship-fail sub-issues manually before retrying." >&2
    echo "  Override: BEADSWAVE_SKIP_FAILURE_BUDGET=1 bd-ship $BEAD_ID" >&2
    exit 6
  fi
fi

# ── Scope declaration gate ────────────────────────────────────────────
# Every bead that reaches main must declare its operational scope so that
# coordinators can reason about blast radius and conflict risk. A bead with
# scope:unknown (or no scope: label at all) has not been triaged — block it.
if [ "${BEADSWAVE_SKIP_SCOPE_CHECK:-0}" != "1" ]; then
  BEAD_LABELS=$(jq -r '
    (if type=="array" then .[0] else . end).labels // [] | .[]
  ' "$BEAD_JSON_FILE" 2>/dev/null || true)
  HAS_SCOPE_LABEL=$(printf '%s\n' "$BEAD_LABELS" | grep -c '^scope:' || true)
  HAS_UNKNOWN_SCOPE=$(printf '%s\n' "$BEAD_LABELS" | grep -c '^scope:unknown$' || true)
  if [ "${HAS_SCOPE_LABEL:-0}" -eq 0 ] || [ "${HAS_UNKNOWN_SCOPE:-0}" -gt 0 ]; then
    echo "✗ Bead '$BEAD_ID' has no declared scope (scope:unknown or missing scope: label)." >&2
    echo "  Assign one of: scope:global  scope:area  scope:chapter  scope:household" >&2
    echo "  e.g.: bd update $BEAD_ID --add-label scope:chapter --remove-label scope:unknown" >&2
    echo "  Override: BEADSWAVE_SKIP_SCOPE_CHECK=1 bd-ship $BEAD_ID" >&2
    exit 6
  fi
fi

if [ -n "$BRANCH_OVERRIDE" ]; then
  BRANCH="$BRANCH_OVERRIDE"
else
  BRANCH="$(resolve_branch)"
  if [ -z "$BRANCH" ]; then
    exit 1
  fi
fi

BEADSWAVE_CHECK="${BEADSWAVE_SKILL_DIR:-$HOME/.claude/skills/beadswave}/scripts/check-working-tree.sh"
if [ -f "$BEADSWAVE_CHECK" ]; then
  # shellcheck disable=SC1090
  . "$BEADSWAVE_CHECK"
  : "${PRESHIP_ISOLATE:=1}"
  export PRESHIP_ISOLATE
  beadswave_check_working_tree "$BRANCH" || exit 1
fi

echo "▶ Shipping bead $BEAD_ID on branch $BRANCH"

cleanup_shipping_label() {
  bd update "$BEAD_ID" --remove-label stage:shipping >/dev/null 2>&1 || true
}

# Write/merge a bead state manifest at .git/beadswave-state/<id>.json.
# Each call passes jq args describing fields to set. Merge-wait consumes
# the same file on timeout / landed transitions. Advisory state — failures
# are swallowed so a flaky jq never breaks a ship.
bd_ship_write_manifest() {
  local dir="$REPO_ROOT/.git/beadswave-state"
  local path="$dir/$BEAD_ID.json"
  mkdir -p "$dir" 2>/dev/null || return 0
  [ -f "$path" ] || printf '{}\n' > "$path"
  local tmp
  tmp="$(mktemp)" || return 0
  if jq "$@" "$path" > "$tmp" 2>/dev/null; then
    mv "$tmp" "$path"
  else
    rm -f "$tmp"
  fi
}

# Guarantee stage:shipping is cleared on ANY abnormal exit below — rebase
# conflicts (exit 21), worktree collisions (23), temp-file failures, gate
# failures, PR creation errors, and unexpected shell errors. Successful
# paths explicitly transition the label to stage:merging / stage:review-hold
# before exit, so running cleanup_shipping_label again is a harmless no-op.
# Without this, an aborted ship would orphan the bead at stage:shipping and
# block the next /drain retry from re-entering the pipeline cleanly.
bd update "$BEAD_ID" --add-label stage:shipping >/dev/null 2>&1 || true
trap 'rc=$?; [ $rc -ne 0 ] && cleanup_shipping_label; exit $rc' EXIT

echo "▶ Rebasing on latest origin/main..."
rebase_on_main

reject_forbidden_support_paths || exit 1

run_gate() {
  local name="$1"
  local cmd="$2"
  local exitcode="$3"
  if [ -z "$cmd" ]; then
    echo "▷ No $name command configured for stack '$STACK' — skipping"
    return 0
  fi
  # Retry the gate up to BEADSWAVE_GATE_RETRIES additional times (default 1)
  # to absorb flaky tests before filing a preship-fail sub-issue. Set to 0
  # to disable retries entirely. Only the test gate retries by default;
  # lint/typecheck failures are deterministic and retrying wastes cycles.
  local retries="${BEADSWAVE_GATE_RETRIES:-1}"
  if [ "$name" != "tests" ]; then retries=0; fi
  local attempt=0
  local max_attempts=$((retries + 1))
  while :; do
    attempt=$((attempt + 1))
    if [ "$attempt" -eq 1 ]; then
      echo "▶ Running $name gate ($cmd)..."
    else
      echo "↻ Retrying $name gate (attempt $attempt/$max_attempts, absorbing flake)..."
    fi
    local out
    out="$(beadswave_tmpfile bd-ship-gate)" || {
      echo "✗ Could not allocate temp file for $name gate output" >&2
      exit "$exitcode"
    }
    if bash -c "$cmd" >"$out" 2>&1; then
      rm -f "$out"
      echo "  ✓ $name passed${attempt:+ (attempt $attempt)}"
      return 0
    fi
    if [ "$attempt" -lt "$max_attempts" ]; then
      echo "  ⚠ $name gate failed on attempt $attempt/$max_attempts — retrying" >&2
      rm -f "$out"
      continue
    fi
    echo "✗ $name gate failed after $attempt attempt(s) — not shipping. Fix the sub-issue and re-run bd-ship." >&2
    echo "--- last 80 lines of $name output ---" >&2
    tail -80 "$out" >&2
    echo "--- end $name output (full: $out) ---" >&2
    create_preship_subissue "$name" "$out"
    cleanup_shipping_label
    exit "$exitcode"
  done
}

if [ -x "$PRESHIP_HOOK" ]; then
  echo "▶ Running pre-ship hook: ${PRESHIP_HOOK#$REPO_ROOT/}"
  if ! "$PRESHIP_HOOK"; then
    echo "✗ Pre-ship hook failed — not shipping. Fix the sub-issue and re-run bd-ship." >&2
    echo "  Hook: $PRESHIP_HOOK" >&2
    create_preship_subissue "pre-ship-hook" ""
    cleanup_shipping_label
    exit 20
  fi
  echo "  ✓ pre-ship hook passed"
elif [ -e "$PRESHIP_HOOK" ]; then
  echo "▷ Pre-ship hook found but not executable: $PRESHIP_HOOK — skipping" >&2
  echo "  Fix with: chmod +x $PRESHIP_HOOK" >&2
fi

run_gate "lint" "$LINT_CMD" 6
run_gate "typecheck" "$TYPECHECK_CMD" 7
run_gate "tests" "$TEST_CMD" 2

echo "▶ Pushing branch..."
beadswave_clear_git_locks "$REPO_ROOT"

SHIPPING_LOCK="${REPO_ROOT}/.beads/.shipping-${BRANCH}"
mkdir -p "$(dirname "$SHIPPING_LOCK")"
touch "$SHIPPING_LOCK"

if ! git push -u origin "$BRANCH" 2>&1; then
  echo "Push failed." >&2
  exit 3
fi

echo "▶ Creating PR..."
if [ ! -f "$PROMPT_FILE" ]; then
  echo "Prompt file missing: $PROMPT_FILE" >&2
  exit 4
fi

if beadswave_fetch_origin_main "$REPO_ROOT"; then
  echo "  Refreshed origin/main before PR composition."
else
  echo "  Warning: could not refresh origin/main before PR composition." >&2
fi

CLAUDE_OUT="$(beadswave_tmpfile bd-ship-claude)" || {
  echo "Could not allocate a temp file for PR creation output." >&2
  exit 4
}
chmod 600 "$CLAUDE_OUT"
# Preserve the stage:shipping cleanup trap installed earlier — without this,
# a PR-creation failure (exit 4) would leave the bead stuck at stage:shipping
# because the new trap silently replaces the old one.
trap 'rc=$?; rm -f "$BEAD_JSON_FILE" "$CLAUDE_OUT"; [ $rc -ne 0 ] && cleanup_shipping_label; exit $rc' EXIT

if command -v timeout >/dev/null 2>&1; then
  TIMEOUT_CMD="timeout 120"
elif command -v gtimeout >/dev/null 2>&1; then
  TIMEOUT_CMD="gtimeout 120"
else
  TIMEOUT_CMD=""
fi

# PR composition: claude -p (default) or droid exec (set BD_SHIP_PR_CMD=droid)
PR_CMD="${BD_SHIP_PR_CMD:-claude}"
case "$PR_CMD" in
  droid)
    BD_SHIP_PR_MODEL="${BD_SHIP_PR_MODEL:-$DEFAULT_MODEL}"
    BEAD_ID="$BEAD_ID" BRANCH="$BRANCH" FORCE_HOLD="$FORCE_HOLD" \
      $TIMEOUT_CMD droid exec --auto high -m "$BD_SHIP_PR_MODEL" -f "$PROMPT_FILE" > "$CLAUDE_OUT" 2>&1 || {
        echo "droid exec PR composition failed or timed out. See $CLAUDE_OUT" >&2
        cat "$CLAUDE_OUT" >&2
        log_event "$BRANCH" "null" "error"
        exit 4
      }
    ;;
  claude|*)
    BEAD_ID="$BEAD_ID" BRANCH="$BRANCH" FORCE_HOLD="$FORCE_HOLD" \
      $TIMEOUT_CMD claude -p --dangerously-skip-permissions < "$PROMPT_FILE" > "$CLAUDE_OUT" 2>&1 || {
        echo "claude -p failed or timed out. See $CLAUDE_OUT" >&2
        cat "$CLAUDE_OUT" >&2
        log_event "$BRANCH" "null" "error"
        exit 4
      }
    ;;
esac

PR_NUMBER=$(grep '^PR_NUMBER=' "$CLAUDE_OUT" | tail -1 | cut -d= -f2 || true)
# Read HOLD from output; fall back to deriving from legacy PR_LABEL for old create-pr.md
HOLD=$(grep '^HOLD=' "$CLAUDE_OUT" | tail -1 | cut -d= -f2 || true)
if [ -z "$HOLD" ]; then
  PR_LABEL=$(grep '^PR_LABEL=' "$CLAUDE_OUT" | tail -1 | cut -d= -f2 || true)
  [ "${PR_LABEL:-}" = "auto-merge:hold" ] && HOLD=true || HOLD=false
fi

if [ -z "$PR_NUMBER" ] || [ "$PR_NUMBER" = "null" ]; then
  echo "claude -p did not return a PR number. Output:" >&2
  cat "$CLAUDE_OUT" >&2
  log_event "$BRANCH" "null" "error"
  exit 4
fi

log_event "$BRANCH" "$PR_NUMBER" "hold=${HOLD}"
echo "✓ PR #$PR_NUMBER created (hold=${HOLD})"

rm -f "$SHIPPING_LOCK"

bd update "$BEAD_ID" \
  --external-ref "gh-$PR_NUMBER" \
  --add-label shipped-via-pr \
  >/dev/null 2>&1 \
  || echo "  Warning: failed to tag bead $BEAD_ID with PR #$PR_NUMBER provenance" >&2

if ! ensure_merge_handoff; then
  echo "PR #$PR_NUMBER exists, but merge handoff was not established." >&2
  echo "Leave the bead open and repair the PR automation path before retrying." >&2
  bd update "$BEAD_ID" --remove-label stage:shipping >/dev/null 2>&1 || true
  exit 4
fi

if [ "${HOLD:-false}" = "true" ]; then
  bd update "$BEAD_ID" --remove-label stage:shipping --add-label stage:review-hold >/dev/null 2>&1 || true
  bd_ship_write_manifest \
    --arg id "$BEAD_ID" \
    --arg br "$BRANCH" \
    --argjson pr "$PR_NUMBER" \
    '. + {bead_id: $id, stage: "review-hold", branch: $br, pr: $pr, last_successful_step: "bd-ship-review-hold"}'
else
  bd update "$BEAD_ID" --remove-label stage:shipping --add-label stage:merging >/dev/null 2>&1 || true
  bd_ship_write_manifest \
    --arg id "$BEAD_ID" \
    --arg br "$BRANCH" \
    --argjson pr "$PR_NUMBER" \
    '. + {bead_id: $id, stage: "merging", branch: $br, pr: $pr, last_successful_step: "bd-ship-merging"}'
fi

CURRENT_PR_STATE="$(pr_handoff_state "$PR_NUMBER")"

if [ "$NO_CLOSE" = "true" ]; then
  echo "▶ Skipping bead close (--no-close). Pipeline driver or merge-wait will close after merge."
elif [ "$CURRENT_PR_STATE" = "closed" ]; then
  echo "▶ Closing bead..."
  if ! bd close "$BEAD_ID" -r "Shipped via bd-ship" >/dev/null 2>&1; then
    echo "PR #$PR_NUMBER exists, but closing bead '$BEAD_ID' failed." >&2
    echo "Fix the bead state manually, then re-run bd-ship only if you still need provenance repair." >&2
    exit 4
  fi
else
  echo "▶ Leaving bead open at stage:merging until PR #$PR_NUMBER is actually merged."
  echo "  Use scripts/merge-wait.sh $BEAD_ID or scripts/pipeline-driver.sh $BEAD_ID to finish the close-after-merge path."
fi

if [ "${HOLD:-false}" = "true" ]; then
  echo "  PR is held for human review (HOLD=true). Approve the PR to trigger merge."
else
  if [ "$CURRENT_PR_STATE" = "closed" ]; then
    echo "  PR merged during this bd-ship run."
  else
    echo "  PR is queued/in-flight. The bead remains open until merge is confirmed."
  fi
fi
