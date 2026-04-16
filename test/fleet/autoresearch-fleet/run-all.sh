#!/usr/bin/env bash
# Test scenarios for autoresearch-fleet skill
# Usage: run-all.sh <skill-dir>
#   e.g. run-all.sh skills/autoresearch-fleet

set -uo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: run-all.sh <autoresearch-fleet-skill-dir>" >&2
  exit 99
fi

SKILL_DIR="$(cd "$1" && pwd)"
SCRIPTS="${SKILL_DIR}/scripts"

for s in launch.sh status.sh pause.sh resume.sh kill.sh; do
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
  local root="/tmp/fleet-test-autoresearch-${name}-$$"
  mkdir -p "$root"
  echo "$root"
}

cleanup_session() {
  local sess="$1"
  tmux has-session -t "$sess" 2>/dev/null && tmux kill-session -t "$sess" 2>/dev/null || true
}

cleanup_root() {
  rm -rf "$1" 2>/dev/null || true
}

make_problem() {
  local root="$1"
  # Create minimal problem files
  cat > "$root/fleet.json" <<'EOF'
{
  "fleet_name": "test-autoresearch",
  "type": "autoresearch",
  "config": {
    "model": "haiku",
    "fallback_model": "haiku",
    "provider": "claude",
    "budget_per_iter": 0.10,
    "max_turns": 0
  },
  "problem": {
    "mutable_file": "solution.py",
    "eval_command": "python3 eval.py",
    "metric_direction": "minimize",
    "results_file": "results.tsv",
    "program_md": "program.md"
  },
  "stop_when": {
    "max_iterations": 5,
    "cost_cap_usd": 1.0
  },
  "search": {
    "enabled": true,
    "plateau_threshold": 3
  }
}
EOF
  cat > "$root/solution.py" <<'EOF'
def solve(x):
    return x * 2
EOF
  cat > "$root/eval.py" <<'EOF'
from solution import solve
print(solve(21))
EOF
  cat > "$root/program.md" <<'EOF'
# Test problem
Edit solution.py. Run python3 eval.py. Log to results.tsv.
EOF
}

# -------------------------------------------------------------------
# A1 — Launch creates orchestrator.sh and logs/ dir
# -------------------------------------------------------------------
run_A1() {
  local root; root=$(mkroot structure)
  make_problem "$root"
  bash "${SCRIPTS}/launch.sh" "$root" --dry-run >"$root/launch.out" 2>&1 || true

  local ok=1
  [[ -f "$root/orchestrator.sh" ]] || ok=0
  [[ -d "$root/logs" ]] || ok=0
  grep -q 'count_trailing_discards' "$root/orchestrator.sh" 2>/dev/null || ok=0
  grep -q 'get_total_cost' "$root/orchestrator.sh" 2>/dev/null || ok=0

  if [[ "$ok" == "1" ]]; then
    record "A1 launch-creates-structure" PASS
  else
    record "A1 launch-creates-structure" FAIL "(orch=$(test -f "$root/orchestrator.sh" && echo Y || echo N) logs=$(test -d "$root/logs" && echo Y || echo N))"
  fi
  cleanup_root "$root"
}

# -------------------------------------------------------------------
# A2 — Orchestrator has baked config from fleet.json
# -------------------------------------------------------------------
run_A2() {
  local root; root=$(mkroot config)
  make_problem "$root"
  bash "${SCRIPTS}/launch.sh" "$root" --dry-run >"$root/launch.out" 2>&1 || true

  local ok=1
  grep -q 'MAX_ITERATIONS=5' "$root/orchestrator.sh" 2>/dev/null || ok=0
  grep -q 'PLATEAU_THRESHOLD=3' "$root/orchestrator.sh" 2>/dev/null || ok=0
  grep -q 'BUDGET_PER_ITER=' "$root/orchestrator.sh" 2>/dev/null || ok=0
  grep -q 'METRIC_DIR="minimize"' "$root/orchestrator.sh" 2>/dev/null || ok=0
  grep -q 'WORKDIR=' "$root/orchestrator.sh" 2>/dev/null || ok=0

  if [[ "$ok" == "1" ]]; then
    record "A2 config-baked-into-orchestrator" PASS
  else
    record "A2 config-baked-into-orchestrator" FAIL
  fi
  cleanup_root "$root"
}

# -------------------------------------------------------------------
# A3 — Plateau detection is bash-side, not LLM
# -------------------------------------------------------------------
run_A3() {
  local root; root=$(mkroot plateau)
  make_problem "$root"
  bash "${SCRIPTS}/launch.sh" "$root" --dry-run >"$root/launch.out" 2>&1 || true

  local ok=1
  # count_trailing_discards must use awk + tac on results.tsv (bash-side, not LLM)
  grep -q 'count_trailing_discards' "$root/orchestrator.sh" 2>/dev/null || ok=0
  grep -q 'awk.*discard' "$root/orchestrator.sh" 2>/dev/null || ok=0
  grep -q 'tac' "$root/orchestrator.sh" 2>/dev/null || ok=0

  if [[ "$ok" == "1" ]]; then
    record "A3 plateau-detection-bash-side" PASS
  else
    record "A3 plateau-detection-bash-side" FAIL
  fi
  cleanup_root "$root"
}

# -------------------------------------------------------------------
# A4 — Search prompt injected on plateau
# -------------------------------------------------------------------
run_A4() {
  local root; root=$(mkroot search-inject)
  make_problem "$root"
  bash "${SCRIPTS}/launch.sh" "$root" --dry-run >"$root/launch.out" 2>&1 || true

  local ok=1
  # Orchestrator must have search prompt injection
  grep -q 'PLATEAU DETECTED' "$root/orchestrator.sh" 2>/dev/null || ok=0
  grep -q 'WebSearch' "$root/orchestrator.sh" 2>/dev/null || ok=0
  grep -q 'is_search.*true' "$root/orchestrator.sh" 2>/dev/null || ok=0
  # Must conditionally add --tools default for claude
  grep -q 'tools.*default\|tools_flag' "$root/orchestrator.sh" 2>/dev/null || ok=0

  if [[ "$ok" == "1" ]]; then
    record "A4 search-prompt-on-plateau" PASS
  else
    record "A4 search-prompt-on-plateau" FAIL
  fi
  cleanup_root "$root"
}

# -------------------------------------------------------------------
# A5 — Git init if no .git exists
# -------------------------------------------------------------------
run_A5() {
  local root; root=$(mkroot git-init)
  make_problem "$root"
  # Ensure no .git
  rm -rf "$root/.git" 2>/dev/null
  bash "${SCRIPTS}/launch.sh" "$root" --dry-run >"$root/launch.out" 2>&1 || true

  local ok=1
  [[ -d "$root/.git" ]] || ok=0

  if [[ "$ok" == "1" ]]; then
    record "A5 git-init-if-missing" PASS
  else
    record "A5 git-init-if-missing" FAIL
  fi
  cleanup_root "$root"
}

# -------------------------------------------------------------------
# A6 — results.tsv created with header if missing
# -------------------------------------------------------------------
run_A6() {
  local root; root=$(mkroot results-init)
  make_problem "$root"
  rm -f "$root/results.tsv" 2>/dev/null
  bash "${SCRIPTS}/launch.sh" "$root" --dry-run >"$root/launch.out" 2>&1 || true

  local ok=1
  [[ -f "$root/results.tsv" ]] || ok=0
  head -1 "$root/results.tsv" 2>/dev/null | grep -q 'commit' || ok=0
  head -1 "$root/results.tsv" 2>/dev/null | grep -q 'metric' || ok=0
  head -1 "$root/results.tsv" 2>/dev/null | grep -q 'status' || ok=0

  if [[ "$ok" == "1" ]]; then
    record "A6 results-tsv-initialized" PASS
  else
    record "A6 results-tsv-initialized" FAIL
  fi
  cleanup_root "$root"
}

# -------------------------------------------------------------------
# A7 — Pause/resume cycle works
# -------------------------------------------------------------------
run_A7() {
  local root; root=$(mkroot pause)
  make_problem "$root"

  local ok=1
  bash "${SCRIPTS}/pause.sh" "$root" >"$root/pause.out" 2>&1 || true
  [[ -f "$root/.paused" ]] || ok=0
  jq -e '.status == "paused"' "$root/fleet.json" >/dev/null 2>&1 || ok=0

  bash "${SCRIPTS}/resume.sh" "$root" >"$root/resume.out" 2>&1 || true
  [[ ! -f "$root/.paused" ]] || ok=0
  jq -e '.status == "running"' "$root/fleet.json" >/dev/null 2>&1 || ok=0

  if [[ "$ok" == "1" ]]; then
    record "A7 pause-resume-cycle" PASS
  else
    record "A7 pause-resume-cycle" FAIL
  fi
  cleanup_root "$root"
}

# -------------------------------------------------------------------
# A8 — Stop conditions baked into orchestrator
# -------------------------------------------------------------------
run_A8() {
  local root; root=$(mkroot stop-cond)
  make_problem "$root"
  bash "${SCRIPTS}/launch.sh" "$root" --dry-run >"$root/launch.out" 2>&1 || true

  local ok=1
  # Max iterations check
  grep -q 'iter.*-gt.*MAX_ITERATIONS\|iter.*-gt.*\${MAX_ITERATIONS}' "$root/orchestrator.sh" 2>/dev/null || ok=0
  # Cost cap check
  grep -q 'COST_CAP\|cost_cap' "$root/orchestrator.sh" 2>/dev/null || ok=0
  # stop_fleet function
  grep -q 'stop_fleet' "$root/orchestrator.sh" 2>/dev/null || ok=0

  if [[ "$ok" == "1" ]]; then
    record "A8 stop-conditions-in-orchestrator" PASS
  else
    record "A8 stop-conditions-in-orchestrator" FAIL
  fi
  cleanup_root "$root"
}

# -------------------------------------------------------------------
# A9 — Orchestrator supports both claude and codex providers
# -------------------------------------------------------------------
run_A9() {
  local root; root=$(mkroot providers)
  make_problem "$root"
  bash "${SCRIPTS}/launch.sh" "$root" --dry-run >"$root/launch.out" 2>&1 || true

  local ok=1
  # Orchestrator must source worker-spawn.sh and use build_inner_cmd
  grep -q 'worker-spawn.sh' "$root/orchestrator.sh" 2>/dev/null || ok=0
  grep -q 'build_inner_cmd' "$root/orchestrator.sh" 2>/dev/null || ok=0
  # Must pass provider to build_inner_cmd
  grep -q 'provider' "$root/orchestrator.sh" 2>/dev/null || ok=0
  # Search mode must inject --tools default for claude
  grep -q 'tools default' "$root/orchestrator.sh" 2>/dev/null || ok=0

  if [[ "$ok" == "1" ]]; then
    record "A9 uses-shared-worker-spawn" PASS
  else
    record "A9 uses-shared-worker-spawn" FAIL
  fi
  cleanup_root "$root"
}

# -------------------------------------------------------------------
# A10 — Status shows results and plateau indicator
# -------------------------------------------------------------------
run_A10() {
  local root; root=$(mkroot status-display)
  make_problem "$root"

  # Create fake results
  printf 'commit\tmetric\tstatus\tdescription\n' > "$root/results.tsv"
  printf 'abc1234\t241.4\tkeep\tbaseline\n' >> "$root/results.tsv"
  printf 'bcd2345\t165.7\tkeep\ttranspose B\n' >> "$root/results.tsv"
  printf 'cde3456\t200.0\tdiscard\tbad idea\n' >> "$root/results.tsv"

  # Create fake orch state
  printf '{"current_iteration":4,"trailing_discards":1,"is_search":false,"best_metric":"165.7","total_cost":"0.45","status":"running"}\n' \
    > "$root/.orch-state.json"

  local status_out
  status_out=$(bash "${SCRIPTS}/status.sh" "$root" 2>&1 || true)

  local ok=1
  echo "$status_out" | grep -q '165.7' || ok=0         # best metric
  echo "$status_out" | grep -q 'keep' || ok=0           # results shown
  echo "$status_out" | grep -q 'Plateau\|plateau' || ok=0  # plateau indicator

  if [[ "$ok" == "1" ]]; then
    record "A10 status-shows-results-plateau" PASS
  else
    record "A10 status-shows-results-plateau" FAIL
    echo "$status_out" | head -20
  fi
  cleanup_root "$root"
}

# -------------------------------------------------------------------
# A11 — Status JSON mode works
# -------------------------------------------------------------------
run_A11() {
  local root; root=$(mkroot status-json)
  make_problem "$root"
  printf '{"current_iteration":2,"trailing_discards":0,"is_search":false,"best_metric":"100","total_cost":"0.20","status":"running"}\n' \
    > "$root/.orch-state.json"

  local json_out
  json_out=$(bash "${SCRIPTS}/status.sh" "$root" --json 2>&1 || true)

  local ok=1
  echo "$json_out" | jq -e '.fleet' >/dev/null 2>&1 || ok=0
  echo "$json_out" | jq -e '.iteration' >/dev/null 2>&1 || ok=0
  echo "$json_out" | jq -e '.best_metric' >/dev/null 2>&1 || ok=0

  if [[ "$ok" == "1" ]]; then
    record "A11 status-json-mode" PASS
  else
    record "A11 status-json-mode" FAIL
    echo "$json_out"
  fi
  cleanup_root "$root"
}

# -------------------------------------------------------------------
# A12 — Kill updates fleet.json and orch state
# -------------------------------------------------------------------
run_A12() {
  local root; root=$(mkroot kill-state)
  make_problem "$root"
  printf '{"current_iteration":3,"status":"running"}\n' > "$root/.orch-state.json"

  bash "${SCRIPTS}/kill.sh" "$root" >"$root/kill.out" 2>&1 || true

  local ok=1
  jq -e '.status == "killed"' "$root/fleet.json" >/dev/null 2>&1 || ok=0
  jq -e '.status == "killed"' "$root/.orch-state.json" >/dev/null 2>&1 || ok=0

  if [[ "$ok" == "1" ]]; then
    record "A12 kill-updates-state" PASS
  else
    record "A12 kill-updates-state" FAIL
  fi
  cleanup_root "$root"
}

# -------------------------------------------------------------------
# A13 — Validation rejects missing program.md
# -------------------------------------------------------------------
run_A13() {
  local root; root=$(mkroot validate)
  make_problem "$root"
  rm -f "$root/program.md"

  local rc=0
  bash "${SCRIPTS}/launch.sh" "$root" --dry-run >"$root/launch.out" 2>&1 || rc=$?

  if [[ $rc -ne 0 ]]; then
    record "A13 rejects-missing-program-md" PASS
  else
    record "A13 rejects-missing-program-md" FAIL "(should have failed but rc=0)"
  fi
  cleanup_root "$root"
}

# -------------------------------------------------------------------
# A14 — Cost tracking uses per-iteration session logs
# -------------------------------------------------------------------
run_A14() {
  local root; root=$(mkroot cost)
  make_problem "$root"
  bash "${SCRIPTS}/launch.sh" "$root" --dry-run >"$root/launch.out" 2>&1 || true

  local ok=1
  # get_total_cost must iterate over session-iter-*.jsonl
  local fn
  fn=$(sed -n '/^get_total_cost/,/^}/p' "$root/orchestrator.sh" 2>/dev/null)
  echo "$fn" | grep -q 'session-iter-' || ok=0
  echo "$fn" | grep -q 'total_cost_usd' || ok=0

  if [[ "$ok" == "1" ]]; then
    record "A14 per-iteration-cost-tracking" PASS
  else
    record "A14 per-iteration-cost-tracking" FAIL
  fi
  cleanup_root "$root"
}

# -------------------------------------------------------------------
# Run all
# -------------------------------------------------------------------
run_A1
run_A2
run_A3
run_A4
run_A5
run_A6
run_A7
run_A8
run_A9
run_A10
run_A11
run_A12
run_A13
run_A14

echo
echo "============================================================"
echo "SUMMARY: ${#PASS[@]} passed, ${#FAIL[@]} failed"
echo "============================================================"
for p in "${PASS[@]}"; do echo "  PASS  $p"; done
for f in "${FAIL[@]}"; do echo "  FAIL  $f"; done

exit "${#FAIL[@]}"
