# Context Monitoring Protocol

**Version**: 1.0
**Date**: 2025-10-04
**Status**: Active

---

## Purpose

This document defines the comprehensive context monitoring system that ensures Claude Code workflows never exceed token limits, automatically pause at thresholds, and persist state for seamless resumption.

---

## Token Counting Methodology

### Current Context Calculation

**Formula**:
```
current_tokens = input_tokens + output_tokens + system_tokens
```

**Components**:
- **input_tokens**: All user messages + tool results + system messages
- **output_tokens**: All Claude responses + tool calls
- **system_tokens**: Base instructions + CLAUDE.md + protocol documents

**Measurement Approach**:
- Claude provides token counts via system warnings: `<system_warning>Token usage: X/200000; Y remaining</system_warning>`
- Monitor these warnings after every response
- Extract `X` value as current usage
- Calculate percentage: `(X / 200000) * 100`

---

## Threshold Definitions

### Three-Tier Warning System

| Threshold | Token Count | Percentage | Severity | Action |
|-----------|-------------|------------|----------|--------|
| **WARNING** | 120,000 | 60% | ⚠️ Low | Log only, continue |
| **ACTION** | 160,000 | 80% | 🛑 Medium | Pause workflow, persist state |
| **CRITICAL** | 190,000 | 95% | 🚨 High | Emergency halt |

### Threshold Behaviors

#### WARNING (60% - 120K tokens)
**Trigger**: Token usage reaches 120,000 tokens

**Actions**:
1. Log internal warning: "⚠️ Context usage at 60% - monitoring closely"
2. Continue normal workflow execution
3. Increase monitoring frequency (check after EVERY tool call)
4. No user notification required

**Purpose**: Early awareness for internal planning

---

#### ACTION (80% - 160K tokens)
**Trigger**: Token usage reaches 160,000 tokens

**Actions**:
1. **STOP** current workflow immediately after completing in-progress task
2. Run mandatory verification on current task
3. Persist all state using `persist_tasks.py` script
4. Analyze workflow context and generate CLEANUP/COMPACT recommendation
5. Present user with structured options (see User Prompt Template below)
6. Wait for explicit user choice before proceeding

**Purpose**: Proactive state preservation before hitting limits

---

#### CRITICAL (95% - 190K tokens)
**Trigger**: Token usage reaches 190,000 tokens

**Actions**:
1. **EMERGENCY HALT** - Stop all workflow execution
2. Force-save current state (even if incomplete)
3. Display critical warning to user
4. Recommend immediate session restart with `/resume`

**Purpose**: Last-resort safety mechanism

---

## Cleanup vs Compact Decision Heuristics

### Decision Tree

```
INPUT: workflow_type, task_dependencies, verification_gaps, code_references

if (debugging OR refactoring OR complex_analysis):
    recommendation = "COMPACT"
    reasoning = "Multi-step analysis requires historical context"
elif (verification_gaps > 0):
    recommendation = "COMPACT"
    reasoning = "Pending verification requires access to original specs"
elif (cross_references > 5):
    recommendation = "COMPACT"
    reasoning = "Multiple cross-references to earlier discussion needed"
elif (task_dependencies == "sequential"):
    recommendation = "COMPACT"
    reasoning = "Sequential tasks benefit from context chain"
elif (all_tasks_verified_complete):
    recommendation = "CLEANUP"
    reasoning = "All tasks verified, fresh context optimal"
elif (tasks_are_independent):
    recommendation = "CLEANUP"
    reasoning = "Independent tasks don't require historical context"
else:
    recommendation = "COMPACT"
    reasoning = "Default to safer option when uncertain"
```

### Heuristic Criteria

**COMPACT Indicators**:
- Debugging sessions (need error traces from earlier)
- Refactoring projects (need to reference original code structure)
- Complex analysis (multi-step reasoning chains)
- Verification gaps (need original specifications)
- Cross-references (>5 references to earlier messages)
- Sequential task dependencies (Task B depends on Task A output)

**CLEANUP Indicators**:
- Simple task lists (no interdependencies)
- All tasks verified complete (no pending verification)
- Independent tasks (can execute in any order)
- Fresh feature development (no historical context needed)

### Recommendation Confidence Levels

| Confidence | Criteria | Action |
|------------|----------|--------|
| **High** | >3 heuristics match | Present recommendation strongly |
| **Medium** | 1-2 heuristics match | Present as suggestion with alternatives |
| **Low** | No clear match | Default to COMPACT, explain uncertainty |

---

## User Prompt Templates

### ACTION Threshold Prompt (80%)

```
🛑 CONTEXT THRESHOLD REACHED (80% - 160K tokens used)

Current Status: {completed_verified_count} tasks completed (verified), {pending_count} tasks pending
Recommendation: {CLEANUP|COMPACT} (Confidence: {High|Medium|Low})
Reasoning: {specific heuristic explanation}

Persisted to: {project}/.claude/pending-tasks-{timestamp}.json

Context Analysis:
- Completed & Verified: {list of task IDs}
- Pending: {list of task IDs}
- In Progress: {list of task IDs with % completion}
- Cross-references: {count}
- Verification gaps: {count}

Options:
1. CLEANUP - Clear context, resume immediately with fresh state
   → Best for: Independent tasks, all verified complete
   → Risk: Loses historical discussion (if needed later)

2. COMPACT - Compress context, resume with essential history
   → Best for: Debugging, refactoring, complex analysis
   → Risk: Still uses tokens, may hit limit again sooner

3. REVIEW - Show full task list, let me choose what to resume
   → Best for: Want to see details before deciding

4. PAUSE - Stop here, I'll resume later via /resume command
   → Best for: Need to step away, will return later

Your choice? [1/2/3/4]
```

### CRITICAL Threshold Prompt (95%)

```
🚨 CRITICAL CONTEXT LIMIT (95% - 190K tokens)

EMERGENCY STATE SAVE IN PROGRESS...

This session is approaching maximum token capacity.
State has been force-saved to: {project}/.claude/pending-tasks-{timestamp}.json

REQUIRED ACTION:
Please start a new session and type '/resume' to continue from this point.

Unsaved work: {count} tasks in progress
Risk: Potential data loss if not resumed promptly

Press Enter to acknowledge and end this session.
```

---

## Monitoring Frequency

### Standard Monitoring
**Frequency**: After every agent response
**Method**: Check `<system_warning>` tags in system output
**Parse**: Extract token count from warning message

### Enhanced Monitoring (After WARNING threshold)
**Frequency**: After EVERY tool call (not just agent responses)
**Method**: Same as above
**Purpose**: Catch rapid token growth during tool-heavy operations

---

## Error Handling

### Edge Cases

#### No Token Warning Available
**Fallback**: Use message count heuristic
- Estimate: ~500 tokens per message exchange
- Formula: `estimated_tokens = message_count * 500`
- Trigger ACTION at 320 messages

#### Token Count Decreases (Impossible)
**Action**: Log anomaly, use previous known value
**Reason**: Possible parsing error in warning extraction

#### State Persistence Fails
**Action**: Retry once, then warn user
**User Message**: "⚠️ Unable to persist state - recommend manual checkpoint"

---

## Integration Points

### Task Manager Integration
**Hook Point**: After every task completion
**Action**: Check context usage before marking task complete
**Behavior**: If ACTION threshold reached, pause before next task

### Agent Invocation Integration
**Hook Point**: Before launching new agent
**Action**: Check if ACTION threshold will likely be exceeded
**Behavior**: If <10K tokens remaining, trigger pause instead

### Verification Integration
**Hook Point**: Before running implementation-verifier
**Action**: Ensure enough tokens for verification report
**Behavior**: If <5K tokens remaining, force-save and pause

---

## Testing & Validation

### Test Scenarios

1. **Gradual Growth**: Simulate 100+ task workflow reaching 80%
2. **Rapid Growth**: Large tool outputs pushing past WARNING quickly
3. **Edge Case**: Hitting CRITICAL during verification run
4. **Recovery**: Ensure `/resume` works after ACTION pause

### Validation Checklist

- ☐ WARNING logged correctly at 60%
- ☐ ACTION triggered reliably at 80%
- ☐ CRITICAL halts execution at 95%
- ☐ State persisted before each threshold action
- ☐ CLEANUP/COMPACT recommendations match heuristics
- ☐ User prompts display all required information
- ☐ Fallback mechanisms work when token counts unavailable

---

## Maintenance

### Version History
- **v1.0 (2025-10-04)**: Initial protocol definition

### Future Enhancements
- Dynamic threshold adjustment based on workflow type
- Predictive token growth modeling
- Automated compression algorithms for context compaction
