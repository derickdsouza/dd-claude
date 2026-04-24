---
name: atomic-execution
description: "Disciplined atomic execution — one commit per logical unit with TDD flow and self-verification."
---

# Atomic Execution Methodology

## Core Principle

Execute work atomically: one commit per logical unit of work. Each commit represents a complete, verifiable change. Never batch unrelated changes. Never leave work uncommitted between tasks.

## Atomic Commit Discipline

### Per-Task Commits

After each task completes (verification passed, done criteria met), commit immediately.

**1. Check modified files:** `git status --short`

**2. Stage task-related files individually.** Never use `git add .` or `git add -A`. Stage each file by name:
```bash
git add src/api/auth.ts
git add src/types/user.ts
```

**3. Select commit type:**

| Type | When |
|------|------|
| `feat` | New feature, endpoint, component |
| `fix` | Bug fix, error correction |
| `test` | Test-only changes (TDD RED phase) |
| `refactor` | Code cleanup, no behavior change |
| `chore` | Config, tooling, dependencies |

**4. Write the commit message:**
```
{type}(scope): {concise task description}

- {key change 1}
- {key change 2}
```

**5. Record the commit hash** for traceability in summaries and reporting.

### What Makes a Good Atomic Commit

- Represents exactly one logical unit of work
- Passes all relevant tests after the commit
- Can be understood in isolation from surrounding commits
- Has a message that explains what changed and why

## Deviation Rules

While executing planned work, you WILL discover issues not in the plan. These four rules determine how to handle them. Track all deviations for reporting.

### Rule 1: Auto-Fix Bugs

**Trigger:** Code doesn't work as intended — broken behavior, errors, incorrect output.

**Examples:** Wrong queries, logic errors, type errors, null pointer exceptions, broken validation, security vulnerabilities, race conditions, memory leaks.

**Action:** Fix inline, add/update tests if applicable, verify the fix, continue the task. No permission needed.

### Rule 2: Auto-Add Missing Critical Functionality

**Trigger:** Code is missing essential features for correctness, security, or basic operation.

**Examples:** Missing error handling, no input validation, missing null checks, no auth on protected routes, missing authorization, no CSRF/CORS protection, no rate limiting, missing database indexes, no error logging.

**Action:** Add the missing functionality inline, verify, continue. No permission needed.

**Key distinction:** These are not "features" — they are correctness requirements. Code without input validation is incomplete, not "missing a feature."

### Rule 3: Auto-Fix Blocking Issues

**Trigger:** Something prevents completing the current task.

**Examples:** Missing dependency, wrong types, broken imports, missing environment variable, database connection error, build config error, missing referenced file, circular dependency.

**Action:** Fix the blocker, verify, continue. No permission needed.

### Rule 4: Ask About Architectural Changes

**Trigger:** The fix requires significant structural modification.

**Examples:** New database table (not just a column), major schema changes, new service layer, switching libraries or frameworks, changing auth approach, new infrastructure, breaking API changes.

**Action:** STOP. Present what was found, the proposed change, why it is needed, its impact, and alternatives. **Human decision required** before proceeding.

### Rule Priority

1. If Rule 4 applies: STOP (architectural decision needed)
2. If Rules 1-3 apply: fix automatically
3. If genuinely unsure: treat as Rule 4 (ask)

### Edge Cases

- Missing validation -> Rule 2 (security/correctness)
- Crashes on null -> Rule 1 (bug)
- Need new table -> Rule 4 (architectural)
- Need new column -> Rule 1 or 2 (depends on context)

**Heuristic:** "Does this affect correctness, security, or ability to complete the task?" YES -> Rules 1-3. MAYBE -> Rule 4.

### Scope Boundary

Only auto-fix issues DIRECTLY caused by the current task's changes. Pre-existing warnings, linting errors, or failures in unrelated files are out of scope. Log out-of-scope discoveries for later. Do not fix them. Do not re-run builds hoping they resolve themselves.

### Fix Attempt Limit

Track auto-fix attempts per task. After 3 attempts on a single task:
- Stop fixing
- Document remaining issues as deferred
- Continue to the next task (or pause if blocked)

## Checkpoint Protocols

Checkpoints are moments where human input is needed before continuing.

### Types

**Human-Verify (most common):** Visual or functional verification after automation. Provide what was built, exact verification steps (URLs, commands), and expected behavior.

**Decision:** An implementation choice is needed that affects direction. Provide context, options with pros/cons, and a clear selection prompt.

**Human-Action (rare):** A truly unavoidable manual step like clicking an email verification link, entering a 2FA code, or completing a 3D Secure flow. These cannot be automated.

### Automation-First Principle

Before any human-verify checkpoint, ensure the verification environment is ready. If a server needs to be running for the human to verify, start it before pausing.

Users NEVER run CLI commands. Users ONLY visit URLs, click UI elements, evaluate visual results, or provide secrets. All automation is the implementer's responsibility.

### When to Pause

- Visual verification is needed (UI looks correct?)
- A decision with real tradeoffs must be made
- An authentication gate is hit (credentials needed)
- An architectural question arises (Rule 4 deviation)

## Authentication Gates

Auth errors during execution are gates, not failures.

**Indicators:** "Not authenticated", "Unauthorized", "401", "403", "Please run login", "Set ENV_VAR"

**Protocol:**
1. Recognize it as an auth gate (not a bug)
2. Stop the current task
3. Provide exact auth steps (CLI commands, where to get keys)
4. Specify a verification command to confirm auth works
5. Document as normal flow, not a deviation

## TDD Execution Flow

When a task calls for test-driven development, follow the RED-GREEN-REFACTOR cycle strictly.

### RED Phase

1. Read the expected behavior specification
2. Create the test file
3. Write failing tests that describe the expected behavior
4. Run the tests — they MUST fail
5. Commit: `test(scope): add failing test for [feature]`

If tests don't fail: investigate. The test may be wrong, or the behavior may already exist.

### GREEN Phase

1. Read the implementation specification
2. Write the MINIMAL code needed to make tests pass
3. Run the tests — they MUST pass
4. Commit: `feat(scope): implement [feature]`

If tests don't pass: debug and iterate. Do not move to refactor until green.

### REFACTOR Phase (if needed)

1. Clean up the implementation
2. Run the tests — they MUST still pass
3. Commit only if changes were made: `refactor(scope): clean up [feature]`

If refactoring breaks tests: undo the refactoring.

### TDD Produces 2-3 Commits

Each TDD cycle yields atomic commits: one for RED (test only), one for GREEN (implementation), and optionally one for REFACTOR. This gives clear traceability of what was tested, what was built, and what was cleaned up.

## Self-Check Verification

After completing work, verify all claims before declaring done. Never trust memory — check the filesystem and git history.

### Check Created Files Exist

```bash
[ -f "path/to/file" ] && echo "FOUND" || echo "MISSING"
```

### Check Commits Exist

```bash
git log --oneline | grep -q "{hash}" && echo "FOUND" || echo "MISSING"
```

### Verify Test Results

Re-run verification commands. Do not rely on cached results or memory of previous runs.

### Record the Self-Check Result

Append either "Self-Check: PASSED" or "Self-Check: FAILED" with specific missing items listed. Do not skip self-check. Do not proceed to further work if self-check fails.

## Deviation Documentation

Track every deviation from the plan for transparency and learning.

### Format

For each deviation, record:
- **Rule applied** (1-4)
- **Category** (bug, missing functionality, blocker, architectural)
- **Found during:** which task
- **Issue:** what was wrong
- **Fix:** what was done
- **Files modified:** which files changed
- **Commit:** the hash

### No Deviations

If the plan executed exactly as written, state that explicitly. "None — plan executed exactly as written" is a valid and valuable signal.

## Execution Checklist

Before declaring any unit of work complete:

- [ ] All tasks executed or paused at checkpoint with full state
- [ ] Each task committed individually with proper type and message
- [ ] All deviations documented with rule classification
- [ ] Authentication gates handled and documented as normal flow
- [ ] Self-check passed (files exist, commits exist, tests pass)
- [ ] No uncommitted changes left in the working tree
