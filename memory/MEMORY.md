# Global Memory - Critical Lessons

## Ask Questions via AskUserQuestion Tool (2026-04-17)

**MANDATORY: Always use the `AskUserQuestion` tool when asking the user questions — never inline questions in plain text.**

**Why:** User requested this globally, applies across ALL projects and conversations.

**How to apply:**
- When I need clarification, a decision, or a preference → call `AskUserQuestion`
- Structure: 1–4 questions per call, each with 2–4 discrete options
- If I recommend a specific option, put it first + suffix with "(Recommended)"
- Use `multiSelect: true` only when choices are genuinely non-exclusive
- "Other" is added automatically by the UI — never include it manually
- Do NOT use for rhetorical questions or yes/no confirmations baked into a plan — only for decisions that shape my next action
- Applies to: all projects, all future conversations

---

## Beads Database Safety (2026-03-04)

**CRITICAL: NEVER run `bd init --force` without checking for backups first!**

**Data loss incident:**
- Ran `bd init --force` on failing beads database
- Wiped 200 issues (142 closed, 43 ready, 15 blocked)
- Only recovered 169 from git history - lost 31 newer issues

**MANDATORY recovery procedure before destructive operations:**
1. Check git history: `git log --oneline --all -- .beads/issues.jsonl`
2. Extract backup: `git show <commit>:.beads/issues.jsonl > /tmp/backup.jsonl`
3. Restore: `cp /tmp/backup.jsonl .beads/issues.jsonl && bd init --force --from-jsonl`
4. ALWAYS attempt recovery before any `--force` operation

**Prevention best practices:**
- Set up remote Dolt: `bd dolt remote add origin <url>`
- Regular backups: `bd dolt push`
- Ask user confirmation before destructive commands
- Check `.beads/issues.jsonl` in git history as first recovery option

**Applies to:** All projects using beads for task tracking

---

## Dolt Port Isolation (2026-03-24)

**CRITICAL: Every beads-enabled project MUST use a unique Dolt port — NEVER the default port (3307).**

- Each project configures its own port in `.beads/dolt/config.yaml` (`listener.port`)
- Multiple projects run their own Dolt servers simultaneously on different ports
- **NEVER** kill or restart another project's Dolt server
- **NEVER** assume the default port is available or correct — always check the project's config
- Before any Dolt/mysql command, verify the port from `.beads/dolt/config.yaml`

**Why:** Projects share the same machine and run Dolt concurrently. Using the standard port causes collisions, corrupts data, or connects to the wrong project's database.

**Applies to:** All projects using beads for task tracking

---

## GitButler Workflow Fixes (2026-04-16)

**`rm -f .git/*.lock &&` breaks in zsh when no locks exist**
- zsh `nomatch` exits 1 on unmatched globs → `&&` kills the chain silently
- Fix: `rm -f .git/*.lock 2>/dev/null; but <mutation>` — semicolon not `&&`
- Updated in: `~/.claude/protocols/git-safety.md`

**`but pull` after `gh pr merge` errors without `but unapply` first**
- Merged branch stays applied in GitButler workspace → "Chosen resolutions do not match" deadlock
- Fix: `but unapply <branch>` BEFORE `but pull --status-after` — always
- Updated in: `~/.claude/protocols/git-safety.md`

## Workspace Sync Stale Overwrite (2026-04-16)

**Workspace sync commits from stale worktrees silently revert merged PRs**
- Worktree branches at commit A → PRs B+C land on main → sync commit squashes worktree changes → old versions of files overwrite B+C changes on main
- 7 files from PR #29 were silently reverted this way in commit `00d7ec3`
- Fix added to `~/.claude/protocols/git-safety.md`: run `git diff origin/main -- <files>` before any sync commit; if it shows reverts, pull first

## GitButler `but pull` after merge — `but branch delete` fallback (2026-04-16)

**When `but unapply` says "not found in any applied stack" but `but pull` still errors**
- The branch is in an unapplied stack entry but GitButler still blocks pull
- Fix: `but branch delete <branch-name>` removes the stale stack entry, then `but pull` succeeds

## GitButler: Pull Before Branch New (2026-04-16)

**`but branch new` before `but pull` causes "parents not referenced" commit failures**
- Creating a branch while local HEAD is behind `origin/main` roots it on the wrong base commit
- GitButler cannot reconcile it; all subsequent `but commit` calls fail
- Fix: `but pull --check` → `but pull` → THEN `but branch new <name>` — mandatory, every time
- Applies even after your own just-merged PR — the merge commit is an upstream change

## GitButler: `gh pr create` Always Needs `--head` (2026-04-16)

**`gh pr create` without `--head` always fails in a GitButler workspace**
- GitButler's virtual branch model means the working directory is never "on" a branch in the git sense
- `git branch --show-current` returns nothing → `gh` inference aborts with "you must first push the current branch"
- Fix: always use `gh pr create --head <branch-name> --base main ...` — never omit `--head`

## General Patterns

- [2026-04-20] tooling: Manual recovery after a failed beadswave ship is a data-integrity bug, not a workflow. Never compensate with hand-run `gh pr create`, PR relabeling, or `bd close`; harden the ship script so branch selection, gate scope, and close timing are correct by construction.
- [2026-04-20] tooling: Cross-shell automation must key sticky session state to a stable session identifier or TTY, not process IDs. `$$`/`$PPID` are per-shell and will silently break coordinator state when slash commands spawn fresh shells.
- [2026-04-20] tooling: Shared shell helpers beat copy-pasted snippets. Put temp-file creation, gate logging, and command resolution in one sourced runtime so every wrapper/template inherits the same cross-platform behavior and fixes land once.
- [2026-04-20] tooling: When pre-ship failures surface files outside the current bead diff, the right response is isolation or owner-branch repair, not patching foreign files from the current bead. Prompt the agent to stop, re-read, and fix the real scope problem.
- [2026-04-21] tooling: GitButler file IDs and applied-branch names are live state, not durable handles. After `Invalid file ID(s)` or branch-not-found errors, refresh `but status -fv` once and stop using stale IDs; never compensate with `but stash`, scratch branches, or staged session-state files.
(Add other cross-project lessons learned here)

---

## Sub-Files

- [debugging.md](debugging.md) — recurring failure patterns and root causes
- [patterns.md](patterns.md) — implementation patterns and conventions
- [architecture.md](architecture.md) — architecture decisions and principles

## Auto-Update Rules

Update this file (or the appropriate sub-file) when:
- A bug is fixed with a non-obvious root cause → `debugging.md`
- A new cross-project pattern is established → `patterns.md`
- A mistake is corrected and worth avoiding in future → `MEMORY.md`

**Format:** `- [YYYY-MM-DD] <category>: <insight>`
**Limit:** Keep MEMORY.md under 200 lines. Remove low-value entries before adding new ones.
