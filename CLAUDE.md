# Global Instructions for Claude AI Assistant

## CRITICAL SAFETY PROTOCOLS

**Mandatory protocols** — violations cause data loss, workflow disruption, broken commits.  
**Protocol Files**: `~/.claude/protocols/`

---

## Protocol Reference

| Protocol | File | Trigger Words |
|----------|------|---------------|
| **Git Safety** | [git-safety.md](~/.claude/protocols/git-safety.md) | commit, push, git add, stage changes |
| **Process Safety** | [process-safety.md](~/.claude/protocols/process-safety.md) | kill, stop, terminate, process |
| **Container Runtime** | [container-runtime.md](~/.claude/protocols/container-runtime.md) | docker, container, podman |
| **Package Manager** | [package-manager.md](~/.claude/protocols/package-manager.md) | npm, pnpm, install, add package |
| **Code Quality** | [code-quality.md](~/.claude/protocols/code-quality.md) | lint, eslint, imports, types |
| **Task Management** | [task-management.md](~/.claude/protocols/task-management.md) | task, issue, implement, fix, feature |
| **Agent Dispatch** | [agent-dispatch.md](~/.claude/protocols/agent-dispatch.md) | agent, subagent, parallel, background, dispatch |
| **Agentic Behavior** | [agentic-behavior.md](~/.claude/protocols/agentic-behavior.md) | how to ask, command discipline, simplicity |
| **Code Exploration** | [code-exploration.md](~/.claude/protocols/code-exploration.md) | jCodemunch, search_symbols, explore code |
| **Context Management** | [context-management.md](~/.claude/protocols/context-management.md) | compact, context window, token limit, resume |
| **Session Startup** | [session-startup.md](~/.claude/protocols/session-startup.md) | session start, cleanup, stale resources |

---

## Quick Safety Rules

### Git Operations
- **Pipeline mode**: Use the beadswave conveyor belt (`pipeline-driver.sh`) for all ship operations. Never manually push + PR + merge.
- **Worktrees**: Use `git worktree` for isolated bead development. Each bead gets its own worktree.
- **NEVER**: `git push origin main` (blocked by pre-push hook)
- **Limit**: ≤5 files, ≤300 lines per commit · code files ≤275 lines (refactor if exceeded)
- **Read-only git** (`git log`, `git blame`, `git show --stat`) is allowed
- **After deploy + smoke tests pass**: merge via the conveyor belt (bd-ship handles direct merge)

### Process Management
- **NEVER**: `pkill`, `killall`, broad patterns
- **ALWAYS**: Port-based (`lsof -ti:PORT`) or PID-based identification

### Package Manager
- **USE**: `bun` for everything · **NEVER**: `npm`, `pnpm`

### Container Runtime
- **USE**: `podman` for everything · **NEVER**: `docker`

### Issue Tracking (Beads / `bd` CLI)
- **USE**: `bd` (beads) for all issue tracking · **NEVER**: TodoWrite, TaskCreate, markdown TODO files
- Full command reference: `~/.claude/protocols/task-management.md`

### Security
- Never expose secrets or API keys in code, logs, or outputs
- Follow OWASP guidelines for web applications

### Dolt Database Safety
- Use port from `.beads/dolt/config.yaml` — never default port (3307)
- Never kill or restart another project's Dolt server

---

## Development Workflow

For every new feature — prefer skills over improvising:

0. **`brainstorming`** → diverge (generate 10+ ideas) → converge (keep top 5, adversarially filtered)
1. **`write-a-prd`** → create PRD with user
2. **`prd-to-issues`** → break into vertical-slice beads issues
3. **`tdd`** → implement each issue one test at a time
4. Validate with passing tests before moving to the next issue

---

## Agent Delegation

Coordinate using specialized agents. Do not solve everything in one response.

| Role | When to Use | Skills |
|------|-------------|--------|
| **planner** | new features, requirements | `write-a-prd`, `prd-to-issues` |
| **plan-reviewer** | validate PRD/issues before build | — |
| **builder** | implementation | `tdd` |
| **tester** | validation, edge cases | — |
| **reviewer** | code quality, architecture | `superpowers:requesting-code-review` — 5 lenses: correctness · testing · security · performance · maintainability |
| **triage** | debugging | `triage-issue` |
| **cicd** | build/deploy validation | — |

Full agent briefs: `~/.claude/agents/`

**Delegation rules:**
- If unsure → delegate to planner
- If implementing → delegate to builder (with `tdd` skill)
- If validating → delegate to tester
- If improving → delegate to reviewer
- If debugging → delegate to triage
- If pipeline-related → delegate to cicd
- Independent tasks → run agents in parallel

---

## TDD Rules

- Always write the failing test first
- One test at a time — never write all tests upfront (horizontal slicing)
- Minimal implementation only — only enough code to pass the current test
- Refactor only after all tests pass (never while RED)
- Test behavior through public interfaces, not implementation details
- No speculative features during the RED→GREEN cycle

See `~/.claude/skills/tdd/` for full skill.

---

## Quality Bar

A feature is complete only when:
- All tests pass
- Edge cases covered (tester validated)
- Code reviewed (reviewer validated)
- Build passes

## Response Discipline

Behavioral guardrails to prevent drift, thrash, and incomplete work:

- **Re-read the user's last message before responding.** Follow through on every instruction completely.
- **Read the full file before editing.** Plan all changes, then make ONE complete edit. If you've edited a file 3+ times, stop and re-read the user's requirements.
- **Double-check your output before presenting it.** Verify that your changes actually address what the user asked for.
- **After 2 consecutive tool failures, stop and change your approach entirely.** Explain what failed and try a different strategy.
- **When the user corrects you, stop and re-read their message.** Quote back what they asked for and confirm before proceeding.
- **Act sooner.** Don't read more than 3–5 files before making a change. Get a basic understanding, make the change, then iterate.
- **Every few turns, re-read the original request** to make sure you haven't drifted from the goal.
- **When stuck, summarize what you've tried and ask the user for guidance** instead of retrying the same approach.
- **When unsure or facing material ambiguity, ask via the `AskUserQuestion` tool.** Present 2–4 concrete options (with a recommended choice where you have one) rather than freeform prose — it's easier for the user to pick than to compose. Use this when the answer would change your approach (which feature to build, which file to edit, which tradeoff to make). Do NOT use it for trivial decisions (variable naming, formatting) — those fall under the autonomy rule below.
- **Work more autonomously.** Make reasonable decisions without asking for confirmation on every step.

---

## Anti-Patterns

- Jumping to requirements/code before diverge-then-converge ideation
- Letting the model make silent design decisions during build (scope drift)
- Writing code without a failing test
- Skipping PRD or issue breakdown
- Mixing planning and execution roles in one response
- Writing all tests upfront before any implementation
- Implementing unrelated improvements while fixing a bug
- Unused abstractions or speculative features

---

## Auto Memory Updates

After completing any feature or bug fix, update `~/.claude/memory/`:

| Trigger | File |
|---------|------|
| Debugging root cause | `~/.claude/memory/debugging.md` |
| Implementation pattern | `~/.claude/memory/patterns.md` |
| Architecture decision | `~/.claude/memory/architecture.md` |
| Cross-cutting critical lesson | `~/.claude/memory/MEMORY.md` |

**Format:** `- [YYYY-MM-DD] <category>: <insight>`  
**Rules:** 1–2 lines per entry · no duplicates · generalize over specifics · keep MEMORY.md under 200 lines.

For project-level reusable decisions, also save to `docs/decisions/<topic>.md` with: problem · root cause · solution · applies-when · avoid-when · affected systems.

---

## Claude Code Settings Pitfall

When Claude Code reports this settings validation error in `~/.claude/settings.json`:

```text
Settings Error

  ~/.claude/settings.json
    statusLine
      type: Invalid value. Expected one of: "command"
```

- **Cause:** the `statusLine` object shape is wrong. Claude Code expects `{"type":"command","command":"..."}`. If the script field is saved as `value` instead of `command`, validation can surface as a misleading `statusLine.type` error.
- **Fix:** rename `statusLine.value` to `statusLine.command` and keep `type` set to `"command"`.
- **Known-good example:**

```json
"statusLine": {
  "type": "command",
  "command": "bash ~/.claude/statusline-command.sh"
}
```

- **Verify:** run `jq '.statusLine' ~/.claude/settings.json` and confirm the object contains `type` and `command`.

---

## References

- **Troubleshooting / API fixes**: `~/.claude/troubleshooting.md`
- **New project template**: `~/.claude/templates/project-agent-md.md`
- **SSOT docs management**: `~/.claude/commands/ssot.md`


## Code Exploration Policy

See `~/.claude/protocols/code-exploration.md` for the full jCodemunch tool usage guide and session-aware routing rules.

**Start any session:** `resolve_repo { "path": "." }` → confirm indexed. Then use `plan_turn` as the opening move for any task.

@RTK.md
