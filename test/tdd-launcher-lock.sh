#!/usr/bin/env bash
# tdd-launcher-lock.sh — verify L scenario: second launch refused when first holds lock
#
# The key invariant: when launch.sh is already active, a second invocation
# must exit 2 AND .launch.pid must point to a live process.
# We do NOT check that .launch.pid == the original shell pid, because
# with HAS_DEPS>0 the supervisor fork overwrites .launch.pid with its own.

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

run_L() {
  local root
  root="/tmp/fleet-test-lock-$$"
  rm -rf "$root"; mkdir -p "$root"

  # Use DAG fixture (has deps → forks supervisor)
  bash "$REPO_ROOT/test/fleet/dag-fleet/fixtures-claude/setup-fleet.sh" dag "$root" >/dev/null
  export PATH="$REPO_ROOT/test/fleet/dag-fleet/fixtures-claude/shim:${PATH}"

  # First launch
  bash "$REPO_ROOT/skills/dag-fleet/scripts/launch.sh" "$root" >"$root/launch1.out" 2>&1 &
  local lpid=$!
  sleep 5

  # Second launch (should be refused)
  bash "$REPO_ROOT/skills/dag-fleet/scripts/launch.sh" "$root" >"$root/launch2.out" 2>&1
  local rc=$?

  # Invariant: rc must be 2 (lock refusal)
  if [[ "$rc" != "2" ]]; then
    record "L-lock-refused" FAIL "(rc=$rc, expected 2)"
    cat "$root/launch2.out"
    kill "$lpid" 2>/dev/null || true
    tmux kill-session -t fleet-test-dag 2>/dev/null || true
    rm -rf "$root"
    return
  fi

  # Invariant: .launch.pid must exist and point to a live process
  local lock_pid
  lock_pid=$(cat "$root/.launch.pid" 2>/dev/null || echo "")
  if [[ -z "$lock_pid" ]]; then
    record "L-pid-file-exists" FAIL "(.launch.pid missing)"
    kill "$lpid" 2>/dev/null || true
    tmux kill-session -t fleet-test-dag 2>/dev/null || true
    rm -rf "$root"
    return
  fi

  if ! kill -0 "$lock_pid" 2>/dev/null; then
    record "L-pid-alive" FAIL "(pid $lock_pid is dead)"
    kill "$lpid" 2>/dev/null || true
    tmux kill-session -t fleet-test-dag 2>/dev/null || true
    rm -rf "$root"
    return
  fi

  # All invariants hold
  record "L-wedged-launcher-lock" PASS "(rc=2, lock_pid=$lock_pid alive)"

  wait "$lpid" 2>/dev/null || true
  tmux kill-session -t fleet-test-dag 2>/dev/null || true
  rm -rf "$root"
}

run_L

echo
echo "============================================================"
echo "SUMMARY: ${#PASS[@]} passed, ${#FAIL[@]} failed"
echo "============================================================"
for p in "${PASS[@]}"; do echo "  PASS  $p"; done
for f in "${FAIL[@]}"; do echo "  FAIL  $f"; done

exit "${#FAIL[@]}"
