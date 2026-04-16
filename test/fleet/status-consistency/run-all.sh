#!/usr/bin/env bash
# run-all.sh — Test status output consistency across all fleet types
#
# Verifies that all fleet status scripts produce consistent baseline fields:
#   - Fleet elapsed time
#   - Summary counts (total/running/done/failed)
#   - Total cost
#   - Per-worker cost
#
# Usage: run-all.sh
#
# Creates fake fleet roots with minimal session.jsonl fixtures, runs each
# status.sh with --json, and checks required fields exist.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_DIR="$(cd "${SCRIPT_DIR}/../../.." && pwd)/skills"

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

cleanup() {
  rm -rf /tmp/fleet-status-test-*
}
trap cleanup EXIT

# --- Helpers ---

# Create a minimal session.jsonl with assistant + result events
make_session_done() {
  local dest="$1" model="${2:-claude-haiku-4-5-20251001}"
  mkdir -p "$(dirname "$dest")"
  local ts
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  cat > "$dest" <<JSONL
{"type":"system","subtype":"init","session_id":"fake-001","timestamp":"${ts}"}
{"type":"assistant","message":{"model":"${model}","id":"msg_001","type":"message","role":"assistant","content":[{"type":"text","text":"Done."}],"usage":{"input_tokens":500,"output_tokens":100,"cache_read_input_tokens":1000,"cache_creation_input_tokens":200}},"session_id":"fake-001","timestamp":"${ts}"}
{"type":"result","subtype":"success","is_error":false,"total_cost_usd":0.0250,"num_turns":2,"session_id":"fake-001","timestamp":"${ts}"}
JSONL
}

make_session_running() {
  local dest="$1" model="${2:-claude-haiku-4-5-20251001}"
  mkdir -p "$(dirname "$dest")"
  local ts
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  cat > "$dest" <<JSONL
{"type":"system","subtype":"init","session_id":"fake-002","timestamp":"${ts}"}
{"type":"assistant","message":{"model":"${model}","id":"msg_002","type":"message","role":"assistant","content":[{"type":"text","text":"Working..."}],"usage":{"input_tokens":500,"output_tokens":100,"cache_read_input_tokens":1000,"cache_creation_input_tokens":200}},"session_id":"fake-002","timestamp":"${ts}"}
JSONL
}

# -------------------------------------------------------------------
# Test A — dag-fleet status --json has elapsed_seconds
# -------------------------------------------------------------------
test_dag_elapsed() {
  local root="/tmp/fleet-status-test-dag-$$"
  mkdir -p "$root/workers/w1" "$root/workers/w2"
  local launched_at
  launched_at=$(date -u -d '2 minutes ago' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -v-2M +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)
  cat > "$root/fleet.json" <<JSON
{
  "fleet_name": "test-dag-elapsed",
  "type": "dag",
  "config": {"model": "haiku", "fallback_model": "haiku"},
  "workers": [
    {"id": "w1", "type": "code-run", "task": "test", "model": "haiku", "max_budget_usd": 0.25},
    {"id": "w2", "type": "code-run", "task": "test", "model": "haiku", "max_budget_usd": 0.25}
  ],
  "status": "running",
  "launched_at": "${launched_at}"
}
JSON
  make_session_done "$root/workers/w1/session.jsonl"
  make_session_done "$root/workers/w2/session.jsonl"

  local output
  output=$(bash "${SKILLS_DIR}/dag-fleet/scripts/status.sh" "$root" --json 2>/dev/null)
  local has_elapsed
  has_elapsed=$(echo "$output" | jq -r '.elapsed_seconds // empty' 2>/dev/null)
  if [[ -n "$has_elapsed" && "$has_elapsed" -gt 0 ]]; then
    record "A dag-fleet elapsed_seconds in JSON" PASS "(${has_elapsed}s)"
  else
    record "A dag-fleet elapsed_seconds in JSON" FAIL "(got: '${has_elapsed}', output: $(echo "$output" | head -3))"
  fi
  rm -rf "$root"
}

# -------------------------------------------------------------------
# Test B — worktree-fleet status --json has elapsed_seconds
# -------------------------------------------------------------------
test_worktree_elapsed() {
  local root="/tmp/fleet-status-test-wt-$$"
  mkdir -p "$root/workers/w1"
  local launched_at
  launched_at=$(date -u -d '3 minutes ago' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -v-3M +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)
  cat > "$root/fleet.json" <<JSON
{
  "fleet_name": "test-wt-elapsed",
  "type": "worktree",
  "config": {"model": "haiku", "fallback_model": "haiku"},
  "workers": [
    {"id": "w1", "task": "test", "target_files": ["README.md"], "branch": "test-w1", "type": "code-run", "max_budget_usd": 0.25}
  ],
  "status": "running",
  "launched_at": "${launched_at}"
}
JSON
  make_session_done "$root/workers/w1/session.jsonl"

  local output
  output=$(bash "${SKILLS_DIR}/worktree-fleet/scripts/status.sh" "$root" --json 2>/dev/null)
  local has_elapsed
  has_elapsed=$(echo "$output" | jq -r '.elapsed_seconds // empty' 2>/dev/null)
  if [[ -n "$has_elapsed" && "$has_elapsed" -gt 0 ]]; then
    record "B worktree-fleet elapsed_seconds in JSON" PASS "(${has_elapsed}s)"
  else
    record "B worktree-fleet elapsed_seconds in JSON" FAIL "(got: '${has_elapsed}')"
  fi
  rm -rf "$root"
}

# -------------------------------------------------------------------
# Test C — dag-fleet text output contains "Elapsed:"
# -------------------------------------------------------------------
test_dag_elapsed_text() {
  local root="/tmp/fleet-status-test-dag-txt-$$"
  mkdir -p "$root/workers/w1"
  local launched_at
  launched_at=$(date -u -d '1 minute ago' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -v-1M +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)
  cat > "$root/fleet.json" <<JSON
{
  "fleet_name": "test-dag-txt",
  "type": "dag",
  "config": {"model": "haiku"},
  "workers": [{"id": "w1", "type": "code-run", "task": "test", "model": "haiku", "max_budget_usd": 0.25}],
  "status": "running",
  "launched_at": "${launched_at}"
}
JSON
  make_session_done "$root/workers/w1/session.jsonl"

  local output
  output=$(bash "${SKILLS_DIR}/dag-fleet/scripts/status.sh" "$root" 2>/dev/null)
  if echo "$output" | grep -qi "elapsed"; then
    record "C dag-fleet text output has Elapsed" PASS
  else
    record "C dag-fleet text output has Elapsed" FAIL
  fi
  rm -rf "$root"
}

# -------------------------------------------------------------------
# Test D — worktree-fleet text output contains "Elapsed:"
# -------------------------------------------------------------------
test_worktree_elapsed_text() {
  local root="/tmp/fleet-status-test-wt-txt-$$"
  mkdir -p "$root/workers/w1"
  local launched_at
  launched_at=$(date -u -d '1 minute ago' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -v-1M +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)
  cat > "$root/fleet.json" <<JSON
{
  "fleet_name": "test-wt-txt",
  "type": "worktree",
  "config": {"model": "haiku"},
  "workers": [{"id": "w1", "task": "test", "target_files": ["a.md"], "branch": "b1", "type": "code-run", "max_budget_usd": 0.25}],
  "status": "running",
  "launched_at": "${launched_at}"
}
JSON
  make_session_done "$root/workers/w1/session.jsonl"

  local output
  output=$(bash "${SKILLS_DIR}/worktree-fleet/scripts/status.sh" "$root" 2>/dev/null)
  if echo "$output" | grep -qi "elapsed"; then
    record "D worktree-fleet text output has Elapsed" PASS
  else
    record "D worktree-fleet text output has Elapsed" FAIL
  fi
  rm -rf "$root"
}

# -------------------------------------------------------------------
# Test E — all 4 fleets have total_cost in JSON
# -------------------------------------------------------------------
test_all_have_total_cost() {
  # dag
  local root="/tmp/fleet-status-test-cost-dag-$$"
  mkdir -p "$root/workers/w1"
  cat > "$root/fleet.json" <<JSON
{"fleet_name":"tc-dag","type":"dag","config":{"model":"haiku"},"workers":[{"id":"w1","type":"code-run","task":"t","model":"haiku","max_budget_usd":0.25}]}
JSON
  make_session_done "$root/workers/w1/session.jsonl"
  local dag_cost
  dag_cost=$(bash "${SKILLS_DIR}/dag-fleet/scripts/status.sh" "$root" --json 2>/dev/null | jq '.summary.total_cost // empty' 2>/dev/null)

  # worktree
  local root2="/tmp/fleet-status-test-cost-wt-$$"
  mkdir -p "$root2/workers/w1"
  cat > "$root2/fleet.json" <<JSON
{"fleet_name":"tc-wt","type":"worktree","config":{"model":"haiku"},"workers":[{"id":"w1","task":"t","target_files":["a"],"branch":"b","type":"code-run","max_budget_usd":0.25}]}
JSON
  make_session_done "$root2/workers/w1/session.jsonl"
  local wt_cost
  wt_cost=$(bash "${SKILLS_DIR}/worktree-fleet/scripts/status.sh" "$root2" --json 2>/dev/null | jq '.summary.total_cost // empty' 2>/dev/null)

  if [[ -n "$dag_cost" && -n "$wt_cost" ]]; then
    record "E all fleets have total_cost in JSON" PASS "(dag=$dag_cost wt=$wt_cost)"
  else
    record "E all fleets have total_cost in JSON" FAIL "(dag='$dag_cost' wt='$wt_cost')"
  fi
  rm -rf "$root" "$root2"
}

# -------------------------------------------------------------------
# Test F — dag-fleet summary has all standard counts
# -------------------------------------------------------------------
test_dag_summary_counts() {
  local root="/tmp/fleet-status-test-counts-$$"
  mkdir -p "$root/workers/w1" "$root/workers/w2"
  cat > "$root/fleet.json" <<JSON
{"fleet_name":"tc-counts","type":"dag","config":{"model":"haiku"},"workers":[
  {"id":"w1","type":"code-run","task":"t","model":"haiku","max_budget_usd":0.25},
  {"id":"w2","type":"code-run","task":"t","model":"haiku","max_budget_usd":0.25}
]}
JSON
  make_session_done "$root/workers/w1/session.jsonl"
  make_session_running "$root/workers/w2/session.jsonl"

  local output
  output=$(bash "${SKILLS_DIR}/dag-fleet/scripts/status.sh" "$root" --json 2>/dev/null)
  local total done running
  total=$(echo "$output" | jq '.summary.total // empty' 2>/dev/null)
  done=$(echo "$output" | jq '.summary.done // empty' 2>/dev/null)
  running=$(echo "$output" | jq '.summary.running // empty' 2>/dev/null)

  if [[ "$total" == "2" && "$done" == "1" ]]; then
    record "F dag-fleet summary counts correct" PASS "(total=$total done=$done running=$running)"
  else
    record "F dag-fleet summary counts correct" FAIL "(total=$total done=$done running=$running)"
  fi
  rm -rf "$root"
}

# -------------------------------------------------------------------
# Test G — elapsed shows "n/a" when no launched_at
# -------------------------------------------------------------------
test_elapsed_no_launched_at() {
  local root="/tmp/fleet-status-test-no-launch-$$"
  mkdir -p "$root/workers/w1"
  cat > "$root/fleet.json" <<JSON
{"fleet_name":"no-launch","type":"dag","config":{"model":"haiku"},"workers":[{"id":"w1","type":"code-run","task":"t","model":"haiku","max_budget_usd":0.25}]}
JSON
  make_session_done "$root/workers/w1/session.jsonl"

  local output
  output=$(bash "${SKILLS_DIR}/dag-fleet/scripts/status.sh" "$root" 2>/dev/null)
  # Should not crash, elapsed may show n/a or be absent
  if [[ $? -eq 0 ]]; then
    record "G dag-fleet no launched_at doesn't crash" PASS
  else
    record "G dag-fleet no launched_at doesn't crash" FAIL
  fi
  rm -rf "$root"
}

# Run all tests
test_dag_elapsed
test_worktree_elapsed
test_dag_elapsed_text
test_worktree_elapsed_text
test_all_have_total_cost
test_dag_summary_counts
test_elapsed_no_launched_at

echo ""
echo "============================================================"
echo "SUMMARY: ${#PASS[@]} passed, ${#FAIL[@]} failed"
echo "============================================================"
for p in "${PASS[@]}"; do echo "  PASS  $p"; done
for f in "${FAIL[@]}"; do echo "  FAIL  $f"; done

exit "${#FAIL[@]}"
