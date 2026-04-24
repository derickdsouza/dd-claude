# Beadswave Skill Hardening — Retrospective & Fixes

## Context

While shipping bead `portfolio-manager-5vwuz`, I hit a three-link failure chain
and then nearly bypassed the pre-ship gate with `but push 5v`. Re-scoping the
diagnosis: of the four original failure modes, only one is project-specific
(the project's `.beadswave/pre-ship.sh` diverged from the skill template,
adding a `.log` suffix that breaks BSD `mktemp` and dropping the orphan-log
GC). The rest are **skill-level** gaps that any user will hit: a latent
`mktemp` bug in the skill's own `bd-ship.sh`, no guidance for GitButler's
virtual-branch working-tree pollution, and no codified "never bypass the
gate" rule. This plan updates only the skill and its supporting files.

## What was done badly

The commit is fine. My response to the failed gate was not: the correct path
on a red pre-ship is **fix the failures or isolate the scope, then re-run
`bd-ship`**, not `but push` to sidestep it. `bd-ship` does work `but push`
doesn't (close the bead, tag PR provenance, create PR, post
`@mergifyio queue`, append to `.beads/auto-pr.log`); bypassing it orphans the
bead from the auto-merge flow.

## Scope decision (per user direction)

| Concern | Scope | Action |
|---|---|---|
| `.log`-suffix mktemp bug in project hook | project | **Out of scope** — project customized the hook; fix over there separately if needed |
| Missing orphan-log GC in project hook | project | **Out of scope** — skill template already has GC at line 18 of `bun-monorepo.sh` |
| Same `mktemp … .XXXXXX.out` pattern in `skill/.../bd-ship.sh:324` | **skill** | Fix |
| No GitButler working-tree-hygiene guidance | **skill** | Add docs + optional guard helper |
| No codified "never bypass" rule | **skill** | Add to SKILL.md + ship-pipeline.md |
| `bd-ship` PATH / shell FUNCNEST | user shell setup | **Out of scope** |

## Skill changes

### 1. Fix latent BSD-mktemp bug in the skill's `bd-ship.sh`

[~/.claude/skills/beadswave/references/templates/bd-ship.sh:324](~/.claude/skills/beadswave/references/templates/bd-ship.sh#L324):

```bash
CLAUDE_OUT="$(mktemp "${TMPDIR:-/tmp}/bd-ship-claude.XXXXXX.out")"
```

Problem: same suffix-after-X's pattern. macOS BSD `mktemp` behaviour with a
suffix after the X's is unreliable; under adverse TMPDIR state it can leave a
literal-X artifact and all future runs collide with "File exists". The other
two `mktemp` calls in this file (lines 233, 273) are bare `mktemp` and are
safe.

**Fix** — drop the suffix:

```bash
CLAUDE_OUT="$(mktemp "${TMPDIR:-/tmp}/bd-ship-claude.XXXXXX")"
```

No downstream reader depends on the `.out` extension (grep+cut on content,
not filename). Adds a preventive line near the top of the script alongside
the existing trap, to clean any prior literal-X artifact exactly once:

```bash
rm -f "${TMPDIR:-/tmp}/bd-ship-claude.XXXXXX" 2>/dev/null || true
```

### 2. Add GitButler working-tree hygiene to the skill

Problem: pre-ship gates run `bun run --filter '*' lint` (or equivalent) over
the **working tree**. Under GitButler, the working tree also holds
"unassigned changes" from other virtual branches. A gate failure on files
outside the current bead's diff looks like your bead is broken when it isn't.
There is zero guidance about this in the skill today.

**Two additions:**

**(a) New reference doc:**
[~/.claude/skills/beadswave/references/gitbutler-integration.md](~/.claude/skills/beadswave/references/gitbutler-integration.md)
— ~60 lines covering:
- Why `bd-ship` + `but` is the recommended pairing
- The virtual-branch / working-tree trap and the diagnostic pattern
  ("gate fails on files not in `but status -fv` for your branch → unassigned
  pollution")
- Three mitigation options: fix-then-ship (preferred), stash unassigned
  (`git stash push --keep-index`), or opt-in `PRESHIP_ISOLATE=1`
- Pointer to helper at `scripts/check-working-tree.sh` (new, see (b))
- Explicit "never `but push` to bypass" callout

**(b) New shared helper:**
[~/.claude/skills/beadswave/scripts/check-working-tree.sh](~/.claude/skills/beadswave/scripts/check-working-tree.sh)
— a small function project pre-ship hooks can source:

```bash
#!/usr/bin/env bash
# beadswave_check_working_tree — abort pre-ship if unassigned changes
# would poison gate scope. No-op if `but` is not installed.
beadswave_check_working_tree() {
  [[ "${PRESHIP_ISOLATE:-0}" = "1" ]] || return 0
  command -v but >/dev/null 2>&1 || return 0
  local unassigned
  unassigned=$(but status -fv --json 2>/dev/null \
    | jq -r '[.unassigned_changes[]?.path] | length' 2>/dev/null || echo "0")
  if [[ "$unassigned" != "0" && "$unassigned" != "" ]]; then
    echo "✗ PRESHIP_ISOLATE=1 and $unassigned unassigned change(s) present." >&2
    echo "  These will poison gate scope under GitButler virtual branches." >&2
    echo "  Fix options: assign them to a branch, stash, or discard." >&2
    return 1
  fi
  return 0
}
```

**(c) Update each preship template** at
[~/.claude/skills/beadswave/references/preship-templates/](~/.claude/skills/beadswave/references/preship-templates/)
(`bun-app.sh`, `bun-monorepo.sh`, `pnpm-monorepo.sh`, `python-poetry.sh`,
`rust-cargo.sh`, `go-modules.sh`, `minimal.sh`) with a three-line block after
`cd "$REPO_ROOT"`:

```bash
# Optional: abort early if GitButler unassigned changes would poison gate scope.
# Enable by setting PRESHIP_ISOLATE=1 in .beadswave.env or at invocation.
if [[ -f "${BEADSWAVE_SKILL_DIR:-$HOME/.claude/skills/beadswave}/scripts/check-working-tree.sh" ]]; then
  # shellcheck disable=SC1091
  . "${BEADSWAVE_SKILL_DIR:-$HOME/.claude/skills/beadswave}/scripts/check-working-tree.sh"
  beadswave_check_working_tree || exit 1
fi
```

Default off = zero behavior change for existing users. Opt-in via
`PRESHIP_ISOLATE=1` for anyone on GitButler.

### 3. Codify "never bypass a failed gate"

Two doc edits:

**(a)** [~/.claude/skills/beadswave/references/ship-pipeline.md](~/.claude/skills/beadswave/references/ship-pipeline.md)
— extend the paragraph at line 27 ("On gate failure, `bd-ship` creates a
sub-issue…") with:

> **Never route around a failed gate by calling `but push`, `git push`, or
> `gh pr create` manually.** `bd-ship` does work the raw push doesn't: close
> the bead, tag PR provenance (`shipped-via-pr` label + `gh-<n>` external
> ref), spawn the PR-creation LLM, and post `@mergifyio queue`. A manual
> push orphans the bead from the auto-merge pipeline and breaks the
> invariant that code only reaches `main` through green gates. If a gate
> fails on files outside your bead's diff, that is a *scope* problem (see
> `gitbutler-integration.md`), not a signal to ship manually.

**(b)** [~/.claude/skills/beadswave/SKILL.md](~/.claude/skills/beadswave/SKILL.md)
— add to the "When NOT to use" / anti-patterns section:

> - Bypassing a failed pre-ship gate with a manual `but push` or `git push`.
>   Fix the failure or isolate the scope; re-run `bd-ship`. There is no
>   skip flag.

## Critical files

| File | Change |
|---|---|
| [~/.claude/skills/beadswave/references/templates/bd-ship.sh](~/.claude/skills/beadswave/references/templates/bd-ship.sh) | L324 mktemp template + cleanup line |
| [~/.claude/skills/beadswave/scripts/check-working-tree.sh](~/.claude/skills/beadswave/scripts/check-working-tree.sh) | **new** helper |
| [~/.claude/skills/beadswave/references/gitbutler-integration.md](~/.claude/skills/beadswave/references/gitbutler-integration.md) | **new** doc |
| [~/.claude/skills/beadswave/references/preship-templates/bun-app.sh](~/.claude/skills/beadswave/references/preship-templates/bun-app.sh) | add isolate-guard block |
| [~/.claude/skills/beadswave/references/preship-templates/bun-monorepo.sh](~/.claude/skills/beadswave/references/preship-templates/bun-monorepo.sh) | add isolate-guard block |
| [~/.claude/skills/beadswave/references/preship-templates/pnpm-monorepo.sh](~/.claude/skills/beadswave/references/preship-templates/pnpm-monorepo.sh) | add isolate-guard block |
| [~/.claude/skills/beadswave/references/preship-templates/python-poetry.sh](~/.claude/skills/beadswave/references/preship-templates/python-poetry.sh) | add isolate-guard block |
| [~/.claude/skills/beadswave/references/preship-templates/rust-cargo.sh](~/.claude/skills/beadswave/references/preship-templates/rust-cargo.sh) | add isolate-guard block |
| [~/.claude/skills/beadswave/references/preship-templates/go-modules.sh](~/.claude/skills/beadswave/references/preship-templates/go-modules.sh) | add isolate-guard block |
| [~/.claude/skills/beadswave/references/preship-templates/minimal.sh](~/.claude/skills/beadswave/references/preship-templates/minimal.sh) | add isolate-guard block |
| [~/.claude/skills/beadswave/references/ship-pipeline.md](~/.claude/skills/beadswave/references/ship-pipeline.md) | "never bypass" paragraph after L27 |
| [~/.claude/skills/beadswave/SKILL.md](~/.claude/skills/beadswave/SKILL.md) | anti-pattern line |

## Reuse check

- Existing orphan-GC pattern at `bun-monorepo.sh:18` (`find … -mtime +1 -delete`) is already correct; propagate unchanged to the other preship templates as part of the guard-block edit if they lack it.
- `queue-prs.sh` pattern of a skill-provided sourceable helper is the precedent for the new `check-working-tree.sh`; same `$BEADSWAVE_SKILL_DIR` lookup.
- No new dependencies — `jq` and `but` are already required by `bd-ship.sh`.

## Verification

1. **Skill mktemp fix:** `bash -n ~/.claude/skills/beadswave/references/templates/bd-ship.sh` passes shellcheck-clean; line 324 no longer has `.out`. A contrived test: `touch "$TMPDIR/bd-ship-claude.XXXXXX"` then run the script up to the mktemp; it should succeed (because the new cleanup line removes the literal-X artifact and the template has no suffix).
2. **Helper works in isolation:** `source ~/.claude/skills/beadswave/scripts/check-working-tree.sh && PRESHIP_ISOLATE=1 beadswave_check_working_tree` — returns 0 when no unassigned changes, returns 1 with diagnostic message when present (tested by creating an uncommitted file via GitButler).
3. **Default off:** unset `PRESHIP_ISOLATE`, source the helper, run — returns 0 regardless of working tree. Zero behavior change for existing users.
4. **Templates still lint:** `for f in ~/.claude/skills/beadswave/references/preship-templates/*.sh; do bash -n "$f"; done` all pass.
5. **Docs render:** open `gitbutler-integration.md` and the updated `ship-pipeline.md` in a Markdown preview; check the new "never bypass" paragraph reads cleanly and the cross-reference to the new doc resolves.
6. **End-to-end** (on a project that picks up the updated preship template after re-running its install or manually copying): `PRESHIP_ISOLATE=1 bash scripts/bd-ship.sh <some-bead>` aborts with the expected message when unassigned changes exist, and proceeds when the tree is clean.

## How this prevents the original incident

- The latent `mktemp` bug in the skill's own `bd-ship.sh` cannot bite a future user.
- Anyone using GitButler gets an explicit early-abort with a message that points to the real root cause, instead of a confusing lint failure on unrelated files.
- The "never bypass" rule is in `SKILL.md` and `ship-pipeline.md`, so future Claude sessions reading the skill have no justification for a manual `but push` after a gate failure.
