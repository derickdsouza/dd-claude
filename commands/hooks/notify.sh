#!/bin/bash

# READ THE JSON INPUT
INPUT=$(cat)

# EXTRACT MESSAGE
MESSAGE=$(echo "$INPUT" | grep -o '"message":"[^"]*"' | sed 's/"message":"//;s/"$//')

# GET REPO INFO
REPO=$(basename "$(git rev-parse --show-toplevel 2>/dev/null)" || echo "Unknown")
BRANCH=$(git branch --show-current 2>/dev/null || echo "main")

# ESTIMATE CONTEXT (simple version)
CONTEXT="~90% remaining"

# DETECT URGENCY
if echo "$MESSAGE" | grep -qi "permission\|waiting\|error"; then
    SOUND="Basso"
    ICON="⚠️"
else
    SOUND="Glass"
    ICON="ℹ️"
fi

# SEND DESKTOP NOTIFICATION
osascript -e "display notification \"$MESSAGE\" with title \"$ICON Claude needs you\" subtitle \"Repo: $REPO/$BRANCH • Context: $CONTEXT\" sound name \"$SOUND\""

# SEND TO IPHONE (update the phone number!)
osascript -e 'tell application "Messages" to send "Claude needs intervention in '$REPO': '$MESSAGE'" to buddy "+919766257263" of (1st service whose service type = iMessage)'

exit 0
