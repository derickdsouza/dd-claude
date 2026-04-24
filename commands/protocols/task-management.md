# Task State Management with Beads

## Overview

**Beads** is an AI-native issue tracking system that lives in your repository. Use it for ALL task management operations.

---

## TRIGGER WORDS for Task Operations

- task, tasks, issue, issues
- implement, implementation, build, create, develop, code
- fix, bug, error, problem, resolve, resolution
- feature, requirement, story, user story
- refactor, refactorings, improve, improvement, optimize
- test, testing, coverage, spec, specification, test case
- document, documentation, readme, guide, manual
- deploy, deployment, release, publish
- security, vulnerability, audit, secure
- performance, optimization, scaling, speed
- dependency, dependencies, library, package, module

---

## When Trigger Word Detected

1. **Check if project uses Beads** (look for `.beads/` directory)
2. **Use Beads CLI** instead of TodoWrite
3. **Create/update Beads issues** for all task-related work
4. **Track dependencies** using Beads' built-in dependency system
5. **Sync with git** using `bd sync` commands

---

## Beads Commands

### Creating Tasks

```bash
# Create new issue
bd create "Implement user authentication"

# Create with description
bd create "Fix login validation bug" -d "Users cannot login with special characters"

# Create with labels
bd create "Add email notifications" -l feature,medium,phase-4
```

### Managing Tasks

```bash
# List all issues
bd list

# List by status
bd list --status open
bd list --status in_progress
bd list --status done

# List by label
bd list --label critical
bd list --label phase-1

# Show issue details
bd show <issue-id>

# Update task status
bd update <issue-id> --status in_progress
bd update <issue-id> --status done

# Add/remove labels
bd update <issue-id> --add-label testing
bd update <issue-id> --remove-label phase-1

# Set priority (1=highest, 2=high, 3=medium, 4=low)
bd update <issue-id> --priority 1
```

### Managing Dependencies

```bash
# Add dependency (task depends on another)
bd depends <issue-id> --add <depends-on-id>

# Remove dependency
bd depends <issue-id> --remove <depends-on-id>

# View dependency graph
bd deps <issue-id>
```

### Other Operations

```bash
# Search issues
bd search "authentication"

# Sync with remote git
bd sync

# Show statistics
bd stats

# Mark as ready for work
bd update <issue-id> --label ready
```

---

## Beads Storage & Integration

- **Location**: Tasks stored in `.beads/issues.jsonl` (git-tracked)
- **Auto-sync**: Automatically syncs with git commits
- **Database**: Uses local SQLite DB at `.beads/beads.db`
- **CLI Socket**: Communicates via `.beads/bd.sock`

---

## Session Workflow

1. **Start**: `bd list --status=open` -> `bd show <id>` -> `bd update <id> --status=in_progress`
2. **Work**: Focus on one `in_progress` task at a time
3. **Complete**: `bd update <id> --status=done`
4. **End**: `bd list --status=in_progress` -> `bd sync`

---

## Label Conventions

- **Priority**: critical, high, medium, low
- **Phase**: phase-1, phase-2, phase-3, phase-4, phase-5, phase-6, phase-7
- **Type**: feature, bug, refactor, doc, test, security, performance

---

## Important Rules

- NEVER use TodoWrite when project has Beads
- ALWAYS create Beads issues for new work
- UPDATE issue status when starting/completing
- CHECK dependencies before starting tasks
- SYNC with git remote regularly
- USE appropriate labels for organization
- REFERENCE related files in descriptions

---

## Examples of Task Creation

```bash
# New feature request
bd create "Implement client order validation" -l feature,critical,phase-3

# Bug report
bd create "Fix trade calculation error for USD pairs" -l bug,high,phase-3

# Refactoring task
bd create "Refactor service layer to use dependency injection" -l refactor,medium,phase-2

# Testing task
bd create "Add unit tests for PricingService" -l test,high,phase-7

# Documentation task
bd create "Update API documentation for new endpoints" -l doc,low,phase-7
```
