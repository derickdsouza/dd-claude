# /waves — Classify, allocate, and claim a lane

Inspect the beads backlog, classify any un-labeled beads into `wave/lane/shape/scope`,
allocate a free lane to this terminal, and show the drained-map. The default flow
makes a worker-ready; follow with `/drain` to start executing.

This command is idempotent. Running it again on an already-claimed lane just shows
the map; running it with a fresh terminal picks the next free lane.

## Steps

### 1. Verify skill + auto-adopt repo

```bash
SKILL="${BEADSWAVE_SKILL:-$HOME/.claude/skills/beadswave}"
[ -d "$SKILL" ] || { echo "beadswave skill missing at $SKILL"; exit 2; }

# Silent auto-adopt if any of scripts/bd-ship.sh is missing.
if ! bash "$SKILL/references/templates/install.sh" --check; then
  bash "$SKILL/references/templates/install.sh" --quiet || exit $?
fi
```

### 1a. Refresh templates (when `--refresh` flag is passed)

Skip all other steps. Cross-check local scripts and templates against the
global skill, report drift, and sync if needed. This keeps per-repo files
in lockstep with the evolving global skill without manual copy-paste.

```bash
SKILL="${BEADSWAVE_SKILL:-$HOME/.claude/skills/beadswave}"
INSTALL="$SKILL/references/templates/install.sh"
[ -f "$INSTALL" ] || { echo "install.sh missing at $INSTALL"; exit 2; }

# Re-run auto-adopt first to pick up any newly-added registry entries
# (new templates added to the global skill since last adopt).
bash "$INSTALL" --quiet

# Now check drift — compares tracked template SHAs against the manifest.
if bash "$INSTALL" --check-drift; then
  echo "All templates up-to-date. Nothing to refresh."
else
  echo "Drift detected — syncing from global skill…"
  bash "$INSTALL" --sync --yes
  echo ""
  echo "Refresh complete. Review .bak files for any local customizations that"
  echo "  need merging back into the synced copies."
fi
```

**What it checks:**
- The `TEMPLATE_REGISTRY` in `install.sh` is the single source of truth. Each
  entry has a `drift-mode`: `tracked` (auto-synced) or `customize` (copied once,
  expected to diverge — e.g. `.beads/prompts/create-pr.md`, `.beadswave/pre-ship.sh`).
- Symlinks (wrappers in `scripts/`) always point to the live global skill, so
  they never drift — only copied templates can.
- After sync, `.bak` files preserve the previous version. The agent should review
  these for any project-specific customizations that need re-applying.

**When to use:** After updating the global skill (`~/.claude/skills/beadswave/`),
or at the start of a session when the skill was recently changed.

### 1b. Bulk-approve PRs (when `--approve` flag is passed)

Skip all other steps. Approve every open PR using
the two GitHub accounts configured in `gh`. For each PR, the account that did
NOT push the last commit provides the approval — satisfying the
`require_last_push_approval` ruleset when a non-self approval is possible.

```bash
SKILL="${BEADSWAVE_SKILL:-$HOME/.claude/skills/beadswave}"
SCRIPT="$SKILL/references/templates/bulk-approve-prs.sh"
[ -f "$SCRIPT" ] || { echo "bulk-approve-prs.sh missing at $SCRIPT"; exit 2; }

# Check that two accounts are authenticated
ACCT_COUNT=$(gh auth status 2>&1 | grep -c 'Logged in to github.com account')
if [ "$ACCT_COUNT" -lt 2 ]; then
  echo "Need two GitHub accounts. Current:"
  gh auth status
  echo ""
  echo "Add a second account: gh auth login --hostname github.com -p ssh -u <user>"
  exit 2
fi

bash "$SCRIPT"
```

**What it does:**
- Detects the repo and both `gh` accounts automatically
- For each open PR: finds the last pusher, switches to the
  other configured account, and posts an approval review
- Skips PRs already approved by the correct user
- Skips impossible two-account cases where the only legal reviewer would be
  the PR opener, and skips PRs whose last pusher is outside the configured pair
- Supports `--dry-run` to preview without writing

**When to use:** After a batch of PRs are shipped via bd-ship and need approval
before they can be merged. Run `/waves --approve` to clear the queue.

### 1c. Queue hygiene preflight

Before classifying or allocating anything, prove the workspace is healthy.
`/waves` should not hand out new work on top of stale branches, mid-rebase
state, or orphaned PR drift.

```bash
RUNTIME="$SKILL/scripts/runtime.sh"
[ -f "$RUNTIME" ] || { echo "beadswave runtime missing at $RUNTIME"; exit 2; }
# shellcheck disable=SC1090
. "$RUNTIME"
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

QUEUE_HYGIENE="$(beadswave_resolve_queue_hygiene "$REPO_ROOT")" || {
  echo "queue-hygiene resolver missing. Re-run /waves --refresh or repair beadswave adoption." >&2
  exit 2
}

"$QUEUE_HYGIENE" --phase "waves preflight" || {
  echo "✗ Queue hygiene failed. Stop and repair the workspace before allocating a lane." >&2
  exit 6
}
```

### 2. Assign an agent name (sticky per session)

Each terminal/pane/session gets a stable name via the beadswave runtime helper,
persisted to a session-keyed `.beads/.agent-*` file. This avoids shell-PID drift
when slash commands hop across new `bash` processes. Do not hand-roll `.agent-$$`
or PID-based files — the runtime owns this state.

**Max 25 beads per agent.** If all existing agents are at or near capacity,
new agent names are generated beyond the initial pool.

```bash
MAX_PER_AGENT=25
POOL=(alpha beta gamma delta epsilon zeta eta theta iota kappa)
RUNTIME="$SKILL/scripts/runtime.sh"
[ -f "$RUNTIME" ] || { echo "beadswave runtime missing at $RUNTIME"; exit 2; }
# shellcheck disable=SC1090
. "$RUNTIME"
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
AGENT="$(beadswave_read_agent_name "$REPO_ROOT" 2>/dev/null || true)"

if [ -z "$AGENT" ]; then
  # Scan all drain:* labels and count beads per agent
  AGENT_LOAD="$(bd list --status=open --label-pattern 'drain:*' --json -n 0 \
    | python3 -c "
import json,sys
ds = json.load(sys.stdin)
from collections import Counter
counts = Counter()
for d in ds:
    for l in (d.get('labels') or []):
        if l.startswith('drain:'):
            counts[l.split(':',1)[1]] += 1
for name, cnt in sorted(counts.items()):
    print(f'{name}\t{cnt}')
')"
  )

  # Find first pool name under the cap
  AGENT=""
  USED_MAP="$(echo "$AGENT_LOAD" | awk -F'\t' '{print $1, $2}')"
  for name in "${POOL[@]}"; do
    COUNT=$(echo "$AGENT_LOAD" | awk -F'\t' -v n="$name" '$1==n{print $2}')
    if [ -z "$COUNT" ] || [ "$COUNT" -lt "$MAX_PER_AGENT" ]; then
      AGENT="$name"; break
    fi
  done

  # Pool exhausted — generate new names (agent-N)
  if [ -z "$AGENT" ]; then
    N=1
    while true; do
      CANDIDATE="agent-$N"
      COUNT=$(echo "$AGENT_LOAD" | awk -F'\t' -v n="$CANDIDATE" '$1==n{print $2}')
      if [ -z "$COUNT" ] || [ "$COUNT" -lt "$MAX_PER_AGENT" ]; then
        AGENT="$CANDIDATE"; break
      fi
      N=$((N + 1))
    done
  fi

  beadswave_write_agent_name "$AGENT" "$REPO_ROOT"
fi
echo "Agent: $AGENT"
```

### 3. Classify un-labeled beads (incremental)

Only classify beads that are missing `wave:*` or `lane:*` labels — never re-label
already-classified work.

```bash
# Lock while classifying so two terminals don't double-label.
# Use the runtime lock helper instead of `flock` or PID files so this works on macOS.
LOCKDIR="$(beadswave_lock_dir "$REPO_ROOT" waves)"
if ! beadswave_lock_acquire "$LOCKDIR"; then
  echo "Another /waves run is already holding $LOCKDIR. Retry in a moment."
  exit 5
fi
trap 'beadswave_lock_release "$LOCKDIR"' EXIT

UNLABELED="$(bd list --status=open --json -n 0 \
  | python3 -c "
import json,sys
ds = json.load(sys.stdin)
out = [d for d in ds if not any((l.startswith('wave:') or l.startswith('lane:')) for l in (d.get('labels') or []))]
print(len(out))
json.dump(out, open('/tmp/bd_unlabeled.json','w'))
)"
)"

if [ "$UNLABELED" -gt 0 ]; then
  echo "Classifying $UNLABELED un-labeled beads…"
  BD_SNAPSHOT=/tmp/bd_unlabeled.json python3 "$SKILL/references/classifier.py"
  bash /tmp/apply_labels.sh
else
  echo "All beads already classified."
fi
```

If the repo has a project-specific classifier override (check for
`docs/beadswave-strategy/operations.md` section "Classifier tuning" and any
`scripts/classifier-overrides.py`), prefer the project override.

### 4. Allocate a free lane to this agent

**Rules:**
- **Max 25 beads per agent.** If a lane has more than 25 beads, it still goes to one agent (lanes are not split). But the agent won't get a second lane.
- **Never split lanes.** All beads in a `(wave, lane)` pair go to the same agent.
- **If this agent is already at 25**, skip allocation and print guidance to spin up a new terminal (which gets a fresh agent name from step 2).

```bash
MAX_PER_AGENT=25

# Count how many beads this agent already has
CURRENT_COUNT="$(bd list --status=open --label "drain:$AGENT" --json -n 0 \
  | python3 -c "import json,sys; print(len(json.load(sys.stdin)))")"

if [ "$CURRENT_COUNT" -ge "$MAX_PER_AGENT" ]; then
  echo "Agent $AGENT already has $CURRENT_COUNT beads (max $MAX_PER_AGENT)."
  echo "Open a new terminal and run /waves to spawn a fresh agent."
  exit 0
fi

# Still holding the .waves.lockdir from step 3
bd list --status=open --json -n 0 \
  | python3 -c "
import json,sys
from collections import defaultdict
ds = json.load(sys.stdin)
free = defaultdict(list)
for d in ds:
    labels = d.get('labels') or []
    if any(l.startswith('drain:') for l in labels): continue
    wave = next((l for l in labels if l.startswith('wave:')), None)
    lane = next((l for l in labels if l.startswith('lane:')), None)
    if wave and lane:
        free[(wave, lane)].append(d['id'])
# Sort: lowest wave first, then largest lane (to keep big work batched)
items = sorted(free.items(), key=lambda kv: (kv[0][0], -len(kv[1])))
if not items:
    print('NONE')
else:
    (w,l), ids = items[0]
    print(f'{w}\t{l}\t{len(ids)}')
    open('/tmp/claim.ids','w').write('\n'.join(ids) + '\n')
" > /tmp/claim.tsv

if grep -q '^NONE' /tmp/claim.tsv; then
  echo "No free lanes. All allocated or backlog drained."
  exit 0
fi

WAVE="$(cut -f1 /tmp/claim.tsv)"
LANE="$(cut -f2 /tmp/claim.tsv)"
COUNT="$(cut -f3 /tmp/claim.tsv)"
while IFS= read -r id; do
  [ -n "$id" ] || continue
  bd update "$id" --add-label "drain:$AGENT"
done < /tmp/claim.ids

beadswave_lock_release "$LOCKDIR"
trap - EXIT
echo "Claimed: $WAVE $LANE → drain:$AGENT ($COUNT beads)"
if [ "$COUNT" -ge "$MAX_PER_AGENT" ]; then
  echo "  Lane has $COUNT beads (at/over cap of $MAX_PER_AGENT). This agent will not receive more lanes."
fi
```

### 5. Create an isolated worktree for this agent

After claiming the lane, provision a dedicated git worktree so parallel agents
never share a working tree. The worktree is keyed to the agent name, so the
same agent resuming in a new session reuses the same directory.

```bash
# $AGENT is set from step 2; $REPO_ROOT was set earlier via runtime.sh
WORKTREE="$(beadswave_ensure_worktree "$REPO_ROOT" "$AGENT" "origin/main")" || {
  echo "✗ Failed to create worktree for $AGENT" >&2
  echo "  Check for stale entries with: git worktree list" >&2
  exit 6
}
echo "Worktree: $WORKTREE (branch drain/$AGENT)"
```

**Notes:**
- Worktree path: `<parent>/<repo>-<agent>/` next to the main clone.
- Branch: `drain/<agent>` — long-lived lane branch; per-bead `fix/<shape>-<id>`
  branches are still created off this at ship-time by `/drain`.
- If the worktree already exists, `beadswave_ensure_worktree` is a no-op.
- Fresh worktrees need their own `scripts/setup-dev.sh` run (node_modules,
  `.env`, podman ports). `/drain` bootstraps this on first entry.

One branch per **bead** (not per lane), per the design. The per-bead branch is
created at ship-time by `/drain` using `fix/<shape>-<bead-id>` off `drain/<agent>`.

### 6. Show the drained-map

Print a table of all agents + their lanes + progress, and what this terminal
owns. Use the coordinator inspect query from `references/coordinator.md`
command 1.

Also print workspace branch health:

```bash
BRANCH_COUNT="$(git branch --list 'fix/*' | wc -l | tr -d ' ')"
MERGED_COUNT="$(git branch --merged origin/main --list 'fix/*' | wc -l | tr -d ' ')"
echo "Workspace: $BRANCH_COUNT branches ($MERGED_COUNT merged, pruneable)"
if [ "$BRANCH_COUNT" -gt 50 ]; then
  echo "  >50 branches — run scripts/branch-prune.sh before draining"
fi
```

Then print:

```
You are drain:$AGENT on $WAVE $LANE
  - Beads claimed: <count>
  - Worktree:      $WORKTREE
  - Next:          cd $WORKTREE && /drain
```

If the current shell is not already inside `$WORKTREE`, the final message must
remind the user to `cd` before running `/drain`, since `/drain` operates on the
current working tree.

## Flags

| Flag | Effect |
|---|---|
| `--map` | Skip allocation; just show the current map |
| `--release` | Release this terminal's allocation (`bd update --remove-label drain:$AGENT` for every open bead), remove the agent's git worktree (`beadswave_remove_worktree`), and forget the agent name |
| `--reclaim` | Force re-pick a new lane (release current + allocate fresh, reuses or re-creates the worktree) |
| `--no-worktree` | Skip worktree creation (use current working tree — only safe for single-agent drains) |
| `--agent <name>` | Override the auto-assigned agent name (use when resuming a previous session) |
| `--refresh` | Cross-check local templates against global skill, sync drifted files; skip classification/allocation |
| `--approve` | Bulk-approve all open PRs using the two configured GitHub accounts; skip classification/allocation |

## Rules

- **Max 25 beads per agent.** An agent can have at most 25 beads across all its lanes. When an agent hits the cap, open a new terminal — step 2 auto-generates a fresh agent name.
- **Never split lanes.** All beads in a `(wave, lane)` pair go to one agent, even if the lane exceeds 25 beads. The cap prevents a *second* lane, not assignment within the first.
- Wave order: drain `wave:0` before `wave:1`. Step 4's sort enforces this — the lowest free wave is picked first.
- Never touch an already-allocated lane. Labels are sacred.
- `migration:NNNN` labels are sacred — classifier pre-allocates; do not rename.
- The `.beads/.agent-*` file is session-keyed state, not shell-PID state. Delete it to forget.
- The `.beads/.waves.lockdir` directory is transient. If /waves crashes while holding it, `rmdir .beads/.waves.lockdir` and retry.

## When to use

- First time on a new repo (triggers auto-adopt)
- Starting a fresh terminal to join a multi-agent drain
- Checking the map of who owns what (`--map`)
- Rotating lanes when stuck (`--reclaim`)
- After updating the global skill — sync per-repo templates (`--refresh`)
- After a batch of PRs shipped — bulk-approve for merge (`--approve`)

## Related

- `/drain` — execute your claimed lane
- `references/orchestrator.md` — full flow + recovery procedures
- `references/coordinator.md` — manual coordinator commands
