#!/usr/bin/env bash
# Codex provider test scenarios for worktree-fleet skill
# Usage: run-all.sh <skill-dir>
#   e.g. run-all.sh skills/worktree-fleet

set -uo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: run-all.sh <worktree-fleet-skill-dir>" >&2
  exit 99
fi

SKILL_DIR="$(cd "$1" && pwd)"
SCRIPTS="${SKILL_DIR}/scripts"
FIXTURES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

for s in launch.sh status.sh merge.sh cleanup.sh; do
  [[ -f "${SCRIPTS}/${s}" ]] || { echo "missing ${SCRIPTS}/${s}" >&2; exit 99; }
done

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

mkroot() {
  local name="$1"
  local root="/tmp/fleet-test-codex-worktree-${name}-$$"
  mkdir -p "$root"
  echo "$root"
}

cleanup_root() {
  rm -rf "$1" 2>/dev/null || true
}

# -------------------------------------------------------------------
# Scenario CW1 — Independence validation passes (codex provider)
# -------------------------------------------------------------------
run_CW1() {
  local root; root=$(mkroot independent)
  cp "${FIXTURES_DIR}/independent-fleet.json" "$root/fleet.json"
  local rc=0
  bash "${SCRIPTS}/launch.sh" "$root" --dry-run >"$root/launch.out" 2>&1 || rc=$?
  if [[ "$rc" == "0" ]] && grep -q "independence.*pass\|validated\|no overlap" "$root/launch.out" 2>/dev/null; then
    record "CW1 independence-validation-pass (codex)" PASS
  else
    record "CW1 independence-validation-pass (codex)" FAIL "(rc=$rc)"
    tail -5 "$root/launch.out" 2>/dev/null || true
  fi
  cleanup_root "$root"
}

# -------------------------------------------------------------------
# Scenario CW2 — Independence validation REJECTS overlap (codex provider)
# -------------------------------------------------------------------
run_CW2() {
  local root; root=$(mkroot overlap)
  cp "${FIXTURES_DIR}/overlapping-fleet.json" "$root/fleet.json"
  local rc=0
  bash "${SCRIPTS}/launch.sh" "$root" --dry-run >"$root/launch.out" 2>&1 || rc=$?
  if [[ "$rc" != "0" ]] && grep -q "overlap\|conflict\|target_files" "$root/launch.out" 2>/dev/null; then
    record "CW2 independence-validation-reject-overlap (codex)" PASS
  else
    record "CW2 independence-validation-reject-overlap (codex)" FAIL "(rc=$rc)"
    tail -5 "$root/launch.out" 2>/dev/null || true
  fi
  cleanup_root "$root"
}

# -------------------------------------------------------------------
# Scenario CW3 — Provider field parsed from fleet.json
# Verify launch.sh reads provider:"codex" and doesn't error on missing claude
# -------------------------------------------------------------------
run_CW3() {
  local root; root=$(mkroot provider)
  cp "${FIXTURES_DIR}/independent-fleet.json" "$root/fleet.json"
  local rc=0
  bash "${SCRIPTS}/launch.sh" "$root" --dry-run >"$root/launch.out" 2>&1 || rc=$?
  # Should NOT complain about missing claude CLI since provider is codex
  local claude_error=0
  grep -q "claude.*not found\|claude.*required" "$root/launch.out" 2>/dev/null && claude_error=1
  if [[ "$rc" == "0" && "$claude_error" == "0" ]]; then
    record "CW3 provider-codex-parsed (no claude error)" PASS
  else
    record "CW3 provider-codex-parsed (no claude error)" FAIL "(rc=$rc claude_error=$claude_error)"
    tail -5 "$root/launch.out" 2>/dev/null || true
  fi
  cleanup_root "$root"
}

run_CW1
run_CW2
run_CW3

echo
echo "============================================================"
echo "CODEX WORKTREE-FLEET SUMMARY: ${#PASS[@]} passed, ${#FAIL[@]} failed"
echo "============================================================"
for p in "${PASS[@]}"; do echo "  PASS  $p"; done
for f in "${FAIL[@]}"; do echo "  FAIL  $f"; done

exit "${#FAIL[@]}"
