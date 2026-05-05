#!/usr/bin/env bash
# tdd-timers.sh — verify per-worker elapsed timers in all fleet status.sh
#
# Checks:
#   1. dag-fleet status.sh shows ELAPSED column per worker
#   2. worktree-fleet status.sh shows ELAPSED column per worker
#   3. autoresearch-fleet status.sh shows per-iteration duration

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

# Helper: format seconds like the fleet scripts do
fmt_dur() {
  local s=$1
  if [[ $s -lt 60 ]]; then
    printf '%ds' "$s"
  elif [[ $s -lt 3600 ]]; then
    printf '%dm %ds' $((s/60)) $((s%60))
  else
    printf '%dh %dm' $((s/3600)) $((s%3600/60))
  fi
}

# -------------------------------------------------------------------
# Test 1 — dag-fleet status.sh shows per-worker ELAPSED
# -------------------------------------------------------------------
run_dag_timer() {
  local root
  root="/tmp/fleet-test-dag-timer-$$"
  rm -rf "$root"; mkdir -p "$root"

  # Setup fake dag fleet with one worker
  bash "$REPO_ROOT/test/fleet/dag-fleet/fixtures-pi/setup-fleet.sh" completion "$root" >/dev/null

  # Create a fake session.jsonl with known age (created 90s ago, modified 30s ago)
  # Worker ran for ~60s
  mkdir -p "$root/workers/w1/output"
  local ts_old ts_new
  ts_old=$(date -u -d '120 seconds ago' +%Y-%m-%dT%H:%M:%SZ)
  ts_new=$(date -u -d '30 seconds ago' +%Y-%m-%dT%H:%M:%SZ)
  cat > "$root/workers/w1/session.jsonl" <<EOF
{"type":"session","id":"sess1","timestamp":"$ts_old"}
{"type":"message","id":"msg1","timestamp":"$ts_new","message":{"role":"assistant","content":[{"type":"text","text":"Done"}],"usage":{"input":1000,"output":500},"stopReason":"stop"}}
EOF
  # Set file times: birth=120s ago, mtime=30s ago
  touch -d '120 seconds ago' "$root/workers/w1/session.jsonl"
  touch -d '30 seconds ago' "$root/workers/w1/session.jsonl"

  # Run status.sh and capture output
  local out
  out=$(bash "$REPO_ROOT/skills/dag-fleet/scripts/status.sh" "$root" 2>/dev/null)

  # Check for ELAPSED column header
  if echo "$out" | grep -q 'ELAPSED'; then
    # Check for actual duration value (not "n/a" or "—")
    if echo "$out" | grep -E 'w1.*RUNNING|w1.*DONE' | grep -qE '[0-9]+[smh]'; then
      record "dag-fleet-worker-timer" PASS
    else
      record "dag-fleet-worker-timer" FAIL "(has ELAPSED header but no duration value)"
      echo "$out" | grep -E 'w1' | head -1
    fi
  else
    record "dag-fleet-worker-timer" FAIL "(no ELAPSED column in status output)"
    echo "$out" | head -5
  fi

  rm -rf "$root"
}

# -------------------------------------------------------------------
# Test 2 — worktree-fleet status.sh shows per-worker ELAPSED
# -------------------------------------------------------------------
run_worktree_timer() {
  local root
  root="/tmp/fleet-test-worktree-timer-$$"
  rm -rf "$root"; mkdir -p "$root"

  # Minimal worktree fleet.json
  cat > "$root/fleet.json" <<'EOF'
{"fleet_name":"test-worktree","workers":[{"id":"wt1","branch":"feat-1","task":"test"}]}
EOF

  mkdir -p "$root/workers/wt1"
  local ts
  ts=$(date -u -d '90 seconds ago' +%Y-%m-%dT%H:%M:%SZ)
  cat > "$root/workers/wt1/session.jsonl" <<EOF
{"type":"message","id":"msg1","timestamp":"$ts","message":{"role":"assistant","content":[{"type":"text","text":"Done"}],"usage":{"input":1000,"output":500},"stopReason":"stop"}}
EOF
  touch -d '90 seconds ago' "$root/workers/wt1/session.jsonl"
  touch -d '10 seconds ago' "$root/workers/wt1/session.jsonl"

  local out
  out=$(bash "$REPO_ROOT/skills/worktree-fleet/scripts/status.sh" "$root" 2>/dev/null)

  if echo "$out" | grep -q 'ELAPSED'; then
    if echo "$out" | grep -E 'wt1.*RUNNING|wt1.*DONE' | grep -qE '[0-9]+[smh]'; then
      record "worktree-fleet-worker-timer" PASS
    else
      record "worktree-fleet-worker-timer" FAIL "(has ELAPSED header but no duration value)"
      echo "$out" | grep -E 'wt1' | head -1
    fi
  else
    record "worktree-fleet-worker-timer" FAIL "(no ELAPSED column in status output)"
    echo "$out" | head -5
  fi

  rm -rf "$root"
}

# -------------------------------------------------------------------
# Test 3 — autoresearch-fleet status.sh shows per-iteration duration
# -------------------------------------------------------------------
run_autoresearch_timer() {
  local root
  root="/tmp/fleet-test-autoresearch-timer-$$"
  rm -rf "$root"; mkdir -p "$root"

  # Minimal autoresearch fleet.json
  cat > "$root/fleet.json" <<'EOF'
{"fleet_name":"test-ar","problem":{"results_file":"results.tsv"}}
EOF

  # Create iteration logs with known age
  mkdir -p "$root/logs"
  local ts
  ts=$(date -u -d '180 seconds ago' +%Y-%m-%dT%H:%M:%SZ)
  cat > "$root/logs/session-iter-1.jsonl" <<EOF
{"type":"session","id":"s1","timestamp":"$ts"}
{"type":"message","id":"m1","timestamp":"$ts","message":{"role":"assistant","content":[{"type":"text","text":"iter 1"}],"usage":{"input":1000,"output":500},"stopReason":"stop"}}
EOF
  touch -d '180 seconds ago' "$root/logs/session-iter-1.jsonl"
  touch -d '60 seconds ago' "$root/logs/session-iter-1.jsonl"

  # orch state
  cat > "$root/.orch-state.json" <<'EOF'
{"current_iteration":2,"trailing_discards":0,"is_search":false,"best_metric":"0.5","status":"running"}
EOF

  local out
  out=$(bash "$REPO_ROOT/skills/autoresearch-fleet/scripts/status.sh" "$root" 2>/dev/null)

  # Check for duration next to iteration cost (e.g. "iter 1  1m 30s  $0.05")
  if echo "$out" | grep -qE 'iter [0-9]+.*[0-9]+[smh].*\$'; then
    record "autoresearch-iteration-timer" PASS
  else
    record "autoresearch-iteration-timer" FAIL "(no iteration duration in status output)"
    echo "$out" | grep -iE 'iter [0-9]+' | head -10
  fi

  rm -rf "$root"
}

# -------------------------------------------------------------------
# Run all
# -------------------------------------------------------------------
run_dag_timer
run_worktree_timer
run_autoresearch_timer

echo
echo "============================================================"
echo "SUMMARY: ${#PASS[@]} passed, ${#FAIL[@]} failed"
echo "============================================================"
for p in "${PASS[@]}"; do echo "  PASS  $p"; done
for f in "${FAIL[@]}"; do echo "  FAIL  $f"; done

exit "${#FAIL[@]}"
