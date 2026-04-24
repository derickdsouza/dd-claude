#!/usr/bin/env bash
# check-bundle-size.sh — fail if the production bundle exceeds a budget.
#
# Opt-in gate. Copy to scripts/check-bundle-size.sh and reference it from
# .beadswave/pre-ship.sh as a run_gate. Not installed automatically because
# bundle-size enforcement is app-specific.
#
# Env overrides:
#   BUNDLE_SIZE_DIR=dist                    # build output directory
#   BUNDLE_SIZE_PATTERNS='*.js *.css'       # space-separated globs to sum
#   BUNDLE_SIZE_BUDGET_KB=1100              # fail threshold
#
# Usage (from .beadswave/pre-ship.sh):
#   run_gate "bundle size" "BUNDLE_SIZE_BUDGET_KB=1100 scripts/check-bundle-size.sh"

set -euo pipefail

DIR="${BUNDLE_SIZE_DIR:-dist}"
PATTERNS="${BUNDLE_SIZE_PATTERNS:-*.js *.css}"
BUDGET_KB="${BUNDLE_SIZE_BUDGET_KB:-1100}"

if [ ! -d "$DIR" ]; then
  echo "✗ bundle dir not found: $DIR (did the build run?)" >&2
  exit 1
fi

total_bytes=0
for pattern in $PATTERNS; do
  while IFS= read -r -d '' f; do
    size=$(wc -c < "$f" | tr -d ' ')
    total_bytes=$((total_bytes + size))
  done < <(find "$DIR" -type f -name "$pattern" -print0)
done

total_kb=$((total_bytes / 1024))
printf 'bundle size: %d KB (budget: %d KB)\n' "$total_kb" "$BUDGET_KB"

if [ "$total_kb" -gt "$BUDGET_KB" ]; then
  echo "✗ bundle exceeds budget — raise BUNDLE_SIZE_BUDGET_KB or trim deps" >&2
  exit 1
fi

echo "✓ bundle within budget"
