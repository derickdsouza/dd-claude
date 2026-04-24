#!/usr/bin/env bash
# sync-gh-issues-to-beads.sh — mirror direct-push-alert GH issues into beads.
#
# Why this exists:
#   .github/workflows/direct-push-alert.yml runs on GitHub Actions when a
#   non-merge commit lands on main (someone bypassed the auto-merge flow).
#   CI doesn't have `bd` + Dolt auth installed, so the alert is filed as a
#   GitHub Issue labeled `direct-push`. Devs run this script at session start
#   to pull those alerts into beads, where the rest of our triage lives.
#
# Behavior (idempotent):
#   1. `gh issue list --label direct-push --state open` — enumerate unmirrored alerts
#   2. For each issue, check if a bead tagged `gh:<issue-number>` already exists
#      (matches by description substring — no native bd metadata yet)
#   3. If not: `bd create --type=incident --priority=0 --labels=direct-push`
#      with a description that includes `gh:<issue-number>` for future idempotence
#   4. Close the GH issue with a pointer to the new bead
#
# Usage:
#   bash scripts/sync-gh-issues-to-beads.sh [--dry-run]
#
# Env:
#   PROJECT_PREFIX   Your beads project prefix (e.g. "myproject-") — used to parse
#                    the bead ID from `bd create` output. Default tries to detect
#                    via `bd list -n 1 --json`.

set -euo pipefail

DRY_RUN=false
if [ "${1:-}" = "--dry-run" ]; then
  DRY_RUN=true
fi

# Required tooling
for bin in gh bd jq; do
  if ! command -v "$bin" >/dev/null 2>&1; then
    echo "ERROR: $bin not found in PATH" >&2
    exit 1
  fi
done

# Auto-detect project prefix if not provided.
if [ -z "${PROJECT_PREFIX:-}" ]; then
  PROJECT_PREFIX="$(bd list -n 1 --json 2>/dev/null \
    | jq -r 'if type=="array" then .[0].id else .id end' \
    | sed -E 's/-[a-z0-9]{5}$/-/' || echo '')"
  if [ -z "$PROJECT_PREFIX" ] || [ "$PROJECT_PREFIX" = "-" ]; then
    echo "ERROR: could not auto-detect PROJECT_PREFIX. Set it explicitly." >&2
    exit 1
  fi
fi

echo "▶ Syncing direct-push GH issues into beads (prefix: $PROJECT_PREFIX)"
[ "$DRY_RUN" = true ] && echo "  (dry-run — no writes)"
echo ""

issues_json="$(gh issue list --label direct-push --state open --json number,title,body,url --limit 100)"
count="$(echo "$issues_json" | jq 'length')"

if [ "$count" -eq 0 ]; then
  echo "  No unmirrored direct-push issues found."
  exit 0
fi

echo "  Found $count open direct-push GH issue(s)."
echo ""

created=0
skipped=0

echo "$issues_json" | jq -c '.[]' | while read -r issue; do
  gh_num="$(echo "$issue" | jq -r '.number')"
  gh_title="$(echo "$issue" | jq -r '.title')"
  gh_body="$(echo "$issue" | jq -r '.body')"
  gh_url="$(echo "$issue" | jq -r '.url')"

  marker="gh:${gh_num}"

  existing="$(bd list --status=open --json 2>/dev/null \
    | jq --arg m "$marker" '[.[] | select(.description // "" | contains($m))] | length' \
    || echo 0)"

  if [ "${existing:-0}" -gt 0 ]; then
    echo "  [skip] GH #${gh_num}: bead already exists (matched by $marker)"
    skipped=$((skipped + 1))
    continue
  fi

  bead_title="Direct push to main — ${gh_title}"
  bead_desc="Mirrored from GitHub Issue: ${gh_url}
Marker: ${marker}

---

${gh_body}"

  if [ "$DRY_RUN" = true ]; then
    echo "  [dry] Would create bead + close GH #${gh_num}: ${gh_title}"
    continue
  fi

  new_bead="$(bd create \
    --title "$bead_title" \
    --description "$bead_desc" \
    --type=incident \
    --priority=0 \
    --labels=direct-push 2>&1 | grep -oE "${PROJECT_PREFIX}[a-z0-9]+" | head -1)"

  if [ -z "$new_bead" ]; then
    echo "  [fail] bd create did not return a bead id for GH #${gh_num}" >&2
    continue
  fi

  gh issue close "$gh_num" --comment "Mirrored to bead \`${new_bead}\`. Further triage happens there." >/dev/null

  echo "  [ok]   GH #${gh_num} → bead ${new_bead} (GH issue closed)"
  created=$((created + 1))
done

echo ""
echo "Done. Created: $created  Skipped (existing): $skipped"
