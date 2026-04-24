# Global Instructions for Claude AI Assistant

## CRITICAL SAFETY PROTOCOLS

This file contains **MANDATORY** safety protocols that MUST be followed for all operations. Violations can cause data loss, workflow disruption, and broken commits.

**Protocol Files Location**: `~/.claude/protocols/`

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

---

## Quick Safety Rules

### Git Operations
- **Read**: `~/.claude/protocols/git-safety.md` before ANY git command
- **Limit**: <=5 files, <=300 lines per commit
- **Code files**: <=275 lines (refactor if exceeded)
- **Pre-commit**: Required for all commits

### Process Management
- **NEVER**: `pkill`, `killall`, broad patterns
- **ALWAYS**: Port-based (`lsof -ti:PORT`) or PID-based identification
- **VERIFY**: Before killing any process

### Package Manager
- **USE**: `bun` for everything
- **NEVER**: `npm`, `pnpm`

### Container Runtime
- **USE**: `podman` for everything
- **NEVER**: `docker`

---

## Context Window Management

Your context window will be automatically compacted as it approaches its limit. Never stop tasks early due to token budget concerns. Always complete tasks fully.

---

## Agentic Coding Behavior

### Proactive Implementation
- Default to implementing changes rather than only suggesting them
- If intent is unclear, infer the most useful likely action and proceed
- Use tools to discover missing details rather than asking

### Code Exploration & Accuracy
- ALWAYS read and understand relevant files before proposing edits
- Do not speculate about code you have not inspected
- If the user references a specific file/path, open and inspect it first
- Never speculate about code you have not opened

### Simplicity & Focus
- Avoid over-engineering - only make changes directly requested or clearly necessary
- Keep solutions simple and focused
- Don't add features, refactor code, or make improvements beyond what was asked
- Don't create helpers, utilities, or abstractions for one-time operations
- Don't design for hypothetical future requirements

### Quality & Generalization
- Write high-quality, general-purpose solutions
- Implement solutions that work correctly for all valid inputs, not just test cases
- Do not hard-code values or create solutions only for specific test inputs

### Cleanup & Efficiency
- If you create temporary files, scripts, or helpers, clean them up at the end
- Make independent tool calls in parallel for efficiency
- After receiving tool results, reflect on quality before proceeding

### State Management
- Use git for comprehensive state tracking across sessions
- Use JSON for structured data (test results, task status)
- Track incremental progress

---

## Security Standards

### Core Principles
- Always maintain security-first approach
- Never expose secrets or API keys in code, logs, or outputs
- Implement proper authentication patterns for all services
- Use encryption for sensitive data storage
- Follow OWASP security guidelines for web applications

---

## Project Reference Guidelines

Each project should create its own `AGENT.md` file that:

1. **References universal guidelines** with a critical reference box at the top
2. **Contains project-specific information only:**
   - Technology stack details
   - Project structure and naming conventions
   - Development setup instructions
   - Project-specific workflows
   - Project-specific troubleshooting

3. **Avoids duplicating universal content**

### Project-Specific AGENT.md Template

```markdown
# Project Name - AI Agent Guidelines

## CRITICAL: Universal Guidelines Reference

> ALL agents MUST read and follow the Universal AI Agent Guidelines FIRST:
>
> Location: `~/.claude/CLAUDE.md`
> Protocols: `~/.claude/protocols/`
>
> This document covers:
> - File size limits (275 lines max for code files)
> - Git commit safety protocols
> - Process management safety rules
> - Container runtime (Podman)
> - Package manager (Bun only)
> - Security standards

## Project-Specific Content

[Insert project-specific information here]
```

---

## Common Tasks

### Starting a New Project

1. **Read these guidelines** (you're doing it!)
2. **Understand critical requirements** (read protocol files)
3. **Create a project-specific `AGENT.md`** with reference to universal guidelines

### SSOT Documentation Management

**MANDATORY**: Use the Global SSOT Commands for all documentation operations:
- **Location**: `~/.claude/commands/ssot.md` and related `ssot-*.md` files
- **Commands**: `/ssot init`, `/ssot migrate`, `/ssot validate`, `/ssot query`, `/ssot generate`, `/ssot enhance`, `/ssot sync`, `/ssot status`, `/ssot coverage`
- **Workflow**: Always work with canonical specs in `spec/` directory, generate docs from specs

### Context Overflow Prevention

1. **Monitor token usage**: 60% (warn), 80% (action), 95% (critical)
2. **At 80% threshold**: Choose from CLEANUP, COMPACT, REVIEW, or PAUSE
3. **Work is automatically persisted** to JSON files

### Session Resumption

1. **Use `/resume` command** or wait for automatic detection
2. **Choose restoration option**: RESUME, DEFER, REVIEW, CLEANUP, COMPACT, or ARCHIVE
3. **Previous work is restored** and session continues

---

## Quick Reference

### File Size Limits
- **Code files** (`.cs`, `.ts`, `.py`, etc.): **Maximum 275 lines**
- **Markdown**, JSON, configuration: No limit
- **Exceeding 275 lines**: CRITICAL FAILURE - must refactor first

### Evidence-Based Communication
- **Cite specific sources**: "Based on {test output}: {claim}"
- **Never invent numbers or statistics**
- **Use qualifying language**: "should", "indicates", "expected"
- **Forbidden phrases**: "Successfully fixed", "100% complete"

### Context Thresholds
- **60%**: Warning (continue, log only)
- **80%**: Action (pause, persist, show options)
- **95%**: Critical (emergency halt)

---

## Troubleshooting

### Common Issues

**Pre-commit hooks failing?**
- Run hooks manually: `bun run lint:fix`
- Address all errors before proceeding

**Context overflow happening?**
- Monitor token usage percentage
- At 80%: Choose CLEANUP, COMPACT, REVIEW, or PAUSE

**Git commit blocked by protocol?**
- This is intentional - safety first
- Read `~/.claude/protocols/git-safety.md` completely
- Follow all steps - no shortcuts

**Process termination not working?**
- Use port-based identification: `kill $(lsof -ti:PORT)`
- Verify with `ps -p $PID` before killing
- Never use `pkill` or broad commands

### Getting More Details

- **Git workflow**: See `~/.claude/protocols/git-safety.md`
- **Process safety**: See `~/.claude/protocols/process-safety.md`
- **Container runtime**: See `~/.claude/protocols/container-runtime.md`
- **Package manager**: See `~/.claude/protocols/package-manager.md`
- **Code quality**: See `~/.claude/protocols/code-quality.md`
- **Task management**: See `~/.claude/protocols/task-management.md`
- **SSOT documentation**: See `~/.claude/commands/ssot.md`

---

*Last updated: December 4, 2025*
