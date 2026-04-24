# Git Safety Protocol

## Rules

**No raw git write commands without bd-ship provenance.**

The pre-push hook (`scripts/setup-dev.sh` installs it) enforces:
- All pushes to `refs/heads/main` are always blocked
- Pushes to `fix/*` branches are blocked unless `.beads/.shipping-<branch>` lock exists
- `bd-ship` creates the lock before push and removes it after PR creation

## Size Limits

| Rule | Limit |
|------|-------|
| Files per commit | ≤5 |
| Lines changed per commit | ≤300 |
| Code file size | ≤275 lines |

## Merge Protocol

After bd-ship creates and merges the PR, clean up:

```bash
git checkout main
git pull origin main
git branch -d <branch-name>
```

## Workspace Sync Commits — Stale Worktree Danger

**NEVER** stage a commit that contains files from a branch that diverged before recent PRs landed.

**The failure pattern**: A branch off commit A. PRs land on main (commits B, C). A sync commit then squashes the branch changes — but the branch still has the old versions of files changed in B and C. The sync commit silently overwrites those PR changes on main.

**Mandatory check before any sync commit**: Run `git diff origin/main -- <files being staged>` for every file in the commit. If the diff shows the file reverting recent PR changes, **do not stage it** — pull first and rebase onto current main.

```bash
# Before staging a sync commit, verify no regressions:
git fetch origin
git diff origin/main -- <file1> <file2> ...
# If you see changes being reverted that don't belong to you → STOP, pull first
```

## Cleanup

After any git operations, prune stale branches and worktrees:

```bash
git fetch origin main --prune
git branch --merged origin/main --format='%(refname:short)' \
  | grep -v 'main\|\*' \
  | xargs -r git branch -d
git worktree prune
git remote prune origin
```
