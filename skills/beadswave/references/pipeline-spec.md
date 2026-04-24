# Conveyor Belt Pipeline Spec

## Overview

The beadswave conveyor belt is a deterministic, fail-closed,
queue-driven issue-to-main pipeline. It uses beads-native labels as the
state store — no external infrastructure required. Works on any repo with
beads + GitHub.

## Pipeline Stages

Each bead progresses through these stages. The current stage is tracked as
a `stage:*` label on the bead. Every stage is idempotent and resumable.

```
claim → branch → implement → ship → merge-wait → land
  │         │         │         │         │          │
  ▼         ▼         ▼         ▼         ▼          ▼
stage:   stage:    stage:    stage:    stage:     stage:
claimed  branched  committed shipping  merging    landed
                                           │
                                    stage:review-hold
                                    (held for human review)
```

### Agent-driven stages (agent controls flow)

| Stage | Label | Action | Actor |
|-------|-------|--------|-------|
| Claim | `stage:claimed` | `bd update --claim` | /drain or /bw-work |
| Branch | `stage:branched` | `git checkout -b fix/<shape>-<id> origin/main` | /drain or /bw-work |
| Implement | `stage:committed` | TDD: failing test → impl → green → `git commit` | Agent (TDD loop) |

### Pipeline-driven stages (automated, resumable)

| Stage | Label | Sub-steps | Script |
|-------|-------|-----------|--------|
| Ship | `stage:shipping` | rebase on origin/main → pre-ship hook → lint → typecheck → tests → push → create PR → merge via gh pr merge | bd-ship --no-close |
| Merge-wait | `stage:merging` | poll PR state until merged or timeout (30 min default) | merge-wait.sh |
| Review-hold | `stage:review-hold` | PR is held for human review (`auto-merge:hold`); set by bd-ship when `--hold` is passed; cleared to `stage:landed` by merge-wait when PR is merged | merge-wait.sh |
| Land | `stage:landed` | close bead → prune branch | merge-wait.sh + branch-prune.sh |

The `pipeline-driver.sh` script orchestrates stages 4-6. It reads the
current `stage:*` label and resumes from the appropriate step.

## Key Design Decisions

### 1. Rebase before gates (not after)

bd-ship rebases the branch onto `origin/main` BEFORE running any pre-ship
gates. This ensures lint/typecheck/tests run against the exact base that
`gh pr merge` will merge into. If the rebase has conflicts, bd-ship fails
immediately (exit 21) with a `preship-fail` sub-issue.

### 2. Beads-native state store

Pipeline state lives in `bd` labels — no external database, no Redis, no
Temporal. Every project with beads installed gets the full pipeline for
free. The `stage:*` labels are queryable (`bd list --label stage:merging`)
and survive across sessions.

### 3. Script-level enforcement (pre-push hook)

The `.githooks/pre-push` hook blocks:
- **All pushes to `refs/heads/main`** — always blocked
- **Pushes to `fix/*` branches** — blocked unless `.beads/.shipping-<branch>`
  lock file exists

bd-ship creates the lock file before push and removes it after PR creation.
Raw `git push` of a fix/* branch without bd-ship is blocked.

### 4. Bead is not closed until merge confirmed

With `--no-close`, bd-ship sets `stage:merging` and exits. The bead stays
open. `merge-wait.sh` polls until the PR is merged on GitHub, then closes
the bead and prunes the branch. This prevents beads from being closed
before their code actually reaches main.

### 5. Fail-closed at every stage

- Rebase conflicts → exit 21, preship sub-issue
- Gate failure → exit 2/6/7/20, preship sub-issue, `stage:shipping` removed
- Push failure → exit 3
- PR creation failure → exit 4
- Merge conflict during merge-wait → exit 22
- Worktree branch collision → exit 23 (the feature branch is checked out in a sibling worktree; bd-ship refuses to rebase rather than emit git's cryptic "fatal: '<branch>' is already used" mid-rebase)
- Merge timeout → exit 2, bead stays at `stage:merging`

**Never local-merge onto `main`.** The skill deliberately avoids `git checkout main` / `git merge origin/main` / `git pull origin main` at every layer — these operations fail unpredictably when `main` is already checked out by the primary worktree (multi-agent setups). Merge verification is advisory: `merge-wait` uses `git merge-base --is-ancestor` against `origin/main` only. Project-local pre-ship hooks (`.beadswave/pre-ship.sh`) must follow the same rule — fetch, don't checkout.

No `--skip-*` flags. The only path to `stage:landed` is through every
stage green.

### 6. Declared scope required before ship

bd-ship rejects beads that have `scope:unknown` or no `scope:*` label at all
(exit 6). The classifier assigns `scope:*` during `/waves` classification.
Unclassified or `scope:unknown` beads must be manually triaged before they can
enter the ship phase. Override with `BEADSWAVE_SKIP_SCOPE_CHECK=1` only for
tooling-internal calls where scope is intentionally undefined (e.g. backfill
scripts that touch every scope).

## Script Inventory

| Script | Location | Purpose |
|--------|----------|---------|
| `bd-ship.sh` | `~/.claude/skills/beadswave/references/templates/` | Ship stage: rebase → gates → push → PR → queue |
| `merge-wait.sh` | (same) | Merge-wait stage: poll until PR merged |
| `pipeline-driver.sh` | (same) | Orchestrator: ship → merge-wait → land (resumable) |
| `branch-prune.sh` | (same) | Remove merged branches |
| `queue-hygiene.sh` | (same) | Refresh main + prune + repair PRs |
| `pre-push.sh` | (same) | Block unauthorized pushes (main + fix/* without provenance) |

Each repo gets thin wrappers in `scripts/` that delegate to the templates.

## Slash Commands

| Command | Stages | Pipeline interaction |
|---------|--------|---------------------|
| `/bw-work <id>` | claim → branch → implement | Then calls `pipeline-driver.sh <id>` |
| `/drain` | Same as /bw-work but for a lane | Loops: pipeline-driver per bead |
| `/bw-land [id\|--all]` | land | Post-merge cleanup if not done by pipeline-driver |
| `/bw-monitor` | merging | PR health dashboard + orphan remediation |
| `/bw-mass` | shipping | Batch ship with rate-limiting |

## Recovery

The pipeline is resumable at every stage:

| Situation | Current label | Recovery |
|-----------|---------------|----------|
| Agent crashed mid-TDD | `stage:branched` or none | Re-run `/bw-work <id>` — it detects existing branch |
| Gate failed, agent fixed code | (no stage label) | Re-run `bd-ship <id>` — picks up from rebase |
| Rebase conflict during ship (exit 21) | (no stage label; `preship-fail` sub-issue) | Resolve the conflict on the feature branch (`git rebase origin/main` manually or `git pull --rebase`), commit the fix, close the `preship-fail` sub-issue, then re-run `bd-ship <id>`. bd-ship clears `stage:shipping` automatically on exit so the next attempt starts clean. |
| bd-ship crashed after push but before PR | `stage:shipping` | Re-run `bd-ship <id>` — detects branch already pushed |
| Mergify slow / timeout (legacy mode) | `stage:merging` | Re-run `merge-wait.sh <id> --timeout 3600` |
| PR has conflicts at merge | `stage:merging` | Rebase branch, re-run `bd-ship <id>` |
| PR merged but bead not closed | `stage:landed` or none | Run `/bw-land <id>` or `/bw-land --all` |
| Orphan PR (no auto-merge label) | N/A | `/bw-monitor --orphans` auto-remediates |

## Integration with Existing Tools

- **Mergify** (legacy, optional): `queue_conditions` match on `auto-merge` label; `merge_conditions: []`
  for CI-disabled repos; `update_method: merge` for rebase at queue time. Enable via `BEADSWAVE_MERGE_STRATEGY=mergify`.
- **GitHub Actions**: `auto-merge.yml` gate checks kill switch and blackout windows
- **Standard git**: All VCS writes via standard git commands; pre-push hook catches unauthorized pushes
- **beads CLI**: State store (`stage:*` labels), task tracking, provenance (`shipped-via-pr`, `gh-<n>`)
