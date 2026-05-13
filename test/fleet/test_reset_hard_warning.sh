#!/usr/bin/env bash
# TDD tests for reset.sh --hard log destruction warning
# Run: bash test_reset_hard_warning.sh <path-to-reset.sh>

set -euo pipefail

RESET_SH="${1:-/home/sagar/.pi/agent/skills/dag-fleet/scripts/reset.sh}"
FAIL=0
PASS=0

assert_contains() {
  local file="$1" needle="$2" msg="$3"
  if grep -qi "$needle" "$file"; then
    echo "  PASS: $msg"
    PASS=$((PASS+1))
  else
    echo "  FAIL: $msg (missing: $needle)"
    FAIL=$((FAIL+1))
  fi
}

echo "=== Testing reset.sh --hard warnings ==="

# 1. Warning about log destruction
assert_contains "$RESET_SH" "archive" "mentions archiving before hard reset"
assert_contains "$RESET_SH" "log" "mentions logs in reset context"
assert_contains "$RESET_SH" "DELETE\|delete" "warns about destruction"

# 2. --hard description in usage/docs
assert_contains "$RESET_SH" "hard" "documents --hard flag"

echo ""
echo "=== Results ==="
echo "PASS: $PASS  FAIL: $FAIL"
exit $FAIL
