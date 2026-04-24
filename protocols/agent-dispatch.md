# Agent Dispatch Protocol — Model & Effort Selection

## MANDATORY: Before dispatching ANY agent or subagent

Assess the task along two dimensions — **complexity** and **effort** — then select the appropriate model and configuration. This applies to every `Agent` tool call.

---

## Step 1: Classify Task Complexity

| Complexity | Indicators | Model |
|------------|-----------|-------|
| **Trivial** | Single file lookup, grep, rename, typo fix, config toggle, simple formatting | `haiku` |
| **Low** | Simple test fix, add mock, update import, small refactor within 1-2 files, known pattern replication | `haiku` |
| **Medium** | Feature implementation with clear patterns, writing tests, multi-file refactor with known scope, bug fix with identified root cause, documentation | `sonnet` |
| **High** | Architecture design, complex multi-file refactor, debugging subtle/intermittent issues, security review, performance optimization, unfamiliar domain | `opus` |
| **Critical** | Cross-cutting system changes, data migration logic, concurrency/race conditions, novel algorithm design | `opus` |

### Quick Decision Tree

```
Is it a search/lookup/grep?           → haiku
Is the change < 20 lines in 1-2 files? → haiku
Is the pattern already established?    → sonnet
Does it require design decisions?      → opus
Am I unsure about the approach?        → opus
```

## Step 2: Assess Effort Level

The effort level controls thinking depth. Set it via the agent prompt or configuration.

| Effort | When to Use | Thinking Behavior |
|--------|------------|-------------------|
| **low** | Trivial/mechanical tasks, lookups, file operations, simple edits | Minimal reasoning, fast execution |
| **medium** | Standard implementation, clear requirements, established patterns | Moderate reasoning, balanced speed |
| **high** | Complex logic, architecture decisions, debugging, security-sensitive code, ambiguous requirements | Deep reasoning, thorough analysis |

### Effort Heuristics

- **low**: "Just do X" — the what and how are both obvious
- **medium**: "Implement X" — the what is clear, the how requires some thought
- **high**: "Figure out X" — either the what or the how (or both) require investigation

## Step 3: Dispatch with Model Override

Always specify the `model` parameter on Agent calls:

```
Agent(
  model: "haiku",    # or "sonnet" or "opus"
  prompt: "...",
  subagent_type: "...",
)
```

## GitButler Cleanup (MANDATORY)

Every agent that may create GitButler branches or worktrees MUST have cleanup instructions appended to its prompt. Append this block:

```
## CLEANUP (mandatory before exiting)
After your work completes — success or failure:
1. If you created a GitButler branch, delete it: `but branch delete <name>`
2. If you created a worktree, remove it: `git worktree remove --force <path>`
3. Remove stale lock: `rm -f .git/index.lock`
Report what you created and cleaned up.
```

Full protocol: `~/.claude/protocols/gitbutler-cleanup.md`

---

## Parallel Dispatch Guidelines

When launching multiple agents in parallel:
- Each agent gets its OWN complexity/effort assessment
- A batch can mix models (e.g., 2 haiku search agents + 1 sonnet implementation agent)
- Never over-provision: don't use opus for tasks that sonnet handles fine

## Examples

| Task | Model | Effort | Rationale |
|------|-------|--------|-----------|
| "Find all files importing X" | haiku | low | Pure search |
| "Add a missing mock to test file" | haiku | low | Mechanical, pattern clear |
| "Fix the TS error in this test" | haiku | medium | Known scope, may need type reasoning |
| "Write unit tests for service X" | sonnet | medium | Established test patterns exist |
| "Implement feature Y following existing patterns" | sonnet | medium | Clear what, how needs thought |
| "Refactor module Z into smaller files" | sonnet | high | Multi-file, needs design judgment |
| "Debug why tests pass locally but fail in CI" | opus | high | Subtle, investigation needed |
| "Design the caching layer for service A" | opus | high | Architecture decision |
| "Review PR for security vulnerabilities" | opus | high | Security-critical analysis |

## Overrides

- When the user explicitly requests a model, use that model regardless of assessment
- When unsure between two levels, pick the higher one — under-provisioning wastes more time than over-provisioning
- For the main conversation thread (not agents), follow the user's global model setting
