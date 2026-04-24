# /bw-monitor — PR health dashboard and auto-remediation

Check the health of open PRs, surface failures, detect orphans,
auto-rebase conflicting PRs, and optionally file beads for failures.
Wraps `monitor-prs.sh` with sensible defaults.

## Usage

```
/bw-monitor                                  # Show all open PRs with status
/bw-monitor --failing                        # Only show PRs with failing checks
/bw-monitor --orphans                        # Detect + auto-remediate orphan PRs
/bw-monitor --resolve-conflicts              # Auto-rebase conflicting PRs
/bw-monitor --file-beads                     # Create beads for failing PRs
/bw-monitor --orphans --resolve-conflicts --file-beads   # Full remediation
/bw-monitor --json                           # Machine-readable JSON output
```

## Steps

### 1. Resolve the script

```bash
SKILL="${BEADSWAVE_SKILL:-$HOME/.claude/skills/beadswave}"
MONITOR="$SKILL/references/templates/monitor-prs.sh"
[ -x "$MONITOR" ] || { echo "monitor-prs.sh not found at $MONITOR"; exit 2; }
```

If the repo has a local wrapper at `scripts/monitor-prs.sh`, prefer that:

```bash
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
if [ -x "$REPO_ROOT/scripts/monitor-prs.sh" ]; then
  MONITOR="$REPO_ROOT/scripts/monitor-prs.sh"
fi
```

### 2. Run monitor-prs

Pass all user flags through:

```bash
"$MONITOR" "$@"
```

The script outputs:
- Total open PRs
- Per-PR status: check results (success/failure/pending/skipped), age, stuck detection
- Failure details: which checks failed per PR
- Orphan detection: PRs missing expected labels (with `--orphans`)
- Conflict detection: PRs with merge conflicts (with `--resolve-conflicts`)

### 3. Post-report actions

If `--orphans` is set, the script auto-remediates by:
- Adding appropriate labels to mergeable orphan PRs
- Requesting GitHub auto-merge

If `--resolve-conflicts` is set, the script auto-rebases conflicting PRs via
`gh pr update-branch` and files beads for unresolvable conflicts (with `--file-beads`).

If `--file-beads` is set, the script creates a `type=bug` bead for each failing PR
with a link to the PR and the failing check names.

### 4. Summary guidance

After the script completes, print contextual guidance based on the result:

```
If failures found:
  "N PR(s) failing. Options:
     - Fix forward: /bw-work <id> to push a fix commit
     - Hold: gh pr edit <n> --add-label auto-merge:hold
     - Close: gh pr close <n>; /bw-land <id>"

If orphans remediated:
  "N orphan PR(s) auto-remediated"

If conflicts found:
  "N conflicting PR(s). Auto-rebase attempted.
     Successful: N
     Filed beads for unresolvable: N (use /bw-work <id> to fix manually)"
```

## Flags

All flags pass through to `monitor-prs.sh`:

| Flag | Effect |
|------|--------|
| (none) | Show all open PRs with health status |
| `--failing` | Only show PRs with at least one FAILURE check |
| `--orphans` | Detect + auto-remediate orphan PRs |
| `--resolve-conflicts` | Auto-rebase CONFLICTING PRs via GitHub API |
| `--file-beads` | Create bug beads for each failing/conflicting PR |
| `--stuck MINUTES` | Flag PRs with no update in N minutes (default: 120) |
| `--json` | JSON output instead of human report |

## Guardrails

- Never auto-close PRs — only label, rebase, and file beads
- Bead filing is idempotent — skips if a bead with the same title exists
- Auto-rebase requires repo setting "Allow updates to pull request branches" enabled
- Monitor is read-only by default; remediation only with explicit flags

## When to use

- After `/bw-mass` to watch the PR queue as merges progress
- On a recurring basis: `/loop 5m /bw-monitor --orphans --file-beads`
- At session start to check if overnight merges succeeded
- When CI is flaky and PRs need attention

## Related

- `/bw-mass` — batch ship; monitor watches what mass-ship produces
- `/bw-land --all` — cleanup after monitored PRs finish merging
- `/bw-circuit` — circuit breaker that may trip during high failure rates
