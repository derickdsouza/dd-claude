#!/usr/bin/env bash
# monitor-prs.sh — Check open PRs on fix/* branches and surface failures.
#
# Usage:
#   monitor-prs [--label LABEL] [--failing] [--stuck MINUTES] [--file-beads]
#               [--resolve-conflicts] [--json]
#
# Options:
#   --label LABEL    Only consider PRs with this label. Default: '' (all open PRs).
#                    Pass a label to narrow scope.
#   --failing        Only print PRs with at least one FAILURE check.
#   --stuck MINUTES  Flag PRs with no status update in MINUTES (default 120).
#   --file-beads     For each failing PR, create a bead of type=bug with a
#                    link to the PR and a summary of the failing checks. Only
#                    files a bead if one doesn't already exist (by title match).
#   --resolve-conflicts  Detect CONFLICTING PRs, auto-rebase via GitHub API
#                    (gh pr update-branch), file bead on failure if --file-beads.
#                    Requires repo setting "Allow updates to pull request branches".
#   --json           Emit JSON summary on stdout instead of the human report.
#
# Exit codes:
#   0   No failing PRs
#   1   One or more failing PRs
#   2   Argument error

set -uo pipefail

LABEL_FILTER=""
ONLY_FAILING=false
STUCK_MIN=120
FILE_BEADS=false
JSON_OUT=false
RESOLVE_CONFLICTS=false

while [ $# -gt 0 ]; do
  case "$1" in
    --label)       LABEL_FILTER="$2"; shift 2 ;;
    --failing)     ONLY_FAILING=true; shift ;;
    --stuck)       STUCK_MIN="$2"; shift 2 ;;
    --file-beads)  FILE_BEADS=true; shift ;;
    --resolve-conflicts) RESOLVE_CONFLICTS=true; shift ;;
    --json)              JSON_OUT=true; shift ;;
    -h|--help)     sed -n '2,/^$/p' "$0" | sed 's/^# \?//'; exit 0 ;;
    *)             echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
BEADSWAVE_RUNTIME="${BEADSWAVE_SKILL_DIR:-$HOME/.claude/skills/beadswave}/scripts/runtime.sh"
if [ -f "$BEADSWAVE_RUNTIME" ]; then
  # shellcheck disable=SC1090
  . "$BEADSWAVE_RUNTIME"
fi


# ──────────────────────────────────────────────────────────────
# Gather open PRs. statusCheckRollup includes CheckRun + StatusContext.
# ──────────────────────────────────────────────────────────────
RAW=$(gh pr list --state open --json number,title,headRefName,labels,updatedAt,statusCheckRollup \
        --jq '[.[] | {
          n: .number,
          title: .title,
          branch: .headRefName,
          labels: [.labels[].name],
          updated: .updatedAt,
          checks: ([.statusCheckRollup[] | select(.__typename=="CheckRun" or .__typename=="StatusContext") |
                    {name: (.name // .context), conclusion: (.conclusion // .state)}]
                   | group_by(.name) | map(.[-1]))
        }]')

# Apply label filter
if [ -n "$LABEL_FILTER" ]; then
  RAW=$(echo "$RAW" | jq --arg lbl "$LABEL_FILTER" '[.[] | select(.labels | index($lbl))]')
fi

# Enrich: counts + staleness
NOW_EPOCH=$(date +%s)
ENRICHED=$(echo "$RAW" | jq --argjson now "$NOW_EPOCH" --argjson stuckMin "$STUCK_MIN" '
  map(
    . + {
      n_failure:  ([.checks[] | select(.conclusion=="FAILURE")]  | length),
      n_success:  ([.checks[] | select(.conclusion=="SUCCESS")]  | length),
      n_pending:  ([.checks[] | select(.conclusion==null or .conclusion=="IN_PROGRESS" or .conclusion=="PENDING" or .conclusion=="QUEUED")] | length),
      n_skipped:  ([.checks[] | select(.conclusion=="SKIPPED")]  | length),
      age_min: (($now - (.updated | fromdate)) / 60 | floor),
      stuck: ((($now - (.updated | fromdate)) / 60 | floor) >= $stuckMin)
    }
  )
')

FAILING=$(echo "$ENRICHED" | jq '[.[] | select(.n_failure > 0)]')
FAILING_COUNT=$(echo "$FAILING" | jq 'length')
TOTAL=$(echo "$ENRICHED" | jq 'length')

# ──────────────────────────────────────────────────────────────
# JSON output mode
# ──────────────────────────────────────────────────────────────
if [ "$JSON_OUT" = "true" ]; then
  echo "$ENRICHED" | jq --argjson total "$TOTAL" --argjson failing "$FAILING_COUNT" '
    { total: $total, failing: $failing, prs: . }'
  [ "$FAILING_COUNT" -gt 0 ] && exit 1 || exit 0
fi

# ──────────────────────────────────────────────────────────────
# Human report
# ──────────────────────────────────────────────────────────────
echo "Open PRs (label filter: ${LABEL_FILTER:-none}): $TOTAL"
echo "  Failing: $FAILING_COUNT"

if [ "$ONLY_FAILING" = "true" ]; then
  SET="$FAILING"
else
  SET="$ENRICHED"
fi

# Sort: failing first, then stuck, then by age desc
SORTED=$(echo "$SET" | jq 'sort_by(-(.n_failure), -(.age_min))')

echo "$SORTED" | jq -r '.[] |
  "#\(.n)  \(.title[0:60])\n  branch=\(.branch)  age=\(.age_min)m  " +
  "✓\(.n_success) ✗\(.n_failure) ⋯\(.n_pending) ⊘\(.n_skipped)" +
  (if .stuck then "  [STUCK]" else "" end) +
  (if .n_failure > 0 then
    "\n  failures: " + ([.checks[] | select(.conclusion=="FAILURE") | .name] | join(", "))
   else "" end)
'

# ──────────────────────────────────────────────────────────────
# Optionally file beads for failing PRs
# ──────────────────────────────────────────────────────────────
if [ "$FILE_BEADS" = "true" ] && [ "$FAILING_COUNT" -gt 0 ]; then
  echo
  echo "▶ Filing beads for $FAILING_COUNT failing PR(s)..."
  echo "$FAILING" | jq -c '.[]' | while read -r pr; do
    n=$(echo "$pr" | jq -r '.n')
    title=$(echo "$pr" | jq -r '.title')
    branch=$(echo "$pr" | jq -r '.branch')
    fails=$(echo "$pr" | jq -r '[.checks[] | select(.conclusion=="FAILURE") | .name] | join(", ")')
    bead_title="CI failing on PR #${n}: ${title:0:50}"

    # Skip if a bead with this title already exists
    if bd list --status=open --json 2>/dev/null | jq -e --arg t "$bead_title" '(if type=="array" then . else [.] end)[] | select(.title==$t)' >/dev/null; then
      echo "  ↪ bead already exists for PR #$n, skipping"
      continue
    fi

    desc="PR #${n} (branch \`${branch}\`) has failing checks: ${fails}.

Open PR: https://github.com/$(gh repo view --json nameWithOwner --jq .nameWithOwner)/pull/${n}

Triage: inspect the failing check logs with \`gh run view --log-failed\` and decide:
- (a) fix-forward: push a commit to the branch
- (b) close the PR and re-ship after fixing locally"

    new_id=$(bd create --title "$bead_title" --description "$desc" --type=bug --priority=2 --json 2>/dev/null | jq -r 'if type=="array" then .[0].id else .id end')
    if [ -n "$new_id" ] && [ "$new_id" != "null" ]; then
      echo "  ✓ filed $new_id for PR #$n"
    else
      echo "  ✗ failed to file bead for PR #$n"
    fi
  done
fi

[ "$FAILING_COUNT" -gt 0 ] && FAIL_EXIT=1 || FAIL_EXIT=0

# ──────────────────────────────────────────────────────────────
# Conflict detection + auto-rebase (--resolve-conflicts)
# ──────────────────────────────────────────────────────────────
if [ "$RESOLVE_CONFLICTS" = "true" ]; then
  echo
  echo "Scanning for conflicting PRs..."
  CONFLICT_RAW=$(gh pr list --state open --json number,title,headRefName,mergeable \
    --jq '[.[] | select(.mergeable == "CONFLICTING")]')
  CONFLICT_COUNT=$(echo "$CONFLICT_RAW" | jq 'length')

  if [ "$CONFLICT_COUNT" -eq 0 ]; then
    echo "  No conflicting PRs found."
  else
    echo "  Found $CONFLICT_COUNT conflicting PR(s):"
    echo "$CONFLICT_RAW" | jq -r '.[] | "    #\(.number) \(.title[0:60])"'

    echo "  Attempting auto-rebase via GitHub API..."
    echo "$CONFLICT_RAW" | jq -c '.[]' | while read -r pr; do
      n=$(echo "$pr" | jq -r '.number')
      title=$(echo "$pr" | jq -r '.title')
      branch=$(echo "$pr" | jq -r '.headRefName')

      if gh pr update-branch "$n" >/dev/null 2>&1; then
        echo "    ok #$n rebased via GitHub API"
      else
        echo "    FAIL #$n auto-rebase failed (complex conflict or repo setting disabled)" >&2

        if [ "$FILE_BEADS" = "true" ]; then
          bead_title="Merge conflict on PR #${n}: ${title:0:50}"
          if bd list --status=open --json 2>/dev/null | jq -e --arg t "$bead_title" '(if type=="array" then . else [.] end)[] | select(.title==$t)' >/dev/null 2>&1; then
            echo "      bead already exists for PR #$n, skipping"
            continue
          fi

          desc="PR #${n} (branch \`${branch}\`) has merge conflicts that could not be auto-resolved.

Open PR: https://github.com/$(gh repo view --json nameWithOwner --jq .nameWithOwner)/pull/${n}

Action required: rebase the branch onto latest main and resolve conflicts."

          new_id=$(bd create --title "$bead_title" --description "$desc" --type=bug --priority=1 --json 2>/dev/null | jq -r 'if type=="array" then .[0].id else .id end')
          if [ -n "$new_id" ] && [ "$new_id" != "null" ]; then
            echo "      filed $new_id for PR #$n"
          else
            echo "      failed to file bead for PR #$n"
          fi
        fi
      fi
    done
  fi
fi

exit "$FAIL_EXIT"
