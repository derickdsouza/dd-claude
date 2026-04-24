#!/bin/bash

# Configuration
PHONE_NUMBER="+919766257263"  # Replace with your phone number

# Get repository and task info
REPO_NAME=$(basename "$(git rev-parse --show-toplevel 2>/dev/null)" 2>/dev/null || echo "Unknown")
REPO_BRANCH=$(git branch --show-current 2>/dev/null || echo "Unknown")

# Calculate task duration if we have session start time
DURATION="Unknown"
SESSION_START_FILE="$HOME/.claude/session_start"
if [ -f "$SESSION_START_FILE" ]; then
    START_TIME=$(cat "$SESSION_START_FILE")
    END_TIME=$(date +%s)
    DURATION_SECS=$((END_TIME - START_TIME))
    DURATION="$((DURATION_SECS / 60))m $((DURATION_SECS % 60))s"
fi

# Get final context usage
CONTEXT_INFO=$(python3 -c "
import os
transcript = os.environ.get('CLAUDE_TRANSCRIPT_PATH', '')
if transcript and os.path.exists(transcript):
    with open(transcript, 'r') as f:
        lines = f.readlines()
        total_chars = sum(len(line) for line in lines)
        used_tokens = total_chars // 4
        remaining = 200000 - used_tokens
        percent = (remaining / 200000) * 100
        print(f'{percent:.1f}% remaining')
else:
    print('Unknown')
" 2>/dev/null || echo "Unknown")

# Send completion notification
TITLE="Claude Code: ✅ Task Complete"
BODY="Repository: $REPO_NAME/$REPO_BRANCH
Duration: $DURATION
Context: $CONTEXT_INFO
Waiting for next task..."

/usr/bin/osascript -e "display notification \"$BODY\" with title \"$TITLE\" sound name \"Hero\""

# Send iPhone notification
/usr/bin/osascript -e "tell application \"Messages\" to send \"✅ Task Complete in $REPO_NAME - Duration: $DURATION, Context: $CONTEXT_INFO\" to buddy \"$PHONE_NUMBER\" of (1st service whose service type = iMessage)"

# Allow Claude to stop
echo '{"continue": true}'
