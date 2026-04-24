# /bw-circuit — Circuit breaker for the auto-merge pipeline

Control the circuit breaker that protects the main branch from a cascade of
failing PRs. When the rolling failure rate exceeds a threshold, the breaker
trips the `.auto-merge-disabled` kill switch. When the rate recovers, it resets.

## Usage

```
/bw-circuit status               # Show current breaker state and recent PR outcomes
/bw-circuit auto                 # Auto-trip or auto-reset based on recent PR failure rate
/bw-circuit trip                 # Manually trip the kill switch (disable auto-merge)
/bw-circuit reset                # Manually reset the breaker (re-enable auto-merge)
```

## Steps

### 1. Resolve the script

```bash
SKILL="${BEADSWAVE_SKILL:-$HOME/.claude/skills/beadswave}"
CIRCUIT="$SKILL/references/templates/bd-circuit.sh"
[ -x "$CIRCUIT" ] || { echo "bd-circuit.sh not found at $CIRCUIT"; exit 2; }
```

If the repo has a local wrapper at `scripts/bd-circuit.sh`, prefer that:

```bash
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
if [ -x "$REPO_ROOT/scripts/bd-circuit.sh" ]; then
  CIRCUIT="$REPO_ROOT/scripts/bd-circuit.sh"
fi
```

### 2. Execute the action

The first argument after the slash command selects the subcommand:

| Subcommand | Script flag | What it does |
|---|---|---|
| `status` | `--action status` | Print breaker state + rolling failure rate |
| `auto` | `--action auto` | Trip if over threshold, reset if under and main is green |
| `trip` | `--action trip` | Create `.auto-merge-disabled` kill switch file |
| `reset` | `--action reset` | Remove `.auto-merge-disabled` file |

```bash
SUBCMD="${1:-status}"
case "$SUBCMD" in
  status|auto|trip|reset)
    "$CIRCUIT" --window 20 --threshold 40 --action "$SUBCMD"
    ;;
  *)
    echo "Unknown subcommand: $SUBCMD"
    echo "Usage: /bw-circuit [status|auto|trip|reset]"
    exit 2
    ;;
esac
```

### 3. Post-action context

After the script runs, print guidance:

```
If tripped:
  "Circuit breaker TRIPPED — auto-merge is disabled.
   All bd-ship runs will fail until the breaker is reset.
   Fix: /bw-circuit reset (after resolving the root cause)"

If reset:
  "Circuit breaker RESET — auto-merge is re-enabled.
   Safe to resume: /bw-mass or /bw-work"

If status shows high failure rate:
  "Failure rate: N% (threshold: 40%)
   Recent failures: <list PR numbers>
   Use /bw-monitor --failing to inspect details"
```

## Flags

| Subcommand | Effect |
|---|---|
| `status` | Show current state without changing anything |
| `auto` | Trip or reset automatically based on rolling failure rate |
| `trip` | Manually disable auto-merge (create `.auto-merge-disabled`) |
| `reset` | Manually re-enable auto-merge (remove `.auto-merge-disabled`) |

Tuning (environment variables or script defaults):
- `--window N` — number of recent PR outcomes to consider (default: 20)
- `--threshold PCT` — failure rate percentage that trips the breaker (default: 40)

## Guardrails

- `trip` creates `.auto-merge-disabled` — this blocks ALL bd-ship runs, not just failing ones
- `reset` removes the file — only do this after the root cause is fixed
- `auto` is safe to run on a schedule: `/loop 15m /bw-circuit auto`
- The breaker state persists across sessions via the `.auto-merge-disabled` file

## When to use

- Before `/bw-mass` — check that the breaker isn't triipped
- On a recurring basis: `/loop 15m /bw-circuit auto` to auto-protect main
- After a batch of CI failures — trip manually while investigating
- After fixing the root cause — reset to resume shipping

## Related

- `/bw-mass` — batch ship; respects the circuit breaker
- `/bw-monitor` — inspect PR health; feeds into breaker decisions
- `/bw-work` — single bead ship; also respects the breaker
