# Orchestrator — Auto-Adopt + /waves + /drain Flow

The beadswave pipeline is driven by two slash commands and an installer. This
document explains how they compose, where state lives, and how to recover from
common failures.

## Command map

| Command | Purpose | State writes |
|---|---|---|
| `/waves` | Auto-adopt repo · classify un-labeled beads · claim a free lane · show map | `.beads/.agent-<session-key>` · `drain:<name>` labels · template files |
| `/drain` | Loop through claimed lane bead-by-bead; ship each via `bd-ship` | Commits · branches · PRs · bead closures |
| `/loop monitor-prs` | Watch all submitted PRs; file beads for failures | New beads labeled `pr-failure` |
| `scripts/queue-hygiene.sh` | Refresh `origin/main` · prune merged branches · repair orphaned/stuck/conflicting PRs | None (repo/queue hygiene only) |

All three are idempotent and safe to re-run.

## State files

| Path | Lifetime | Owner | Purpose |
|---|---|---|---|
| `.beads/.agent-<session-key>` | Terminal/pane session | /waves | Sticky agent name for this session |
| `.beads/.waves.lockdir` | Transient (held during classify + allocate) | /waves | atomic `mkdir` prevents racing terminals without `flock` |
| `drain:<name>` labels | Until bead closed | /waves + /drain | Allocation record |
| `.beads/auto-pr.log` | Append-only | `bd-ship` | Ship event log |
| `.auto-merge-disabled` | User-managed | — | Global kill switch |

The skill's shared `scripts/runtime.sh` provides the stable session key,
repo-local `bd-ship` resolution, and shared pre-ship gate helpers.

## Full flow (first-time + subsequent terminals)

```
┌──────────────────────────────────────────────────────────────────┐
│ Terminal 1 (first use on a fresh repo)                           │
├──────────────────────────────────────────────────────────────────┤
│ user: /waves                                                     │
│   ├── install.sh --check → fails → install.sh --quiet            │
│   │    ├── copy auto-merge.yml, pre-push hook…                   │
│   │    ├── write scripts/bd-ship.sh (thin wrapper)               │
│   │    └── ✓ adopted                                             │
│   ├── pick agent name: alpha                                     │
│   ├── mkdir .beads/.waves.lockdir                                │
│   ├── classifier.py on un-labeled beads → apply labels           │
│   ├── pick lowest free (wave, lane) → add drain:alpha            │
│   └── rmdir .beads/.waves.lockdir                                │
│                                                                   │
│ user: /drain                                                     │
│   └── loop:                                                      │
│       for each ready bead in drain:alpha:                        │
│         bd claim → queue-hygiene → TDD → git commit → bd-ship    │
│           → git checkout main → git pull → queue-hygiene         │
│       when lane empty → /waves (auto) → next lane or STOP        │
└──────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────┐
│ Terminal 2 (joining the drain)                                    │
├──────────────────────────────────────────────────────────────────┤
│ user: /drain         (no /waves needed — auto-bootstraps)         │
│   ├── no .beads/.agent-<session-key> → invoke /waves inline      │
│   │   ├── install.sh --check → already adopted, skip             │
│   │   ├── pick agent name: beta (alpha is taken)                 │
│   │   ├── mkdir .beads/.waves.lockdir                            │
│   │   ├── classify (no-op — already classified)                  │
│   │   └── claim next free lane                                   │
│   └── start the drain loop                                       │
└──────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────┐
│ Terminal 3 (PR monitor, runs forever)                             │
├──────────────────────────────────────────────────────────────────┤
│ user: /loop monitor-prs                                          │
│   └── every 5 min:                                               │
│       scripts/monitor-prs.sh --failing --file-beads              │
│       (files beads labeled pr-failure; drain terminals pick up)  │
└──────────────────────────────────────────────────────────────────┘
```

## Agent name pool

```
alpha · beta · gamma · delta · epsilon · zeta · eta · theta · iota · kappa
```

Each terminal picks the first pool name not currently assigned to any open bead.
If all 10 are taken, /waves keeps going with `agent-1`, `agent-2`, ... so the
pool never hard-stops the drain. The cap is still enforced per agent (one lane,
max 25 beads), but name exhaustion is no longer a blocker.

Names are sticky per terminal/pane session via `.beads/.agent-<session-key>`.
The session key comes from `scripts/runtime.sh` and prefers an explicit slot or
session ID, then falls back to TTY, then finally PID only as a last resort. To
deliberately resume a prior session, re-create the file:
```bash
echo alpha > .beads/.agent-<session-key>
```

## Classification rules (enforced by classifier.py)

| Label | Set by | Rule |
|---|---|---|
| `wave:0` | classifier | Foundation (≥4 beads reference it OR title matches FOUNDATION_TITLES) |
| `wave:1` | classifier | Single file, no hotspot, no migration |
| `wave:2` | classifier | Hotspot-touching OR migration-producing |
| `wave:4` | classifier | ≥4 files OR known BIG_FILE |
| `wave:9` | classifier | No file paths discoverable — worker reclassifies on claim |
| `lane:A..Z` | classifier | Disjoint file sets inside a wave |
| `shape:<kind>` | classifier | First regex match from SHAPE_ORDER |
| `scope:<pkg>` | classifier | Derived from file paths |
| `migration:NNNN` | classifier | Pre-allocated from MIGRATION_SEED; **never renamed** |
| `drain:<name>` | /waves coordinator | Allocation record |
| `pr-failure` | monitor-prs.sh | New bead filed for a failing PR |

## Allocation invariants

- One lane per agent at a time. /waves picks the **lowest free wave**, then
  the **largest free lane** inside that wave.
- Wave ordering: /waves will not allocate `wave:1` while any `wave:0` bead is
  still open — foundations drain first.
- Lanes are file-disjoint within a wave. Cross-wave collisions are allowed;
  drain the earlier wave first.
- `drain:<name>` labels follow the bead, not the terminal. A terminal that
  closes mid-drain leaves the labels intact; a new terminal with `--agent <name>`
  resumes.

## Failure recovery

### "No free lanes"

Every allocated bead is owned by some agent. Options:
1. Wait — running agents will close beads and free lanes.
2. `/waves --release` in an idle terminal to return its allocation to the pool.
3. `/waves --reclaim` to swap your terminal's lane for a different free one.

### "Lane has blocked beads only"

All remaining beads in your lane have unmet dependencies. The blocking beads
are in a different lane. /drain surfaces the dep list; typical resolution:
1. Wait for the other lane's agent to close the blockers.
2. Or, escalate — the coordinator (you) reassigns the blockers to your lane
   via `bd update <blocker> --remove-label drain:<other> --add-label drain:<self>`.
   Only do this if the other lane is genuinely stalled.

### Gate failure (lint/typecheck/test/PR-create)

`/drain` pauses. The failing bead is left **un-claimed** (`assignee=""`) but
still labeled `drain:<name>`. Two paths:
1. **Fix the gate**: edit the code, re-run `/drain` — it picks the bead back up
   from the same point (no need to reclaim).
2. **File a blocker bead**: `bd create --title "…" --deps "blocks:<failing-bead-id>"`
   and stop the drain until the blocker is fixed. Do not manually create/edit
   the PR or close the failing bead by hand.

### Stale branches, merge conflicts

When the workspace starts accumulating merged branches or orphaned PRs, run:

```bash
scripts/queue-hygiene.sh --phase "before <bead-or-batch>"
```

That single pass refreshes `origin/main`, runs `scripts/branch-prune.sh`,
repairs orphaned/stuck/conflicting PRs via `scripts/monitor-prs.sh`. Use it before a
new bead, after each successful ship, and before `scripts/mass-ship.sh --auto`.

### `.beads/.waves.lockdir` stuck

Only one /waves can classify/allocate at a time. If a terminal crashed mid-run:
```bash
rmdir .beads/.waves.lockdir
```
Then re-run `/waves`.

### Subagent rate limits

If an audit or verification session starts returning `429` rate-limit errors,
that is a stop signal. Do not keep spawning parallel subagents from inside a
worker. Back off to a smaller batch or continue serially; beadswave's intended
parallelism is lane-level, not nested fan-out inside one bead.

### Direct push to main detected

The pre-push hook blocks it client-side. If it slipped through (hook not
installed), the `direct-push-alert.yml` workflow files a GH issue labeled
`direct-push`. `sync-gh-issues-to-beads.sh` (cron or manual) mirrors it into
beads as a P0 incident. Triage like any other bead.

## Idempotency guarantees

Every command can be safely re-run:

- `install.sh` — checks existence before writing; `--check` is read-only.
- `/waves` — re-runs on an already-claimed terminal just show the map; with
  `--reclaim` it atomically swaps lanes under the lock directory.
- `/drain` — auto-bootstraps via /waves if allocation lost; resumes from the
  next unclaimed bead in the lane on every invocation.
- Classifier — only labels un-labeled beads; `migration:NNNN` is never renamed.

## Where to edit what

| Change | File |
|---|---|
| Allocation algorithm (wave ordering, lane selection) | `~/.claude/commands/waves.md` step 4 |
| Per-bead worker loop | `~/.claude/commands/drain.md` step 2 |
| Adoption file list | `~/.claude/skills/beadswave/references/templates/install.sh` |
| Project-specific classifier tuning | Repo `docs/beadswave-strategy/operations.md` |
| Risk heuristics for `auto-merge:hold` | Repo `.beads/prompts/create-pr.md` |
| Lint/typecheck/test commands | Repo `.beadswave.env` |

## Related

- `SKILL.md` — top-level skill entry
- `adapt.md` — manual adoption (what install.sh automates)
- `coordinator.md` — manual lane allocation (what /waves automates)
- `worker-prompt.md` — per-bead steps (what /drain inlines)
- `ship-pipeline.md` — bd-ship + Actions deep-dive
- `pipeline-spec.md` — conveyor belt pipeline specification
