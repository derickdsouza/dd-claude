# /bw-land — Resume landing or run cleanup recovery

`/bw-work` and `/drain` already call `pipeline-driver.sh`. `/bw-land` exists for
recovery: resume a bead that is already in flight, or run a repo-wide cleanup
pass when prior sessions left merged branches, stale worktrees, or open beads
behind.

## Usage

```bash
/bw-land              # infer the bead id from the current branch and resume landing
/bw-land <id>         # resume/recover one bead via pipeline-driver
/bw-land --all        # repo-wide cleanup/recovery pass
/bw-land --dry-run    # preview the repo-wide recovery targets
```

## Rules

- Prefer `scripts/pipeline-driver.sh <id>` for single-bead recovery. It is the
  authoritative resumable path for `stage:shipping`, `stage:merging`, and
  post-merge cleanup.
- Run `scripts/queue-hygiene.sh` before any repo-wide cleanup. If it fails,
  stop. Do not keep closing beads or pruning branches on top of an unhealthy
  workspace.
- Never manually `gh pr merge`, `gh pr edit --head`, `git cherry-pick`, or
  close a bead unless the PR is confirmed merged.

## Single-bead mode

### 1. Resolve runtime, repo, and bead id

```bash
SKILL="${BEADSWAVE_SKILL:-$HOME/.claude/skills/beadswave}"
RUNTIME="$SKILL/scripts/runtime.sh"
[ -f "$RUNTIME" ] || { echo "beadswave runtime missing at $RUNTIME"; exit 2; }
# shellcheck disable=SC1090
. "$RUNTIME"

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$REPO_ROOT"
```

- If `<id>` was provided, use it.
- Otherwise infer from the current branch suffix:
  `fix/<shape>-<project-prefix-id>` → `<project-prefix-id>`.

### 2. Resume the conveyor belt

```bash
PIPELINE_DRIVER="$(beadswave_resolve_pipeline_driver "$REPO_ROOT")" || {
  echo "pipeline-driver resolver missing. Re-run /waves --refresh or repair beadswave adoption." >&2
  exit 2
}

"$PIPELINE_DRIVER" "$BEAD_ID"
```

Interpretation:

- Exit `0`: the bead is landed, or cleanup completed for an already-closed bead.
- Exit `2`: merge-wait timed out. Leave the bead open at `stage:merging` and
  resume later; do not close it manually.
- Exit `22`: merge conflicts. Rebase/fix through the owning bead branch, then
  re-run `/bw-land <id>` or `pipeline-driver.sh <id>`.
- Exit `23`: post-merge queue hygiene failed. Fix the workspace first.

## `--all` mode

Use this only for session recovery or backlog cleanup, not as the normal path.

### 1. Queue-hygiene preflight

```bash
QUEUE_HYGIENE="$(beadswave_resolve_queue_hygiene "$REPO_ROOT")" || {
  echo "queue-hygiene resolver missing. Re-run /waves --refresh or repair beadswave adoption." >&2
  exit 2
}

"$QUEUE_HYGIENE" --phase "bw-land preflight"
```

### 2. Find merged-but-open beads

Inspect open beads with `external-ref` values like `gh-123`. For each one:

- If the PR is still open: skip it.
- If the PR is merged and the bead is at `stage:merging`: run
  `scripts/pipeline-driver.sh <id>` to finish the landing path.
- If the PR is merged and the bead has no trustworthy stage label: close it only
  after GitHub confirms the merge, then note that this was recovery from drift.

Example recovery query:

```bash
bd list --status=open --json -n 0 \
  | python3 -c "
import json, sys
for bead in json.load(sys.stdin):
    refs = bead.get('external_refs') or []
    for ref in refs:
        value = ref.get('ref', '')
        if value.startswith('gh-'):
            print(bead['id'], value[3:])
            break
"
```

Then verify each PR with `gh pr view <n> --json state,mergedAt` before taking
any close action.

### 3. Final hygiene pass

After all recoverable merged beads are handled, run:

```bash
"$QUEUE_HYGIENE" --phase "bw-land final"
```

## Summary output

For a single bead:

```text
Landed <id> via pipeline-driver
  Result: landed | still merging | cleanup failed
```

For `--all`:

```text
Recovery pass complete
  Merged beads resumed: <N>
  Already clean: <N>
  Skipped (open PR / ambiguous state): <N>
```

## Related

- `/bw-work <id>` — normal single-bead path
- `/drain` — normal stream path
- `/bw-monitor` — PR health and orphan/conflict repair
