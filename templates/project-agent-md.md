# New Project Setup Guide

## Starting a New Project

1. **Read global guidelines**: `~/.claude/CLAUDE.md`
2. **Understand critical protocols**: `~/.claude/protocols/`
3. **Create a project-specific `CLAUDE.md`** using the template below

---

## Project-Specific CLAUDE.md Template

Reference universal guidelines — do not duplicate them.

```markdown
# Project Name — AI Agent Guidelines

## CRITICAL: Universal Guidelines Reference

> ALL agents MUST read and follow the Universal AI Agent Guidelines FIRST:
>
> Location: `~/.claude/CLAUDE.md`
> Protocols: `~/.claude/protocols/`
>
> Covers: file size limits (275 lines), git safety (gitbutler skill),
> process safety, container runtime (Podman), package manager (Bun only),
> security standards, TDD rules, agent delegation, code exploration.

## Tech Stack

[Language, runtime, framework, database, queue, frontend]

## Project Structure

[Directory layout, naming conventions]

## Architecture Principles

[Key decisions, constraints — link to docs/adr/ for full ADRs]

## Local Development

[Container setup, ports, how to start services]

## Development Commands

| Intent | Command |
|--------|---------|
| Run tests | `bun test` |
| Lint | `bun run lint` |
| Build | `bun run build` |
| Start dev | `bun run dev` |

## Code Conventions

- Code files: max 275 lines
- [Project-specific naming, patterns]

## Reliability Guardrails

[Project-specific command gotchas, known failure patterns]
```

---

## Rules

- **References universal guidelines** at the top — never duplicate protocol content
- **Project-specific only** — tech stack, structure, local dev, commands, conventions
- **Link to protocols** instead of copying rules inline
