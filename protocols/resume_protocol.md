# Resume Protocol

**Version**: 1.0
**Date**: 2025-10-04
**Status**: Active

---

## Purpose

This document defines the resume workflow that enables users to seamlessly continue interrupted work sessions by automatically detecting persisted task files and providing intelligent resumption options.

---

## Detection Algorithm

### Execution Timing

**Primary Trigger**: NEW_SESSION initialization (after project menu selection)
**Secondary Trigger**: Explicit user command (`/resume` or `resume`)

### Detection Workflow

```
STEP 1: Scan for Pending Task Files
├── Identify current project from session state
├── Construct search path: {project}/.claude/pending-tasks-*.json
├── Use glob pattern to find all matching files
└── If no files found → Exit (no resume needed)

STEP 2: Filter by Current Project
├── For each file found:
│   ├── Parse JSON to extract project_path
│   └── Compare with current session project_path
└── Keep only files matching current project

STEP 3: Sort by Timestamp
├── Extract timestamp from filename
├── Sort files by timestamp (newest first)
└── Select most recent file

STEP 4: Calculate File Age
├── Parse timestamp from selected file
├── Calculate: age_hours = (now - file_timestamp) / 3600
└── Determine age category: <24hrs or >24hrs

STEP 5: Return Detection Result
└── Return: {file_path, age_hours, age_category, task_counts}
```

---

## Age-Based Conditional Logic

### Two-Tier Prompt System

| Age Category | Threshold | Behavior | Prompt Type |
|--------------|-----------|----------|-------------|
| **Recent** | < 24 hours | Blocking | Full options prompt |
| **Older** | > 24 hours | Non-blocking | Subtle notification |

### Rationale

**Recent (<24 hours)**:
- User likely intends to continue this work
- High probability of context still relevant
- Prompt immediately to prevent duplicate effort
- **Blocking**: Requires user response before proceeding

**Older (>24 hours)**:
- User may have moved to different work
- Context may no longer be relevant
- Don't interrupt with blocking prompt
- **Non-blocking**: Show subtle notification, let user decide

---

## User Prompt Variations

### Blocking Prompt (< 24 hours)

```
🔄 PENDING TASKS DETECTED

Session: {session-id}
Last Active: {timestamp} ({age_hours} hours ago)
Progress: {completed_count}/{total_count} tasks ({completion_percentage}% complete)
Recommendation: {CLEANUP|COMPACT} (Confidence: {confidence_level})

┌─────────────────────────────────────────┐
│ Task Summary                            │
├─────────────────────────────────────────┤
│ ✅ Completed & Verified: {count}       │
│ 📋 Pending: {count}                    │
│ 🔄 In Progress: {count}                │
└─────────────────────────────────────────┘

Persisted file: {relative_path}

Options:
1. RESUME - Continue from where we left off
   → Loads all pending + in-progress tasks
   → Re-invokes specialist agents in parallel
   → Applies mandatory verification to each task

2. DEFER - Skip for now, remind me later (I have other work first)
   → Sets reminder flag for this session
   → You can type 'resume' later to come back
   → Will re-prompt at session end if not addressed

3. REVIEW - Show full task list, let me choose what to resume
   → Displays detailed breakdown of all tasks
   → Allows selective task resumption
   → Can archive unwanted tasks

4. CLEANUP - Clear old context, then resume fresh
   → Discards previous conversation context
   → Restores only task list + verification reports
   → Best for independent tasks

5. COMPACT - Compress context, then resume with history
   → Preserves essential historical context
   → Removes verbose tool outputs
   → Best for debugging/refactoring

6. ARCHIVE - Move to archive, start completely fresh
   → Moves pending-tasks file to archive/
   → Starts new work session from scratch
   → Can manually resume archived tasks later

Your choice? [1/2/3/4/5/6]
```

### Non-Blocking Notification (> 24 hours)

```
💡 Found {pending_count} pending tasks from {date} ({age_days} days ago).

Last session: {brief_task_summary}
File: {relative_path}

Type 'resume' or '/resume' to continue, or proceed with new work.
```

---

## DEFER Mechanism

### Purpose
Allow users to postpone resume decision without losing awareness.

### Implementation

**When User Selects DEFER**:
1. Set session flag: `deferred_resume = true`
2. Store file path: `deferred_file_path = {path}`
3. Continue with normal session work
4. Monitor for explicit resume trigger

**Re-Prompt Triggers**:
- User types "resume" or "/resume" (anytime during session)
- Session end detected (if possible)
- User explicitly asks about pending tasks

**Storage**:
```bash
# Session-specific flag file
~/.claude/deferred-resume-{session_id}.flag

# Contents (simple JSON)
{
  "file_path": "/path/to/pending-tasks.json",
  "deferred_at": "2025-10-04T16:30:00Z",
  "prompt_count": 1
}
```

**Cleanup**: Delete flag file when:
- User selects RESUME (task addressed)
- User selects ARCHIVE (task discarded)
- Session ends normally
- Flag file >7 days old (auto-cleanup)

---

## Explicit Resume Command

### Command Formats
- `resume` (simple keyword)
- `/resume` (slash command)
- `/resume --review` (with options)

### Behavior Difference from Auto-Detection

**Auto-Detection**:
- Age-based conditional prompt (blocking vs non-blocking)
- Happens automatically at session start
- Respects DEFER flag (won't re-prompt immediately)

**Explicit Command**:
- ALWAYS shows blocking prompt (ignores age)
- User deliberately requested resume
- Bypasses DEFER flag (explicit override)
- Works even if user previously selected DEFER

### Command Options

```bash
# Basic resume (interactive prompt)
/resume

# Auto-resume without prompting (uses default RESUME option)
/resume --auto

# Review tasks before resuming
/resume --review

# Resume with specific context handling
/resume --cleanup    # Clear context first
/resume --compact    # Compress context first

# Resume specific task file (if multiple exist)
/resume --file pending-tasks-20251004-163000.json
```

---

## State Restoration Procedures

### Resume Execution Flow

```
STEP 1: Load Persisted File
├── Read JSON from {file_path}
├── Validate schema (see task_persistence.md)
├── Extract task lists (completed/pending/in-progress)
└── Parse metadata (session_id, context_usage, recommendation)

STEP 2: Display Progress Summary
├── Show completion statistics
├── List completed_verified tasks (with checkmarks)
├── List pending tasks (with assigned agents)
├── List in-progress tasks (with progress %)
└── Highlight any verification gaps

STEP 3: Handle User Choice
├── If CLEANUP selected:
│   ├── Clear conversation context
│   └── Preserve only task data + verification reports
├── If COMPACT selected:
│   ├── Compress context (remove verbose tool outputs)
│   └── Preserve task chains + key decisions
├── If REVIEW selected:
│   ├── Display detailed task breakdown
│   ├── Allow user to select specific tasks
│   └── Archive or skip unwanted tasks
└── If RESUME selected:
    └── Proceed to STEP 4

STEP 4: Re-Invoke Specialist Agents
├── Group pending tasks by agent type
├── Identify tasks with no dependencies (can start immediately)
├── Launch agents in parallel for independent tasks
├── Queue dependent tasks for sequential execution
└── For in-progress tasks: Pass partial_state to agent

STEP 5: Apply Mandatory Verification
├── After each agent completes task:
│   ├── Invoke implementation-verifier
│   ├── Verify ≥95% coverage against original spec
│   ├── Save verification report to evidence/
│   └── Mark as verified_complete or create gap-closure tasks
└── Update task status in memory

STEP 6: Update Persistence File
├── Collect new task states
├── Calculate new completion percentage
├── Check context usage
├── If still >80%: Persist again with updated state
└── If <80%: Continue with auto-monitoring

STEP 7: Archive on Completion
├── If all tasks verified_complete:
│   ├── Move file to .claude/archive/
│   ├── Append -completed suffix
│   └── Log success message
└── Delete any associated deferred-resume flags
```

---

## Conflict Resolution

### Scenario 1: Multiple Pending Files for Same Project

**Detection**: More than one pending-tasks file found for current project

**Resolution**:
1. Show list of all files with timestamps and task counts
2. Ask user which session to resume:
   ```
   ⚠️ Multiple pending task sessions found:

   [1] Oct 4, 2025 4:30 PM (6 hours ago) - 5/10 tasks complete
   [2] Oct 3, 2025 2:15 PM (1 day ago) - 3/8 tasks complete

   Which session would you like to resume? [1/2]
   Or type 'merge' to combine both sessions.
   ```
3. If user selects 'merge':
   - Combine task lists (deduplicate by task_id)
   - Use newer file's metadata
   - Mark merge conflict in new file

---

### Scenario 2: Session State Mismatch

**Detection**: File's project_path ≠ current session project_path

**Resolution**:
1. Stop immediately (critical safety check)
2. Display mismatch details:
   ```
   ❌ PROJECT MISMATCH DETECTED

   Pending tasks file: {file_project_path}
   Current session:    {session_project_path}

   This file belongs to a different project.

   Options:
   - Switch to project: {file_project_name}
   - Ignore this file and continue with current project
   ```

---

### Scenario 3: Verification Reports Missing

**Detection**: Task marked verified_complete but report file doesn't exist

**Resolution**:
1. Log warning
2. Downgrade task status to "in_progress"
3. Add to pending verification queue
4. Notify user:
   ```
   ⚠️ Verification report missing for TASK-{id}
   Task will be re-verified during resume.
   ```

---

### Scenario 4: Assigned Agent No Longer Exists

**Detection**: Task's assigned_agent not in current agent registry

**Resolution**:
1. Show agent compatibility warning
2. Suggest replacement agent:
   ```
   ⚠️ Agent 'old-agent-name' not available

   Task: {task_description}
   Original agent: old-agent-name

   Suggested replacement: new-agent-name
   Proceed with replacement? [Y/N]
   ```

---

## Error Handling

### Corrupted File Recovery

**Detection**: JSON parse error or schema validation failure

**Actions**:
1. Rename file to `.corrupted` extension
2. Look for previous valid file (next most recent)
3. If found: Offer to resume from that file
4. If not found: Notify user, recommend manual reconstruction

**User Message**:
```
⚠️ CORRUPTED TASK FILE DETECTED

File: {filename}
Error: {parse_error_message}

Action taken: Renamed to {filename}.corrupted

Found previous valid file from {date}.
Resume from this file instead? [Y/N]
```

---

### Permission Errors

**Detection**: Cannot read/write pending-tasks file

**Actions**:
1. Check file permissions
2. Attempt to fix common permission issues
3. If cannot fix: Notify user with specific error

**User Message**:
```
❌ PERMISSION ERROR

Cannot access: {file_path}
Error: {permission_error}

Suggested fix: chmod 644 {file_path}
```

---

## Testing & Validation

### Test Scenarios

1. **Fresh Resume (<24hrs)**: Create file 6 hours ago, verify blocking prompt
2. **Old Resume (>24hrs)**: Create file 2 days ago, verify non-blocking notification
3. **DEFER Mechanism**: Select DEFER, continue work, then type 'resume'
4. **Multiple Files**: Create 3 files, verify newest selected
5. **Project Mismatch**: File from different project, verify safety check
6. **Corrupted File**: Manually corrupt JSON, verify recovery mechanism
7. **Complete Resume**: Full workflow from persist → resume → complete

### Validation Checklist

- ☐ Detection runs during NEW_SESSION initialization
- ☐ Age calculation accurate (<24hrs vs >24hrs)
- ☐ Blocking prompt shows for recent files
- ☐ Non-blocking notification shows for old files
- ☐ DEFER mechanism sets flag correctly
- ☐ Explicit /resume command bypasses age logic
- ☐ Project mismatch detected and blocked
- ☐ Agents re-invoked with correct task context
- ☐ Verification applied to all resumed tasks
- ☐ File archived on successful completion

---

## Integration Points

### NEW_SESSION Initialization
**Hook Point**: After project menu selection, before user work begins
**Action**: Run detection algorithm
**Behavior**: Show appropriate prompt based on file age

### Task Manager Integration
**Hook Point**: Task manager receives restore_from_state() call
**Action**: Restore task states, rebuild task graph
**Behavior**: Preserve task dependencies, priority, assignments

### Implementation Verifier Integration
**Hook Point**: After each resumed task completes
**Action**: Verify against original specification
**Behavior**: Same verification rules as normal workflow (≥95% coverage)

---

## Maintenance

### Version History
- **v1.0 (2025-10-04)**: Initial protocol definition

### Future Enhancements
- Smart conflict resolution (auto-merge compatible tasks)
- Context compression algorithms (automated COMPACT)
- Cloud sync for pending tasks (multi-device resume)
- Machine learning for better CLEANUP/COMPACT recommendations
