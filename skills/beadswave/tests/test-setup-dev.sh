#!/usr/bin/env bash
set -euo pipefail

. "$(dirname "$0")/lib/testlib.sh"

test_setup_dev_bootstraps_bun_worktree_and_warns_on_missing_env() (
  set -euo pipefail
  local tmp output
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  create_basic_repo "$tmp/repo"
  mkdir -p "$tmp/repo/.githooks" "$tmp/bin"
  printf '{}' > "$tmp/repo/bun.lock"
  printf '{ "name": "demo" }\n' > "$tmp/repo/package.json"
  printf 'EXAMPLE=1\n' > "$tmp/repo/.env.example"
  cat > "$tmp/repo/.githooks/pre-push" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
  chmod +x "$tmp/repo/.githooks/pre-push"

  export TRACE_FILE="$tmp/trace.log"
  cat > "$tmp/bin/bun" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
trace="${TRACE_FILE:?}"
{
  printf 'bun'
  for arg in "$@"; do
    printf '\t%q' "$arg"
  done
  printf '\n'
} >> "$trace"
exit 0
EOF
  chmod +x "$tmp/bin/bun"
  export PATH="$tmp/bin:$PATH"

  output="$(cd "$tmp/repo" && "$SETUP_DEV_SCRIPT" 2>&1)"

  assert_contains "$output" "detected stack: bun"
  assert_contains "$output" "WARNING: missing .env"
  assert_file_contains "$TRACE_FILE" $'bun\tinstall'
)

run_test "setup-dev bootstraps bun worktrees and warns on missing env files" test_setup_dev_bootstraps_bun_worktree_and_warns_on_missing_env
