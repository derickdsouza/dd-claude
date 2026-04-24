#!/usr/bin/env bash
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

count=0
for test_script in "$TESTS_DIR"/test-*.sh; do
  [[ -e "$test_script" ]] || continue
  echo "==> $(basename "$test_script")"
  bash "$test_script"
  count=$((count + 1))
done

echo "PASS - ${count} test scripts"
