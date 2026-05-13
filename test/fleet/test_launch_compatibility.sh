#!/usr/bin/env bash
# TDD tests for dag-fleet launch.sh macOS compatibility
# Run: bash test_launch_compatibility.sh <path-to-launch.sh>

set -euo pipefail

LAUNCH_SH="${1:-/home/sagar/.pi/agent/skills/dag-fleet/scripts/launch.sh}"
FAIL=0
PASS=0

assert_contains() {
  local file="$1" needle="$2" msg="$3"
  if grep -qF "$needle" "$file"; then
    echo "  PASS: $msg"
    PASS=$((PASS+1))
  else
    echo "  FAIL: $msg (missing: $needle)"
    FAIL=$((FAIL+1))
  fi
}

assert_not_contains() {
  local file="$1" needle="$2" msg="$3"
  if grep -qF "$needle" "$file"; then
    echo "  FAIL: $msg (found forbidden: $needle)"
    FAIL=$((FAIL+1))
  else
    echo "  PASS: $msg"
    PASS=$((PASS+1))
  fi
}

echo "=== Testing launch.sh macOS compatibility ==="

# 1. flock fallback for macOS
assert_contains "$LAUNCH_SH" "command -v flock" "checks flock availability before use"
assert_contains "$LAUNCH_SH" "NO_FLOCK" "has NO_FLOCK fallback path"

# 2. bash version check
assert_contains "$LAUNCH_SH" "BASH_VERSINFO" "checks bash version for associative array support"

# 3. macOS-compatible worker lookup (no raw declare -A without guard)
# The script should either not use declare -A, or guard it
if grep -q "declare -A" "$LAUNCH_SH"; then
  if grep -q "BASH_VERSINFO\[0\]" "$LAUNCH_SH"; then
    echo "  PASS: declare -A is guarded by version check"
    PASS=$((PASS+1))
  else
    echo "  FAIL: declare -A present without bash version guard"
    FAIL=$((FAIL+1))
  fi
else
  echo "  PASS: no declare -A (bash 3.2 compatible)"
  PASS=$((PASS+1))
fi

# 4. flock fallback in worker spawn
assert_contains "$LAUNCH_SH" "try_flock" "worker spawn lock uses flock fallback helper"

echo ""
echo "=== Results ==="
echo "PASS: $PASS  FAIL: $FAIL"
exit $FAIL
