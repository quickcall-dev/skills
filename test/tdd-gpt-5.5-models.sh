#!/usr/bin/env bash
# tdd-gpt-5.5-models.sh — verify that gpt-5.5 is documented as a valid model
# in all skill markdown files that list Codex / GPT models.
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
# Test 1 — Any skill markdown that mentions gpt-5.4 must also mention gpt-5.5
# -------------------------------------------------------------------
run_gpt55_mentioned() {
  local files_missing=""
  # Find all markdown files under skills/ that mention gpt-5.4
  local files_with_gpt54
  files_with_gpt54=$(grep -rln "gpt-5\.4" "$REPO_ROOT/skills/" 2>/dev/null | grep '\.md$' || true)

  for f in $files_with_gpt54; do
    if ! grep -q "gpt-5\.5" "$f" 2>/dev/null; then
      files_missing="$files_missing\n  $f"
    fi
  done

  if [[ -z "$files_missing" ]]; then
    record "gpt-5.5-documented" PASS
  else
    record "gpt-5.5-documented" FAIL "(missing in:$files_missing)"
  fi
}

# -------------------------------------------------------------------
# Test 2 — fleet-plan SKILL.md must list gpt-5.5 in valid models section
# -------------------------------------------------------------------
run_fleet_plan_gpt55() {
  local file="$REPO_ROOT/skills/fleet-plan/SKILL.md"
  if grep -q "gpt-5\.5" "$file" 2>/dev/null; then
    record "fleet-plan-gpt-5.5" PASS
  else
    record "fleet-plan-gpt-5.5" FAIL "(not in valid models)"
  fi
}

# -------------------------------------------------------------------
# Test 3 — dag-fleet SKILL.md must list gpt-5.5 in Codex aliases
# -------------------------------------------------------------------
run_dag_fleet_gpt55() {
  local file="$REPO_ROOT/skills/dag-fleet/SKILL.md"
  if grep -q "gpt-5\.5" "$file" 2>/dev/null; then
    record "dag-fleet-gpt-5.5" PASS
  else
    record "dag-fleet-gpt-5.5" FAIL "(not in Codex model aliases)"
  fi
}

# -------------------------------------------------------------------
# Run
# -------------------------------------------------------------------
run_gpt55_mentioned
run_fleet_plan_gpt55
run_dag_fleet_gpt55

echo
echo "============================================================"
echo "SUMMARY: ${#PASS[@]} passed, ${#FAIL[@]} failed"
echo "============================================================"
for p in "${PASS[@]}"; do echo "  PASS  $p"; done
for f in "${FAIL[@]}"; do echo "  FAIL  $f"; done

exit "${#FAIL[@]}"
