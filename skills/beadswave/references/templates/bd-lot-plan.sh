#!/usr/bin/env bash
# Thin wrapper — actual logic lives in the beadswave skill.
set -euo pipefail
SKILL="${BEADSWAVE_SKILL:-${HOME}/.claude/skills/beadswave}"
TARGET="$SKILL/references/templates/bd-lot-plan.sh"
if [ ! -x "$TARGET" ]; then
  echo "Requires beadswave skill at: $SKILL" >&2
  exit 2
fi
exec "$TARGET" "$@"
