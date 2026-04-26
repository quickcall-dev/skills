#!/usr/bin/env bash
# Pi provider smoke test — validates Pi support across all fleet types
# Usage: bash test/fleet/pi-smoke-test.sh

set -uo pipefail

SKILL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
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
  local tag="$1"
  local root="/tmp/pi-smoke-${tag}-$$"
  rm -rf "$root"
  mkdir -p "$root"
  echo "$root"
}

cleanup_tmux() {
  local sess="$1"
  tmux kill-session -t "$sess" 2>/dev/null || true
}

# Activate fake pi shim
export PATH="${SKILL_ROOT}/test/fleet/dag-fleet/fixtures-pi/shim:${PATH}"

# -------------------------------------------------------------------
# DAG-FLEET Pi smoke test
# -------------------------------------------------------------------
run_dag() {
  local root; root=$(mkroot dag)
  bash "${SKILL_ROOT}/test/fleet/dag-fleet/fixtures-pi/setup-fleet.sh" dag "$root" >/dev/null
  bash "${SKILL_ROOT}/skills/dag-fleet/scripts/launch.sh" "$root" >"$root/launch.out" 2>&1 &
  local lpid=$!
  sleep 5
  local has_tools; has_tools=$(grep -c -- '--tools' "$root/workers/a/.run.sh" 2>/dev/null)
  local has_model; has_model=$(grep -c "kimi-coding" "$root/workers/a/.run.sh" 2>/dev/null)
  if [[ "$has_tools" -ge 1 && "$has_model" -ge 1 ]]; then
    record "dag-fleet pi launch" PASS
  else
    record "dag-fleet pi launch" FAIL "(tools=$has_tools model=$has_model)"
  fi
  kill "$lpid" 2>/dev/null || true
  cleanup_tmux fleet-test-dag-pi
  rm -rf "$root"
}

# -------------------------------------------------------------------
# AUTORESEARCH-FLEET Pi smoke test
# -------------------------------------------------------------------
run_autoresearch() {
  local root; root=$(mkroot autoresearch)
  mkdir -p "$root"
  cat > "$root/fleet.json" <<'EOF'
{
  "fleet_name": "test-autoresearch-pi",
  "type": "autoresearch",
  "config": {
    "model": "kimi-coding/kimi-k2-thinking",
    "fallback_model": "kimi-coding/kimi-k2-thinking",
    "provider": "pi",
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
EOF
  bash "${SKILL_ROOT}/skills/autoresearch-fleet/scripts/launch.sh" "$root" --dry-run >"$root/launch.out" 2>&1 || true
  local has_tools; has_tools=$(grep -c -- '--tools' "$root/orchestrator.sh" 2>/dev/null)
  local has_provider; has_provider=$(grep -c 'PROVIDER="pi"' "$root/orchestrator.sh" 2>/dev/null)
  if [[ "$has_tools" -ge 1 && "$has_provider" -ge 1 ]]; then
    record "autoresearch-fleet pi dry-run" PASS
  else
    record "autoresearch-fleet pi dry-run" FAIL "(tools=$has_tools provider=$has_provider)"
  fi
  rm -rf "$root"
}

# -------------------------------------------------------------------
# ITERATIVE-FLEET Pi smoke test
# -------------------------------------------------------------------
run_iterative() {
  local root; root=$(mkroot iterative)
  mkdir -p "$root"
  cat > "$root/fleet.json" <<'EOF'
{
  "fleet_name": "test-iterative-pi",
  "type": "iterative",
  "config": {
    "model": "kimi-coding/kimi-k2-thinking",
    "fallback_model": "kimi-coding/kimi-k2-thinking",
    "provider": "pi",
    "max_concurrent": 2
  },
  "stop_when": {
    "max_iterations": 3,
    "reviewer_lgtm_count": 1
  },
  "workers": [
    { "id": "builder", "type": "code-run", "task": "Build feature" },
    { "id": "reviewer", "type": "reviewer", "task": "Review code" }
  ]
}
EOF
  mkdir -p "$root/workers/builder" "$root/workers/reviewer"
  echo "build" > "$root/workers/builder/prompt.md"
  echo "review" > "$root/workers/reviewer/prompt.md"
  bash "${SKILL_ROOT}/skills/iterative-fleet/scripts/launch.sh" "$root" >"$root/launch.out" 2>&1 &
  local lpid=$!
  sleep 5
  local has_tools; has_tools=$(grep -c -- '--tools' "$root/.worker-cmd-builder.sh" 2>/dev/null)
  local has_provider; has_provider=$(grep -c "provider=\"pi\"" "$root/orchestrator.sh" 2>/dev/null)
  if [[ "$has_tools" -ge 1 ]]; then
    record "iterative-fleet pi launch" PASS
  else
    record "iterative-fleet pi launch" FAIL "(tools=$has_tools)"
  fi
  kill "$lpid" 2>/dev/null || true
  cleanup_tmux test-iterative-pi
  rm -rf "$root"
}

# -------------------------------------------------------------------n# WORKTREE-FLEET Pi smoke test
# -------------------------------------------------------------------
run_worktree() {
  local root; root=$(mkroot worktree)
  local branch="feat-pi-smoke-$$"
  git init "$root" >/dev/null 2>&1
  echo "hello" > "$root/README.md"
  git -C "$root" add README.md >/dev/null 2>&1
  git -C "$root" commit -m "init" >/dev/null 2>&1
  cat > "$root/fleet.json" <<EOF
{
  "fleet_name": "test-worktree-pi",
  "type": "worktree",
  "config": {
    "model": "kimi-coding/kimi-k2-thinking",
    "fallback_model": "kimi-coding/kimi-k2-thinking",
    "provider": "pi"
  },
  "workers": [
    { "id": "w1", "type": "code-run", "branch": "${branch}", "target_files": ["w1.txt"] }
  ]
}
EOF
  mkdir -p "$root/workers/w1"
  echo "task" > "$root/workers/w1/prompt.md"
  bash "${SKILL_ROOT}/skills/worktree-fleet/scripts/launch.sh" "$root" >"$root/launch.out" 2>&1 &
  local lpid=$!
  sleep 5
  local has_tools; has_tools=$(grep -c -- '--tools' "$root/.worker-cmd-w1.sh" 2>/dev/null)
  if [[ "$has_tools" -ge 1 ]]; then
    record "worktree-fleet pi launch" PASS
  else
    record "worktree-fleet pi launch" FAIL "(tools=$has_tools)"
  fi
  kill "$lpid" 2>/dev/null || true
  cleanup_tmux test-worktree-pi
  rm -rf "$root"
}

# -------------------------------------------------------------------
# WORKTREE-FLEET Pi smoke test (direct command build)
# -------------------------------------------------------------------
run_worktree_cmd() {
  local cmd
  cmd=$(bash -c '
    source "'"${SKILL_ROOT}"'/skills/worktree-fleet/lib/tools.sh" 2>/dev/null || source "'"${SKILL_ROOT}"'/_canonical/fleet-lib/tools.sh"
    source "'"${SKILL_ROOT}"'/skills/worktree-fleet/lib/worker-spawn.sh" 2>/dev/null || source "'"${SKILL_ROOT}"'/_canonical/fleet-lib/worker-spawn.sh"
    PI_TOOLS=$(get_pi_tools "code-run")
    echo "TOOLS=$PI_TOOLS"
    CMD=$(build_inner_cmd \
      --cwd "/tmp" --fleet-root "/tmp" --worker-id "w1" \
      --worker-prompt "/tmp/p.md" --worker-model "kimi-coding/kimi-k2-thinking" \
      --max-budget "1.0" --session-name "test" \
      --session-jsonl "/tmp/s.jsonl" --worker-dir "/tmp/w" \
      --extra-exports "WORKER_BRANCH=main PI_TOOLS=${PI_TOOLS}" \
      --provider "pi")
    echo "$CMD"
  ')
  local has_tools; has_tools=$(echo "$cmd" | grep -c -- '--tools')
  local has_pi; has_pi=$(echo "$cmd" | grep -c 'pi -p')
  if [[ "$has_tools" -ge 1 && "$has_pi" -ge 1 ]]; then
    record "worktree-fleet pi command" PASS
  else
    record "worktree-fleet pi command" FAIL "(tools=$has_tools pi=$has_pi)"
  fi
}

run_dag
run_autoresearch
run_iterative
run_worktree_cmd

echo
echo "============================================================"
echo "PI SMOKE TEST SUMMARY: ${#PASS[@]} passed, ${#FAIL[@]} failed"
echo "============================================================"
for p in "${PASS[@]}"; do echo "  PASS  $p"; done
for f in "${FAIL[@]}"; do echo "  FAIL  $f"; done

exit "${#FAIL[@]}"
