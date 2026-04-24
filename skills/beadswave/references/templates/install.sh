#!/usr/bin/env bash
# install.sh — Idempotent auto-adopter for the beadswave pipeline.
#
# Invoked silently from /waves on first use. Copies templates into the repo,
# installs thin wrappers for the ship/merge/cleanup pipeline plus the queue
# helpers, and checks repo state.
#
# Re-runs are safe — each step skips if the target already exists.
#
# Usage:
#   install.sh                         # interactive, prints what it did
#   install.sh --quiet                 # no output unless something needed doing
#   install.sh --check                 # exit 0 if adopted, 1 if not (no writes)
#   install.sh --check-drift           # exit 0 if templates match manifest, 1 if drift
#   install.sh --sync                  # re-copy drifted templates (with .bak backups)
#   install.sh --sync --yes            # same, no confirmation prompt

set -euo pipefail

SKILL="${BEADSWAVE_SKILL:-${HOME}/.claude/skills/beadswave}"
REPO="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
TEMPLATES="$SKILL/references/templates"
PRESHIP_TEMPLATES="$SKILL/references/preship-templates"
MANIFEST="$REPO/.beadswave/templates.lock.json"

QUIET=false
CHECK_ONLY=false
CHECK_DRIFT=false
SYNC=false
ASSUME_YES=false
while [ $# -gt 0 ]; do
  case "$1" in
    --quiet) QUIET=true; shift ;;
    --check) CHECK_ONLY=true; shift ;;
    --check-drift) CHECK_DRIFT=true; shift ;;
    --sync) SYNC=true; shift ;;
    --yes|-y) ASSUME_YES=true; shift ;;
    -h|--help) sed -n '2,/^$/p' "$0" | sed 's/^# \?//'; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

log()  { [ "$QUIET" = "true" ] || echo "$@"; }
warn() { echo "$@" >&2; }

sha256_of() {
  # macOS: shasum; Linux: sha256sum. Both are POSIX-ish.
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

# ─── Template registry ──────────────────────────────────────────────────────
# Single source of truth: every template tracked for install + drift sync.
# Format: <template-basename>|<dest-relative>|<mode>|<drift-mode>
#   drift-mode:
#     tracked    — reported by --check-drift and re-copied by --sync
#     customize  — copied once, then expected to diverge (drift not reported)
TEMPLATE_REGISTRY=(
  "auto-merge-workflow.yml|.github/workflows/auto-merge.yml|644|tracked"
  "direct-push-alert.yml|.github/workflows/direct-push-alert.yml|644|tracked"
  "mergify.yml|.mergify.yml|644|tracked"  # optional — only needed if using Mergify legacy mode
  "pre-push.sh|.githooks/pre-push|755|tracked"
  "bd-ship-prompt.md|.beads/prompts/create-pr.md|644|customize"
  "sync-gh-issues-to-beads.sh|scripts/sync-gh-issues-to-beads.sh|755|tracked"
  "setup-dev.sh|scripts/setup-dev.sh|755|tracked"
  "beadswave.env.example|.beadswave.env.example|644|tracked"
  "bulk-approve-prs.sh|scripts/bulk-approve-prs.sh|755|tracked"
)

# ─── Stack detection (for pre-ship template selection) ──────────────────────
# Detects the repo's primary stack to pick a starter pre-ship template.
# First match wins. Callers can override via PRESHIP_STACK env var.
has_workspaces() {
  # $1 = path to package.json. Returns 0 if it declares a workspaces array/object.
  [ -f "$1" ] || return 1
  python3 -c "
import json, sys
try:
    with open('$1') as f: pkg = json.load(f)
except Exception:
    sys.exit(1)
sys.exit(0 if 'workspaces' in pkg else 1)
" 2>/dev/null
}

detect_stack() {
  if [ -n "${PRESHIP_STACK:-}" ]; then
    echo "$PRESHIP_STACK"
    return
  fi
  if [ -f "$REPO/bun.lock" ] || [ -f "$REPO/bun.lockb" ]; then
    if has_workspaces "$REPO/package.json"; then
      echo "bun-monorepo"; return
    fi
    echo "bun-app"; return
  fi
  if [ -f "$REPO/pnpm-workspace.yaml" ]; then
    echo "pnpm-monorepo"; return
  fi
  if [ -f "$REPO/pnpm-lock.yaml" ]; then
    # Single-app pnpm — reuse the monorepo template (pnpm -r is a no-op on single package).
    echo "pnpm-monorepo"; return
  fi
  if [ -f "$REPO/poetry.lock" ] || { [ -f "$REPO/pyproject.toml" ] && grep -q 'tool.poetry' "$REPO/pyproject.toml" 2>/dev/null; }; then
    echo "python-poetry"; return
  fi
  if [ -f "$REPO/go.mod" ]; then
    echo "go-modules"; return
  fi
  if [ -f "$REPO/Cargo.toml" ]; then
    echo "rust-cargo"; return
  fi
  echo "minimal"
}

preship_template_for() {
  local stack="$1"
  local candidate="$PRESHIP_TEMPLATES/$stack.sh"
  if [ -f "$candidate" ]; then
    echo "$candidate"
  else
    echo "$PRESHIP_TEMPLATES/minimal.sh"
  fi
}

registry_iter() {
  # Prints one entry per line. Consumers use `IFS='|' read`.
  printf '%s\n' "${TEMPLATE_REGISTRY[@]}"
}

# ─── Manifest I/O (.beadswave/templates.lock.json) ──────────────────────────

manifest_write() {
  # Writes the manifest from the registry + current template SHAs.
  mkdir -p "$(dirname "$MANIFEST")"
  local tmp; tmp="$(mktemp)"
  {
    echo "{"
    echo "  \"skill_dir\": \"$SKILL\","
    echo "  \"generated_at\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\","
    echo "  \"templates\": {"
    local first=1
    while IFS='|' read -r src dst _mode drift; do
      [ -z "$src" ] && continue
      local src_path="$TEMPLATES/$src"
      [ -f "$src_path" ] || continue
      local sha; sha="$(sha256_of "$src_path")"
      [ "$first" -eq 1 ] || echo ","
      printf '    "%s": { "sha256": "%s", "drift_mode": "%s" }' "$dst" "$sha" "$drift"
      first=0
    done < <(registry_iter)
    echo ""
    echo "  }"
    echo "}"
  } > "$tmp"
  mv "$tmp" "$MANIFEST"
}

manifest_get_sha() {
  # $1 = dst path. Returns the recorded upstream sha256 or empty.
  [ -f "$MANIFEST" ] || return 0
  python3 -c "
import json, sys
with open('$MANIFEST') as f:
    m = json.load(f)
entry = m.get('templates', {}).get('$1')
if entry:
    print(entry.get('sha256', ''))
" 2>/dev/null || true
}

# ─── Adoption check ─────────────────────────────────────────────────────────

wrapper_current() {
  local path="$1" target_rel="$2"
  [ -e "$REPO/$path" ] || return 1
  # Symlink to the global skill template — always current
  [ -L "$REPO/$path" ] && return 0
  # Wrapper script containing a reference to the skill template
  [ -x "$REPO/$path" ] && grep -q "$target_rel" "$REPO/$path" 2>/dev/null
}

adopted() {
  [ -f "$REPO/.github/workflows/auto-merge.yml" ] \
    && [ -f "$REPO/.beads/prompts/create-pr.md" ] \
    && [ -f "$MANIFEST" ] \
    && wrapper_current "scripts/bd-ship.sh" "references/templates/bd-ship.sh" \
    && wrapper_current "scripts/merge-wait.sh" "references/templates/merge-wait.sh" \
    && wrapper_current "scripts/pipeline-driver.sh" "references/templates/pipeline-driver.sh" \
    && wrapper_current "scripts/mass-ship.sh" "references/templates/mass-ship.sh" \
    && wrapper_current "scripts/monitor-prs.sh" "references/templates/monitor-prs.sh" \
    && wrapper_current "scripts/queue-hygiene.sh" "references/templates/queue-hygiene.sh" \
    && wrapper_current "scripts/queue-drain.sh" "references/templates/queue-drain.sh" \
    && wrapper_current "scripts/bulk-approve-prs.sh" "references/templates/bulk-approve-prs.sh" \
    && wrapper_current "scripts/bd-lot-plan.sh" "references/templates/bd-lot-plan.sh" \
    && wrapper_current "scripts/bd-lot-ship.sh" "references/templates/bd-lot-ship.sh" \
    && wrapper_current "scripts/bd-circuit.sh" "references/templates/bd-circuit.sh" \
    && wrapper_current "scripts/branch-prune.sh" "references/templates/branch-prune.sh" \
    && wrapper_current "scripts/safe-rebase.sh" "references/templates/safe-rebase.sh"
}

if [ "$CHECK_ONLY" = "true" ]; then
  adopted && exit 0 || exit 1
fi

if [ ! -d "$SKILL" ]; then
  warn "✗ beadswave skill not found at: $SKILL"
  warn "  Install from: https://github.com/anthropics/claude-skills (or your fork)"
  exit 2
fi

# ─── --check-drift: compare current templates vs manifest ──────────────────

if [ "$CHECK_DRIFT" = "true" ]; then
  if [ ! -f "$MANIFEST" ]; then
    warn "✗ No manifest at $MANIFEST — run install.sh first to adopt."
    exit 2
  fi
  drifted=()
  while IFS='|' read -r src dst _mode drift; do
    [ -z "$src" ] && continue
    [ "$drift" = "tracked" ] || continue
    local_src="$TEMPLATES/$src"
    [ -f "$local_src" ] || continue
    current_sha="$(sha256_of "$local_src")"
    recorded_sha="$(manifest_get_sha "$dst")"
    if [ -n "$recorded_sha" ] && [ "$current_sha" != "$recorded_sha" ]; then
      drifted+=("$dst")
    fi
  done < <(registry_iter)
  if [ "${#drifted[@]}" -eq 0 ]; then
    log "✓ No template drift — all tracked files match the manifest."
    exit 0
  fi
  warn "✗ Drift detected — upstream templates have changed:"
  for d in "${drifted[@]}"; do warn "    • $d"; done
  warn ""
  warn "  Run: install.sh --sync    to pull updates (creates .bak backups)"
  exit 1
fi

# ─── --sync: re-copy drifted templates with .bak backups ───────────────────

if [ "$SYNC" = "true" ]; then
  if [ ! -f "$MANIFEST" ]; then
    warn "✗ No manifest at $MANIFEST — run install.sh first to adopt."
    exit 2
  fi
  drifted=()
  while IFS='|' read -r src dst _mode drift; do
    [ -z "$src" ] && continue
    [ "$drift" = "tracked" ] || continue
    local_src="$TEMPLATES/$src"
    [ -f "$local_src" ] || continue
    current_sha="$(sha256_of "$local_src")"
    recorded_sha="$(manifest_get_sha "$dst")"
    if [ -n "$recorded_sha" ] && [ "$current_sha" != "$recorded_sha" ]; then
      drifted+=("$src|$dst|$_mode")
    fi
  done < <(registry_iter)
  if [ "${#drifted[@]}" -eq 0 ]; then
    log "✓ No drifted templates to sync."
    exit 0
  fi
  log "Will sync ${#drifted[@]} drifted template(s):"
  for entry in "${drifted[@]}"; do
    IFS='|' read -r _src dst _mode <<< "$entry"
    log "    • $dst"
  done
  if [ "$ASSUME_YES" != "true" ]; then
    printf "Proceed? [y/N] "
    read -r ans
    case "$ans" in [yY]|[yY][eE][sS]) ;; *) log "aborted"; exit 1 ;; esac
  fi
  for entry in "${drifted[@]}"; do
    IFS='|' read -r src dst mode <<< "$entry"
    target="$REPO/$dst"
    if [ -f "$target" ]; then
      cp "$target" "$target.bak"
      log "  ~ $dst (backup: $dst.bak)"
    fi
    cp "$TEMPLATES/$src" "$target"
    chmod "$mode" "$target"
    log "  + $dst synced"
  done
  manifest_write
  log ""
  log "✓ Sync complete. Review .bak files and merge any local customizations."
  exit 0
fi

# ─── Install (default path) ─────────────────────────────────────────────────


copy_once() {
  local src="$1" dst="$2" mode="${3:-644}"
  if [ -e "$REPO/$dst" ]; then
    log "  ✓ $dst already present"
    return
  fi
  mkdir -p "$(dirname "$REPO/$dst")"
  cp "$src" "$REPO/$dst"
  chmod "$mode" "$REPO/$dst"
  log "  + $dst installed"
}

write_wrapper() {
  local path="$1" target_rel="$2"
  if [ -x "$REPO/$path" ] && grep -q "$target_rel" "$REPO/$path" 2>/dev/null; then
    log "  ✓ $path already delegates to skill"
    return
  fi
  mkdir -p "$(dirname "$REPO/$path")"
  cat > "$REPO/$path" <<EOF
#!/usr/bin/env bash
# Thin wrapper — actual logic lives in the beadswave skill.
set -euo pipefail
SKILL="\${BEADSWAVE_SKILL:-\${HOME}/.claude/skills/beadswave}"
TARGET="\$SKILL/$target_rel"
if [ ! -x "\$TARGET" ]; then
  echo "Requires beadswave skill at: \$SKILL" >&2
  exit 2
fi
exec "\$TARGET" "\$@"
EOF
  chmod +x "$REPO/$path"
  log "  + $path wrapper installed"
}

log "Beadswave auto-adopt → $REPO"

ALREADY_ADOPTED=false
if adopted; then
  ALREADY_ADOPTED=true
  log "  already adopted — checking for new templates + manifest freshness"
fi

log "[templates]"
NEW_COUNT=0
while IFS='|' read -r src dst mode _drift; do
  [ -z "$src" ] && continue
  if [ ! -e "$REPO/$dst" ]; then
    copy_once "$TEMPLATES/$src" "$dst" "$mode"
    NEW_COUNT=$((NEW_COUNT+1))
  elif [ "$ALREADY_ADOPTED" = "false" ]; then
    copy_once "$TEMPLATES/$src" "$dst" "$mode"
  fi
done < <(registry_iter)
if [ "$ALREADY_ADOPTED" = "true" ] && [ "$NEW_COUNT" -eq 0 ]; then
  log "  ✓ all registry entries present"
fi

log "[pre-ship starter]"
STACK="$(detect_stack)"
PRESHIP_SRC="$(preship_template_for "$STACK")"
if [ -e "$REPO/.beadswave/pre-ship.sh" ]; then
  log "  ✓ .beadswave/pre-ship.sh already present (stack detected: $STACK)"
else
  mkdir -p "$REPO/.beadswave"
  cp "$PRESHIP_SRC" "$REPO/.beadswave/pre-ship.sh"
  chmod 755 "$REPO/.beadswave/pre-ship.sh"
  log "  + .beadswave/pre-ship.sh installed (stack: $STACK → $(basename "$PRESHIP_SRC"))"
  log "    Tune gates to match your CI. See portfolio-manager's 14-gate suite"
  log "    (referenced in SKILL.md) for a gold-standard exemplar."
fi

log "[thin wrappers]"
write_wrapper "scripts/bd-ship.sh"        "references/templates/bd-ship.sh"
write_wrapper "scripts/merge-wait.sh"     "references/templates/merge-wait.sh"
write_wrapper "scripts/pipeline-driver.sh" "references/templates/pipeline-driver.sh"
write_wrapper "scripts/mass-ship.sh"      "references/templates/mass-ship.sh"
write_wrapper "scripts/monitor-prs.sh"    "references/templates/monitor-prs.sh"
write_wrapper "scripts/queue-hygiene.sh"  "references/templates/queue-hygiene.sh"
write_wrapper "scripts/queue-drain.sh"    "references/templates/queue-drain.sh"
write_wrapper "scripts/beadswave-lint.sh" "references/templates/beadswave-lint.sh"
write_wrapper "scripts/bulk-approve-prs.sh" "references/templates/bulk-approve-prs.sh"
write_wrapper "scripts/bd-lot-plan.sh"    "references/templates/bd-lot-plan.sh"
write_wrapper "scripts/bd-lot-ship.sh"    "references/templates/bd-lot-ship.sh"
write_wrapper "scripts/bd-circuit.sh"     "references/templates/bd-circuit.sh"
write_wrapper "scripts/branch-prune.sh"  "references/templates/branch-prune.sh"
write_wrapper "scripts/safe-rebase.sh"   "references/templates/safe-rebase.sh"

# Install the git hook path (idempotent — setup-dev.sh handles this).
if [ -x "$REPO/scripts/setup-dev.sh" ]; then
  ( cd "$REPO" && BEADSWAVE_SETUP_INSTALL=0 bash scripts/setup-dev.sh >/dev/null 2>&1 || true )
  log "  + git hooks path configured"
fi

# Write the drift-detection manifest. Regenerated on every install so new
# registry entries get tracked in already-adopted repos.
log "[manifest]"
manifest_write
log "  + $MANIFEST"

# If already adopted, we've just refreshed the manifest with any new registry
# entries. pipeline setup only applies to fresh adoption.
if [ "$ALREADY_ADOPTED" = "true" ]; then
  log ""
  log "✓ Refresh complete. Run install.sh --check-drift to compare against upstream."
  log "  Tip: run scripts/beadswave-lint.sh --strict after customizing .beadswave/pre-ship.sh."
  exit 0
fi


log ""
log "✓ Adoption complete. Next:"
log "    1. Tune .beads/prompts/create-pr.md (risk globs for your repo)"
log "    3. Run scripts/setup-dev.sh once per fresh clone/worktree before first test or ship"
log "       so hooks and local dependencies exist in that workspace"
log "    4. Customize .beadswave/pre-ship.sh (starter picked for stack: $STACK)"
log "       Then run scripts/beadswave-lint.sh --strict to catch custom-hook regressions"
log "    5. Optional bundle-size gate:"
log "       cp $TEMPLATES/check-bundle-size.sh scripts/ && chmod +x scripts/check-bundle-size.sh"
log "       Then uncomment the bundle-size run_gate in .beadswave/pre-ship.sh"
log "    6. Periodically run: install.sh --check-drift  (or wire into weekly CI)"
log "    7. Run /waves to classify + allocate beads"
log ""
log "⚠ BOOTSTRAP NOTE — the first push is different:"
log "    The pre-push hook you just installed blocks direct pushes to main,"
log "    can't self-activate on the PR that installs it."
log ""
log "    For this initial bootstrap PR only:"
log "      git checkout -b bootstrap/beadswave"
log "      git add -A && git commit -m 'chore: adopt beadswave pipeline'"
log "      git push -u origin bootstrap/beadswave"
log "      gh pr create --fill"
log ""
log "    After that lands on main, normal bd-ship flow works end-to-end."
