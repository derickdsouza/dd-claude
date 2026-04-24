# Context Management

## Context Window

Your context window will be automatically compacted as it approaches its limit. Never stop tasks early due to token budget concerns. Always complete tasks fully.

## Context Thresholds

- **60%**: Warning (continue, log only)
- **80%**: Action (pause, persist, show options — choose: CLEANUP, COMPACT, REVIEW, or PAUSE)
- **95%**: Critical (emergency halt)

## Compact Instructions

When `/compact` runs (manual or auto), the summary **must preserve**:

- **Active objective** — what task/goal is in progress and its exit condition
- **Progress state** — completed IDs, remaining ready/in_progress counts, blocked IDs and their spike/blocker IDs
- **Modified files** — paths changed this session
- **Commands** — build, test, lint commands for this project
- **Open dependencies** — what is blocking what
- **Errors in flight** — failing test names, error signatures under investigation
- **Git state** — active branch/worktree, uncommitted changes

After compaction, Claude Code injects the summary back via PostCompact hook. Resume work immediately — do not re-bootstrap from scratch, re-read files already summarized, or ask the user what was happening.

## Context Overflow Prevention

1. **Monitor token usage**: 60% (warn), 80% (action), 95% (critical)
2. **At 80% threshold**: Choose from CLEANUP, COMPACT, REVIEW, or PAUSE
3. **Work is automatically persisted** to JSON files

## Session Resumption

1. **Use `/resume` command** or wait for automatic detection
2. **Choose restoration option**: RESUME, DEFER, REVIEW, CLEANUP, COMPACT, or ARCHIVE
3. **Previous work is restored** and session continues
