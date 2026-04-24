# Claude AI Agent Ecosystem

Specialized AI agents organized by function. All task tracking uses **beads** (`bd` CLI).

## Structure

```
agents/
├── analyzers/          # (empty - using plugins for code review)
├── builders/           # Code generation and construction
├── roles/              # Specialized development roles
├── security/           # (empty - using plugins for security guidance)
├── utils/              # Utility operations and support
├── gsd-*               # GSD agents (pending conversion to beads skills)
└── task-manager.md     # Beads-based task management (canonical)
```

## Agents

### Task Management
- **task-manager**: Beads-based issue tracking and task lifecycle (`bd` CLI)

### Builders (`builders/`)
- **config-builder**: Configuration file generation and management

### Roles (`roles/`)
- **debugger**: Advanced debugging and troubleshooting
- **documentation-specialist**: Technical documentation creation and maintenance
- **spec-decomposer**: Requirements analysis and specification breakdown
- **test-automation-specialist**: Test framework architecture and automation strategy

### Utils (`utils/`)
- **bash-executor**: Command execution and system operations
- **file-operations**: File system management and operations
- **git-operations**: Git workflow and repository management

### GSD Agents (pending conversion to beads-compatible skills)
- **gsd-codebase-mapper**, **gsd-debugger**, **gsd-verifier**, **gsd-integration-checker**, **gsd-plan-checker**, **gsd-planner**, **gsd-phase-researcher**, **gsd-project-researcher**, **gsd-research-synthesizer**, **gsd-roadmapper**, **gsd-executor**

## Plugins (managed via installed_plugins.json)

Code review, security guidance, and frontend design are handled by plugins, not local agents.

## Rules

- **Task tracking**: Always use beads (`bd` CLI) — never TodoWrite, TaskCreate, or markdown files
- **Max file size**: 275 lines per code file
- **Git commits**: Max 5 files, max 300 lines per commit
