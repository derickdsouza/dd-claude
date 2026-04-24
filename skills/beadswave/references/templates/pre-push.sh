#!/usr/bin/env bash
# pre-push — block direct pushes to main and fix/* branches without bd-ship provenance.
#
# The auto-merge pipeline (.github/workflows/auto-merge.yml)
# is the only permitted path for changes to land on main. Free-tier GitHub
# has no branch protection, so this is the client-side enforcement.
#
# Two layers of protection:
#   1. Any push to refs/heads/main is always blocked.
#   2. Any push to refs/heads/fix/* is blocked unless a shipping lock file
#      exists at .beads/.shipping-<branch>. bd-ship creates this file before
#      pushing and removes it after PR creation. This prevents agents from
#      bypassing bd-ship with raw `git push`.
#
# Installed by `bash scripts/setup-dev.sh` which sets core.hooksPath=.githooks.
#
# Detection:
#   Git passes refs via stdin: "<local-ref> <local-sha> <remote-ref> <remote-sha>".
#
# Bypass:
#   Forbidden. Do not use `git push --no-verify`.
#
# Exit 0 = allow push, non-zero = abort.

set -euo pipefail

protected_ref="refs/heads/main"
blocked=0
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

while read -r local_ref local_sha remote_ref remote_sha; do
  [ -z "${remote_ref:-}" ] && continue

  if [ "$remote_ref" = "$protected_ref" ]; then
    blocked=1
    echo "" >&2
    echo "================================================================" >&2
    echo "  BLOCKED: direct push to $protected_ref is forbidden" >&2
    echo "================================================================" >&2
    echo "" >&2
    echo "  All changes to main must go through the auto-merge pipeline:" >&2
    echo "    1. Commit on a feature branch via \`git commit\`" >&2
    echo "    2. Ship via \`bd-ship <bead-id>\` (opens PR + labels auto-merge)" >&2
    echo "    3. PR is merged via direct merge after CI passes" >&2
    echo "" >&2
    echo "  --no-verify is NOT a supported workaround." >&2
    echo "================================================================" >&2
    echo "" >&2
    continue
  fi

  branch="${remote_ref#refs/heads/}"
  if [[ "$branch" == fix/* ]]; then
    shipping_lock="$REPO_ROOT/.beads/.shipping-${branch}"
    if [ ! -f "$shipping_lock" ]; then
      blocked=1
      echo "" >&2
      echo "================================================================" >&2
      echo "  BLOCKED: push to $branch without bd-ship provenance" >&2
      echo "================================================================" >&2
      echo "" >&2
      echo "  fix/* branches must be pushed through bd-ship, which:" >&2
      echo "    - Runs all pre-ship gates (lint, typecheck, tests)" >&2
      echo "    - Creates the PR with auto-merge label" >&2
      echo "    - Tags bead provenance and merges the PR" >&2
      echo "" >&2
      echo "  To ship this branch: bd-ship <bead-id>" >&2
      echo "  Emergency bypass: touch $shipping_lock" >&2
      echo "================================================================" >&2
      echo "" >&2
    fi
  fi
done

if [ "$blocked" -ne 0 ]; then
  exit 1
fi

exit 0
