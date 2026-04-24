# Git Commit Protocol → GitButler

**This protocol has been superseded by GitButler (`but`).**

## MANDATORY: Invoke the gitbutler skill

Before performing any commit, push, branch, or other write operation, you MUST invoke the skill:

```
Skill({ skill: "gitbutler" })
```

The gitbutler skill covers the full workflow:
- Inspecting state: `but status -fv`
- Committing: `but commit <branch> -m "<msg>" --changes <id1>,<id2> --status-after`
- Branching: `but branch new <name>`
- Pushing: `but push --status-after`
- Pulling: `but pull --check` then `but pull --status-after`
- Amending, reordering, stacking, conflict resolution

**Full skill location:** `~/.claude/skills/gitbutler/`

## Size Limits (unchanged)

| Rule | Limit |
|------|-------|
| Files per commit | ≤5 |
| Lines changed per commit | ≤300 |
| Code file size | ≤275 lines |
