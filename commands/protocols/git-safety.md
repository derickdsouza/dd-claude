# Git Commit Safety Protocol

## CRITICAL RULE: STOP Before Any Git Operation

**TRIGGER WORDS:** commit, push, git commit, create commit, save changes, stage changes, git add, commit message

**WHEN USER SAYS ANY TRIGGER WORD:**

```
MANDATORY CIRCUIT BREAKER ACTIVATED

1. STOP IMMEDIATELY - Do not proceed with ANY git commands
2. READ ~/.aiagent/git_commit_protocol.md IN FULL
3. ACKNOWLEDGE protocol requirements to user
4. FOLLOW protocol starting from Step 0 (pre-commit hooks)
5. DO NOT take shortcuts, even if user says "quick commit"
6. DO NOT skip categorization, file size checks, or commit plan
```

**NO EXCEPTIONS. NO SHORTCUTS. NO "JUST THIS ONCE."**

---

## Git Commit Enforcement Checklist

Before executing **ANY** git command, verify:

- [ ] Have I read git_commit_protocol.md completely?
- [ ] Have I acknowledged the protocol to the user?
- [ ] Am I starting from Step 0 (pre-commit hooks)?
- [ ] Will I create a categorization table?
- [ ] Will I verify file size limits (<=275 lines per file)?
- [ ] Will I create a commit plan review?
- [ ] Will I use --no-verify flag for commits?
- [ ] Will I run pre-push audit before pushing?

**If ANY answer is "NO" -> STOP and restart from protocol Step 0**

---

## Required User Acknowledgment

When user triggers git operation, respond with:

```
GIT COMMIT PROTOCOL TRIGGERED

I've detected a git operation request. Before proceeding, I must:

1. Read the complete git commit protocol
2. Run pre-commit hooks to apply auto-fixes
3. Create categorization table for all changes
4. Verify all files <=275 lines (refactor if needed)
5. Create commit plan review
6. Split into atomic commits (<=5 files OR <=300 lines each)
7. Check for untracked files
8. Run pre-push audit before pushing

This will take a few extra steps but ensures clean, reviewable commits.

Proceeding with protocol now...
```

---

## Common Violations to NEVER Commit

- Single commit with 10+ files
- Single commit with 300+ lines (except .md/.json files)
- Mixing .md + .py files in same commit
- Skipping pre-commit hooks
- Not categorizing changes
- Committing files >275 lines without refactoring
- Using `git commit -m` without --no-verify
- Skipping pre-push audit

**Even if user says "just commit quickly" -> FOLLOW FULL PROTOCOL**

---

## Quick Reference

| Rule | Limit |
|------|-------|
| Files per commit | <=5 |
| Lines added per commit | <=300 |
| Code file size | <=275 lines |
| Pre-commit hooks | Required |
| Pre-push audit | Required |
