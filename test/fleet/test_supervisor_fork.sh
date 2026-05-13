#!/usr/bin/env bash
# TDD test for supervisor fork SIGHUP fix
# Run: bash test_supervisor_fork.sh <path-to-launch.sh>

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

echo "=== Testing supervisor fork SIGHUP protection ==="

assert_contains "$LAUNCH_SH" "trap '' HUP" "child ignores HUP signal"
assert_contains "$LAUNCH_SH" "disown -h" "disown uses -h to prevent SIGHUP"
assert_contains "$LAUNCH_SH" "supervisor.log" "child stdout/stderr redirected to log file"
assert_contains "$LAUNCH_SH" "SIGPIPE cannot kill us" "comment explains SIGPIPE protection"

echo ""
echo "=== Results ==="
echo "PASS: $PASS  FAIL: $FAIL"
exit $FAIL
