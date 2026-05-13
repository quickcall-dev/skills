#!/usr/bin/env bash
# TDD tests for dag-fleet/SKILL.md OS compatibility docs
# Run: bash test_dag_fleet_skill.sh <path-to-dag-fleet-SKILL.md>

set -euo pipefail

SKILL="${1:-/home/sagar/.pi/agent/skills/dag-fleet/SKILL.md}"
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

echo "=== Testing dag-fleet/SKILL.md OS compatibility ==="

# 1. macOS / bash compatibility
assert_contains "$SKILL" "bash 4" "documents bash 4.0+ requirement"
assert_contains "$SKILL" "macos\|macOS\|darwin" "mentions macOS compatibility"
assert_contains "$SKILL" "flock" "documents flock requirement"
assert_contains "$SKILL" "homebrew\|brew" "suggests brew install for macOS deps"

# 2. --no-lock flag
assert_contains "$SKILL" "no-lock" "documents --no-lock flag"

# 3. Pre-flight checks
assert_contains "$SKILL" "prerequisite" "has prerequisite check section"

# 4. Model family guidance
assert_contains "$SKILL" "Model family guidance" "has model family guidance section"
assert_contains "$SKILL" "Claude family" "documents Claude family mapping"
assert_contains "$SKILL" "Pi / Kimi family" "documents Pi/Kimi family mapping"
assert_contains "$SKILL" "Codex / GPT family" "documents Codex/GPT family mapping"
assert_contains "$SKILL" "Match model capability to task complexity" "has model-task complexity rule"

echo ""
echo "=== Results ==="
echo "PASS: $PASS  FAIL: $FAIL"
exit $FAIL
