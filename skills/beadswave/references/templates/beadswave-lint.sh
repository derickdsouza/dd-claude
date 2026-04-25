#!/usr/bin/env bash
# beadswave-lint.sh — Detect drift between this repo and the beadswave skill.
#
# Reports when in-repo copies of skill-canonical files have diverged. Two
# modes of divergence are expected and allowed:
#
#   - Thin wrappers in scripts/ — they SHOULD differ from the skill (they're shims)
#   - Project-tuned configs (auto-merge.yml, create-pr.md) — they SHOULD have
#     project-specific sections; we only flag structural drift
#
# For the authoritative SHA-based drift report (tracked templates vs manifest),
# prefer: install.sh --check-drift
#
# Usage:
#   beadswave-lint.sh [--strict] [--diff]
#     --strict   Exit 1 on any drift (suitable for CI)
#     --diff     Show unified diffs for drifted files

set -uo pipefail

SKILL="${BEADSWAVE_SKILL:-${HOME}/.claude/skills/beadswave}"
REPO="$(git rev-parse --show-toplevel)"

STRICT=false
SHOW_DIFF=false

while [ $# -gt 0 ]; do
  case "$1" in
    --strict) STRICT=true; shift ;;
    --diff)   SHOW_DIFF=true; shift ;;
    -h|--help) sed -n '2,/^$/p' "$0" | sed 's/^# \?//'; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

if [ ! -d "$SKILL" ]; then
  echo "✗ beadswave skill not installed at: $SKILL" >&2
  exit 2
fi

DRIFT=0
WARN=0

check_wrapper() {
  local path="$1"; local target="$2"
  if [ ! -e "$REPO/$path" ]; then
    echo "  ✗ missing: $path"
    DRIFT=$((DRIFT+1))
    return
  fi
  if ! grep -q "$target" "$REPO/$path" 2>/dev/null; then
    echo "  ✗ $path does not delegate to skill ($target)"
    DRIFT=$((DRIFT+1))
  else
    echo "  ✓ $path → skill"
  fi
}

check_diff() {
  local path="$1"; local skill_rel="$2"; local allow_msg="$3"
  local local="$REPO/$path"
  local canonical="$SKILL/$skill_rel"
  if [ ! -e "$local" ]; then
    echo "  ✗ $path missing in repo (skill template: $skill_rel)"
    DRIFT=$((DRIFT+1))
    return
  fi
  if [ ! -e "$canonical" ]; then
    echo "  ✗ $skill_rel missing in skill"
    DRIFT=$((DRIFT+1))
    return
  fi
  if diff -q "$local" "$canonical" >/dev/null 2>&1; then
    echo "  ✓ $path matches skill template"
  else
    echo "  ∿ $path diverges from skill template — $allow_msg"
    WARN=$((WARN+1))
    if [ "$SHOW_DIFF" = "true" ]; then
      diff -u "$canonical" "$local" | sed 's/^/      /'
    fi
  fi
}

check_preship_hook() {
  local path="$REPO/.beadswave/pre-ship.sh"
  if [ ! -e "$path" ]; then
    echo "  ∿ .beadswave/pre-ship.sh missing — starter not customized yet"
    WARN=$((WARN+1))
    return
  fi

  if grep -q 'scripts/runtime.sh' "$path" 2>/dev/null; then
    echo "  ✓ .beadswave/pre-ship.sh sources beadswave runtime"
  else
    echo "  ∿ .beadswave/pre-ship.sh does not source beadswave runtime — shared helpers/tests may drift"
    WARN=$((WARN+1))
  fi

  if grep -q 'beadswave_run_gate' "$path" 2>/dev/null; then
    echo "  ✓ .beadswave/pre-ship.sh uses the shared gate runner"
  elif grep -Eq '(^|[[:space:]])run_gate[[:space:]]*\(' "$path" 2>/dev/null; then
    echo "  ✗ .beadswave/pre-ship.sh redefines run_gate() instead of using beadswave_run_gate"
    DRIFT=$((DRIFT+1))
  else
    echo "  ∿ .beadswave/pre-ship.sh does not use beadswave_run_gate — verify gate logging manually"
    WARN=$((WARN+1))
  fi

  if grep -Eq 'rm -f[[:space:]]+\.git/\*\.lock' "$path" 2>/dev/null; then
    echo "  ✓ .beadswave/pre-ship.sh handles git lock cleanup"
  fi

  if grep -Eq 'mktemp[[:space:]].*preship\.XXXXXX(\.log)?' "$path" 2>/dev/null; then
    echo "  ✗ .beadswave/pre-ship.sh uses a bespoke preship mktemp pattern — use beadswave_run_gate/beadswave_tmpfile"
    DRIFT=$((DRIFT+1))
  fi
}

echo "Beadswave lint — skill: $SKILL"
echo
echo "[thin wrappers — must delegate to skill]"
check_wrapper "scripts/bd-ship.sh"      "references/templates/bd-ship.sh"
check_wrapper "scripts/mass-ship.sh"    "references/templates/mass-ship.sh"
check_wrapper "scripts/monitor-prs.sh"  "references/templates/monitor-prs.sh"
check_wrapper "scripts/queue-hygiene.sh" "references/templates/queue-hygiene.sh"
check_wrapper "scripts/queue-drain.sh"  "references/templates/queue-drain.sh"
check_wrapper "scripts/bulk-approve-prs.sh" "references/templates/bulk-approve-prs.sh"
check_wrapper "scripts/bd-lot-plan.sh"  "references/templates/bd-lot-plan.sh"
check_wrapper "scripts/bd-lot-ship.sh"  "references/templates/bd-lot-ship.sh"
check_wrapper "scripts/bd-circuit.sh"   "references/templates/bd-circuit.sh"
check_wrapper "scripts/branch-prune.sh" "references/templates/branch-prune.sh"

echo
echo "[project-tuned configs — drift expected but watch for structural changes]"
check_diff ".github/workflows/auto-merge.yml" "references/templates/auto-merge-workflow.yml" "env + secrets will differ"
check_diff ".beads/prompts/create-pr.md"      "references/templates/bd-ship-prompt.md"     "risk globs will differ"

echo
echo "[custom pre-ship hooks — drift allowed, anti-patterns are not]"
check_preship_hook

check_stage_mutation_invariant() {
  local hits
  hits="$(grep -lE "bd[[:space:]]+update[[:space:]].*(--add-label|--remove-label)[[:space:]]+stage:" \
    "$SKILL"/scripts/*.sh "$SKILL"/references/templates/*.sh 2>/dev/null \
    | grep -vE "/(stage_machine|beadswave-lint)\.sh$" || true)"
  if [ -z "$hits" ]; then
    echo "  ✓ stage:* labels mutated only by stage_machine.sh"
    return
  fi
  echo "  ✗ raw 'add-label stage:' / 'remove-label stage:' found outside stage_machine.sh:"
  printf '    %s\n' $hits
  echo "    Use bead_advance / bead_rollback / bead_divert from scripts/stage_machine.sh."
  DRIFT=$((DRIFT+1))
}

echo
echo "[stage-machine invariant — only stage_machine.sh may mutate stage:* labels]"
check_stage_mutation_invariant

echo
echo "Summary: ${DRIFT} drift(s), ${WARN} warning(s)"
if [ "$DRIFT" -gt 0 ]; then
  exit 1
fi
if [ "$STRICT" = "true" ] && [ "$WARN" -gt 0 ]; then
  exit 1
fi
exit 0
