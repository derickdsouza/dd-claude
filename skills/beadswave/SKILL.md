---
name: beadswave
version: 1.2.0
description: "Multi-agent backlog drain — classify beads into waves, allocate lanes to parallel workers, drain via TDD → PRs → merge queue."
author: Derick D'souza
---

# Beadswave Skill — Issue-to-Main Automation

End-to-end recipe for moving work from a beads backlog through code, branches, PRs, and into `main` using parallel AI-agent workers plus a deterministic auto-merge queue. Works on any repository that uses beads + GitHub.

## When to Use

Match on user intent, not just literal phrasing:

| Intent | Invoke this skill |
|---|---|
| "drain the backlog" / "fan out agents" / "run multiple agents in parallel" | Phases 1–3 |
| "classify beads" / "apply wave labels" / "label my open issues" | Phase 1 |
| "coordinate agents" / "allocate lanes" / "assign a lane to X" | Phase 2 |
| "claim my lane" / "I'm agent X, what do I do" / "worker prompt" | Phase 3 |
| "ship this bead" / "open a PR for <id>" / "bd-ship" | Phase 4 |
| "bulk create PRs" / "batch PR" / "submit all branches as PRs" | `bulk-pr-create.sh` |
| "schedule drain" / "delayed drain" / "drain after merge" | `delayed-drainer.sh` or `trigger-drainer-delayed.sh` |
| "stale branches" / "queue hygiene" / "repair orphaned PRs" / "refresh the workspace" | `scripts/queue-hygiene.sh` |
| "bootstrap beadswave on this repo" / "adopt this workflow" | `references/adapt.md` |
| "work on <id>" / "implement <id>" / "do this bead" | `/bw-work <id>` |
| "land" / "cleanup" / "prune branches" / "close merged beads" | `/bw-land [--all]` |
| "mass ship" / "ship all branches" / "batch ship" | `/bw-mass` |
| "monitor PRs" / "check PR health" / "show PR status" | `/bw-monitor` |
| "circuit breaker" / "trip breaker" / "reset breaker" | `/bw-circuit [status\|auto\|trip\|reset]` |

## Fast path — slash commands

Two slash commands compose the whole pipeline for parallel terminals. Both are
idempotent and safe to re-run:

| Command | Does |
|---|---|
| `/waves` | Auto-adopt repo (silent) · classify un-labeled beads · claim a free lane for this terminal |
| `/drain` | Loop through my claimed lane bead-by-bead (claim → TDD → commit → ship). Auto-invokes `/waves` if no allocation yet |
| `/bw-work <id>` | Single bead: read → branch → TDD → commit → bd-ship. No lane allocation overhead |
| `/bw-land [id\|--all]` | Recovery landing: resume `pipeline-driver` for one bead, or run repo-wide cleanup recovery |
| `/bw-mass` | Batch ship pre-implemented branches through bd-ship with rate-limiting |
| `/bw-monitor` | PR health dashboard: failures, orphans, conflicts, auto-remediation |
| `/bw-circuit [status\|auto\|trip\|reset]` | Circuit breaker control for the auto-merge pipeline |

Typical usage: open N terminals, type `/drain` in each — each picks a different
agent name from the pool and drains a different lane. Open one more for
`/loop monitor-prs` to auto-file beads for PR failures. Pass `--orphans` to detect PRs created outside `bd-ship` plus stuck labeled PRs missing queue / auto-merge handoff, and auto-remediate them. Pass `--resolve-conflicts` to auto-rebase CONFLICTING PRs via GitHub API and file beads for unresolvable conflicts (requires repo setting "Allow updates to pull request branches").

Use `scripts/queue-hygiene.sh --phase "<label>"` before a new bead, after a
successful landing, before `/waves` allocates a lane, and before any
`mass-ship` batch. It is the fail-closed control loop that keeps workspace
state, merged-branch pruning, and orphan/conflict repair from drifting apart.

Flow reference: `references/orchestrator.md`.

## Non-Negotiable Rules

1. **Beads is the only task tracker.** Never use TodoWrite / TaskCreate / markdown TODO files.
2. **One issue, one branch, one PR.** Never bundle multiple beads into one branch.
3. **Lanes are sacred.** A worker only touches beads labeled `drain:<its-name>`. Bugs found outside the lane become new beads, not commits.
4. **Pre-allocated `migration:NNNN` labels are sacred.** The classifier assigns them to prevent parallel migration-number collisions on `_journal.json`.
5. **Drain waves in order.** `wave:0` (foundations) must complete before `wave:1` starts — later waves may depend on shared types/helpers foundations introduce.
6. **Never merge directly to main.** All changes land via the repo's `scripts/bd-ship.sh <id>` wrapper (or a runtime-resolved equivalent) → PR → auto-merge pipeline. Direct-push is blocked by pre-push hook and alerted by GH Action.
7. **Use the repo's approved VCS write path.** In the current workflow that means standard non-interactive git commands plus the beadswave wrappers. Do not guess or introduce alternate frontends.
8. **Pre-ship checks are mandatory and never skippable.** If any gate (pre-ship hook, lint, typecheck, tests) fails, `bd-ship` creates a sub-issue linked to the parent bead with label `preship-fail`, the worker fixes the sub-issue, and re-runs `bd-ship` — repeating until all gates pass. There are no `--skip-*` flags. The only way to ship is through all gates green.
9. **Never route around a failed gate with a manual push / `gh pr create`.** `bd-ship` does work a raw push doesn't: it tags PR provenance, records merge handoff, and leaves the bead open at `stage:merging` until merge is confirmed. Manual pushing orphans the bead from auto-merge and breaks the bead-to-main invariant. When a gate fails on files outside your bead's diff, that's a **scope** problem — stop and fix workspace isolation instead of patching foreign files from the current bead.
10. **Do not stack guess-fixes under pressure.** After 2 consecutive failed edits, edit-state/read-state tool errors (`File has not been read yet`, `File has been modified since read`, `String to replace not found`, `Found <N> matches`), tests, or ship attempts on the same bead, stop and re-read the failing file(s), latest gate output, and bead context before changing code again. Speed is not a reason to accept a brittle fix.
11. **Session-state files are not bead files.** Never stage or commit `.beads/.agent-*`, `.beads/.waves.lockdir`, or similar bookkeeping files to quiet an isolation failure.
12. **Use current state, not stable identifiers.** If git says `error ID(s)` or a branch is missing, refresh with `git fetch origin main --prune && git branch --list` and work only from the current branch names. Do not invent scratch branches or use `git stash` as a recovery shortcut.
13. **Bead IDs stay fully qualified.** Keep the project prefix (`portfolio-manager-oivqp.1`, not `oivqp.1`) when shipping beads, creating child beads, or linking `discovered-from:` dependencies.
14. **Do not fan out nested subagents from a worker bead.** Beadswave already parallelizes by lane. If a worker or audit run hits `429` rate limits, stop spawning more agents and continue serially or with a much smaller batch.
15. **Never sleep-poll or keep guessing CLI flags.** Use `merge-wait.sh`, `monitor-prs.sh`, and `bd <subcommand> --help` instead of `sleep 30 && gh pr view ...`, ad-hoc loops, or made-up `bd`/`gh` flags.

## CLI Guardrails

When this skill touches beads, use the exact current `bd` command surface.
The last 144 hours of logs were full of wasted retries from "close enough"
flag guesses.

- Use `bd list --label <x>`, not `bd list --labels <x>`.
- Use `bd close <id> -r "..."`, not `bd close --note` or `--notes`.
- Use `bd note <id> "..."` (or `bd update <id> --append-notes "..."`) for notes.
- Use `bd update <id> --assignee "" --status open` to reset/unclaim, not `--unclaim`.
- Use `bd link <id1> <id2> -t blocks`, not `--blocks`.
- Use `bd children <id>` as-is; there is no `--recursive` flag.
- Use `bd list --all --closed-after YYYY-MM-DD` for recent closures, not `--closed --last`.
- If a `bd` command returns `unknown flag`, stop after the first failure and run `bd <subcommand> --help`. Do not keep guessing mid-drain.

## Architecture at a Glance

```
Backlog (bd list)
  │
  ├── Phase 1: CLASSIFY ── classifier.py → wave/lane/shape/scope labels
  │
  ├── Phase 2: ALLOCATE  ── coordinator adds drain:<name> labels (agent:* is creator provenance)
  │
  ├── Phase 3: EXECUTE   ── N workers in parallel, each on one lane
  │                        ├── bd claim → TDD → git commit
  │                        └── scripts/bd-ship.sh <id>  (trigger Phase 4)
  │
  ├── Phase 4: SHIP      ── bd-ship.sh → rebase → gates → push → claude -p → gh pr create
  │                        └── bd-ship creates the PR and hands merge to the queue
  │
  └── Phase 5: MERGE     ── GitHub Actions gate → CI → direct merge → main
```

## Conveyor Belt Pipeline

Deterministic, fail-closed, queue-driven issue-to-main pipeline. Every bead
progresses through labeled stages tracked in `bd`. The pipeline is idempotent
and resumable — re-running from any stage picks up where it left off.

Full spec: `references/pipeline-spec.md`

```
claim → branch → implement → ship → merge-wait → land
  │         │         │         │         │          │
  ▼         ▼         ▼         ▼         ▼          ▼
stage:   stage:    stage:    stage:    stage:     stage:
claimed  branched  committed shipping  merging    landed
```

| Stage | Label | Actor | Script |
|-------|-------|-------|--------|
| Claim | `stage:claimed` | Agent | `bd update --claim` |
| Branch | `stage:branched` | Agent | `git checkout -b` |
| Implement | `stage:committed` | Agent | TDD loop + `git commit` |
| Ship | `stage:shipping` | Automated | `bd-ship --no-close` (rebase → gates → push → PR → queue) |
| Merge-wait | `stage:merging` | Automated | `merge-wait.sh` (polls until PR merged) |
| Land | `stage:landed` | Automated | `pipeline-driver.sh` (close bead + prune branch) |

**Key enforcement**: bd-ship rebases on `origin/main` before gates. Pre-push hook blocks `fix/*` pushes without bd-ship provenance. Bead is not closed until merge is confirmed on GitHub.

**Recovery**: re-run `pipeline-driver.sh <id>` from any stage. It reads the current `stage:*` label and resumes.

## Phase 1 — Classify (one-shot per backlog snapshot)

Goal: label every open bead with `wave:N`, `lane:X`, `shape:<kind>`, `scope:<pkg>`, plus pre-allocated `migration:NNNN` where applicable.

```bash
# Snapshot open beads (beads CLI must be installed and authed)
bd list --status=open --json -n 0 > /tmp/bd_open.json

# Run the classifier. Edit tuning knobs at top of the script first —
# see references/classifier.py (PROJECT_PREFIX, HOTSPOTS, MIGRATION_SEED).
python3 ~/.claude/skills/beadswave/references/classifier.py

# Apply labels
bash /tmp/apply_labels.sh
```

Wave rules (one bead → one wave):

| Wave | Rule | Parallelism |
|---|---|---|
| 0 | foundation (≥4 beads reference it OR title matches foundation regex) | Serial — stack of shared types/helpers |
| 1 | single-file, no hotspot, no migration, no metric/alert | Max parallel — file-disjoint |
| 2 | hotspot-touching OR migration-producing OR metric/alert/runbook | Parallel by lane — lanes serialize shared file |
| 4 | ≥4 files OR known big-file (e.g. `transaction-import-parsers.ts`) | One agent per lane — multi-file cluster |
| 9 | no file paths in description | Triage — worker reclassifies on claim |

Full classifier: `references/classifier.py`

## Phase 2 — Allocate (one coordinator session)

One Claude session acts as coordinator. It adds `drain:<name>` labels to every bead in `(wave, lane)` pairs to assign them to named workers. `agent:*` labels are reserved for creator provenance (which agent generated the bead).

| Operation | Command shape |
|---|---|
| Show free lanes | `bd list --status=open --json -n 0 \| python3 <free-lanes-script>` |
| Allocate lane | For every bead in `(wave, lane)`: `bd update <id> --add-label drain:<name>` |
| Release lane | `bd update <id> --remove-label drain:<name>` |
| Reassign lane | Combined remove + add in one `bd update` |
| Progress report | Group by `drain:*` label, count by status |

Operating rhythm: every 15–30 min, inspect allocation, reassign stalled lanes, allocate new lanes to idle agents. Drain `wave:0` fully before starting `wave:1`.

Full commands: `references/coordinator.md`

## Phase 3 — Execute (one worker session per lane)

Each worker gets `references/worker-prompt.md` with `{{AGENT_NAME}}`, `{{WAVE}}`, `{{LANE}}` substituted.

Per-bead loop:

1. `bd ready --label drain:<name>` → next bead
2. `bd show <id>` → read files, `migration:NNNN`, `touches-hotspot:*`, deps. Keep the full project-prefixed bead ID from `bd` output for every later `bd-ship`, `--parent`, and `discovered-from:` call.
3. **Sync + branch**: run `scripts/setup-dev.sh` once per fresh clone/worktree, then `scripts/queue-hygiene.sh --phase "before <id>"` when available, then `git fetch origin main --prune` → `git checkout -b fix/<shape>-<id> origin/main`
4. Set `stage:branched`: `bd update <id> --add-label stage:branched`
5. **TDD**: failing test → minimal impl → green → refactor
6. **Migration slot** (schema beads only): use `migration:NNNN` number exactly; append to `_journal.json`
7. Commit via the repo's approved VCS write path: standard git plus the beadswave wrappers. Keep the bead invariant: ≤5 files, ≤300 lines, one bead per branch.
8. Set `stage:committed`: `bd update <id> --add-label stage:committed`
9. `scripts/pipeline-driver.sh <id>` — triggers Phases 4-5 (ship → merge-wait → land)

After each successful pipeline completion, trust the conveyor belt. `pipeline-driver.sh` now runs the post-merge queue-hygiene pass itself. Do not stack extra manual `git pull`, manual branch deletes, or manual bead closes on top of it.

Hard limits: code files ≤275 lines; commits ≤5 files, ≤300 lines.

Conflict signals (stop and escalate, don't steal):
- `bd update --claim` says already claimed
- `git pull` has unresolvable conflicts
- A file you need is modified on another unapplied branch
- Your `migration:NNNN` is already taken in `_journal.json`

## Phase 4 — Ship (`scripts/bd-ship.sh <id>`)

`bd-ship` is the canonical ship script that runs the gates deterministically. In practice, workers should prefer the repo's `scripts/bd-ship.sh` wrapper or resolve it via `scripts/runtime.sh` rather than assuming a global `bd-ship` binary is on PATH. It replaces manual `gh pr create` + `gh pr merge`.

1. Kill switch check (`.auto-merge-disabled` file)
2. Validate bead (exists, not closed)
3. Resolve branch (current branch or `--branch` override)
4. **Rebase on `origin/main`** — fetches latest main, rebases branch. Fails (exit 21) if conflicts, creating a `preship-fail` sub-issue.
5. Set `stage:shipping` label on the bead
6. **Pre-ship hook** (`.beadswave/pre-ship.sh` if executable) — **mandatory**
7. `lint` (`$LINT_CMD`) — **mandatory**
8. `typecheck` (`$TYPECHECK_CMD`) — **mandatory**
9. `bun test` (or your repo's `$TEST_CMD`) — **mandatory**

On any gate failure (rebase, pre-ship, lint, typecheck, tests), `bd-ship` creates a sub-issue (`preship-fail` label) linked to the parent bead, removes the `stage:shipping` label, and exits. The worker must fix the sub-issue and re-run `bd-ship` until all gates pass. If the failure points at files outside the bead's diff, treat that as workspace contamination or an owning-branch problem — do not patch foreign files from the current bead. There are no skip flags — the only path to shipping is through all gates green.
10. `git push origin <branch>` (shipping lock file `.beads/.shipping-<branch>` created before push, removed after PR creation)
11. Spawn `claude -p < create-pr.md` — LLM reads bead + diff, applies risk heuristics, runs `gh pr create --label <auto-merge|auto-merge:hold>`
12. Tag bead with PR provenance: `bd update <id> --external-ref gh-<pr> --add-label shipped-via-pr` — lets audits distinguish sanctioned closes from manual ones (non-fatal on failure)
13. Reject accidental support-file diffs (`.beads/` session state, `.beadswave/`, `.githooks/`) unless explicitly overridden for intentional workflow work
14. Request merge handoff via `gh pr merge` (skipped if `auto-merge:hold`)
15. Set `stage:merging`, remove `stage:shipping`, and leave the bead open until merge is confirmed
16. With `--no-close`: always defer closure to `merge-wait.sh` / `pipeline-driver.sh`. Without `--no-close`: close only if the PR is already confirmed merged during this invocation.

If push or PR creation fails, the bead stays open. Never paper over a failed ship
by creating the PR manually and closing the bead by hand.

Before PR composition, `bd-ship` refreshes `origin/main` so the PR prompt always
diffs against the remote base, not a stale local `main`.

### Retroactive adoption (`bd-ship adopt <pr-number>`)

If a PR was created outside `bd-ship` (manual `gh pr create`, bypassed gates),
use `bd-ship adopt <pr-number>` to retroactively add the merge handoff metadata
and request the same auto-merge path the normal ship flow would have used.

```bash
scripts/bd-ship.sh adopt 1514
```

### Pre-ship hook (project-specific gates)

For anything the three canonical gates can't express — second-pass type checkers (`tsgo`), SAST (`semgrep`), secret scan (`trufflehog`), dependency audit (`bun audit`), migration drift checks, build verification, workspace-specific test splits — drop an executable script at `.beadswave/pre-ship.sh` in the repo root. `bd-ship` runs it after branch resolution and before the lint gate. Exit 0 = pass; non-zero = abort ship with exit code 20.

**Starter templates** (`references/preship-templates/`) — `install.sh` auto-picks one based on detected stack (`bun-monorepo`, `pnpm-monorepo`, `python-poetry`, `go-modules`, `rust-cargo`, or `minimal`). Detection uses lockfiles (`bun.lock`, `pnpm-lock.yaml`, `poetry.lock`, `go.mod`, `Cargo.toml`); override via `PRESHIP_STACK=<name>` env var. The starters source `scripts/runtime.sh` from the global skill so they share session-state helpers, repo-local `bd-ship` resolution, safe `.git/*.lock` cleanup, PR auto-merge fallback, and cross-platform gate logging.

If you customize `.beadswave/pre-ship.sh`, keep sourcing the runtime and prefer
`beadswave_run_gate` over local `run_gate()` wrappers. Run
`scripts/beadswave-lint.sh --strict` after edits or refreshes; it now flags the
known regressions from real sessions: raw `.git/*.lock` globs, bespoke
`mktemp ... preship.XXXXXX.log` wrappers, and drift away from the shared runtime.

**Gold-standard exemplar**: portfolio-manager's 14-gate suite covers lint · tsc×3 (backend/frontend/shared) · tsgo×3 (dual-pass type check) · drizzle migration drift · `bun audit` · trufflehog (secret scan) · semgrep (SAST) · migrate · backend tests · frontend tests · build. Use it as reference when tuning a starter into a production-grade hook — the starters cover the skeleton; the portfolio-manager suite shows where the teeth go.

**Single-source-of-truth pattern**: if your hook runs lint + typecheck + tests too, set `LINT_CMD=""` / `TYPECHECK_CMD=""` / `TEST_CMD=""` in `.beadswave.env` so the canonical gates no-op. The hook becomes the only thing that runs.

Discovery order (high wins):
1. `$BEADSWAVE_PRESHIP_HOOK` env var (absolute path override)
2. `$REPO_ROOT/.beadswave/pre-ship.sh`

Risk heuristics → `auto-merge:hold` (first match wins, prevents bypass):
- Touches schema/migration files
- Touches deploy/rollback scripts
- >300 line diff
- >5 files
- Bead is P0 bug/incident
- Bead body contains "requires human review" or "breaking change"

Templates: `references/templates/bd-ship.sh`, `references/templates/bd-ship-prompt.md`

## Phase 4a — Merge-wait (`scripts/merge-wait.sh <id>`)

After bd-ship sets `stage:merging`, `merge-wait.sh` takes over. It reads the PR
number from the bead's `external-ref` (`gh-<n>`) and polls until:

- **PR is MERGED** → set `stage:landed`, close bead, exit 0
- **PR is CLOSED (not merged)** → exit 3 (unexpected state)
- **PR has conflicts** → exit 22 (agent must rebase + re-run bd-ship)
- **Timeout** (default 30 min) → exit 2 (re-run with longer timeout)

```bash
scripts/merge-wait.sh <id>                     # wait up to 30 min
scripts/merge-wait.sh <id> --timeout 3600      # wait up to 60 min
scripts/merge-wait.sh <id> --json              # JSON output
```

The pipeline driver calls merge-wait automatically. For standalone use, use it
only to recover a bead that is already at `stage:merging` and already has a PR
external-ref. Do not replace it with sleep-poll loops.

## Phase 5 — Merge (direct via `gh pr merge`)

**CI mode detection:** Before reporting PR status or investigating failures, check if GitHub CI is disabled. If `.github/workflows/ci.yml` has no `push`/`pull_request` triggers (only `workflow_dispatch`), CI does not run on PRs. In CI-disabled mode:
- Do NOT report CI check failures as blockers
- Do NOT investigate CI failures
- Pre-ship checks (`.beadswave/pre-ship.sh`) are the sole quality gate
- The `auto-merge` label is proof that all local gates passed
- `monitor-prs` should track PR count, review status, merges only — skip CI analysis
- `monitor-prs --orphans` detects PRs missing the `auto-merge` label and stuck labeled PRs, then auto-remediates them
- `monitor-prs --resolve-conflicts` detects CONFLICTING PRs, auto-rebases via `gh pr update-branch`, and files beads for unresolvable conflicts when combined with `--file-beads`. **Repo prerequisite:** "Allow updates to pull request branches" must be enabled in GitHub repo settings.

bd-ship merges immediately after PR creation via `gh pr merge`. Merge method controlled by `BEADSWAVE_GH_PR_MERGE_METHOD` (default: merge). If the primary method fails, it falls back through squash, merge, rebase.

**Legacy Mergify mode:** Set `BEADSWAVE_MERGE_STRATEGY=mergify` to use Mergify queue instead of direct merge. Requires `.mergify.yml` and the Mergify GitHub App installed.

## Queue Hygiene

`scripts/queue-hygiene.sh` is the shared guardrail for both single-bead and
stream workflows. One pass does four things in order:

1. Refresh `origin/main`.
2. Run `scripts/branch-prune.sh` to drop merged branches.
3. Fail closed if workspace is still unhealthy such as missing-base,
   outside-workspace, or head-graph mismatch errors after prune.
4. Run `scripts/monitor-prs.sh --orphans --resolve-conflicts` to repair PR drift.

Use it before a bead, after a bead, and before `scripts/mass-ship.sh --auto`.
If the queue-hygiene pass fails, stop. Do not keep creating branches or pushing
new PRs on top of a corrupted workspace.

### Auto-queue from pre-ship re-runs (`scripts/queue-prs.sh`)

`bd-ship` handles tag+queue for fresh PRs, but leaves a gap when you re-run pre-ship against existing PRs (e.g. after a rebase or a composite-workspace validation). Use the reusable helper to close it from inside your repo's `.beadswave/pre-ship.sh`:

```bash
BEADSWAVE_SKILL_DIR="${BEADSWAVE_SKILL_DIR:-$HOME/.claude/skills/beadswave}"
QUEUE_PRS="$BEADSWAVE_SKILL_DIR/scripts/queue-prs.sh"

# Preflight (before gates — fail fast on typos)
"$QUEUE_PRS" verify "$QUEUE_BRANCHES" || exit 2

# …run your gates…

# Post-green (after gates)
"$QUEUE_PRS" queue "$QUEUE_BRANCHES"
```

The helper is idempotent (skips PRs already `auto-merge`-labelled), accepts comma-separated branch lists, and now requests GitHub auto-merge as the same second handoff path that `bd-ship` uses. `QUEUE_BRANCHES` typically comes from a `--queue-on-green <branches>` flag or a `PRESHIP_AUTOQUEUE_BRANCHES` env var that your repo's pre-ship script parses.

**Full copy-paste boilerplate** — drop this near the top of `.beadswave/pre-ship.sh` (after `cd "$REPO_ROOT"`, before any gates) to wire both the CLI flag and the env var plus the preflight verify:

```bash
# ── --queue-on-green <b1>[,<b2>...] / PRESHIP_AUTOQUEUE_BRANCHES ─────────
QUEUE_BRANCHES="${PRESHIP_AUTOQUEUE_BRANCHES:-}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --queue-on-green)    QUEUE_BRANCHES="${2:-}"; shift 2 ;;
    --queue-on-green=*)  QUEUE_BRANCHES="${1#*=}"; shift ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

BEADSWAVE_SKILL_DIR="${BEADSWAVE_SKILL_DIR:-$HOME/.claude/skills/beadswave}"
QUEUE_PRS="$BEADSWAVE_SKILL_DIR/scripts/queue-prs.sh"

# Fail fast before running ~8 min of gates if a branch typo slipped in.
if [[ -n "$QUEUE_BRANCHES" ]]; then
  [[ -x "$QUEUE_PRS" ]] || { echo "error: --queue-on-green requires $QUEUE_PRS" >&2; exit 2; }
  "$QUEUE_PRS" verify "$QUEUE_BRANCHES" || exit 2
  echo "▶ Auto-queue on green: ${QUEUE_BRANCHES}"
fi
```

And at the bottom, after gates pass:

```bash
if [[ -n "$QUEUE_BRANCHES" ]]; then
  echo
  echo "▶ Tagging + queueing PRs for auto-merge"
  "$QUEUE_PRS" queue "$QUEUE_BRANCHES"
fi
```

**Post-merge**: let `pipeline-driver.sh` run `queue-hygiene.sh` after the merge is confirmed. Do not improvise extra manual branch deletion, PR mutation, or bead closure steps on top.

## Safeguards

- `.githooks/pre-push` — blocks raw `git push origin main` (see `references/templates/pre-push.sh`)
- `.github/workflows/direct-push-alert.yml` — detects non-merge commits to main, files GH issue labeled `direct-push` (see `references/templates/direct-push-alert.yml`)
- `scripts/sync-gh-issues-to-beads.sh` — mirrors `direct-push` GH issues into beads as P0 incidents
- `auto-merge:hold` label — pause valve (dequeues via `queue_conditions`)
- `.auto-merge-disabled` file — full-pipeline kill switch

## Adversarial Audit Findings

The last 24 hours of real sessions across `portfolio-manager` and `mfcapp`
showed the same families of failures repeating:

- edit-without-read / stale-read tool errors from patching in a hurry
- invalid bead ids and guessed `bd`/`gh` flags
- dirty worktrees and resumed runs on top of unfinished rebases/cherry-picks
- manual recovery moves (`gh pr merge`, cherry-pick, hand-closing beads) that created worse drift than the original failure
- stale branches, stale worktrees, and beads closed before merge confirmation
- fresh worktrees missing bootstrap/deps, leading to misleading lint/test failures
- broken git refs, stale branch pointers, or worktree metadata drift that cannot be repaired by optimistic retries

The skill now biases toward fail-closed behavior:

- `queue-hygiene.sh` runs before allocation and after landing, and it stops on unsafe repo state
- `pipeline-driver.sh` resumes from `stage:shipping`, waits at `stage:merging`, and still runs cleanup for already-closed beads
- `bd-ship.sh` keeps beads open unless merge is already confirmed
- docs now treat manual PR/bead mutation as recovery anti-patterns, not shortcuts

## Determinism Limits

Beadswave can make the pipeline much more deterministic, but not perfectly so.
The main residual failure factors are external or cross-cutting:

- GitHub state: queue latency, mergeability changes, approvals, auth/session expiry
- CI/environment state: flaky runners, missing secrets, infra outages, rate limits
- local repo state outside the skill: git ref corruption, missing dependencies, stale worktrees from previous sessions
- domain coupling: two beads touching the same hotspot, migration numbering, or hidden shared ownership
- human/manual intervention outside the conveyor belt

The rule is simple: when one of those factors appears, stop progressing the
queue and surface the specific blocker. Determinism comes more from refusing bad
states than from retrying through them.

## Phase 6 — Lot shipping (batched flow)

When `bd ready` is deep and you want to ship in lots instead of one-by-one:

**`scripts/bd-lot-plan.sh`** — pick top-N ready beads ranked by priority asc, age desc, dependent_count desc. Outputs an ordered plan. Flags: `--size N`, `--priority 0,1`, `--label foo`, `--max-age DAYS`, `--json`, `--out FILE`.

**`scripts/bd-lot-ship.sh`** — takes a plan (pipe/file/CSV), stacks the branches, runs `.beadswave/pre-ship.sh` once on the combined working tree, **bisects on failure** to isolate the offender (labelled `preship-fail` or `lot-deferred`), then ships survivors individually. Flags: `--plan -`, `--ids a,b,c`, `--no-bisect`, `--hold`, `--dry-run`.

**`scripts/bd-circuit.sh`** — circuit breaker. Reads the last N GH PR outcomes; if the rolling failure rate ≥ threshold, drops the `.auto-merge-disabled` kill switch. Resets when main's last commit is `status=success` and rate is back below threshold. Flags: `--window N`, `--threshold PCT`, `--action status|trip|reset|auto`.

Typical loop:

```bash
# 1. Every hour (cron/daemon): check + auto-trip or auto-reset
scripts/bd-circuit.sh --window 20 --threshold 40 --action auto

# 2. When the breaker is green, ship a lot
scripts/bd-lot-plan.sh --size 8 --priority 0,1 --json |
  scripts/bd-lot-ship.sh --plan -

# 3. Monitor + file beads on any CI-failing PRs that leaked through
scripts/monitor-prs.sh --failing --file-beads --orphans --resolve-conflicts
```

Because lot-plan/lot-ship/circuit are thin wrappers, a repo that already has `install.sh` run gets them for free on the next adoption refresh.

## Phase 7 — Mass ship with rate-limit + queue-drain

When draining dozens of pre-shipped branches at once, naive batching saturates GitHub Actions concurrency (Team plan = 60 Linux slots; each CI run = 7 jobs → 10 PRs fan out to 70 slot demands → runners never provision → fail in 2s with `runner_id=0`, empty `steps`, 404 logs).

Two scripts pair up to handle this:

**`scripts/mass-ship.sh`** — serial batch over many branches. New `--rate-limit N` flag sleeps N seconds between ships. Default **90s** (sized for Team plan 60-slot ceiling with a 7-job pipeline: 60/7 ≈ 8 PRs in-flight → one every 90s keeps the pool draining faster than it fills). Override via `PRESHIP_RATE_LIMIT` env var. Set `--rate-limit 0` to disable.

**`scripts/queue-drain.sh`** — throttled requeue for PRs that *already* infra-failed. Detects the infra-fail signature (all non-SKIPPED CheckRuns for `$WORKFLOW_NAME` are FAILURE and completed within `--stale-seconds` of starting, default 15s). Calls `gh run rerun --failed` up to `--max-per-pass` (default 5) while staying under `--max-concurrent` (default 15) in-flight runs. `--watch N` mode loops with adaptive pacing (3× interval when throttled, 2× when idle, 1× when actively reruning).

**`scripts/mass-ship.sh`** is now the preferred stream workflow for several
already-implemented beads. Around every ship it delegates to
`scripts/queue-hygiene.sh`, so `origin/main` refresh, merged-branch pruning,
and orphan/conflict repair stay in one shared control loop. Use it instead of a
hand-written `for` loop when you need a controlled ship queue.

**Recommended pattern for a mass drain:**

```bash
# Terminal 1 — mass-ship the backlog with default 90s pacing
scripts/mass-ship.sh --auto

# Terminal 2 — watch and requeue infra-failed PRs alongside the fan-out
scripts/queue-drain.sh --watch 120
```

The rate-limit on mass-ship prevents the pool from ever getting saturated; queue-drain cleans up stragglers from prior runs or transient provisioning flakes. Drop the rate-limit (or shorten it) once you've confirmed your org's concurrency headroom.

## Adopting on a New Repo

Follow `references/adapt.md`. The checklist covers:

2. Tune `PROJECT_PREFIX`, `HOTSPOTS`, `MIGRATION_SEED`, `SHAPE_ORDER`, `FOUNDATION_TITLES` in `classifier.py`
3. Adapt risk heuristics in `bd-ship-prompt.md` to your repo's "sensitive" paths
5. (Optional, legacy mode) Install Mergify GitHub App and set `BEADSWAVE_MERGE_STRATEGY=mergify`
7. Run `setup-dev.sh` once per clone to install the pre-push hook
8. Enable "Allow updates to pull request branches" in GitHub repo Settings → General → Pull Requests (required for `--resolve-conflicts` auto-rebase)

## Reference Files

| File | Purpose |
|---|---|
| `references/pipeline-spec.md` | Conveyor belt pipeline specification — stages, state machine, enforcement, recovery |
| `references/classifier.py` | Portable Python wave classifier with tuning knobs |
| `references/coordinator.md` | Lane allocation commands (inspect, allocate, reassign, report) |
| `references/worker-prompt.md` | Worker claim prompt with `{{AGENT_NAME}}`/`{{WAVE}}`/`{{LANE}}` placeholders |
| `references/ship-pipeline.md` | bd-ship + Actions gate + direct merge architecture deep-dive |
| `references/adapt.md` | Bootstrap checklist for a new repo |
| `references/templates/bd-ship.sh` | Ship stage: rebase → gates → push → PR → queue |
| `references/templates/merge-wait.sh` | Merge-wait stage: poll until PR merged |
| `references/templates/pipeline-driver.sh` | Full pipeline orchestrator: ship → merge-wait → land (resumable) |
| `references/templates/queue-hygiene.sh` | Shared queue/workspace hygiene pass for single-bead and batch flows |
| `references/templates/bd-ship-prompt.md` | PR-creation prompt for `claude -p` |
| `references/templates/monitor-prs.sh` | PR monitor with `--orphans` auto-remediation |
| `references/templates/auto-merge-workflow.yml` | GitHub Actions gate |
| `references/templates/direct-push-alert.yml` | Direct-push detection workflow |
| `references/templates/pre-push.sh` | Client-side main-push guard |
| `references/templates/sync-gh-issues-to-beads.sh` | Alert → beads mirror |
| `references/templates/setup-dev.sh` | One-shot dev environment setup |
| `references/templates/bulk-pr-create.sh` | Batch-create PRs for branches missing PRs, label `auto-merge`, enable auto-merge |
| `references/templates/delayed-drainer.sh` | Wait N minutes then trigger backlog drain with `bd` status + ready-list output |
| `references/templates/trigger-drainer-delayed.sh` | Wait N minutes then write a `.drainer-trigger` file for Claude to detect and start draining |

## Batch Operations

Scripts for one-time bulk operations that sit outside the per-bead ship flow. Trigger them from a terminal when the backlog has accumulated many pre-shipped branches or when scheduling a delayed drain.

### `scripts/bulk-pr-create.sh`

Batch-creates PRs for local/remote branches that don't yet have PRs. For each branch:

1. Reads the tip commit message for the PR title
2. Skips branches that already have open or merged PRs
3. Creates the PR with `auto-merge` label
4. Posts `direct merge via gh pr merge` to enqueue for merge

```bash
# DRY_RUN — see what would be created
DRY_RUN=true scripts/bulk-pr-create.sh /tmp/branches-needing-prs.txt

# Create for real
scripts/bulk-pr-create.sh /tmp/branches-needing-prs.txt
```

**When to use:** After a mass agent drain where many branches were pushed but PRs weren't created (e.g. `bd-ship` was bypassed or failed at the PR step). Generate the branch list with `git branch -r | grep -v main | sed 's|origin/||' > /tmp/branches-needing-prs.txt`.

### `scripts/delayed-drainer.sh`

Waits a configurable delay (default 15 min), then prints backlog status and a ready-issue list. Designed for scheduling a drain after CI settles or after a batch of PRs merges.

```bash
# Default: 15-minute delay
scripts/delayed-drainer.sh

# Custom delay (edit DELAY_SECONDS in the script)
DELAY_SECONDS=300 scripts/delayed-drainer.sh
```

**When to use:** When you want to kick off a drain cycle after a known delay (e.g. waiting for a batch of merges to complete). The script outputs `bd ready` + `bd stats` so a Claude session can pick up the next wave. Sends a macOS notification when the timer fires.

### `scripts/trigger-drainer-delayed.sh`

Waits a configurable delay (default 30 min), then writes a `.drainer-trigger` file in the project root. A Claude session polling for this file can auto-start draining when it appears.

```bash
# Default: 30-minute delay
scripts/trigger-drainer-delayed.sh
```

**When to use:** When running a Claude session that should auto-detect when it's time to drain. The session polls for `.drainer-trigger`; when found, it starts the drain loop and deletes the trigger file. Useful for scheduling overnight or multi-hour drain windows. Sends macOS notification + alert dialog when the trigger fires.


Continuously queues mergeable PRs oldest-first with a configurable delay between each. Stops when no mergeable PRs remain (either all merged or all need rebase). Works with any GitHub repo.

```bash
# Default: 30s delay between queues

# Custom delay (60s)
```

**When to use:** After a mass drain where many PRs are queued. Run in a background terminal to keep feeding PRs for auto-merge as they become mergeable. Pairs well with rebase sessions — run this in one terminal while resolving conflicts in another. The loop exits on its own when done.
