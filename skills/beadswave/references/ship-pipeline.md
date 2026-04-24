# Ship Pipeline — `bd-ship` → PR → Merge → Main

Event-driven auto-merge. LLM creates the PR (judgment calls — title, risk paragraph, hold label), `gh pr merge` performs the merge (deterministic).

## Why this split

| Concern | Owner | Why |
|---|---|---|
| Reading bead context, composing PR body, risk classification | `claude -p` | judgment |
| Kill switch, blackout window, merge execution | `gh pr merge` + Actions gate | deterministic |

LLMs are good at synthesis (PR body from bead + diff) and bad at deterministic coordination. This pipeline separates the two.

## The trigger: `scripts/bd-ship.sh <id>`

`scripts/bd-ship.sh` (template in `templates/bd-ship.sh`) is the preferred entry point. Workers should call the repo-local wrapper directly, or resolve it via the beadswave runtime helper when they cannot assume PATH contains `bd-ship`. It runs the ship pipeline in order and exits non-zero on any failure:

1. **Kill switch** — `.auto-merge-disabled` file in repo root blocks shipping entirely
2. **Bead validation** — `bd show <id>` must exist and not be closed
3. **Branch resolution** — current branch (or `--branch` override)
4. **Rebase on main** — `git fetch origin main` then `git rebase origin/main` (exit 21 on conflicts)
5. **Pre-ship hook** — `.beadswave/pre-ship.sh` runs lint/typecheck/tests; **mandatory, no skip**
6. **Push** — `git push origin <branch>` (only with `.beads/.shipping-<branch>` lock)
7. **Refresh `origin/main` + spawn LLM** — `claude -p < .beads/prompts/create-pr.md` with `BEAD_ID`/`BRANCH`/`FORCE_HOLD` in env; PR context must be diffed against the remote base, not stale local `main`
8. **Tag bead provenance** — attach `gh-<n>` external ref + `shipped-via-pr`
9. **Reject accidental support-file diffs** — fail closed on `.beads/` session files and, unless explicitly allowed, `.beadswave/` / `.githooks/`
10. **Direct merge** — `gh pr merge <PR> --<method> --delete-branch` immediately after PR creation
11. **Close bead** — `bd close <id> -r "Shipped via bd-ship"` after merge confirmed

On gate failure, `bd-ship` creates a sub-issue under the parent bead with label `preship-fail` and removes the `stage:shipping` label. The worker must fix the sub-issue and re-run `bd-ship` until all gates pass. There are no `--skip-*` flags.

**Never route around a failed gate by calling `git push`, `gh pr create`, `gh pr edit --add-label auto-merge`, or `bd close` manually.** `bd-ship` does work a raw push doesn't: keep the bead open until the PR is real, tag PR provenance (`shipped-via-pr` label + `gh-<n>` external ref), spawn `claude -p` to compose the PR, and merge. A manual push or close orphans the bead from the pipeline and breaks the invariant that code only reaches `main` through green gates. If a gate fails on files outside your bead's diff, that is a **scope** problem, not a signal to ship manually.

Logs one JSON line to `.beads/auto-pr.log`.

## The LLM: `.beads/prompts/create-pr.md`

Template in `templates/bd-ship-prompt.md`. Reads:

- `git fetch origin main --prune` — refresh merge base
- `bd show $BEAD_ID` — title, description, type, priority
- `git log origin/main..origin/$BRANCH --oneline` — commits
- `git diff --stat origin/main...origin/$BRANCH` — files + lines
- `git diff --name-only origin/main...origin/$BRANCH` — risk input

### Risk heuristics → `auto-merge:hold` (first match wins)

Tune these for your repo in the prompt template:

- `$FORCE_HOLD == "true"` (from `bd-ship --hold`)
- Touches schema files (e.g. `packages/backend/src/db/schema/**`)
- Touches migration files (e.g. `packages/*/migrations/**`)
- Touches deploy/rollback scripts (e.g. `scripts/deploy*.sh`, `scripts/rollback.sh`)
- Diff >300 lines
- >5 files
- Bead is P0 and type `bug` or `incident`
- Bead body contains "requires human review" or "breaking change"

### Output contract

On the final two lines, exactly:

```
PR_NUMBER=<n>
PR_LABEL=<auto-merge|auto-merge:hold|empty-branch>
```

`bd-ship.sh` parses these to log the event and decide whether to merge immediately.

### Guardrails (in prompt)

- Never run `gh pr merge`, `gh pr close`, or anything other than `gh pr create` + `gh label create`
- Never compare the branch to local `main`; only `origin/main` is authoritative in long-lived worktrees
- Never push new commits — bd-ship already did
- If the branch has zero commits ahead of main, print `PR_NUMBER=null` + `PR_LABEL=empty-branch` and stop

## The gate: `.github/workflows/auto-merge.yml`

Template in `templates/auto-merge-workflow.yml`. Fires on PR `opened/labeled/unlabeled/synchronize/reopened`.

Two jobs:

**`gate`** — sets an output `proceed=true/false`:
- Checks `.auto-merge-disabled` file
- Checks deploy blackout window (market hours, release freezes, etc.)

**`report`** — if `proceed=false`, comments once on the PR explaining why.

## CI-Disabled Mode

When GitHub CI is disabled (`.github/workflows/ci.yml` has no `push`/`pull_request` triggers), the pre-ship hook (`.beadswave/pre-ship.sh`) is the **sole quality gate**. The `auto-merge` label on a PR is proof that `bd-ship` ran all local gates successfully.

**How to detect:** Check if `.github/workflows/ci.yml` has commented-out `push`/`pull_request` triggers, or check for a `.ci-disabled` marker file in the repo root.

**Implications for agents:**
- **Do NOT report CI check failures** as blockers — CI does not run on PRs.
- **Do NOT investigate CI failures** — they are stale runs from before disabling.
- **Pre-ship check results** (from `.beadswave/pre-ship.sh`) are the authoritative quality signal.
- **monitor-prs** should skip CI status analysis and only track: PR count, review status, merges, and new/closed PRs.

## Perimeter safeguards

- **Pre-push hook** (`templates/pre-push.sh`) — blocks raw `git push origin main` and `fix/*` pushes without bd-ship provenance (free tier has no branch protection)
- **Direct-push alert** (`templates/direct-push-alert.yml`) — on every non-merge commit to main, files a GH issue labeled `direct-push`
- **Alert mirror** (`templates/sync-gh-issues-to-beads.sh`) — pulls those GH issues into beads as P0 `incident`
- **Dev setup** (`templates/setup-dev.sh`) — installs the pre-push hook and bootstraps local dependencies; run once per clone/worktree

## End-to-end timing

| Stage | Typical (CI-enabled) | Typical (CI-disabled) |
|---|---|---|
| `bd-ship` (incl. local tests + push + claude -p + merge) | 1–3 min | 1–2 min |
| Total issue-in-progress → main | ~1–3 min | ~1–2 min |

## Pipeline stage labels

Beads track pipeline state via `stage:*` labels:

| Label | Meaning | Set by |
|---|---|---|
| `stage:shipping` | Pre-ship gates + push + PR + merge in progress | bd-ship |
| `stage:merging` | PR created, merge in progress | bd-ship (--no-close) |
| `stage:landed` | Merged to main | pipeline-driver |

These labels make the pipeline resumable — `pipeline-driver.sh` reads the current label and resumes from the appropriate step.
