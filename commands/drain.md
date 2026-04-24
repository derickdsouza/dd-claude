# /drain — Execute my claimed lane bead-by-bead

Work every bead in my claimed lane end-to-end (claim → TDD → commit → landing),
then loop to the next bead until the lane is empty. One branch per bead.

**Auto-bootstraps**: if this session has no allocation (its session-keyed
`.beads/.agent-*` file is missing or `bd list --label drain:<name>` returns
empty), invoke `/waves` inline before proceeding — the user doesn't need to run
/waves first.

## Steps

### 0. Bootstrap (auto-invoke /waves if needed)

```bash
SKILL="${BEADSWAVE_SKILL:-$HOME/.claude/skills/beadswave}"
RUNTIME="$SKILL/scripts/runtime.sh"
[ -f "$RUNTIME" ] || { echo "beadswave runtime missing at $RUNTIME"; exit 2; }
# shellcheck disable=SC1090
. "$RUNTIME"

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
AGENT_FILE="$(beadswave_agent_file "$REPO_ROOT")"
NEED_WAVES=false
AGENT="$(beadswave_read_agent_name "$REPO_ROOT" 2>/dev/null || true)"

if [ -z "$AGENT" ]; then
  NEED_WAVES=true
else
  OPEN_COUNT="$(bd list --status=open --label "drain:$AGENT" --json -n 0 \
    | python3 -c "import json,sys; print(len(json.load(sys.stdin)))")"
  [ "$OPEN_COUNT" -eq 0 ] && NEED_WAVES=true
fi

if [ "$NEED_WAVES" = "true" ]; then
  echo "No lane claimed — invoking /waves to allocate one…"
  # Invoke the /waves command inline (same session). Do NOT spawn a subshell
  # — /waves needs to persist the same session-keyed .beads/.agent-* file.
fi
```

Follow the `/waves` flow (steps 1–6) inline if `NEED_WAVES=true`. After /waves
completes, re-read `$AGENT_FILE` and continue to step 1.

If /waves exits 0 with "No free lanes", print:
```
Nothing to drain. Backlog empty or all lanes allocated to other agents.
```
and stop.

### 0a. Ensure we're in the agent's worktree

`/drain` operates on the current working tree, so a sibling agent's shell that
lands on the wrong worktree would clobber files. After bootstrap, verify the
cwd is inside `$AGENT`'s worktree and `cd` to it if not.

```bash
# AGENT is set from step 0 (or re-read after /waves)
if [ "${BEADSWAVE_NO_WORKTREE:-0}" = "1" ] || [ -f "$REPO_ROOT/.beadswave/no-worktree" ]; then
  echo "→ Worktree enforcement disabled (BEADSWAVE_NO_WORKTREE or .beadswave/no-worktree)"
else
EXPECTED_WT="$(beadswave_worktree_dir "$REPO_ROOT" "$AGENT")"
CURRENT_WT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

if [ "$CURRENT_WT" != "$EXPECTED_WT" ]; then
  if [ ! -d "$EXPECTED_WT/.git" ] && [ ! -f "$EXPECTED_WT/.git" ]; then
    # Worktree missing — re-provision it (safe: ensure is idempotent)
    EXPECTED_WT="$(beadswave_ensure_worktree "$REPO_ROOT" "$AGENT" origin/main)" || {
      echo "✗ Could not create worktree for $AGENT — run /waves --reclaim" >&2
      exit 6
    }
  fi
  echo "→ Switching to agent worktree: $EXPECTED_WT"
  cd "$EXPECTED_WT" || {
    echo "✗ Failed to cd into $EXPECTED_WT" >&2
    exit 6
  }
  REPO_ROOT="$EXPECTED_WT"
fi
fi  # end worktree-enforcement block
```

**Opt-out:** set `BEADSWAVE_NO_WORKTREE=1` in the environment, or create
`.beadswave/no-worktree` at the repo root, to bypass this check. Only do this
when you are the only agent draining and want to work in the main checkout.

### 1. Recover stalled in-progress beads

Before claiming new work, recover `in_progress` beads that are stale — no longer
actively worked on. Three categories, processed in order:

**a. Current agent's lane** — `in_progress` + `drain:$AGENT` label (from previous
interrupted drain of the same lane). Always safe to reset — this agent owns the lane.

**b. Current agent's assignments** — `in_progress` + assignee matches current agent
(but may lack `drain:` label, e.g. claimed directly). Reset because this is a new session.

**c. Globally orphaned** — `in_progress` beads whose assignee has no recently
updated session-keyed `.beads/.agent-*` file, AND whose `updated_at` is older
than `STALE_MINUTES` (default 60). These are likely from dead or abandoned
sessions of other agents.

```bash
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
AGENT="$(beadswave_read_agent_name "$REPO_ROOT")"
STALE_MINUTES="${STALE_MINUTES:-60}"
ACTIVE_SESSION_MINUTES="${ACTIVE_SESSION_MINUTES:-$STALE_MINUTES}"

# ── a. Current agent's lane ──────────────────────────────
LANE_STALLED=$(bd list --status=in_progress --label "drain:$AGENT" --json -n 0 2>/dev/null \
  | python3 -c "import json,sys; ds=json.load(sys.stdin); print(len(ds))" 2>/dev/null || echo "0")

if [ "$LANE_STALLED" -gt 0 ]; then
  echo "Found $LANE_STALLED in_progress bead(s) in your lane:"
  bd list --status=in_progress --label "drain:$AGENT" -n 0
  bd list --status=in_progress --label "drain:$AGENT" --json -n 0 \
    | python3 -c "import json,sys
for b in json.load(sys.stdin):
    print(b['id'])" \
    | while read -r ID; do
      bd update "$ID" --assignee ""
      echo "  reset $ID to open (lane recovery)"
    done
fi

# ── b. Current agent's assignments (any label) ──────────
ASSIGNED_STALLED=$(bd list --status=in_progress --json -n 0 2>/dev/null \
  | python3 -c "
import json, sys
beads = json.load(sys.stdin)
matching = [b for b in beads if b.get('assignee') == '$AGENT'
            and 'drain:$AGENT'.replace('\$AGENT','$AGENT') not in [l if isinstance(l,str) else l.get('name','') for l in b.get('labels',[])]]
print(len(matching))" 2>/dev/null || echo "0")

if [ "$ASSIGNED_STALLED" -gt 0 ]; then
  echo "Found $ASSIGNED_STALLED in_progress bead(s) assigned to you (outside lane):"
  bd list --status=in_progress --json -n 0 \
    | python3 -c "
import json, sys
beads = json.load(sys.stdin)
for b in beads:
    if b.get('assignee') == '$AGENT':
        drain_labels = [l if isinstance(l,str) else l.get('name','') for l in b.get('labels',[]) if (l if isinstance(l,str) else l.get('name','')).startswith('drain:')]
        if not drain_labels:
            print(b['id'])" \
    | while read -r ID; do
      bd update "$ID" --assignee ""
      echo "  reset $ID to open (agent assignment recovery)"
    done
fi

# ── c. Globally orphaned (stale, no recently-updated session file) ─────
ACTIVE_AGENTS="$(beadswave_recent_agent_names "$REPO_ROOT" "$ACTIVE_SESSION_MINUTES" | tr '\n' ' ')"

ORPHAN_COUNT=$(bd list --status=in_progress --json -n 0 2>/dev/null \
  | python3 -c "
import json, sys
from datetime import datetime, timedelta, timezone
beads = json.load(sys.stdin)
active = set('''$ACTIVE_AGENTS'''.split())
stale_min = int('''$STALE_MINUTES''' or '60')
cutoff = datetime.now(timezone.utc) - timedelta(minutes=stale_min)
orphans = []
for b in beads:
    assignee = b.get('assignee', '')
    if assignee and assignee in active:
        continue
    updated = b.get('updated_at', '')
    if updated:
        try:
            dt = datetime.fromisoformat(updated.replace('Z','+00:00'))
            if dt >= cutoff:
                continue
        except: pass
    orphans.append(b['id'])
print(len(orphans))" 2>/dev/null || echo "0")

if [ "$ORPHAN_COUNT" -gt 0 ]; then
  echo "Found $ORPHAN_COUNT globally orphaned in_progress bead(s) (stale >${STALE_MINUTES}m, no active session):"
  bd list --status=in_progress --json -n 0 \
    | python3 -c "
import json, sys
from datetime import datetime, timedelta, timezone
beads = json.load(sys.stdin)
active = set('''$ACTIVE_AGENTS'''.split())
stale_min = int('''$STALE_MINUTES''' or '60')
cutoff = datetime.now(timezone.utc) - timedelta(minutes=stale_min)
for b in beads:
    assignee = b.get('assignee', '')
    if assignee and assignee in active:
        continue
    updated = b.get('updated_at', '')
    if updated:
        try:
            dt = datetime.fromisoformat(updated.replace('Z','+00:00'))
            if dt >= cutoff:
                continue
        except: pass
    print(b['id'])" \
    | while read -r ID; do
      bd update "$ID" --assignee ""
      echo "  reset $ID to open (orphan recovery)"
    done
fi
```

**Staleness heuristic:** Category (c) considers a bead orphaned if (1) its
assignee has no recently updated session-keyed `.beads/.agent-*` file within
`ACTIVE_SESSION_MINUTES` (default: same as `STALE_MINUTES`), AND (2) the bead's
`updated_at` is older than `STALE_MINUTES` (default 60). Override with
`STALE_MINUTES=120 ACTIVE_SESSION_MINUTES=120 /drain`. Categories (a) and (b)
always reset — the agent is in a new session, so any prior in-progress work for
this agent is definitively stale.

**Risk of skipping this step:** If the agent was interrupted mid-bead (crash, session timeout, gate failure pause), the bead stays `in_progress` + assigned. The `open`-only query in the loop below never sees it. The lane appears drained when it isn't, and the bead is orphaned indefinitely — no other agent can claim it, and this agent skips it.

### 2. Read the lane

```bash
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
AGENT="$(beadswave_read_agent_name "$REPO_ROOT")"
bd list --status=open --label "drain:$AGENT" -n 0
```

Print a one-line summary: `drain:<name> · <wave> <lane> · <N> open · <N> in_progress`.

### 3. Per-bead loop

Repeat until `bd list --status=open --label drain:$AGENT -n 0` is empty:

```bash
# a. Next bead (ready = no blocking deps)
NEXT="$(bd ready --label "drain:$AGENT" --limit 1 --json \
  | python3 -c "import json,sys; ds=json.load(sys.stdin); print(ds[0]['id'] if ds else '')")"

if [ -z "$NEXT" ]; then
  # Nothing ready but lane not empty → all remaining beads are blocked on deps
  echo "Lane has blocked beads only — escalating to coordinator view:"
  bd list --status=open --label "drain:$AGENT" --json -n 0 \
    | python3 -c "<print each id + its unmet deps>"
  break
fi

# b. Claim
bd update "$NEXT" --claim || {
  echo "  ✗ $NEXT already claimed — skipping (lane conflict)"
  continue
}

# c. Read context
bd show "$NEXT"
# Note: files touched, migration:NNNN, touches-hotspot:*, dependency list.
```

For each `$NEXT`, execute the worker flow from `references/worker-prompt.md`
steps 3–8 verbatim:

  3. Run `scripts/setup-dev.sh` once per fresh clone/worktree, then resolve and run
     `scripts/queue-hygiene.sh --phase "before $NEXT"` before branching. If queue
     hygiene fails, stop the loop. Do not branch on top of a dirty, mid-rebase, or
     stale workspace. Only then create `fix/<shape>-$NEXT` from `origin/main`.
  4. **TDD**: failing test → minimal impl → green → refactor (behavior-only changes)
  5. **Migration slot** (if the bead has `migration:NNNN`): use that exact number
  6. Commit via the repo's approved VCS write path: standard non-interactive git
     commands and the repo's wrappers. Do not invent alternate frontends or ad-hoc aliases.
     The bead invariant still holds: one bead, one branch, one commit intent.
  7. Resolve the pipeline wrapper, then run it:
     ```bash
     PIPELINE_DRIVER="$(beadswave_resolve_pipeline_driver "$REPO_ROOT")" || {
       echo "✗ pipeline-driver not found. Expected repo-local scripts/pipeline-driver.sh or the skill template."
       exit 7
     }
     "$PIPELINE_DRIVER" "$NEXT"
     ```
     The pipeline driver is the only supported path from `stage:committed`
     to `stage:landed`. Do not replace it with manual `gh pr create`, manual
     `gh pr merge`, sleep-polling, or hand-closing the bead.
  8. If the pipeline exits 0, treat the bead as fully handed off. It already ran
     ship → merge-wait → queue-hygiene. Do not add extra manual close/merge/pull
     steps on top.

Emit one progress line per bead:
```
✓ <id> · <shape>/<scope> · pipeline landed
```

### 4. Pause-on-gate-failure

If `pipeline-driver.sh` exits non-zero (gate failure, merge-wait conflict/timeout,
or queue-hygiene failure):

1. **Do not skip the bead.** Print the failure output verbatim.
2. If the failure is in files outside `$NEXT`'s diff, or points at sibling branches / unassigned changes, do **not** edit those files from this bead. Treat it as a workspace-isolation problem and stop.
3. `beadswave_reset_issue_open "$NEXT"` to unclaim/reset (leaves `drain:$AGENT` label intact).
4. Add a note via `beadswave_append_issue_note "$NEXT" "drain paused: <one-line summary>"`.
5. **Stop the loop.** Surface to the user with:
   ```
   ✗ Gate failed on <id> — loop paused.
   Options: fix the issue and re-run /drain, or file a blocker bead.
   ```
6. **Do not** manually create/edit the PR, add merge labels, cherry-pick the fix
   elsewhere, sleep-poll `gh pr view`, or close the bead by hand.
7. If you have already tried 2 speculative edits, edit-state/read-state tool
   retries, or test reruns on the same bead, stop. Re-read the full failing
   file(s), the latest gate output, and the bead context before changing code
   again. Do not stack guess-fixes just to keep the
   lane moving.
8. If the workspace still is not clean after `git status`, pause the bead.
   Do not use stash or invent scratch branches to absorb foreign changes.

The user decides: fix the gate (re-run `/drain` to resume from the same bead), or
file a new blocker bead and stop the drain until the blocker is resolved.

### 5. Lane drained

When the loop exits with the lane empty:

```
LANE DONE $WAVE $LANE · <N> beads closed · 0 open · 0 in_progress
```

Then auto-invoke `/waves` inline to pick the next free lane. If none, print:
```
Backlog drained. Nothing left to claim.
```
and stop.

### 6. PR monitor reminder

If no other terminal is already running `monitor-prs`, print:
```
Tip: open a new terminal and run `/loop monitor-prs` to auto-file beads for
failed PRs as they appear.
```

## Flags

| Flag | Effect |
|---|---|
| `--once` | Execute one bead only, then stop (for debugging the flow) |
| `--dry-run` | Show what would be shipped; do not write |

## Environment variables

| Variable | Default | Effect |
|----------|---------|--------|
| `STALE_MINUTES` | `60` | Globally orphaned in-progress beads older than this are reset to open |
| `ACTIVE_SESSION_MINUTES` | `STALE_MINUTES` | Session-keyed `.beads/.agent-*` files newer than this count as active owners during orphan recovery |

## Guardrails

- Follow every rule in `references/worker-prompt.md`:
  - Stay in the lane — never touch a bead not labeled `drain:$AGENT`.
  - Use the repo's approved VCS write path — never shortcut around the conveyor belt.
  - One branch per bead — never bundle.
  - TDD: failing test first, minimal implementation, refactor only while green.
  - Code files ≤275 lines; commits ≤5 files / ≤300 lines.
- Resolve the landing path deterministically. Prefer the repo's
  `scripts/pipeline-driver.sh`; only fall back to the skill template when the
  repo wrapper is missing.
- On market-hours deploys: blocked automatically by `scripts/pm-commands/_config.sh`
  and the Actions gate. Never set `PM_CONFIRM_MARKET_HOURS=true` without human approval.
- Beads is the only task tracker. Never use TodoWrite/TaskCreate.
- Session-state files under `.beads/` are not bead content. Never stage or commit them.
- **No bead, no ship.** Every commit that reaches `main` must trace to a bead — no
  exceptions for hotfixes, typos, config tweaks, or infra changes. For emergencies,
  `bd create --title="hotfix: X" --type=bug --priority=0` takes seconds and keeps
  the audit trail intact. Only local-only branches that are never merged are exempt.
- **No claim, no ship.** `bd-ship` enforces that the bead is `in_progress` before
  it will proceed. A bead is only `in_progress` after being claimed by `/drain` or
  `/bw-work`. You cannot ship a bead that was never properly claimed.

## When to use

- After `/waves` has claimed a lane (or as the single-command entry — `/drain` will auto-invoke `/waves`).
- To resume after a gate failure once you've fixed the issue.
- To continue draining after the PR monitor files new beads into your lane.

## Related

- `/waves` — inspect allocation map, claim a lane
- `/loop monitor-prs` — watch submitted PRs, file beads for failures
- `references/orchestrator.md` — full flow + recovery procedures
- `references/worker-prompt.md` — per-bead worker steps (drain inlines these)
