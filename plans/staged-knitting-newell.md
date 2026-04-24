# Automatic Stale Process Monitor on Session Start

## Context
Stale node/vitest processes from background agents accumulate during sessions. Currently requires manual `/loop` setup each time. User wants this automated across all projects.

## Approach
1. **Shell script** (`~/.claude/scripts/stale-process-monitor.sh`) — already created
   - Runs in background, checks every 5 min for node/vitest processes older than 10 min
   - PID-file guard prevents duplicate monitors
   - Logs kills to `~/.claude/logs/stale-monitor.log`

2. **SessionStart hook** in `~/.claude/settings.json`
   - Add `hooks.SessionStart` entry that launches the monitor script with `nohup`
   - Uses `"async": false` so stdout message appears as session context
   - Outputs confirmation message Claude sees on startup

## Files to modify
- `~/.claude/settings.json` — add `hooks.SessionStart` array
- `~/.claude/scripts/stale-process-monitor.sh` — already created, needs `chmod +x`

## Hook config to add
```json
"hooks": {
  "SessionStart": [
    {
      "matcher": "",
      "hooks": [
        {
          "type": "command",
          "command": "nohup ~/.claude/scripts/stale-process-monitor.sh >> ~/.claude/logs/stale-monitor.log 2>&1 & echo 'Stale process monitor started (PID '$!')'",
          "timeout": 5
        }
      ]
    }
  ]
}
```

## Verification
- Start a new Claude Code session and confirm "Stale process monitor started" appears in hook output
- Check `ps aux | grep stale-process-monitor` shows the background process
- Verify `~/.claude/scripts/.stale-monitor.pid` is written
