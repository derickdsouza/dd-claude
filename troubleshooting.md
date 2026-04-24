# Troubleshooting

## Claude Code API Error Fix

If you encounter `API Error: 400 "Invalid signature in thinking block"`:

1. **Add disable flag to settings** (one-time):
   ```bash
   jq '.env.CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS = "1"' ~/.claude/settings.json > /tmp/settings.json && mv /tmp/settings.json ~/.claude/settings.json
   ```

2. **Clear the corrupted session**: `/clear`

3. **Restart Claude Code** (close and reopen terminal/app)

The error occurs when experimental beta features send invalid fields to the API. The setting prevents this, but you must clear the current session because the corruption is already in the conversation history.

---

## Common Issues

**Pre-commit hooks failing?**
- Run hooks manually: `bun run lint:fix`
- Address all errors before proceeding

**Context overflow happening?**
- See `~/.claude/protocols/context-management.md` for thresholds and options

**Git commit blocked by protocol?**
- This is intentional — safety first
- Read `~/.claude/protocols/git-safety.md` completely
- Follow all steps — no shortcuts

**Process termination not working?**
- Use port-based identification: `kill $(lsof -ti:PORT)`
- Verify with `ps -p $PID` before killing
- Never use `pkill` or broad commands

---

## Reference Index

- **Git workflow**: `~/.claude/protocols/git-safety.md`
- **Process safety**: `~/.claude/protocols/process-safety.md`
- **Container runtime**: `~/.claude/protocols/container-runtime.md`
- **Package manager**: `~/.claude/protocols/package-manager.md`
- **Code quality**: `~/.claude/protocols/code-quality.md`
- **Task management**: `~/.claude/protocols/task-management.md`
- **Agentic behavior**: `~/.claude/protocols/agentic-behavior.md`
- **Code exploration**: `~/.claude/protocols/code-exploration.md`
- **Context management**: `~/.claude/protocols/context-management.md`
- **SSOT documentation**: `~/.claude/commands/ssot.md`
