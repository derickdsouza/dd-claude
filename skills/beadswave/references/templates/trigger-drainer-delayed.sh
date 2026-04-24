#!/bin/bash
# Delayed Trigger for Claude Backlog Drainer
# Waits 30 minutes then creates a trigger file

DELAY_SECONDS=1800  # 30 minutes
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
TRIGGER_FILE="$PROJECT_DIR/.drainer-trigger"
LOG_FILE="$PROJECT_DIR/drainer-trigger-$(date +%Y%m%d-%H%M%S).log"

echo "========================================" | tee -a "$LOG_FILE"
echo "Claude Backlog Drainer - Delayed Trigger" | tee -a "$LOG_FILE"
echo "Started: $(date)" | tee -a "$LOG_FILE"
echo "Will trigger in: $DELAY_SECONDS seconds (30 minutes)" | tee -a "$LOG_FILE"
echo "Trigger time: $(date -v+30M)" | tee -a "$LOG_FILE"
echo "Project: $PROJECT_DIR" | tee -a "$LOG_FILE"
echo "Trigger file: $TRIGGER_FILE" | tee -a "$LOG_FILE"
echo "Log: $LOG_FILE" | tee -a "$LOG_FILE"
echo "========================================" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# Show start notification
osascript -e 'display notification "Drainer will trigger in 30 minutes" with title "Claude Drainer Scheduled" sound name "Glass"' 2>/dev/null || true

# Wait for 30 minutes
echo "Waiting for 30 minutes..." | tee -a "$LOG_FILE"
sleep "$DELAY_SECONDS"

echo "" | tee -a "$LOG_FILE"
echo "========================================" | tee -a "$LOG_FILE"
echo "Timer complete at $(date)" | tee -a "$LOG_FILE"
echo "Creating trigger file..." | tee -a "$LOG_FILE"
echo "========================================" | tee -a "$LOG_FILE"

# Create trigger file with timestamp and status
cat > "$TRIGGER_FILE" <<EOF
TRIGGERED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
TRIGGER_REASON=scheduled_30min
STATUS=ready
MESSAGE=Backlog drainer ready to run
EOF

echo "Trigger file created: $TRIGGER_FILE" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# Show completion notification with sound
osascript -e 'display notification "Backlog drainer is ready! Check your Claude session." with title "⏰ Drainer Triggered" sound name "Glass"' 2>/dev/null

# Also show an alert dialog for visibility
osascript <<EOF 2>/dev/null
display dialog "The backlog drainer trigger has fired!

Time: $(date)

Next steps:
1. The trigger file has been created
2. Check your Claude session
3. Claude will detect the trigger and start draining

Click OK to continue." buttons {"OK"} default button "OK" with title "Claude Backlog Drainer" with icon note
EOF

echo "========================================" | tee -a "$LOG_FILE"
echo "TRIGGER COMPLETE" | tee -a "$LOG_FILE"
echo "Next: Claude should detect the trigger file and start draining" | tee -a "$LOG_FILE"
echo "Completed at: $(date)" | tee -a "$LOG_FILE"
echo "========================================" | tee -a "$LOG_FILE"

# Print trigger status
cat "$TRIGGER_FILE" | tee -a "$LOG_FILE"
