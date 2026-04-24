#!/bin/bash
# GitButler upstream sync — runs on UserPromptSubmit
#
# - Checks for upstream commits (but pull --check, fast + read-only)
# - Clean workspace  → auto-pulls silently, then notifies Claude
# - Dirty workspace  → warns Claude to pull manually before branch new
# - No new commits   → exits silently (no noise)
# - Cooldown         → skips check if last check was <60s ago (avoids network
#                      overhead on every keystroke in a rapid conversation)

# Only run in directories with a git repo
[ -d ".git" ] || exit 0

# Only run if 'but' CLI is available
command -v but >/dev/null 2>&1 || exit 0

# Cooldown: avoid hammering the network on every message
COOLDOWN_DIR="/tmp/.ai-dev-workflow/claude"
mkdir -p "$COOLDOWN_DIR"
COOLDOWN_KEY=$(echo "$(pwd)" | shasum | cut -c1-8)
COOLDOWN_FILE="$COOLDOWN_DIR/gitbutler-sync-$COOLDOWN_KEY"
if [ -f "$COOLDOWN_FILE" ]; then
  LAST=$(cat "$COOLDOWN_FILE" 2>/dev/null)
  NOW=$(date +%s)
  [ -n "$LAST" ] && [ $(( NOW - LAST )) -lt 60 ] && exit 0
fi
date +%s > "$COOLDOWN_FILE"

# Check for upstream changes (read-only, fast)
CHECK_OUTPUT=$(but pull --check 2>&1)

# Extract new commit count — "X new commits on origin/main"
NEW_COMMITS=$(echo "$CHECK_OUTPUT" | grep -oE "[0-9]+ new commit" | grep -oE "^[0-9]+")
[ -z "$NEW_COMMITS" ] && NEW_COMMITS=0
[ "$NEW_COMMITS" -eq 0 ] && exit 0

# There are upstream commits — check if working tree is clean
# (GitButler uncommitted changes live in the working tree as normal git changes)
if git diff --quiet 2>/dev/null && git diff --cached --quiet 2>/dev/null; then
  # Clean workspace — auto-pull
  rm -f .git/*.lock 2>/dev/null
  but pull >/dev/null 2>&1
  echo "GitButler: auto-pulled $NEW_COMMITS upstream commit(s) — workspace is up to date."
else
  # Dirty workspace — surface the warning so Claude knows before any branch new
  COMMIT_LIST=$(echo "$CHECK_OUTPUT" | grep -E "^\s+[0-9a-f]{7}" | head -3 | sed 's/^/  /')
  echo "GitButler: $NEW_COMMITS upstream commit(s) pending — workspace has uncommitted changes, so auto-pull was skipped. Run 'but pull' manually before 'but branch new' to avoid 'parents not referenced' errors:
$COMMIT_LIST"
fi
