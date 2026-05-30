#!/usr/bin/env bash
# tdd-no-fleet-index.sh — verify FLEET-INDEX.md is removed and fleet-plan
# inlines all fleet type guidance. No external index dependency.
#
# Run from repo root.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=()
FAIL=()

record() {
  local name="$1" status="$2" note="${3:-}"
  if [[ "$status" == "PASS" ]]; then
    PASS+=("$name")
    echo -e "\033[0;32m[PASS]\033[0m $name ${note}"
  else
    FAIL+=("$name")
    echo -e "\033[0;31m[FAIL]\033[0m $name ${note}"
  fi
}

# -------------------------------------------------------------------
# Test 1 — No FLEET-INDEX.md anywhere in skills/ tree
# -------------------------------------------------------------------
run_no_fleet_index() {
  local hits
  hits=$(find "$REPO_ROOT/skills" -name "FLEET-INDEX.md" 2>/dev/null | wc -l)
  if [[ "$hits" == "0" ]]; then
    record "no-fleet-index" PASS
  else
    record "no-fleet-index" FAIL "($hits FLEET-INDEX.md files found)"
    find "$REPO_ROOT/skills" -name "FLEET-INDEX.md" 2>/dev/null
  fi
}

# -------------------------------------------------------------------
# Test 2 — fleet-plan SKILL.md does NOT reference FLEET-INDEX
# -------------------------------------------------------------------
run_fleet_plan_no_ref() {
  local hits
  hits=$(grep -c "FLEET-INDEX" "$REPO_ROOT/skills/fleet-plan/SKILL.md" 2>/dev/null)
  if [[ "$hits" == "0" ]]; then
    record "fleet-plan-no-index-ref" PASS
  else
    record "fleet-plan-no-index-ref" FAIL "($hits references remain)"
    grep -n "FLEET-INDEX" "$REPO_ROOT/skills/fleet-plan/SKILL.md"
  fi
}

# -------------------------------------------------------------------
# Test 3 — fleet-plan SKILL.md inlines all 4 fleet types
# -------------------------------------------------------------------
run_fleet_plan_inline_types() {
  local file="$REPO_ROOT/skills/fleet-plan/SKILL.md"
  local missing=""
  for fleet in "dag-fleet" "worktree-fleet" "iterative-fleet" "autoresearch-fleet"; do
    if ! grep -q "$fleet" "$file" 2>/dev/null; then
      missing="$missing $fleet"
    fi
  done
  if [[ -z "$missing" ]]; then
    record "fleet-plan-inline-types" PASS
  else
    record "fleet-plan-inline-types" FAIL "(missing:$missing)"
  fi
}

# -------------------------------------------------------------------
# Test 4 — fleet-plan SKILL.md has decision tree inline
# -------------------------------------------------------------------
run_fleet_plan_decision_tree() {
  local file="$REPO_ROOT/skills/fleet-plan/SKILL.md"
  if grep -q "Q1:" "$file" 2>/dev/null && grep -q "STOP" "$file" 2>/dev/null; then
    record "fleet-plan-decision-tree" PASS
  else
    record "fleet-plan-decision-tree" FAIL "(no decision tree found)"
  fi
}

# -------------------------------------------------------------------
# Run
# -------------------------------------------------------------------
run_no_fleet_index
run_fleet_plan_no_ref
run_fleet_plan_inline_types
run_fleet_plan_decision_tree

echo
echo "============================================================"
echo "SUMMARY: ${#PASS[@]} passed, ${#FAIL[@]} failed"
echo "============================================================"
for p in "${PASS[@]}"; do echo "  PASS  $p"; done
for f in "${FAIL[@]}"; do echo "  FAIL  $f"; done

exit "${#FAIL[@]}"
