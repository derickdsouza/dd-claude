#!/usr/bin/env bash
# bulk-approve-prs.sh — Approve open auto-merge PRs using two GitHub accounts.
#
# For each PR with the auto-merge label:
#   - Detects the PR opener and who last pushed
#   - Approves as the configured account that is NOT the last pusher
#   - Skips impossible cases (e.g. the only eligible approver would be the PR opener)
#   - Skips PRs already approved by the correct user
#
# Usage:
#   bulk-approve-prs.sh                    # approve all eligible PRs
#   bulk-approve-prs.sh --dry-run          # show what would be approved, no writes
#   bulk-approve-prs.sh --user-a <login>   # override first account (default: from gh)
#   bulk-approve-prs.sh --user-b <login>   # override second account (default: from gh)
#
# Prerequisites:
#   - gh CLI with two authenticated accounts: gh auth status shows both
#   - Both accounts need write access to the repo
#   - Run from inside a git repo (uses remote to detect repo)

set -euo pipefail

DRY_RUN=false
USER_A=""
USER_B=""

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run|-n) DRY_RUN=true; shift ;;
    --user-a) USER_A="$2"; shift 2 ;;
    --user-b) USER_B="$2"; shift 2 ;;
    -h|--help) sed -n '2,/^$/p' "$0" | sed 's/^# \?//'; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

# Detect repo from git remote
REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)" || {
  echo "✗ Could not detect repo. Run from inside a git repo with a GitHub remote." >&2
  exit 2
}

# Detect the two accounts from gh auth status
if [ -z "$USER_A" ] || [ -z "$USER_B" ]; then
  ACCOUNTS=$(gh auth status 2>&1 | grep -oE 'account [^ ]+' | awk '{print $2}' | head -2)
  if [ -z "$USER_A" ]; then USER_A=$(echo "$ACCOUNTS" | sed -n '1p'); fi
  if [ -z "$USER_B" ]; then USER_B=$(echo "$ACCOUNTS" | sed -n '2p'); fi
fi

if [ -z "$USER_A" ] || [ -z "$USER_B" ]; then
  echo "✗ Need two GitHub accounts. Use --user-a and --user-b, or log in with both:" >&2
  echo "  gh auth login --hostname github.com -p ssh -u <user1>" >&2
  echo "  gh auth login --hostname github.com -p ssh -u <user2>" >&2
  exit 2
fi

echo "Repo: $REPO"
echo "Accounts: $USER_A (A) / $USER_B (B)"
echo ""

approved=0
skipped=0
errors=0
total=0

pick_approver() {
  local pr_opener="$1"
  local last_pusher="$2"
  local approver=""

  case "$last_pusher" in
    "$USER_A") approver="$USER_B" ;;
    "$USER_B") approver="$USER_A" ;;
    *)
      echo "skip:last_pusher_outside_config"
      return 0
      ;;
  esac

  if [ "$approver" = "$pr_opener" ]; then
    echo "skip:approver_would_be_pr_opener"
    return 0
  fi

  echo "$approver"
}

# Get all open PRs with auto-merge label
PRS=$(gh pr list --label auto-merge --state open --json number --jq '.[].number' --repo "$REPO")

if [ -z "$PRS" ]; then
  echo "No open PRs with auto-merge label."
  exit 0
fi

for pr_num in $PRS; do
  total=$((total+1))

  # Get PR opener and last commit author
  PR_OPENER=$(gh api "repos/$REPO/pulls/$pr_num" --jq '.user.login' 2>/dev/null || echo "unknown")
  LAST_PUSHER=$(gh api "repos/$REPO/pulls/$pr_num/commits" \
    --jq '.[-1].author.login // .[-1].committer.login // "unknown"' 2>/dev/null || echo "unknown")

  APPROVER="$(pick_approver "$PR_OPENER" "$LAST_PUSHER")"
  if [[ "$APPROVER" == skip:* ]]; then
    case "$APPROVER" in
      skip:last_pusher_outside_config)
        echo "PR #$pr_num: last pusher '$LAST_PUSHER' is outside configured accounts — skip"
        ;;
      skip:approver_would_be_pr_opener)
        echo "PR #$pr_num: opener '$PR_OPENER' differs from last pusher '$LAST_PUSHER'; two-account approval would require self-approval — skip"
        ;;
    esac
    skipped=$((skipped+1))
    continue
  fi

  # Check if approver already approved
  APPROVALS=$(gh api "repos/$REPO/pulls/$pr_num/reviews" \
    --jq '[.[] | select(.state == "APPROVED") | .user.login] | unique | join(",")' 2>/dev/null || echo "")

  if echo ",$APPROVALS," | grep -q ",$APPROVER,"; then
    echo "PR #$pr_num: already approved by $APPROVER — skip"
    skipped=$((skipped+1))
    continue
  fi

  if [ "$DRY_RUN" = "true" ]; then
    echo "PR #$pr_num: would approve as $APPROVER (last pusher: $LAST_PUSHER)"
    approved=$((approved+1))
    continue
  fi

  echo "PR #$pr_num: opener=$PR_OPENER last pusher=$LAST_PUSHER -> approving as $APPROVER"
  if gh auth switch --user "$APPROVER" >/dev/null 2>&1; then
    if REVIEW_OUTPUT="$(gh pr review "$pr_num" --approve --body "Auto-approved by beadswave" --repo "$REPO" 2>&1)"; then
      echo "  + Approved"
      approved=$((approved+1))
    else
      echo "  x Failed: $REVIEW_OUTPUT"
      errors=$((errors+1))
    fi
  else
    echo "  x Failed: could not switch gh auth to $APPROVER"
    errors=$((errors+1))
  fi
done

# Switch back to first account
gh auth switch --user "$USER_A" >/dev/null 2>&1 || true

echo ""
echo "Done: $total total, $approved approved, $skipped skipped, $errors errors"
[ "$errors" -eq 0 ] || exit 1
