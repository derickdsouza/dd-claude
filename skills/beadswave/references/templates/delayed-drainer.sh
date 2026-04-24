#!/bin/bash
# Delayed Backlog Drainer
# Waits 15 minutes then triggers the drainer

DELAY_SECONDS=900  # 15 minutes
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LOG_FILE="$PROJECT_DIR/drainer-$(date +%Y%m%d-%H%M%S).log"

echo "========================================" | tee -a "$LOG_FILE"
echo "Delayed Backlog Drainer" | tee -a "$LOG_FILE"
echo "Started: $(date)" | tee -a "$LOG_FILE"
echo "Will run in: $DELAY_SECONDS seconds (15 minutes)" | tee -a "$LOG_FILE"
echo "Project: $PROJECT_DIR" | tee -a "$LOG_FILE"
echo "Log: $LOG_FILE" | tee -a "$LOG_FILE"
echo "========================================" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# Wait for 15 minutes
echo "Waiting..." | tee -a "$LOG_FILE"
sleep "$DELAY_SECONDS"

echo "" | tee -a "$LOG_FILE"
echo "========================================" | tee -a "$LOG_FILE"
echo "Timer complete! Starting drainer at $(date)" | tee -a "$LOG_FILE"
echo "========================================" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# Change to project directory
cd "$PROJECT_DIR" || exit 1

# Show notification (macOS)
osascript -e 'display notification "Backlog drainer starting now" with title "Claude Drainer" sound name "Glass"' 2>/dev/null || true

# Run the drainer commands
{
    echo "=== BOOTSTRAP ==="
    bd doctor
    bd ready --json | jq 'length'
    bd list --status open --json | jq 'length'
    bd blocked
    bd stats
    
    echo ""
    echo "=== BACKLOG STATUS ==="
    echo "Ready issues:"
    bd ready --json | jq -r '.[] | "\(.id) [\(.priority)] \(.title)"'
    
    echo ""
    echo "=== INSTRUCTIONS ==="
    echo "The drainer has been triggered."
    echo "To continue, run Claude with the backlog drainer prompt."
    echo ""
    echo "Log saved to: $LOG_FILE"
    
    # Show final notification
    osascript -e 'display notification "Check terminal for results" with title "Claude Drainer Complete" sound name "Glass"' 2>/dev/null || true
    
} 2>&1 | tee -a "$LOG_FILE"

echo ""
echo "========================================" | tee -a "$LOG_FILE"
echo "Drainer trigger complete at $(date)" | tee -a "$LOG_FILE"
echo "========================================" | tee -a "$LOG_FILE"
