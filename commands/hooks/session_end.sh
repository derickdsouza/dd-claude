#!/bin/bash

# GET REPO INFO
REPO=$(basename "$(git rev-parse --show-toplevel 2>/dev/null)" || echo "Unknown")
BRANCH=$(git branch --show-current 2>/dev/null || echo "main")

# CALCULATE SESSION DURATION (if we tracked it)
DURATION="Unknown"
if [ -f /tmp/.ai-dev-workflow/claude/session_start ]; then
    START=$(cat /tmp/.ai-dev-workflow/claude/session_start)
    NOW=$(date +%s)
    DIFF=$((NOW - START))
    HOURS=$((DIFF / 3600))
    MINUTES=$(((DIFF % 3600) / 60))
    DURATION="${HOURS}h ${MINUTES}m"
fi

# GET FINAL CONTEXT USAGE ESTIMATE
# Count approximate tokens used (rough estimate)
TRANSCRIPT_SIZE=$(du -sh ~/.claude/transcripts/* 2>/dev/null | tail -1 | awk '{print $1}' || echo "0")
CONTEXT="Used ~${TRANSCRIPT_SIZE}B of context"

# SEND SESSION END WARNING
osascript -e "display notification \"Session ending. Duration: $DURATION\n$CONTEXT\" with title \"🔚 Claude Session Ending\" subtitle \"Repo: $REPO/$BRANCH\" sound name \"Purr\""

# SEND TO IPHONE (update the phone number!)
osascript -e 'tell application "Messages" to send "🔚 Claude session ending in '$REPO/$BRANCH' - Duration: '$DURATION' - '$CONTEXT'" to buddy "+919766257263" of (1st service whose service type = iMessage)'

# Log session end
echo "[$(date)] Session ended - Repo: $REPO, Duration: $DURATION" >> /tmp/.ai-dev-workflow/claude/session.log

# Allow session to end
echo '{"continue": true}'
