#!/bin/bash

# GET REPO INFO
REPO=$(basename "$(git rev-parse --show-toplevel 2>/dev/null)" || echo "Unknown")
BRANCH=$(git branch --show-current 2>/dev/null || echo "main")

# SEND COMPLETION NOTIFICATION
osascript -e "display notification \"Task complete. Waiting for next instruction.\" with title \"✅ Claude finished\" subtitle \"Repo: $REPO/$BRANCH\" sound name \"Hero\""

# SEND TO IPHONE (update the phone number!)
osascript -e 'tell application "Messages" to send "✅ Claude completed task in '$REPO/$BRANCH'" to buddy "+919766257263" of (1st service whose service type = iMessage)'

# Let Claude continue
echo '{"continue": true}'
