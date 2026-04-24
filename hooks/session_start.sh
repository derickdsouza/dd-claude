#!/bin/bash
# Create directories if they don't exist
mkdir -p /tmp/.ai-dev-workflow/claude

# Record session start time
date +%s > /tmp/.ai-dev-workflow/claude/session_start
echo "[$(date)] Session started in $(pwd)" >> /tmp/.ai-dev-workflow/claude/session.log

# Generate unique session ID and store it
SESSION_ID="session-$(date +%s)-$$"
echo "$SESSION_ID" > /tmp/.ai-dev-workflow/claude/session-${$}.id

# Set initial IDLE state for this session
STATE_FILE="/tmp/.ai-dev-workflow/claude/project-state-${SESSION_ID}.json"
cat > "$STATE_FILE" <<EOF
{
  "project": "",
  "action": "IDLE",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF

# Clean up session files older than 24 hours
find /tmp/.ai-dev-workflow/claude -name "session-*.id" -mtime +1 -delete 2>/dev/null
find /tmp/.ai-dev-workflow/claude -name "project-state-session-*.json" -mtime +1 -delete 2>/dev/null

exit 0
