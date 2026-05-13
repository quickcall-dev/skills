#!/usr/bin/env bash
# TDD tests for fleet-plan/SKILL.md rules
# Run: bash test_fleet_plan_rules.sh <path-to-fleet-plan-SKILL.md>

set -euo pipefail

SKILL="${1:-/home/sagar/.pi/agent/skills/fleet-plan/SKILL.md}"
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

echo "=== Testing fleet-plan/SKILL.md guardrails ==="

# 1. Guardrail for unsupported provider/model
assert_contains "$SKILL" "unsupported provider" "has unsupported provider guardrail"
assert_contains "$SKILL" "never silently emit" "prohibits silent invalid config emission"
assert_contains "$SKILL" "map to closest valid" "has mapping rule for invalid requests"

# 2. max_turns prohibition
assert_contains "$SKILL" "do not set max_turns" "reinforces max_turns prohibition"
assert_contains "$SKILL" "budget is the only limiter" "budget-only limiter rule present"

# 3. Status command uses path
assert_contains "$SKILL" "status.sh <fleet-root>" "status command uses fleet-root path"
assert_contains "$SKILL" "absolute path" "status command clarifies absolute path"

# 4. type field required
assert_contains "$SKILL" "type.*worktree.*dag.*iterative" "type field documented with valid values"
assert_contains "$SKILL" "required top-level" "type field marked as required"

# 5. Config → prompt sync
assert_contains "$SKILL" "regenerate ALL.*prompt.md" "prompt regeneration rule after config change"
assert_contains "$SKILL" "After ANY change" "mentions config change propagation"

# 6. Prerequisite checks
assert_contains "$SKILL" "prerequisite" "has prerequisite check step"
assert_contains "$SKILL" "bash >= 4" "checks bash version"
assert_contains "$SKILL" "flock" "checks flock availability"

# 7. Model family guidance
assert_contains "$SKILL" "Model family guidance" "has model family guidance section"
assert_contains "$SKILL" "Claude family" "documents Claude family mapping"
assert_contains "$SKILL" "Pi / Kimi family" "documents Pi/Kimi family mapping"
assert_contains "$SKILL" "Codex / GPT family" "documents Codex/GPT family mapping"
assert_contains "$SKILL" "Match model capability to task complexity" "has model-task complexity rule"

echo ""
echo "=== Results ==="
echo "PASS: $PASS  FAIL: $FAIL"
exit $FAIL
