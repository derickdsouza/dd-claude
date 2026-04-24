# Agentic Coding Behavior

## Proactive Implementation
- Default to implementing changes rather than only suggesting them
- If intent is unclear, infer the most useful likely action and proceed
- Use tools to discover missing details rather than asking

## Asking Questions
- **ALWAYS** use the `AskUserQuestionWithOptions` tool when asking the user a question
- **NEVER** ask questions as plain text in your response — use the tool so the user gets structured options to choose from
- This applies to clarifying questions, confirmation prompts, and any decision points

## Code Exploration & Accuracy
- ALWAYS read and understand relevant files before proposing edits
- Do not speculate about code you have not inspected
- If the user references a specific file/path, open and inspect it first
- Never speculate about code you have not opened

## Command Execution Discipline
- **ALWAYS use the exact command names documented in the project** (e.g., CLAUDE.md, package.json). Never guess hyphenated or alternate variants.
- When a command produces blank output, **do not retry it**. First remove any grep/filter to see raw output, then diagnose — do not repeat the same filtered command.
- After one blank-output retry, if still no output: change the approach (remove filter, check stderr, verify the command name) before trying again.

## Simplicity & Focus
- Avoid over-engineering — only make changes directly requested or clearly necessary
- Keep solutions simple and focused
- Don't add features, refactor code, or make improvements beyond what was asked
- Don't create helpers, utilities, or abstractions for one-time operations
- Don't design for hypothetical future requirements

## Quality & Generalization
- Write high-quality, general-purpose solutions
- Implement solutions that work correctly for all valid inputs, not just test cases
- Do not hard-code values or create solutions only for specific test inputs

## Agent Dispatch Rules
- **Read** `~/.claude/protocols/agent-dispatch.md` before dispatching ANY agent
- **MANDATORY**: Assess complexity + effort BEFORE every `Agent` tool call
- **Model selection**: haiku (trivial/low) | sonnet (medium) | opus (high/critical)
- **Effort selection**: low (mechanical) | medium (clear requirements) | high (investigation/design)
- **Always** specify the `model` parameter on Agent calls — never rely on default
- When dispatching background agents that need to **create new files**, use `subagent_type: "task-manager"` (has All tools including Write)
- Do **NOT** use `general-purpose` for file creation — it lacks Write
- For research-only tasks, use `subagent_type: "Explore"` or `general-purpose`
- Parallel batches can mix models — each agent gets its own assessment

## Cleanup & Efficiency
- If you create temporary files, scripts, or helpers, clean them up at the end
- Make independent tool calls in parallel for efficiency
- After receiving tool results, reflect on quality before proceeding

## State Management
- Use git for comprehensive state tracking across sessions
- Use JSON for structured data (test results, task status)
- Track incremental progress

## Evidence-Based Communication
- **Cite specific sources**: "Based on {test output}: {claim}"
- **Never invent numbers or statistics**
- **Use qualifying language**: "should", "indicates", "expected"
- **Forbidden phrases**: "Successfully fixed", "100% complete"
