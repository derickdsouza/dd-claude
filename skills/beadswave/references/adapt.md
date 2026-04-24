# Adopting Beadswave on a New Repo

Checklist to bootstrap the whole pipeline. Order matters — skipping steps creates silent failure modes.

## Prerequisites

- Beads CLI installed and authed (`bd list --status=open` returns something sensible)
- GitHub CLI authed (`gh auth status` green)
- Python 3.8+ on PATH (for the classifier + allocation scripts)
- `jq` installed (used by some template scripts)

## 1. Install templates into the repo

The beadswave pipeline uses two categories of files: **symlinks** (point to the global skill) and **local copies** (must live at specific paths or contain project-specific logic).

### Symlinks — ship tooling and pre-push hook

These delegate entirely to the global skill. Symlinking means updates to the skill are picked up automatically — no per-repo copy drift.

```bash
SKILL=~/.claude/skills/beadswave
TEMPLATES=$SKILL/references/templates

mkdir -p scripts .githooks

# Ship tooling — symlinks to global skill
ln -sf $TEMPLATES/bd-ship.sh              scripts/bd-ship.sh
ln -sf $TEMPLATES/bd-lot-plan.sh          scripts/bd-lot-plan.sh
ln -sf $TEMPLATES/bd-lot-ship.sh          scripts/bd-lot-ship.sh
ln -sf $TEMPLATES/bd-circuit.sh           scripts/bd-circuit.sh
ln -sf $TEMPLATES/mass-ship.sh            scripts/mass-ship.sh
ln -sf $TEMPLATES/queue-drain.sh          scripts/queue-drain.sh
ln -sf $TEMPLATES/monitor-prs.sh          scripts/monitor-prs.sh
ln -sf $TEMPLATES/beadswave-lint.sh       scripts/beadswave-lint.sh
ln -sf $TEMPLATES/sync-gh-issues-to-beads.sh scripts/sync-gh-issues-to-beads.sh
ln -sf $TEMPLATES/setup-dev.sh            scripts/setup-dev.sh

# Pre-push hook — blocks direct pushes to main
ln -sf $TEMPLATES/pre-push.sh             .githooks/pre-push
```

### Local copies — project-specific content

These contain repo-specific logic and cannot be shared:

```bash
mkdir -p .beadswave .beads/prompts

# PR creation prompt — has repo-specific risk heuristics
cp $TEMPLATES/bd-ship-prompt.md       .beads/prompts/create-pr.md

# Pre-ship hook — project-specific gates (lint, test, security scan, etc.)
# Pick a starter template based on your stack, then customize:
#   $SKILL/references/preship-templates/<stack>.sh → .beadswave/pre-ship.sh
# Or write from scratch. See "Customize .beadswave/pre-ship.sh" below.
```

### Verify the setup

```bash
echo "=== Symlinks (should point to skill templates) ==="
for f in scripts/bd-ship.sh scripts/bd-lot-plan.sh scripts/bd-lot-ship.sh \
         scripts/bd-circuit.sh .githooks/pre-push; do
  file "$f" | grep "symbolic" || echo "WARNING: $f is NOT a symlink"
done

echo ""
echo "=== Local copies (should be regular files) ==="
for f in .beads/prompts/create-pr.md .beadswave/pre-ship.sh; do
  file "$f" | grep -v "symbolic" || echo "WARNING: $f is a symlink (should be local copy)"
done
```

Putting `scripts/` on PATH is optional convenience. If you want the shortcut:

```bash
# .envrc
PATH_add scripts
```

## 2. Tune the classifier

Copy `references/classifier.py` into your repo (optional — you can also invoke it straight from the skill) and edit the **Tuning knobs** block:

| Constant | What to set |
|---|---|
| `PROJECT_PREFIX` | Your beads project prefix. Run `bd list --limit 1 --json \| jq -r '.[0].id'` and take everything before the 5-char suffix. |
| `HOTSPOTS` | Files multiple beads touch that should serialize. Usual suspects: shared barrel/index files, monitoring alert YAMLs, protocol/parser files, DB journal files. |
| `BIG_FILE` | A single known mega-file that should force `wave:4` even for 1-file beads. Set `None` if you don't have one. |
| `MIGRATION_SEED` | First unused migration number. `ls <migrations-dir>/*.sql \| tail`. Set `None` if no SQL migrations. |
| `SHAPE_ORDER` | Your repo's work-types. Add/remove entries. First regex match wins. |
| `FOUNDATION_TITLES` | Title phrases that always mark a bead as foundation (shared helpers, branded types, etc.) |
| `PATH_RE` | Extend the prefix group if you have top-level dirs beyond `packages/`, `src/`, `apps/`, `services/`, etc. |

Run once on the existing backlog:

```bash
bd list --status=open --json -n 0 > /tmp/bd_open.json
python3 ~/.claude/skills/beadswave/references/classifier.py
bash /tmp/apply_labels.sh
```

## 3. Customize `.beads/prompts/create-pr.md`

The PR-creation prompt has risk heuristics that trigger `auto-merge:hold`. Adjust to your repo:

- **File globs**: replace `packages/backend/src/db/schema/**`, `scripts/deploy*.sh`, etc. with your repo's sensitive paths
- **Size thresholds**: the defaults are 300 lines / 5 files — tune based on your typical PR size
- **Priority rule**: the default holds P0 `bug`/`incident`. Adjust if your triage uses different labels.

## 4. Customize the Actions gate

`auto-merge-workflow.yml` has a **blackout window** placeholder (comment block near the top). If you have one (trading market hours, deploy freezes, maintenance windows), replace the placeholder with a shell check. If not, delete the blackout-window step entirely.

The kill-switch step should stay as-is.

## 5. Customize `.beadswave/pre-ship.sh`

This is the **only file that needs heavy per-project customization**. It defines the local quality gates that run before any PR is created. The global skill provides starter templates by stack:

```bash
# List available starters
ls ~/.claude/skills/beadswave/references/preship-templates/
```

Pick the one matching your stack and customize it:

```bash
SKILL=~/.claude/skills/beadswave
cp $SKILL/references/preship-templates/<stack>.sh .beadswave/pre-ship.sh
chmod +x .beadswave/pre-ship.sh
```

Then add your repo's specific gates. Use the runtime helper for consistent log formatting:

```bash
BEADSWAVE_SKILL_DIR="${BEADSWAVE_SKILL_DIR:-$HOME/.claude/skills/beadswave}"
# shellcheck disable=SC1090
. "$BEADSWAVE_SKILL_DIR/scripts/runtime.sh"

beadswave_run_gate "lint" "bun run lint"
beadswave_run_gate "tests" "bun run test --run"
```

## 6. Configure GitHub repo settings

Two repo-level settings are required for the pipeline to work correctly. Apply via `gh`:

### Enable "Allow updates to pull request branches"

```bash
gh api repos/{owner}/{repo} -X PATCH -f allow_update_branch=true
```

Required for:
- `monitor-prs.sh --resolve-conflicts` to auto-rebase conflicting PRs via `gh pr update-branch`
- `/bw-monitor --resolve-conflicts` slash command
- Preventing stale base branches between merge batches

Without this, conflicting PRs can only be resolved by local rebase + force-push.

### Enable "Automatically delete head branches"

```bash
gh api repos/{owner}/{repo} -X PATCH -f delete_branch_on_merge=true
```

Removes the remote branch after the PR is merged. Without this, `git fetch --prune` never cleans up and branches accumulate.

## 7. Dev-environment setup

Every developer (human or AI agent) runs this once per clone/worktree:

```bash
bash scripts/setup-dev.sh
```

It points `core.hooksPath` at `.githooks/` so the pre-push hook runs.

## 8. Try it end-to-end

Pick a small bead and drive it through:

```bash
bd ready
# pick one, say <id>

git fetch origin main --prune
git checkout -b fix/test-<id> origin/main

# make a trivial change, commit
git add <files>
git commit -m "test(beadswave): first ship"

bash scripts/bd-ship.sh <project>-<id>
```

Watch:

- `.beads/auto-pr.log` gets a new line
- A PR appears with `auto-merge` or `auto-merge:hold` label
- bd-ship merges the PR via `gh pr merge`
- GH auto-deletes head branch
- `git checkout main && git pull origin main` syncs the merge commit locally

## 9. Onboard workers

For each parallel agent you want to run:

1. Coordinator allocates a lane: `bd update <id> --add-label agent:<name>` for every bead in the `(wave, lane)`
2. Start a Claude session with `references/worker-prompt.md` contents, substituting `{{AGENT_NAME}}`, `{{WAVE}}`, `{{LANE}}`

## Common adoption gotchas

| Symptom | Cause | Fix |
|---|---|---|
| PRs never merge | `bd-ship` failing at merge step | check `gh auth status` has write access |
| Direct pushes to main happen anyway | Pre-push hook not installed | re-run `scripts/setup-dev.sh`; verify `git config --local core.hooksPath` is `.githooks` |
| Classifier says every bead is wave:9 | Path regex doesn't match your repo's structure | extend `PATH_RE` prefix group |
| `bd-ship: command not found` in worker sessions | repo wrapper exists but isn't on PATH | call `bash scripts/bd-ship.sh <id>` or source `scripts/runtime.sh` and use `beadswave_resolve_bd_ship` |

## When NOT to use beadswave

- Backlog <20 beads — overhead of classify/allocate exceeds benefit; just work them sequentially
- No beads dependency available — the workflow is designed around `bd` labels as the coordination primitive; retrofitting onto GH issues loses most of the clean-room lane semantics
- Single-agent workflow — classifier still useful (foundation detection, migration numbering) but wave/lane parallelism is dead weight
