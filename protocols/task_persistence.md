# Task Persistence Protocol

**Version**: 1.0
**Date**: 2025-10-04
**Status**: Active

---

## Purpose

This document defines the task persistence system that enables workflow state preservation when context limits are approached, allowing seamless resumption across sessions without loss of progress.

---

## Storage Architecture

### File Location Strategy

**Primary Location**: `{project-root}/.claude/pending-tasks-{timestamp}.json`

**Rationale**:
- Project-specific isolation (each project has its own pending tasks)
- Travels with project (can be version controlled if desired)
- Easy to locate during resume detection
- Supports multiple concurrent projects

**Directory Structure**:
```
project-root/
└── .claude/
    ├── pending-tasks-20251004-163000.json  (most recent)
    ├── pending-tasks-20251004-120000.json  (older)
    ├── pending-tasks-20251003-150000.json  (oldest kept)
    └── archive/
        └── pending-tasks-20251002-100000.json  (completed, archived)
```

---

## File Naming Convention

### Format
```
pending-tasks-YYYYMMDD-HHMMSS.json
```

**Components**:
- **Prefix**: `pending-tasks-` (constant)
- **Date**: `YYYYMMDD` (year, month, day)
- **Time**: `HHMMSS` (hour, minute, second in 24h format)
- **Extension**: `.json` (JSON format)

**Examples**:
- `pending-tasks-20251004-163045.json` (Oct 4, 2025 at 4:30:45 PM)
- `pending-tasks-20251231-235959.json` (Dec 31, 2025 at 11:59:59 PM)

**Sorting**: Lexicographic sort automatically orders by date/time (newest last)

---

## JSON Schema Definition

### Top-Level Structure

```json
{
  "session_id": "string",
  "project_path": "string (absolute path)",
  "project_name": "string",
  "timestamp": "string (ISO 8601 format)",
  "context_usage": "string (e.g., '162000/200000 (81%)')",
  "recommendation": "string (enum: 'cleanup' | 'compact')",
  "reasoning": "string (explanation for recommendation)",
  "completed_verified_tasks": [TaskObject],
  "pending_tasks": [TaskObject],
  "in_progress_tasks": [TaskObject]
}
```

### TaskObject Schema

```json
{
  "task_id": "string (e.g., 'TASK-001')",
  "description": "string (brief task description)",
  "assigned_agent": "string (specialist agent type)",
  "status": "string (enum: 'verified_complete' | 'not_started' | 'in_progress')",
  "dependencies": ["string (array of task IDs)"],
  "priority": "string (enum: 'low' | 'medium' | 'high' | 'critical')",
  "verification_report": "string (path to evidence file) [optional]",
  "completion_timestamp": "string (ISO 8601 format) [optional]",
  "progress_percentage": "number (0-100) [optional]",
  "partial_state": "string (description of partial completion) [optional]",
  "verification_status": "string (enum: 'pending' | 'passed' | 'failed') [optional]"
}
```

### Field Constraints

| Field | Required | Type | Validation |
|-------|----------|------|------------|
| session_id | Yes | string | Non-empty |
| project_path | Yes | string | Valid absolute path |
| project_name | Yes | string | Non-empty |
| timestamp | Yes | string | ISO 8601 format |
| context_usage | Yes | string | Format: "{used}/{total} ({percent}%)" |
| recommendation | Yes | enum | Must be "cleanup" or "compact" |
| reasoning | Yes | string | Non-empty |
| task_id | Yes | string | Unique within file |
| assigned_agent | Yes | string | Must match known agent type |
| status | Yes | enum | Must be valid status |

---

## Persistence Triggers

### Automatic Triggers

1. **Context Threshold Reached (80%)**
   - **When**: Token usage reaches 160,000 tokens
   - **Action**: Persist immediately after completing current task + verification
   - **Priority**: High

2. **User Requests Pause**
   - **When**: User selects "PAUSE" option from context threshold prompt
   - **Action**: Persist current state immediately
   - **Priority**: High

3. **Session Termination Detected**
   - **When**: Claude detects session ending (if possible)
   - **Action**: Force-save current state
   - **Priority**: Critical

### Manual Triggers

1. **Explicit /pause Command**
   - **When**: User types `/pause` or `/save-state`
   - **Action**: Persist current state
   - **Note**: Creates checkpoint even if below threshold

---

## State Serialization Process

### Step-by-Step Workflow

```
STEP 1: Collect Current State
├── Query task-manager for task list
├── Identify completed_verified tasks
├── Identify pending tasks
├── Identify in_progress tasks
└── Extract partial completion state

STEP 2: Calculate Metadata
├── Get current session_id
├── Get project_path from session state
├── Extract project_name from path
├── Generate timestamp (ISO 8601)
├── Calculate context_usage string
└── Generate cleanup/compact recommendation

STEP 3: Construct JSON Object
├── Populate top-level fields
├── Serialize completed_verified_tasks array
├── Serialize pending_tasks array
├── Serialize in_progress_tasks array
└── Validate against schema

STEP 4: Write to File
├── Ensure {project}/.claude/ directory exists
├── Generate filename with current timestamp
├── Write JSON with pretty-printing (indent=2)
└── Verify file written successfully

STEP 5: Trigger Auto-Cleanup
├── Run cleanup_pending_tasks.sh script
├── Delete files >7 days old (except 3 most recent)
└── Log cleanup actions
```

---

## Auto-Cleanup Algorithm

### Cleanup Rules

1. **Age-Based Deletion**: Delete files older than 7 days
2. **Keep Recent**: ALWAYS keep 3 most recent files (even if >7 days old)
3. **Archive Completed**: Move completed task files to `archive/` subdirectory

### Cleanup Execution Schedule

**Triggers**:
- Session initialization (when loading base instructions)
- After successful resume (when tasks completed)
- When creating new pending-tasks file (before write)

### Algorithm Pseudocode

```python
def cleanup_pending_tasks(project_path):
    pending_dir = f"{project_path}/.claude/"
    files = glob(f"{pending_dir}/pending-tasks-*.json")

    # Sort by timestamp (newest first)
    files.sort(reverse=True)

    # Always keep 3 most recent
    keep_files = files[:3]
    candidate_files = files[3:]

    # Calculate 7-day threshold
    cutoff_date = now() - timedelta(days=7)

    for file in candidate_files:
        file_date = parse_timestamp_from_filename(file)

        if file_date < cutoff_date:
            # Check if completed (all tasks verified_complete)
            if is_completed(file):
                move_to_archive(file)
            else:
                delete_file(file)

            log_cleanup(file, action="deleted" or "archived")
```

---

## Recovery Procedures

### Corrupted File Detection

**Validation Checks**:
1. File exists and readable
2. Valid JSON syntax
3. All required top-level fields present
4. Task objects conform to schema
5. No duplicate task IDs
6. Referenced verification reports exist

### Recovery Strategies

#### Scenario 1: Invalid JSON Syntax
**Detection**: JSON parse error
**Recovery**:
1. Attempt to repair common issues (trailing commas, missing quotes)
2. If repair fails, rename to `.corrupted` extension
3. Look for previous valid file
4. Notify user of corruption + recovery action

#### Scenario 2: Missing Required Fields
**Detection**: Schema validation failure
**Recovery**:
1. Attempt to infer missing fields from available data
2. If critical fields missing (e.g., task_id), mark file as unrecoverable
3. Rename to `.partial` extension
4. Notify user, ask if they want to manually reconstruct

#### Scenario 3: Orphaned Verification Reports
**Detection**: `verification_report` path doesn't exist
**Recovery**:
1. Log warning about missing evidence
2. Continue with resume (non-critical)
3. Note in console: "⚠️ Verification report missing for task {id}"

#### Scenario 4: Conflicting Task States
**Detection**: Task marked "verified_complete" but verification_status = "pending"
**Recovery**:
1. Treat verification_status as source of truth
2. Downgrade status to "in_progress"
3. Log inconsistency for debugging

---

## File Format Examples

### Minimal Valid File

```json
{
  "session_id": "session-12345",
  "project_path": "/Users/user/Projects/my-project",
  "project_name": "my-project",
  "timestamp": "2025-10-04T16:30:00Z",
  "context_usage": "162000/200000 (81%)",
  "recommendation": "compact",
  "reasoning": "Active multi-step refactoring with cross-references",
  "completed_verified_tasks": [],
  "pending_tasks": [
    {
      "task_id": "TASK-001",
      "description": "Implement user authentication",
      "assigned_agent": "auth-builder",
      "status": "not_started",
      "dependencies": [],
      "priority": "high"
    }
  ],
  "in_progress_tasks": []
}
```

### Complete Example with All Fields

```json
{
  "session_id": "session-67890",
  "project_path": "/Users/user/Projects/trading-platform",
  "project_name": "trading-platform",
  "timestamp": "2025-10-04T18:45:30Z",
  "context_usage": "165000/200000 (82.5%)",
  "recommendation": "compact",
  "reasoning": "Debugging session requires access to error traces from earlier analysis",
  "completed_verified_tasks": [
    {
      "task_id": "TASK-001",
      "description": "Create database schema for users",
      "assigned_agent": "database-builder",
      "status": "verified_complete",
      "dependencies": [],
      "priority": "high",
      "verification_report": "evidence/task-001-verification.md",
      "completion_timestamp": "2025-10-04T18:20:00Z"
    },
    {
      "task_id": "TASK-002",
      "description": "Implement user registration endpoint",
      "assigned_agent": "api-builder",
      "status": "verified_complete",
      "dependencies": ["TASK-001"],
      "priority": "high",
      "verification_report": "evidence/task-002-verification.md",
      "completion_timestamp": "2025-10-04T18:40:00Z"
    }
  ],
  "pending_tasks": [
    {
      "task_id": "TASK-004",
      "description": "Create login UI component",
      "assigned_agent": "ui-component-specialist",
      "status": "not_started",
      "dependencies": ["TASK-003"],
      "priority": "medium"
    },
    {
      "task_id": "TASK-005",
      "description": "Implement JWT token refresh mechanism",
      "assigned_agent": "auth-builder",
      "status": "not_started",
      "dependencies": ["TASK-003"],
      "priority": "low"
    }
  ],
  "in_progress_tasks": [
    {
      "task_id": "TASK-003",
      "description": "Implement authentication middleware",
      "assigned_agent": "middleware-builder",
      "status": "in_progress",
      "dependencies": ["TASK-002"],
      "priority": "high",
      "progress_percentage": 65,
      "partial_state": "JWT validation implemented, refresh logic pending",
      "verification_status": "pending"
    }
  ]
}
```

---

## Integration with Task Manager

### Task Manager Responsibilities

1. **Track Task States**: Maintain authoritative task state
2. **Provide Serialization API**: Expose method to get current state
3. **Support State Restoration**: Accept deserialized state and restore

### API Contract

```python
# Task Manager exposes:
def get_serializable_state() -> dict:
    """Returns dict conforming to persistence schema"""

def restore_from_state(state: dict) -> None:
    """Restores task manager state from persisted data"""

def validate_state_consistency() -> list[str]:
    """Returns list of validation warnings/errors"""
```

---

## Testing & Validation

### Test Scenarios

1. **Normal Persistence**: Reach 80% threshold, verify file created correctly
2. **Partial Completion**: Save with mix of completed/pending/in-progress tasks
3. **Cleanup Execution**: Create 10 files, verify only 3 most recent kept
4. **Corruption Recovery**: Manually corrupt file, verify recovery mechanism
5. **Resume After Persistence**: Persist → Resume → Verify all tasks restored

### Validation Checklist

- ☐ Files created with correct naming convention
- ☐ JSON schema validation passes
- ☐ All task states preserved accurately
- ☐ Verification reports linked correctly
- ☐ Auto-cleanup runs on schedule
- ☐ 3 most recent files always kept (even if >7 days)
- ☐ Corrupted files handled gracefully
- ☐ Archive directory created when needed

---

## Maintenance

### Version History
- **v1.0 (2025-10-04)**: Initial protocol definition

### Future Enhancements
- Compression for large task lists
- Encryption for sensitive project data
- Cloud sync integration
- Conflict resolution for concurrent sessions
