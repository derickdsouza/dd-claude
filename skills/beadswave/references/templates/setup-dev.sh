#!/usr/bin/env bash
# setup-dev.sh — one-shot developer environment setup for the beadswave pipeline.
#
# Idempotent. Safe to re-run. Every developer (human or AI agent) must run
# this once per clone/worktree. CI does not run this.
#
# What it does:
#   1. Install .githooks/pre-push into git's hook path (blocks direct push to main)
#   2. Bootstrap per-worktree dependencies for the detected stack (unless disabled)
#   3. Surface missing env-file hints for the current worktree
#   4. Print verification summary
#
# Usage:
#   bash scripts/setup-dev.sh
#
# Exit codes:
#   0  setup complete (or already in place)
#   1  git repo not detected or hooks path not writable

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [ -z "$REPO_ROOT" ]; then
  echo "ERROR: not inside a git repository" >&2
  exit 1
fi

cd "$REPO_ROOT"

detect_stack() {
  if [ -f bun.lock ] || [ -f bun.lockb ]; then
    echo "bun"
    return 0
  fi
  if [ -f pnpm-lock.yaml ]; then
    echo "pnpm"
    return 0
  fi
  if [ -f yarn.lock ]; then
    echo "yarn"
    return 0
  fi
  if [ -f package.json ]; then
    echo "npm"
    return 0
  fi
  if [ -f poetry.lock ] || { [ -f pyproject.toml ] && grep -q 'tool.poetry' pyproject.toml 2>/dev/null; }; then
    echo "python-poetry"
    return 0
  fi
  if [ -f requirements.txt ]; then
    echo "python-requirements"
    return 0
  fi
  if [ -f go.mod ]; then
    echo "go"
    return 0
  fi
  if [ -f Cargo.toml ]; then
    echo "rust"
    return 0
  fi
  echo "unknown"
}

bootstrap_dependencies() {
  local stack="$1"
  case "$stack" in
    bun)
      command -v bun >/dev/null 2>&1 || { echo "  WARNING: bun not found — skipping dependency bootstrap"; return 0; }
      bun install
      ;;
    pnpm)
      command -v pnpm >/dev/null 2>&1 || { echo "  WARNING: pnpm not found — skipping dependency bootstrap"; return 0; }
      pnpm install --frozen-lockfile
      ;;
    yarn)
      command -v yarn >/dev/null 2>&1 || { echo "  WARNING: yarn not found — skipping dependency bootstrap"; return 0; }
      yarn install --immutable
      ;;
    npm)
      command -v npm >/dev/null 2>&1 || { echo "  WARNING: npm not found — skipping dependency bootstrap"; return 0; }
      npm install
      ;;
    python-poetry)
      command -v poetry >/dev/null 2>&1 || { echo "  WARNING: poetry not found — skipping dependency bootstrap"; return 0; }
      poetry install
      ;;
    python-requirements)
      command -v python3 >/dev/null 2>&1 || { echo "  WARNING: python3 not found — skipping dependency bootstrap"; return 0; }
      python3 -m pip install -r requirements.txt
      ;;
    go)
      command -v go >/dev/null 2>&1 || { echo "  WARNING: go not found — skipping dependency bootstrap"; return 0; }
      go mod download
      ;;
    rust)
      command -v cargo >/dev/null 2>&1 || { echo "  WARNING: cargo not found — skipping dependency bootstrap"; return 0; }
      cargo fetch
      ;;
    *)
      echo "  [skip] no known dependency bootstrap for this repo"
      ;;
  esac
}

warn_missing_env_files() {
  local warned=0
  local sample target
  while IFS= read -r sample; do
    [ -n "$sample" ] || continue
    target="${sample%.example}"
    if [ ! -e "$target" ]; then
      if [ "$warned" -eq 0 ]; then
        echo ""
        echo "▶ Env-file hints:"
        warned=1
      fi
      echo "  WARNING: missing ${target#./} (sample: ${sample#./})"
    fi
  done < <(find . \
    \( -path './.git' -o -path './node_modules' -o -path './.beads' -o -path './.claude' \) -prune \
    -o -maxdepth 3 -type f \( -name '.env.example' -o -name '.env.local.example' \) -print | sort)
}

echo "▶ beadswave dev setup"
echo "  repo: $REPO_ROOT"
echo ""

# 1. Point git at .githooks/ so the pre-push hook runs.
current_hookpath="$(git config --local --get core.hooksPath || echo '')"
if [ "$current_hookpath" = ".githooks" ]; then
  echo "  [skip] core.hooksPath already set to .githooks"
else
  git config --local core.hooksPath .githooks
  echo "  [ok]   core.hooksPath → .githooks"
fi

# Ensure hook is executable (git requires this; a fresh worktree on
# Windows/WSL may strip the mode bit).
if [ -f .githooks/pre-push ]; then
  chmod +x .githooks/pre-push
  echo "  [ok]   .githooks/pre-push is executable"
else
  echo "  WARNING: .githooks/pre-push is missing — direct-to-main pushes will NOT be blocked"
  echo "  Restore the file and re-run this script."
fi

# Smoke-test: the hook should reject a simulated push to refs/heads/main.
if [ -f .githooks/pre-push ] && [ -x .githooks/pre-push ]; then
  if echo "refs/heads/feat/x abc1234 refs/heads/main def5678" | \
       .githooks/pre-push >/dev/null 2>&1; then
    echo "  WARNING: pre-push hook FAILED to block a main push in smoke test"
  else
    echo "  [ok]   pre-push hook blocks main in smoke test"
  fi
fi

STACK="$(detect_stack)"
echo ""
echo "▶ Dependency bootstrap:"
echo "  detected stack: $STACK"
if [ "${BEADSWAVE_SETUP_INSTALL:-1}" = "0" ]; then
  echo "  [skip] disabled by BEADSWAVE_SETUP_INSTALL=0"
else
  bootstrap_dependencies "$STACK"
fi

warn_missing_env_files

echo ""
echo "▶ Required one-time actions (outside this script):"
echo ""
echo "  1. Ensure GitHub repo setting is on:"
echo "       Settings → General → Pull Requests → Automatically delete head branches"
echo ""
echo "▶ Verification:"
echo ""
echo "  • core.hooksPath     → $(git config --local --get core.hooksPath || echo '(unset)')"
echo "  • pre-push exec bit  → $( [ -x .githooks/pre-push ] && echo 'yes' || echo 'no' )"
echo "  • bd CLI present     → $( command -v bd >/dev/null && echo 'yes' || echo 'no' )"
echo "  • gh CLI present     → $( command -v gh >/dev/null && echo 'yes' || echo 'no' )"
echo "  • detected stack     → $STACK"
echo ""
echo "Setup complete."
