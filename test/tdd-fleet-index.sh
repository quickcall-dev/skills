#!/usr/bin/env bash
# tdd-fleet-index.sh — verify FLEET-INDEX.md exists and lists all fleet types
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
# Test 1 — FLEET-INDEX.md exists in skills directory
# -------------------------------------------------------------------
run_fleet_index_exists() {
  if [[ -f "$REPO_ROOT/skills/FLEET-INDEX.md" ]]; then
    record "fleet-index-exists" PASS
  else
    record "fleet-index-exists" FAIL "(skills/FLEET-INDEX.md missing)"
  fi
}

# -------------------------------------------------------------------
# Test 2 — FLEET-INDEX.md mentions all fleet types
# -------------------------------------------------------------------
run_fleet_index_content() {
  local file="$REPO_ROOT/skills/FLEET-INDEX.md"
  if [[ ! -f "$file" ]]; then
    record "fleet-index-content" FAIL "(file missing, skipping content check)"
    return
  fi

  local missing=""
  for fleet in "dag-fleet" "worktree-fleet" "iterative-fleet" "autoresearch-fleet"; do
    if ! grep -q "$fleet" "$file" 2>/dev/null; then
      missing="$missing $fleet"
    fi
  done

  if [[ -z "$missing" ]]; then
    record "fleet-index-content" PASS
  else
    record "fleet-index-content" FAIL "(missing:$missing)"
  fi
}

# -------------------------------------------------------------------
# Test 3 — fleet-plan SKILL.md references FLEET-INDEX.md
# -------------------------------------------------------------------
run_fleet_plan_refs_index() {
  local file="$REPO_ROOT/skills/fleet-plan/SKILL.md"
  if grep -q "FLEET-INDEX" "$file" 2>/dev/null; then
    record "fleet-plan-refs-index" PASS
  else
    record "fleet-plan-refs-index" FAIL "(no FLEET-INDEX reference)"
  fi
}

# -------------------------------------------------------------------
# Run
# -------------------------------------------------------------------
run_fleet_index_exists
run_fleet_index_content
run_fleet_plan_refs_index

echo
echo "============================================================"
echo "SUMMARY: ${#PASS[@]} passed, ${#FAIL[@]} failed"
echo "============================================================"
for p in "${PASS[@]}"; do echo "  PASS  $p"; done
for f in "${FAIL[@]}"; do echo "  FAIL  $f"; done

exit "${#FAIL[@]}"
