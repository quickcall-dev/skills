#!/usr/bin/env bash
# Test scenarios for worktree-fleet skill
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
  local root="/tmp/fleet-test-worktree-${name}-$$"
  mkdir -p "$root"
  echo "$root"
}

cleanup_root() {
  rm -rf "$1" 2>/dev/null || true
}

# -------------------------------------------------------------------
# Scenario W1 — Independence validation passes for non-overlapping workers
# -------------------------------------------------------------------
run_W1() {
  local root; root=$(mkroot independent)
  cp "${FIXTURES_DIR}/independent-fleet.json" "$root/fleet.json"
  local rc=0
  bash "${SCRIPTS}/launch.sh" "$root" --dry-run >"$root/launch.out" 2>&1 || rc=$?
  if [[ "$rc" == "0" ]] && grep -q "independence.*pass\|validated\|no overlap" "$root/launch.out" 2>/dev/null; then
    record "W1 independence-validation-pass" PASS
  else
    record "W1 independence-validation-pass" FAIL "(rc=$rc)"
    tail -5 "$root/launch.out" 2>/dev/null || true
  fi
  cleanup_root "$root"
}

# -------------------------------------------------------------------
# Scenario W2 — Independence validation REJECTS overlapping target_files
# -------------------------------------------------------------------
run_W2() {
  local root; root=$(mkroot overlap)
  cp "${FIXTURES_DIR}/overlapping-fleet.json" "$root/fleet.json"
  local rc=0
  bash "${SCRIPTS}/launch.sh" "$root" --dry-run >"$root/launch.out" 2>&1 || rc=$?
  if [[ "$rc" != "0" ]] && grep -q "overlap\|conflict\|target_files" "$root/launch.out" 2>/dev/null; then
    record "W2 independence-validation-reject-overlap" PASS
  else
    record "W2 independence-validation-reject-overlap" FAIL "(rc=$rc — expected nonzero with overlap message)"
    tail -5 "$root/launch.out" 2>/dev/null || true
  fi
  cleanup_root "$root"
}

# -------------------------------------------------------------------
# Scenario W3 — Worktrees are created per worker
# After launch, each worker has its own git worktree on its own branch
# -------------------------------------------------------------------
run_W3() {
  local root; root=$(mkroot worktrees)
  cp "${FIXTURES_DIR}/independent-fleet.json" "$root/fleet.json"
  local rc=0
  bash "${SCRIPTS}/launch.sh" "$root" >"$root/launch.out" 2>&1 || rc=$?
  if [[ "$rc" != "0" ]]; then
    record "W3 worktrees-created" FAIL "(launch rc=$rc)"
    tail -5 "$root/launch.out" 2>/dev/null || true
    cleanup_root "$root"
    return
  fi
  # Check worktrees exist
  local wt_count=0
  for branch in rename-foo add-bar fix-docs; do
    git worktree list 2>/dev/null | grep -q "$branch" && wt_count=$((wt_count + 1))
  done
  if [[ "$wt_count" -eq 3 ]]; then
    record "W3 worktrees-created" PASS "(3 worktrees)"
  else
    record "W3 worktrees-created" FAIL "(expected 3 worktrees, found $wt_count)"
  fi
  # Cleanup worktrees
  bash "${SCRIPTS}/cleanup.sh" "$root" --force >/dev/null 2>&1 || true
  cleanup_root "$root"
}

# -------------------------------------------------------------------
# Scenario W4 — Cleanup removes worktrees
# -------------------------------------------------------------------
run_W4() {
  local root; root=$(mkroot cleanup)
  cp "${FIXTURES_DIR}/independent-fleet.json" "$root/fleet.json"
  bash "${SCRIPTS}/launch.sh" "$root" >"$root/launch.out" 2>&1 || true
  # Wait for workers to finish (they're fake/fast)
  sleep 5
  local before; before=$(git worktree list 2>/dev/null | grep -c "fleet-test-worktree" 2>/dev/null || echo 0); before=${before%%$'\n'*}
  bash "${SCRIPTS}/cleanup.sh" "$root" --force >"$root/cleanup.out" 2>&1
  local after; after=$(git worktree list 2>/dev/null | grep -c "fleet-test-worktree" 2>/dev/null || echo 0); after=${after%%$'\n'*}
  if [[ "$after" -eq 0 ]]; then
    record "W4 cleanup-removes-worktrees" PASS "(before=$before after=$after)"
  else
    record "W4 cleanup-removes-worktrees" FAIL "(before=$before after=$after)"
  fi
  cleanup_root "$root"
}

run_W1
run_W2
run_W3
run_W4

echo
echo "============================================================"
echo "SUMMARY: ${#PASS[@]} passed, ${#FAIL[@]} failed"
echo "============================================================"
for p in "${PASS[@]}"; do echo "  PASS  $p"; done
for f in "${FAIL[@]}"; do echo "  FAIL  $f"; done

exit "${#FAIL[@]}"
