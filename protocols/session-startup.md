# Session Startup

## Step 1: GitButler Workspace Cleanup (MANDATORY)

Run immediately on session start, before any work:

```bash
# 1. Remove stale git index locks
rm -f .git/index.lock

# 2. Prune orphaned worktrees
git worktree prune

# 3. Remove agent worktrees left from previous sessions
git worktree list | grep worktree-agent | awk '{print $1}' | while read wt; do
  git worktree remove --force "$wt"
done

# 4. Delete local branches already merged into main
git fetch origin main
git branch --merged origin/main --format='%(refname:short)' \
  | grep -v 'main\|gitbutler\|\*' \
  | xargs -r git branch -D

# 5. Prune remote-tracking branches
git remote prune origin

# 6. Remove stale .claude/worktrees directories
rm -rf .claude/worktrees/agent-*

# 7. Run GitButler gc
but gc
```

**Safety**: Never delete `main`, `gitbutler/workspace`, or `gitbutler/target`.

Full protocol: `~/.claude/protocols/gitbutler-cleanup.md`

---

## Step 2: Stale Resource Cleanup Loop

Schedule a recurring cleanup using `CronCreate` within the first few messages. This prevents resource leaks from background agents, forgotten dev servers, and orphaned test runners.

**Schedule**: Every 30 minutes, recurring.

**Prompt to schedule**:
```
check for and clean up all stale session resources:
1. Background bash shells (use TaskStop for any completed background tasks visible in the session)
2. Stale OS processes started by this session (bun test, bun dev, vitest, vite, playwright, node test runners) — kill by PID
3. Orphaned port listeners on dev ports (3001, 5176, 8080) — kill by lsof -ti:PORT
4. Completed background agents that left child processes
5. Stale GitButler worktrees from agent activity
Report what was found and cleaned.
```

**Why**: Background shells (`run_in_background` bash commands) persist even after completion and are invisible unless explicitly checked. Agents that spawn dev servers or test runners may not clean up child processes. This loop catches all of them.
