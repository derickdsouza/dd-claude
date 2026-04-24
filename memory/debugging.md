# Debugging Patterns

Cross-project debugging insights and recurring failure patterns.

Check this file before investigating a bug — many root causes recur.

---

## Known Patterns

(Populated as bugs are investigated and fixed)

---

## Format

When adding an entry:
```
- [YYYY-MM-DD] <system>: <root cause> → <fix pattern>
```

Example:
```
- [2026-04-15] async-queue: race condition on dequeue → use atomic INCR+EXPIRE via shared utility
- [2026-04-15] websocket: dropped ticks on reconnect → buffer during reconnect window, replay on reconnect
```

- [2026-04-19] claude-code-settings: `statusLine` uses `command`, not `value`; schema validation can surface this as an invalid `statusLine.type` error → rename the key and revalidate the JSON object shape
- [2026-04-20] claude-code-permissions: Bash allow rules for `rm -f .git/*.lock` persist correctly, but `.git` remains a protected path and can still prompt separately → use a narrow `PermissionRequest` hook for stale lock cleanup and keep GitButler preflight commands on one canonical `rm -f .git/index.lock .git/background-refresh.lock 2>/dev/null; but ...` form
