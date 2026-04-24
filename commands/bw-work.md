# /bw-work — Implement a single bead end-to-end

Implement one bead: read it, create a branch, TDD, commit, and run it through
the conveyor belt to PR/merge/cleanup.
No lane allocation, no wave classification — just one bead through the full pipeline.

## Usage

```
/bw-work <bead-id>          # Full flow: read → branch → TDD → commit → pipeline-driver
/bw-work <bead-id> --impl   # Stop after commit (skip shipping/landing, for manual review)
```

## Steps

### 1. Validate and read the bead

```bash
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
SKILL="${BEADSWAVE_SKILL:-$HOME/.claude/skills/beadswave}"
RUNTIME="$SKILL/scripts/runtime.sh"
[ -f "$RUNTIME" ] || { echo "beadswave runtime missing at $RUNTIME"; exit 2; }
# shellcheck disable=SC1090
. "$RUNTIME"

PIPELINE_DRIVER="$(beadswave_resolve_pipeline_driver "$REPO_ROOT" 2>/dev/null)" || {
  echo "pipeline-driver not found. Run /waves --refresh or repair beadswave adoption first."; exit 2;
}
```

Show the bead details. The user provides the bead ID as the first argument.
Read it with `bd show <id>` and extract: title, description, files to touch,
labels (migration:NNNN, touches-hotspot:*), dependencies.

If the bead does not exist or is closed, stop and surface the error.

### 2. Claim the bead

```bash
bd update "<id>" --claim
```

If already claimed by another agent, stop and tell the user. Do not force-claim.

### 3. Sync and create branch

```bash
[ -x scripts/setup-dev.sh ] && scripts/setup-dev.sh

QUEUE_HYGIENE="$(beadswave_resolve_queue_hygiene "$REPO_ROOT" 2>/dev/null || true)"
[ -n "$QUEUE_HYGIENE" ] && "$QUEUE_HYGIENE" --phase "before <id>"

git fetch origin main --prune

# Branch name convention: fix/<shape>-<bead-id>
# Derive <shape> from bead labels (shape:fix, shape:feat, shape:refactor, etc.)
# Fall back to "fix" if no shape label.
git checkout -b "fix/<shape>-<id>" origin/main
```

Before creating the branch, check branch count:
```bash
BRANCH_COUNT="$(git branch --list 'fix/*' | wc -l | tr -d ' ')"
if [ "$BRANCH_COUNT" -gt 50 ]; then
  bash "$SKILL/references/templates/branch-prune.sh"
fi
```

### 4. Implement via TDD

Read the bead description and files to touch. Implement using TDD:

1. Write a failing test that captures the bead's requirement
2. Write minimal implementation to make the test pass
3. Refactor only after green (behavior-only changes)
4. Respect file limits: code files <=275 lines, commits <=5 files / <=300 lines

If the bead has a `migration:NNNN` label, use that exact migration number.

### 5. Commit

```bash
# Use the repo's approved VCS write path.
# Example only: raw git is allowed only where the repo policy permits it.
git add <owned-files>
git commit -m "<type>(<scope>): <description> — <id>"
```

Commit message format: `<type>(<scope>): <short description> — <bead-id>`

### 6. Land The Bead (unless --impl)

```bash
"$PIPELINE_DRIVER" "<id>"
```

If `pipeline-driver` fails:
- Print the failure output verbatim
- Do NOT manually push, create/edit/merge the PR, cherry-pick the fix elsewhere, or close the bead
- Stop and surface the error to the user
- Fix the actual blocker, then re-run `/bw-work <id>` (it will skip back to the landing path)

If `pipeline-driver` succeeds:
- If the output says the bead remains at `stage:merging`, do NOT close it by hand. That usually means `auto-merge:hold` or reviewer-gated work.
- If it reports `Pipeline complete`, the bead is landed and cleanup already ran.
- Print the PR URL and whether the bead is `landed` or still `stage:merging`.

### 7. Summary

Print:
```
<id> · fix/<shape>-<id> · PR #<n>
  Status: landed | stage:merging
  Next: re-run /bw-land <id> after review clears, or continue with the next bead
```

## Flags

| Flag | Effect |
|------|--------|
| `--impl` | Stop after commit, skip shipping/landing (for manual review before running the conveyor belt) |

## Guardrails

- One bead, one branch, one PR — never bundle multiple beads
- Use the repo's approved VCS write path — never guess or shortcut around the conveyor belt
- Code files <=275 lines; commits <=5 files / <=300 lines
- TDD: failing test first, minimal implementation, refactor only while green
- If pipeline-driver fails, do NOT route around it with manual push/PR
- If the bead is still `stage:merging`, do NOT close it manually just to satisfy the queue
- After 2 consecutive failed edits or gate attempts, stop and re-read before retrying
- Beads is the only task tracker — never use TodoWrite/TaskCreate
- **No bead, no ship.** Every commit that reaches `main` must trace to a bead.
  Hotfixes, typos, config tweaks, and infra changes all need one — `bd create` is
  a one-liner. Only local-only branches never intended to merge are exempt.
- **No claim, no ship.** `bd-ship` blocks unless the bead is `in_progress`. The
  bead only reaches `in_progress` through `/bw-work` or `/drain` claiming it.
  Bypassing these entry points means the landing path is no longer trustworthy.

## When to use

- Working on a single bead solo (no multi-agent drain needed)
- Re-implementing a bead after a gate failure fix
- Quick feature/fix that doesn't warrant a full `/drain` session

## Related

- `/drain` — multi-bead lane execution (the batch version)
- `/bw-land` — post-merge cleanup after PR merges
- `/bw-mass` — batch ship multiple pre-implemented branches
