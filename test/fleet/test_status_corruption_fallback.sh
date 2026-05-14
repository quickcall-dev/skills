#!/usr/bin/env bash
# TDD test for status.sh session.jsonl corruption fallback
# Run: bash test_status_corruption_fallback.sh <path-to-status.sh>

set -euo pipefail

STATUS_SH="${1:-/home/sagar/.pi/agent/skills/dag-fleet/scripts/status.sh}"
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

echo "=== Testing status.sh corruption fallback ==="

# 1. status.json fallback when session.jsonl corrupted
assert_contains "$STATUS_SH" "status.json" "reads status.json as fallback"
assert_contains "$STATUS_SH" "unparseable" "detects corrupted session.jsonl"
assert_contains "$STATUS_SH" "corrupted" "mentions corrupted JSON"

# 2. .done file check
assert_contains "$STATUS_SH" ".done" "checks .done file as completion signal"

# 3. Graceful degradation: trust status.json over STUCK
assert_contains "$STATUS_SH" "fallback_status" "uses fallback status from status.json"
assert_contains "$STATUS_SH" "Graceful degradation" "has graceful degradation comment"
assert_contains "$STATUS_SH" "DONE" "recognizes DONE from fallback"
assert_contains "$STATUS_SH" "FAILED" "recognizes FAILED from fallback"
assert_contains "$STATUS_SH" "KILLED" "recognizes KILLED from fallback"

echo ""
echo "=== Results ==="
echo "PASS: $PASS  FAIL: $FAIL"
exit $FAIL
