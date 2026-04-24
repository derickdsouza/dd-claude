# /bw-mass — Batch ship pre-implemented branches

Ship many already-implemented branches through bd-ship in a controlled serial batch.
Wraps `mass-ship.sh` with sensible defaults. Use after a drain session or when
multiple branches are committed but not yet shipped.

## Usage

```
/bw-mass                        # Auto-discover branches, ship with default 90s rate-limit
/bw-mass --dry-run              # Show the ship plan without executing
/bw-mass --hold                 # Ship but label PRs auto-merge:hold (no auto-merge)
/bw-mass --rate-limit 60        # Custom rate-limit (seconds between ships)
/bw-mass --from 3 --to 8        # Ship branches 3 through 8 from the auto-discovered list
/bw-mass branch-a branch-b      # Ship specific branches by name
```

## Steps

### 1. Resolve the script

```bash
SKILL="${BEADSWAVE_SKILL:-$HOME/.claude/skills/beadswave}"
MASS_SHIP="$SKILL/references/templates/mass-ship.sh"
[ -x "$MASS_SHIP" ] || { echo "mass-ship.sh not found at $MASS_SHIP"; exit 2; }
```

If the repo has a local wrapper at `scripts/mass-ship.sh`, prefer that instead:

```bash
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
if [ -x "$REPO_ROOT/scripts/mass-ship.sh" ]; then
  MASS_SHIP="$REPO_ROOT/scripts/mass-ship.sh"
fi
```

### 2. Pre-flight check

```bash
# Verify workspace is in a shippable state
git status
```

Show the number of branches that will be considered. If >50 branches exist,
suggest running `/bw-land --all` first to prune merged ones.

### 3. Execute mass-ship

Pass all user flags through to `mass-ship.sh`:

```bash
"$MASS_SHIP" --auto "$@"
```

The script handles per-branch:
- Refresh `origin/main` and prune merged branches
- Derive bead ID from branch name suffix
- Skip branches that already have open PRs
- Reopen beads if closed (bd-ship refuses closed beads)
- Run bd-ship (gates → push → PR → merge)
- Hygiene pass between ships

### 4. Post-ship summary

```bash
# Show current PR queue status
gh pr list --state open --json number,title,statusCheckRollup \
  --jq '.[] | "#\(.number) \(.title[0:60])"'
```

Print:
```
Mass ship complete.
  Shipped: <N> PRs created
  Skipped: <S> (already had PRs)
  Failed:  <F>

Tip: run /bw-monitor to watch PR health, or /bw-land --all after merges complete
```

If any failures occurred, list them with the failure reason.

## Flags

All flags are passed through to `mass-ship.sh`:

| Flag | Effect |
|------|--------|
| `--auto` | Auto-discover branches (default when no positional args) |
| `--dry-run` | Show the plan without shipping |
| `--hold` | Label all PRs `auto-merge:hold` |
| `--rate-limit N` | Seconds between ships (default: 90) |
| `--from N` | 1-indexed start of branch slice |
| `--to N` | 1-indexed end of branch slice |

## Guardrails

- Mass-ship is serial — bd-ship mutates the git workspace and cannot run in parallel
- Default 90s rate-limit prevents saturating GitHub Actions runner concurrency
- If the circuit breaker is triipped (`.auto-merge-disabled` exists), mass-ship will fail
- Check with `/bw-circuit status` before mass shipping

## When to use

- After a multi-agent drain session where branches are committed but not shipped
- When multiple beads were implemented in parallel worktrees
- As the "ship" half of: implement in parallel, ship serially

## Related

- `/bw-work <id>` — ship a single bead
- `/bw-land --all` — cleanup after mass ship PRs merge
- `/bw-monitor` — watch PR health during mass merge
- `/bw-circuit` — check/reset circuit breaker before mass shipping
