#!/usr/bin/env bash
# run-all.sh — drive Pi-specific scenarios P1–P7 plus E, G, K, L in sequence
# against the fake-pi fixtures, each in isolation, print a pass/fail summary.
#
# Usage:
#   run-all.sh <fleet-skill-dir>
#
# Exit code = number of failed scenarios. Does NOT bail on first failure.

set -u

if [[ $# -ne 1 ]]; then
  echo "usage: run-all.sh <fleet-skill-dir>" >&2
  exit 99
fi

SKILL_DIR="$(cd "$1" && pwd)"
SCRIPTS="${SKILL_DIR}/scripts"
FIXTURES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

for s in launch.sh kill.sh status.sh report.sh; do
  [[ -f "${SCRIPTS}/${s}" ]] || { echo "missing ${SCRIPTS}/${s}" >&2; exit 99; }
done

# Activate fake pi shim ahead of the real CLI.
# Also add claude shim for mixed-provider tests (P5).
export PATH="${FIXTURES_DIR}/shim:$(dirname "$FIXTURES_DIR")/fixtures-claude/shim:${PATH}"
if [[ "$(command -v pi)" != "${FIXTURES_DIR}/shim/pi" ]]; then
  echo "WARN: PATH override failed, pi resolves to $(command -v pi)" >&2
fi

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

cleanup_session() {
  local sess="$1"
  tmux has-session -t "$sess" 2>/dev/null && tmux kill-session -t "$sess" 2>/dev/null || true
}

cleanup_root() {
  local root="$1"
  pkill -f "FLEET_ROOT=${root}" 2>/dev/null || true
  sleep 1
  rm -rf "$root"
}

mkroot() {
  local tag="$1"
  local root="/tmp/fleet-test-fixtures-${tag}-$$"
  rm -rf "$root"
  mkdir -p "$root"
  echo "$root"
}

# -------------------------------------------------------------------
# Scenario P1 — Pi JSONL terminal detection
# -------------------------------------------------------------------
run_P1() {
  local root; root=$(mkroot pi-P1)
  bash "${FIXTURES_DIR}/setup-fleet.sh" completion "$root" >/dev/null
  bash "${SCRIPTS}/launch.sh" "$root" >"$root/launch.out" 2>&1 &
  local lpid=$!
  wait "$lpid" 2>/dev/null || true
  sleep 35
  local stops; stops=$(grep -l '"stopReason":"stop"' "$root"/workers/*/session.jsonl 2>/dev/null | wc -l)
  local status_done; status_done=$(bash "${SCRIPTS}/status.sh" "$root" --json 2>/dev/null | jq '[.workers[] | select(.status == "DONE")] | length')
  if [[ "$stops" == "3" && "$status_done" == "3" ]]; then
    record "P1 pi-terminal-detection" PASS "(stops=$stops done=$status_done)"
  else
    record "P1 pi-terminal-detection" FAIL "(stops=$stops done=$status_done)"
  fi
  cleanup_session fleet-test-completion-pi
  cleanup_root "$root"
}

# -------------------------------------------------------------------
# Scenario P2 — Pi tool allowlist
# -------------------------------------------------------------------
run_P2() {
  local root; root=$(mkroot pi-P2)
  bash "${FIXTURES_DIR}/setup-fleet.sh" dag "$root" >/dev/null
  # Patch worker types (use first-wave workers a,b,d,e; c/f have deps)
  jq '.workers[0].type = "read-only" | .workers[1].type = "write" | .workers[3].type = "reviewer" | .workers[4].type = "research"' "$root/fleet.json" > "$root/fleet.json.tmp" && mv "$root/fleet.json.tmp" "$root/fleet.json"
  bash "${SCRIPTS}/launch.sh" "$root" >"$root/launch.out" 2>&1 &
  local lpid=$!
  sleep 8
  local ro_tools; ro_tools=$(sed -n "s/.*\(--tools '[^']*'\).*/\1/p" "$root/workers/a/.run.sh" 2>/dev/null | head -1)
  local wr_tools; wr_tools=$(sed -n "s/.*\(--tools '[^']*'\).*/\1/p" "$root/workers/b/.run.sh" 2>/dev/null | head -1)
  local re_tools; re_tools=$(sed -n "s/.*\(--tools '[^']*'\).*/\1/p" "$root/workers/e/.run.sh" 2>/dev/null | head -1)
  local rv_tools; rv_tools=$(sed -n "s/.*\(--tools '[^']*'\).*/\1/p" "$root/workers/d/.run.sh" 2>/dev/null | head -1)
  local has_dis; has_dis=$(grep -r -- '--disallowed-tools' "$root/workers/" 2>/dev/null | wc -l)
  if [[ "$ro_tools" == "--tools 'read,grep,find,ls'" && \
        "$wr_tools" == "--tools 'read,edit,write,grep,find,ls'" && \
        "$re_tools" == "--tools 'read,bash,grep,find,ls'" && \
        "$rv_tools" == "--tools 'read,edit,write,grep,find,ls'" && \
        "$has_dis" == "0" ]]; then
    record "P2 pi-tool-allowlist" PASS
  else
    record "P2 pi-tool-allowlist" FAIL "(ro=$ro_tools wr=$wr_tools re=$re_tools rv=$rv_tools dis=$has_dis)"
  fi
  kill "$lpid" 2>/dev/null || true
  cleanup_session fleet-test-dag-pi
  cleanup_root "$root"
}

# -------------------------------------------------------------------
# Scenario P3 — Pi session path determinism
# -------------------------------------------------------------------
run_P3() {
  local root; root=$(mkroot pi-P3)
  bash "${FIXTURES_DIR}/setup-fleet.sh" completion "$root" >/dev/null
  bash "${SCRIPTS}/launch.sh" "$root" >"$root/launch.out" 2>&1 &
  local lpid=$!
  sleep 8
  local sessions; sessions=$(ls "$root/workers/w1/.pi-sessions/"*.jsonl 2>/dev/null | wc -l)
  local symlink_ok; symlink_ok=$(test -L "$root/workers/w1/session.jsonl" && echo 1 || echo 0)
  if [[ "$sessions" == "1" && "$symlink_ok" == "1" ]]; then
    record "P3 pi-session-path" PASS
  else
    record "P3 pi-session-path" FAIL "(sessions=$sessions symlink=$symlink_ok)"
  fi
  kill "$lpid" 2>/dev/null || true
  cleanup_session fleet-test-completion-pi
  cleanup_root "$root"
}

# -------------------------------------------------------------------
# Scenario P4 — Pi running-state (toolUse)
# -------------------------------------------------------------------
run_P4() {
  local root; root=$(mkroot pi-P4)
  bash "${FIXTURES_DIR}/setup-fleet.sh" completion "$root" >/dev/null
  EMIT_TOOL_USE=1 bash "${SCRIPTS}/launch.sh" "$root" >"$root/launch.out" 2>&1 &
  local lpid=$!
  sleep 35
  local running; running=$(bash "${SCRIPTS}/status.sh" "$root" --json 2>/dev/null | jq '[.workers[] | select(.status == "RUNNING")] | length')
  local done_count; done_count=$(bash "${SCRIPTS}/status.sh" "$root" --json 2>/dev/null | jq '[.workers[] | select(.status == "DONE")] | length')
  if [[ "$running" == "3" && "$done_count" == "0" ]]; then
    record "P4 pi-toolUse-running" PASS
  else
    record "P4 pi-toolUse-running" FAIL "(running=$running done=$done_count)"
  fi
  kill "$lpid" 2>/dev/null || true
  cleanup_session fleet-test-completion-pi
  cleanup_root "$root"
}

# -------------------------------------------------------------------
# Scenario P5 — Mixed-provider fleet
# -------------------------------------------------------------------
run_P5() {
  local root; root=$(mkroot pi-P5)
  bash "${FIXTURES_DIR}/setup-fleet.sh" dag "$root" >/dev/null
  # Patch: a,b = claude (use claude shim), c,d,e,f = pi
  jq '.workers[0].provider = "claude" | .workers[1].provider = "claude" | .workers[2].provider = "pi" | .workers[3].provider = "pi" | .workers[4].provider = "pi" | .workers[5].provider = "pi"' "$root/fleet.json" > "$root/fleet.json.tmp" && mv "$root/fleet.json.tmp" "$root/fleet.json"
  bash "${SCRIPTS}/launch.sh" "$root" >"$root/launch.out" 2>&1 &
  local lpid=$!
  wait "$lpid" 2>/dev/null || true
  sleep 35
  local done_count; done_count=$(bash "${SCRIPTS}/status.sh" "$root" --json 2>/dev/null | jq '[.workers[] | select(.status == "DONE")] | length')
  local claude_dis; claude_dis=$(grep -c -- '--disallowed-tools' "$root/workers/a/.run.sh" 2>/dev/null)
  local pi_tools; pi_tools=$(grep -c -- '--tools' "$root/workers/c/.run.sh" 2>/dev/null)
  if [[ "$done_count" == "6" && "$claude_dis" -ge 1 && "$pi_tools" -ge 1 ]]; then
    record "P5 mixed-provider" PASS
  else
    record "P5 mixed-provider" FAIL "(done=$done_count claude_dis=$claude_dis pi_tools=$pi_tools)"
  fi
  cleanup_session fleet-test-dag-pi
  cleanup_root "$root"
}

# -------------------------------------------------------------------
# Scenario P6 — Pi cost estimation fallback
# -------------------------------------------------------------------
run_P6() {
  local root; root=$(mkroot pi-P6)
  bash "${FIXTURES_DIR}/setup-fleet.sh" completion "$root" >/dev/null
  bash "${SCRIPTS}/launch.sh" "$root" >"$root/launch.out" 2>&1 &
  local lpid=$!
  wait "$lpid" 2>/dev/null || true
  sleep 35
  local total_cost; total_cost=$(bash "${SCRIPTS}/status.sh" "$root" --json 2>/dev/null | jq -r '.summary.total_cost')
  if awk "BEGIN {exit !($total_cost > 0)}"; then
    record "P6 pi-cost-estimation" PASS "(cost=$total_cost)"
  else
    record "P6 pi-cost-estimation" FAIL "(cost=$total_cost)"
  fi
  cleanup_session fleet-test-completion-pi
  cleanup_root "$root"
}

# -------------------------------------------------------------------
# Scenario P7 — Pi model alias passthrough
# -------------------------------------------------------------------
run_P7() {
  local root; root=$(mkroot pi-P7)
  bash "${FIXTURES_DIR}/setup-fleet.sh" dag "$root" >/dev/null
  jq '.config.model = "anthropic/claude-sonnet-4-20250514"' "$root/fleet.json" > "$root/fleet.json.tmp" && mv "$root/fleet.json.tmp" "$root/fleet.json"
  bash "${SCRIPTS}/launch.sh" "$root" >"$root/launch.out" 2>&1 &
  local lpid=$!
  sleep 8
  local has_model; has_model=$(grep -c "anthropic/claude-sonnet-4-20250514" "$root/workers/a/.run.sh" 2>/dev/null)
  if [[ "$has_model" -ge 1 ]]; then
    record "P7 pi-model-passthrough" PASS
  else
    record "P7 pi-model-passthrough" FAIL "(has_model=$has_model)"
  fi
  kill "$lpid" 2>/dev/null || true
  cleanup_session fleet-test-dag-pi
  cleanup_root "$root"
}

# -------------------------------------------------------------------
# Scenario E — topo sort first wave (reused for Pi)
# -------------------------------------------------------------------
run_E() {
  local root; root=$(mkroot dag-E)
  bash "${FIXTURES_DIR}/setup-fleet.sh" dag "$root" >/dev/null
  bash "${SCRIPTS}/launch.sh" "$root" >"$root/launch.out" 2>&1 &
  local lpid=$!
  local windows="" waited=0
  while [[ $waited -lt 15 ]]; do
    windows=$(tmux list-windows -t fleet-test-dag-pi -F '#W' 2>/dev/null | grep -vx monitor | sort | tr '\n' ',' || true)
    if [[ "$windows" == *"a,"* && "$windows" == *"b,"* && "$windows" == *"d,"* && "$windows" == *"e,"* ]]; then
      break
    fi
    sleep 1; waited=$((waited+1))
  done
  if [[ "$windows" == *"a,"* && "$windows" == *"b,"* && "$windows" == *"d,"* && "$windows" == *"e,"* ]]; then
    record "E topo-sort-first-wave" PASS "($windows)"
  else
    record "E topo-sort-first-wave" FAIL "(got: $windows)"
  fi
  wait "$lpid" 2>/dev/null || true
  cleanup_session fleet-test-dag-pi
  cleanup_root "$root"
}

# -------------------------------------------------------------------
# Scenario G — topo cycle detection (reused for Pi)
# -------------------------------------------------------------------
run_G() {
  local root; root=$(mkroot cycle-G)
  bash "${FIXTURES_DIR}/setup-fleet.sh" cycle "$root" >/dev/null
  bash "${SCRIPTS}/launch.sh" "$root" >"$root/launch.out" 2>&1
  local rc=$?
  local has_cycle_msg=0
  grep -q 'CYCLE:' "$root/launch.out" && has_cycle_msg=1
  local has_session=0
  tmux has-session -t fleet-test-cycle-pi 2>/dev/null && has_session=1
  if [[ "$rc" != "0" && "$has_cycle_msg" == "1" && "$has_session" == "0" ]]; then
    record "G topo-cycle-detection" PASS
  else
    record "G topo-cycle-detection" FAIL "(rc=$rc cycle_msg=$has_cycle_msg session=$has_session)"
  fi
  cleanup_session fleet-test-cycle-pi
  cleanup_root "$root"
}

# -------------------------------------------------------------------
# Scenario K — pane auto-close .done sentinel (reused for Pi)
# -------------------------------------------------------------------
run_K() {
  local root; root=$(mkroot completion-K)
  bash "${FIXTURES_DIR}/setup-fleet.sh" completion "$root" >/dev/null
  bash "${SCRIPTS}/launch.sh" "$root" >"$root/launch.out" 2>&1 &
  local lpid=$!
  wait "$lpid" 2>/dev/null || true
  sleep 40
  local dones; dones=$(ls "$root"/workers/*/.done 2>/dev/null | wc -l)
  local remaining; remaining=$({ tmux list-windows -t fleet-test-completion-pi -F '#W' 2>/dev/null | grep -vxc monitor || true; } | head -1); remaining=${remaining:-0}
  if [[ "$dones" == "3" && "$remaining" == "0" ]]; then
    record "K pane-auto-close .done sentinel" PASS
  else
    record "K pane-auto-close .done sentinel" FAIL "(dones=$dones remaining_windows=$remaining)"
  fi
  cleanup_session fleet-test-completion-pi
  cleanup_root "$root"
}

# -------------------------------------------------------------------
# Scenario L — wedged-launcher fleet lock (reused for Pi)
# -------------------------------------------------------------------
run_L() {
  local root; root=$(mkroot dag-L)
  bash "${FIXTURES_DIR}/setup-fleet.sh" dag "$root" >/dev/null
  bash "${SCRIPTS}/launch.sh" "$root" >"$root/launch1.out" 2>&1 &
  local lpid=$!
  sleep 8
  bash "${SCRIPTS}/launch.sh" "$root" >"$root/launch2.out" 2>&1
  local rc=$?
  local pid_file_ok=0
  [[ -f "$root/.launch.pid" ]] && [[ "$(cat "$root/.launch.pid")" == "$lpid" ]] && pid_file_ok=1
  if [[ "$rc" == "2" && "$pid_file_ok" == "1" ]]; then
    record "L wedged-launcher fleet lock" PASS
  else
    record "L wedged-launcher fleet lock" FAIL "(rc=$rc pid_ok=$pid_file_ok expected_pid=$lpid actual_pid=$(cat "$root/.launch.pid" 2>/dev/null))"
  fi
  wait "$lpid" 2>/dev/null || true
  cleanup_session fleet-test-dag-pi
  cleanup_root "$root"
}

# -------------------------------------------------------------------
# Run all scenarios
# -------------------------------------------------------------------
run_P1
run_P2
run_P3
run_P4
run_P5
run_P6
run_P7
run_E
run_G
run_K
run_L

echo
echo "============================================================"
echo "SUMMARY: ${#PASS[@]} passed, ${#FAIL[@]} failed"
echo "============================================================"
for p in "${PASS[@]}"; do echo "  PASS  $p"; done
for f in "${FAIL[@]}"; do echo "  FAIL  $f"; done

exit "${#FAIL[@]}"
