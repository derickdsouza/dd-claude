#!/bin/bash
# Batch-create PRs for all branches needing PRs, with auto-merge label + queue.
set -euo pipefail

BEADSWAVE_RUNTIME="${BEADSWAVE_SKILL_DIR:-$HOME/.claude/skills/beadswave}/scripts/runtime.sh"
if [[ -f "$BEADSWAVE_RUNTIME" ]]; then
  # shellcheck disable=SC1090
  . "$BEADSWAVE_RUNTIME"
fi

BRANCHES_FILE="${1:-/tmp/branches-needing-prs.txt}"
DRY_RUN="${DRY_RUN:-false}"
SUCCESS=0
FAILED=0
SKIPPED=0

while IFS= read -r branch; do
  # Get commit message for PR title/description
  MSG=$(git log -1 --format='%s' "origin/$branch" 2>/dev/null || echo "chore: merge $branch")
  TITLE=$(echo "$MSG" | head -c 70)

  # Skip branches that already have PRs (open or merged)
  EXISTING=$(gh pr list --state all --head "$branch" --json number --jq 'length' 2>/dev/null || echo "0")
  if [ "$EXISTING" != "0" ]; then
    echo "SKIP (existing PR): $branch"
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  if [ "$DRY_RUN" = "true" ]; then
    echo "WOULD CREATE: $branch — $TITLE"
    SUCCESS=$((SUCCESS + 1))
    continue
  fi

  # Create PR
  PR_URL=$(gh pr create \
    --head "$branch" \
    --base main \
    --title "$TITLE" \
    --body "Auto-generated PR for agent worktree branch." \
    --label "auto-merge" \
    2>/dev/null) || {
    echo "FAILED: $branch"
    FAILED=$((FAILED + 1))
    continue
  }

  PR_NUM=$(echo "$PR_URL" | grep -oE '[0-9]+$')
  echo "CREATED #$PR_NUM: $branch — $TITLE"

  # Enable auto-merge
  if command -v beadswave_request_pr_auto_merge >/dev/null 2>&1; then
    beadswave_request_pr_auto_merge "$PR_NUM" "" >/dev/null 2>&1 || true
  fi

  SUCCESS=$((SUCCESS + 1))
  sleep 0.5
done < "$BRANCHES_FILE"

echo ""
echo "=== Summary ==="
echo "Created: $SUCCESS"
echo "Skipped: $SKIPPED"
echo "Failed:  $FAILED"
