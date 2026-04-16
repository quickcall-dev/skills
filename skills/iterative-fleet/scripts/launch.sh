#!/usr/bin/env bash
# launch.sh — Iterative Fleet Launcher
#
# Parses fleet.json + stop_when, creates iterations/ dir, generates
# orchestrator.sh (bash loop that reads worker logs + reviewer verdicts,
# decides iterate/pause/stop, NEVER kills workers), spawns workers in tmux,
# spawns orchestrator in tmux. Supports --dry-run.
#
# Usage: launch.sh <fleet-root> [--dry-run]

set -euo pipefail

# ---------------------------------------------------------------------------
# Shared helpers
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/../lib"

# shellcheck source=../lib/logging.sh
source "${LIB_DIR}/logging.sh"
# shellcheck source=../lib/tools.sh
source "${LIB_DIR}/tools.sh"
# shellcheck source=../lib/worker-spawn.sh
source "${LIB_DIR}/worker-spawn.sh"
# shellcheck source=../lib/dag.sh
source "${LIB_DIR}/dag.sh"

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------
usage() {
  cat <<EOF
${BOLD}USAGE${NC}
  launch.sh <fleet-root> [--dry-run]

${BOLD}DESCRIPTION${NC}
  Reads fleet.json, creates iterations/ dir, generates orchestrator.sh,
  spawns workers in tmux, spawns orchestrator in tmux.

  The orchestrator NEVER kills or restarts workers. It reads verdict files
  and decides whether to iterate, pause, or stop. Workers run to natural
  completion each iteration.

${BOLD}FLAGS${NC}
  --dry-run   Validate, generate orchestrator.sh, print plan — do not spawn

${BOLD}EXAMPLES${NC}
  launch.sh ./my-iterative-fleet
  launch.sh /home/user/fleets/feature-x --dry-run
EOF
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage; exit 0
fi

DRY_RUN=0
POSITIONAL=()
for arg in "$@"; do
  case "${arg}" in
    --dry-run) DRY_RUN=1 ;;
    *) POSITIONAL+=("${arg}") ;;
  esac
done
set -- "${POSITIONAL[@]:-}"

if [[ $# -lt 1 ]]; then
  error "Missing required argument: fleet-root"
  echo ""
  usage
  exit 1
fi

FLEET_ROOT="${1}"
FLEET_ROOT="$(realpath "${FLEET_ROOT}")"

# ---------------------------------------------------------------------------
# Source registry
# ---------------------------------------------------------------------------
# shellcheck source=../lib/registry.sh
if [[ -f "${SCRIPT_DIR}/../lib/registry.sh" ]]; then
  # shellcheck disable=SC1091
  source "${SCRIPT_DIR}/../lib/registry.sh"
fi

# ---------------------------------------------------------------------------
# Validate
# ---------------------------------------------------------------------------
[[ ! -d "${FLEET_ROOT}" ]] && die "Fleet root does not exist: ${FLEET_ROOT}"

FLEET_JSON="${FLEET_ROOT}/fleet.json"
[[ ! -f "${FLEET_JSON}" ]] && die "fleet.json not found at: ${FLEET_JSON}"

command -v jq &>/dev/null   || die "jq is required but not installed"
command -v tmux &>/dev/null || die "tmux is required but not installed"

# ---------------------------------------------------------------------------
# Parse fleet.json
# ---------------------------------------------------------------------------
info "Reading fleet.json from: ${FLEET_ROOT}"

FLEET_NAME=$(jq -r '.fleet_name // "fleet"' "${FLEET_JSON}")
DEFAULT_MODEL=$(jq -r '.config.model // "sonnet"' "${FLEET_JSON}")
FALLBACK_MODEL=$(jq -r '.config.fallback_model // "haiku"' "${FLEET_JSON}")
DEFAULT_PROVIDER=$(jq -r '.config.provider // "claude"' "${FLEET_JSON}")
DEFAULT_REASONING_EFFORT=$(jq -r '.config.reasoning_effort // ""' "${FLEET_JSON}")
MAX_CONCURRENT=$(jq -r '.config.max_concurrent // 5' "${FLEET_JSON}")
LAUNCH_DELAY=$(jq -r '.config.launch_delay_seconds // 2' "${FLEET_JSON}")

# Validate fleet.json inputs against shell injection
validate_fleet_id "fleet_name" "${FLEET_NAME}"
validate_fleet_id "model" "${DEFAULT_MODEL}"
validate_fleet_id "fallback_model" "${FALLBACK_MODEL}"
validate_fleet_id "provider" "${DEFAULT_PROVIDER}"
for _wid in $(jq -r '.workers[].id' "${FLEET_JSON}"); do
  validate_fleet_id "worker_id" "${_wid}"
done

# Validate required CLI tools based on provider
if [[ "${DRY_RUN}" -eq 0 ]]; then
  if [[ "${DEFAULT_PROVIDER}" == "codex" ]]; then
    command -v codex &>/dev/null || die "codex CLI is required but not found in PATH"
  else
    command -v claude &>/dev/null || die "claude CLI is required but not found in PATH"
  fi
fi
MAX_ITERATIONS=$(jq -r '.stop_when.max_iterations // .config.max_iterations // 10' "${FLEET_JSON}")
REVIEWER_LGTM_COUNT=$(jq -r '.stop_when.reviewer_lgtm_count // 1' "${FLEET_JSON}")
COST_CAP=$(jq -r '.stop_when.cost_cap_usd // .config.cost_cap_usd // 0' "${FLEET_JSON}")

WORKER_COUNT=$(jq '.workers | length' "${FLEET_JSON}")
WORKER_IDS=$(jq -r '.workers[].id' "${FLEET_JSON}")
# Detect reviewer: check role field first, then type field, then id containing "reviewer"
REVIEWER_ID=$(jq -r '.workers[] | select(.role == "reviewer") | .id' "${FLEET_JSON}" 2>/dev/null | head -1)
if [[ -z "${REVIEWER_ID}" ]]; then
  REVIEWER_ID=$(jq -r '.workers[] | select(.type == "reviewer") | .id' "${FLEET_JSON}" | head -1)
fi
if [[ -z "${REVIEWER_ID}" ]]; then
  REVIEWER_ID=$(jq -r '.workers[] | select(.id | test("review"; "i")) | .id' "${FLEET_JSON}" 2>/dev/null | head -1)
fi

info "Fleet: ${BOLD}${FLEET_NAME}${NC} (${WORKER_COUNT} workers)"
info "Stop conditions: max_iterations=${MAX_ITERATIONS}, reviewer_lgtm_count=${REVIEWER_LGTM_COUNT}, cost_cap=${COST_CAP}"
info "Reviewer worker: ${REVIEWER_ID:-none}"

if [[ -z "${REVIEWER_ID}" ]]; then
  warn "No reviewer worker found. The orchestrator will not have a verdict gate."
  warn "  To fix: set role=\"reviewer\" or type=\"reviewer\" on one worker, or include 'review' in the worker id."
fi

# ---------------------------------------------------------------------------
# Create directory structure
# ---------------------------------------------------------------------------
mkdir -p "${FLEET_ROOT}/iterations/1"
mkdir -p "${FLEET_ROOT}/workers"
mkdir -p "${FLEET_ROOT}/logs"
info "Created iterations/1/ directory"

# ---------------------------------------------------------------------------
# DAG layer computation (needed before orchestrator generation)
# ---------------------------------------------------------------------------
DAG_NUM_LAYERS=$(dag_count_layers "${FLEET_JSON}")
info "DAG layers: ${DAG_NUM_LAYERS}"
for _l in $(seq 0 $((DAG_NUM_LAYERS - 1))); do
  _lw=$(dag_get_layer_workers "$_l" "${FLEET_JSON}")
  info "  Layer ${_l}: ${_lw}"
done

# ---------------------------------------------------------------------------
# Generate orchestrator.sh
# ---------------------------------------------------------------------------
ORCH_SCRIPT="${FLEET_ROOT}/orchestrator.sh"

info "Generating orchestrator.sh with stop conditions (max_iterations=${MAX_ITERATIONS}, lgtm_count=${REVIEWER_LGTM_COUNT})"

cat > "${ORCH_SCRIPT}" <<ORCH_EOF
#!/usr/bin/env bash
# orchestrator.sh — generated by iterative-fleet launch.sh
# DO NOT EDIT manually — regenerate via launch.sh
#
# DAG-aware orchestrator: each iteration executes workers layer by layer.
# Layer 0 workers (no depends_on) are spawned at launch.
# Layers 1+ are spawned by this orchestrator after prior layers complete.
#
# Stop conditions baked in at generation time:
#   max_iterations = ${MAX_ITERATIONS}
#   reviewer_lgtm_count = ${REVIEWER_LGTM_COUNT}
#   cost_cap_usd = ${COST_CAP}
#   dag_layers = ${DAG_NUM_LAYERS}
#
# Verdict interface: reviewer writes iterations/<N>/review.md with:
#   verdict: lgtm | iterate | escalate

set -euo pipefail

FLEET_ROOT="${FLEET_ROOT}"
FLEET_JSON="${FLEET_JSON}"
MAX_ITERATIONS=${MAX_ITERATIONS}
REVIEWER_LGTM_COUNT=${REVIEWER_LGTM_COUNT}
COST_CAP="${COST_CAP}"
REVIEWER_ID="${REVIEWER_ID:-}"
DAG_NUM_LAYERS=${DAG_NUM_LAYERS}
POLL_INTERVAL=15
TMUX_SESSION="${FLEET_NAME}"
COST_LEDGER="\${FLEET_ROOT}/.cost-ledger.jsonl"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log() { echo -e "\${CYAN}[orchestrator]\${NC} \$(date -u +%H:%M:%S) \$*"; }
warn() { echo -e "\${YELLOW}[orchestrator]\${NC} \$(date -u +%H:%M:%S) \$*"; }
success() { echo -e "\${GREEN}[orchestrator]\${NC} \$(date -u +%H:%M:%S) \$*"; }
stop_fleet() { echo -e "\${BOLD}\${GREEN}[orchestrator]\${NC} STOP: \$*"; exit 0; }

# Source shared DAG library
source "${LIB_DIR}/dag.sh"

# Read cost from a single session.jsonl
_read_worker_cost() {
  local jsonl="\$1"
  [[ -f "\${jsonl}" ]] || { echo "0"; return; }
  if grep -q '"type":"result"' "\${jsonl}" 2>/dev/null; then
    grep '"type":"result"' "\${jsonl}" 2>/dev/null | tail -1 | jq -r '.total_cost_usd // 0' 2>/dev/null || echo "0"
  elif grep -q '"type":"turn.completed"' "\${jsonl}" 2>/dev/null; then
    grep '"type":"turn.completed"' "\${jsonl}" 2>/dev/null | tail -1 | python3 -c "
import sys, json
line = sys.stdin.readline().strip()
if not line: print('0'); sys.exit()
ev = json.loads(line)
u = ev.get('usage', {})
inp = u.get('input_tokens', 0)
outp = u.get('output_tokens', 0)
c = (inp * 2.0 + outp * 8.0) / 1_000_000.0
print(f'{c:.6f}')
" 2>/dev/null || echo "0"
  else
    echo "0"
  fi
}

# Snapshot costs from session.jsonl into cost ledger (append-only) before reset
snapshot_costs_to_ledger() {
  local iter="\$1"
  local worker_ids
  worker_ids=\$(jq -r '.workers[].id' "\${FLEET_JSON}" 2>/dev/null)
  for wid in \${worker_ids}; do
    local jsonl="\${FLEET_ROOT}/workers/\${wid}/session.jsonl"
    local cost
    cost=\$(_read_worker_cost "\${jsonl}")
    if [[ "\${cost}" != "0" ]]; then
      printf '{"iter":%d,"worker":"%s","cost":%s,"ts":"%s"}\n' \\
        "\${iter}" "\${wid}" "\${cost}" "\$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "\${COST_LEDGER}"
    fi
  done
}

# Read total cost from cost ledger + current session.jsonl files
get_total_cost() {
  local total=0
  # Ledger costs (from completed iterations)
  if [[ -f "\${COST_LEDGER}" ]]; then
    local ledger_total
    ledger_total=\$(python3 -c "
import json, sys
total = 0.0
for line in open(sys.argv[1]):
    line = line.strip()
    if not line: continue
    try: total += json.loads(line).get('cost', 0)
    except: pass
print(f'{total:.6f}')
" "\${COST_LEDGER}" 2>/dev/null || echo "0")
    total=\$(awk "BEGIN {printf \"%.6f\", \${total} + \${ledger_total}}")
  fi
  # Current in-progress session costs
  local worker_ids
  worker_ids=\$(jq -r '.workers[].id' "\${FLEET_JSON}" 2>/dev/null)
  for wid in \${worker_ids}; do
    local jsonl="\${FLEET_ROOT}/workers/\${wid}/session.jsonl"
    local cost
    cost=\$(_read_worker_cost "\${jsonl}")
    total=\$(awk "BEGIN {printf \"%.6f\", \${total} + \${cost}}")
  done
  echo "\${total}"
}

get_cumulative_cost() { get_total_cost; }

# Wait for specific workers to complete
wait_for_layer_workers() {
  local worker_list="\$1"
  while true; do
    if [[ -f "\${FLEET_ROOT}/.paused" ]]; then
      warn "Fleet is paused. Waiting for resume..."
      while [[ -f "\${FLEET_ROOT}/.paused" ]]; do sleep 5; done
      log "Resumed."
    fi
    local pending=()
    for wid in \${worker_list}; do
      if [[ -f "\${FLEET_ROOT}/workers/\${wid}/.done" ]] || \\
         [[ -f "\${FLEET_ROOT}/workers/\${wid}/.failed" ]]; then
        continue
      else
        pending+=("\${wid}")
      fi
    done
    if [[ "\${#pending[@]}" -eq 0 ]]; then
      return 0
    fi
    log "Waiting for workers: \$(IFS=', '; echo "\${pending[*]}")"
    sleep "\${POLL_INTERVAL}"
  done
}

# Build an iteration-aware prompt: original prompt + prior review feedback
# For iter 1, returns the original prompt path unchanged.
# For iter > 1, creates .prompt-iter-{iter}-{wid}.md with review context appended.
build_iter_prompt() {
  local wid="\$1"
  local iter="\$2"
  local original_prompt="\${FLEET_ROOT}/workers/\${wid}/prompt.md"

  if [[ "\${iter}" -le 1 ]]; then
    echo "\${original_prompt}"
    return
  fi

  local iter_prompt="\${FLEET_ROOT}/workers/\${wid}/.prompt-iter-\${iter}.md"

  # Start with original prompt
  cp "\${original_prompt}" "\${iter_prompt}"

  # Append prior review feedback
  {
    echo ""
    echo "---"
    echo ""
    echo "# Reviewer Feedback from Prior Iterations"
    echo ""
    echo "You are on iteration \${iter}. Address ALL issues listed below."
    echo ""
    for prev in \$(seq 1 \$((iter - 1))); do
      local review_file
      review_file=\$(find_review_file "\${prev}" 2>/dev/null || echo "")
      if [[ -n "\${review_file}" && -f "\${review_file}" ]]; then
        echo "## Iteration \${prev} Review"
        echo ""
        cat "\${review_file}"
        echo ""
      fi
    done
  } >> "\${iter_prompt}"

  echo "\${iter_prompt}"
}

# Spawn a worker by reading its saved command file
dag_spawn_worker() {
  local wid="\$1"
  local iter="\$2"
  local cmd_file="\${FLEET_ROOT}/.worker-cmd-\${wid}.sh"
  if [[ ! -f "\${cmd_file}" ]]; then
    warn "No command file for worker '\${wid}' — cannot spawn"
    return 1
  fi

  # Kill any prior tmux window for this worker
  tmux kill-window -t "\${TMUX_SESSION}:\${wid}" 2>/dev/null || true

  # Clear stale state
  local wdir="\${FLEET_ROOT}/workers/\${wid}"
  rm -f "\${wdir}/session.jsonl" "\${wdir}/.done" "\${wdir}/.failed"

  # Update status
  printf '{"worker_id":"%s","status":"RUNNING","step":"iter-%d","last_updated":"%s","cost_usd":0}\n' \\
    "\${wid}" "\${iter}" "\$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "\${wdir}/status.json"

  # Build iteration-aware prompt (injects prior review feedback for iter > 1)
  local iter_prompt
  iter_prompt=\$(build_iter_prompt "\${wid}" "\${iter}")
  local original_prompt="\${FLEET_ROOT}/workers/\${wid}/prompt.md"

  # Launch in tmux — swap prompt path if enhanced prompt was generated
  local worker_cmd
  worker_cmd=\$(cat "\${cmd_file}")
  if [[ "\${iter_prompt}" != "\${original_prompt}" ]]; then
    worker_cmd=\$(echo "\${worker_cmd}" | sed "s|cat '\${original_prompt}'|cat '\${iter_prompt}'|g")
    log "Injected review feedback from iterations 1-\$((iter - 1)) into prompt for '\${wid}'"
  fi
  tmux new-window -t "\${TMUX_SESSION}" -n "\${wid}" \\
    "bash -c \\"\${worker_cmd}\\""

  log "Spawned worker '\${wid}' (iteration \${iter})"
}

# Reset worker state between iterations (snapshot costs first)
reset_workers_for_iteration() {
  local iter="\$1"
  snapshot_costs_to_ledger "\$((iter - 1))"
  local worker_ids
  worker_ids=\$(jq -r '.workers[].id' "\${FLEET_JSON}" 2>/dev/null)
  for wid in \${worker_ids}; do
    local wdir="\${FLEET_ROOT}/workers/\${wid}"
    tmux kill-window -t "\${TMUX_SESSION}:\${wid}" 2>/dev/null || true
    rm -f "\${wdir}/session.jsonl" "\${wdir}/.done" "\${wdir}/.failed"
  done
  log "Reset all worker state for iteration \${iter}"
}

# Check if any worker committed to a displaced clone instead of the repo root.
# Scans each worker dir for .git directories — a sign the builder cloned
# the repo into the fleet dir when the sandbox was read-only.
check_displaced_repos() {
  local layer_workers="\$1"
  for wid in \${layer_workers}; do
    local wdir="\${FLEET_ROOT}/workers/\${wid}"
    local found_clones=()
    while IFS= read -r gitdir; do
      [[ -z "\${gitdir}" ]] && continue
      found_clones+=("\$(dirname "\${gitdir}")")
    done < <(find "\${wdir}" -maxdepth 3 -name ".git" -type d 2>/dev/null)
    if [[ "\${#found_clones[@]}" -gt 0 ]]; then
      for clone_path in "\${found_clones[@]}"; do
        warn "DISPLACED REPO: worker '\${wid}' committed to \${clone_path}, not to repo root"
        echo "\${clone_path}" >> "\${wdir}/.displaced-repo"
      done
    fi
  done
}

find_review_file() {
  local iter="\$1"
  local candidates=(
    "\${FLEET_ROOT}/iterations/\${iter}/review.md"
    "\${FLEET_ROOT}/iterations/\${iter}/review-\${iter}.md"
    "\${FLEET_ROOT}/iterations/review-\${iter}.md"
    "\${FLEET_ROOT}/iterations/\${iter}/review-1.md"
  )
  for f in "\${candidates[@]}"; do
    if [[ -f "\$f" ]] && grep -qi "verdict:" "\$f" 2>/dev/null; then
      echo "\$f"
      return 0
    fi
  done
  echo ""
  return 1
}

# Wait for reviewer to write its verdict for current iteration
wait_for_verdict() {
  local iter="\$1"
  log "Waiting for reviewer verdict (iteration \${iter}) ..."
  while true; do
    if [[ -f "\${FLEET_ROOT}/.paused" ]]; then
      warn "Fleet is paused. Waiting for resume..."
      while [[ -f "\${FLEET_ROOT}/.paused" ]]; do sleep 5; done
      log "Resumed."
    fi
    if [[ -f "\${FLEET_ROOT}/workers/\${REVIEWER_ID}/.done" ]] || \\
       [[ -f "\${FLEET_ROOT}/workers/\${REVIEWER_ID}/.failed" ]]; then
      local found
      found=\$(find_review_file "\${iter}" 2>/dev/null || echo "")
      if [[ -n "\${found}" ]]; then
        return 0
      fi
      warn "Reviewer finished but no verdict file found — treating as iterate"
      mkdir -p "\${FLEET_ROOT}/iterations/\${iter}"
      echo "verdict: iterate" > "\${FLEET_ROOT}/iterations/\${iter}/review.md"
      echo "NOTE: Reviewer process completed but did not write a verdict file." >> "\${FLEET_ROOT}/iterations/\${iter}/review.md"
      return 0
    fi
    local found
    found=\$(find_review_file "\${iter}" 2>/dev/null || echo "")
    if [[ -n "\${found}" ]]; then
      return 0
    fi
    sleep "\${POLL_INTERVAL}"
  done
}

read_verdict() {
  local iter="\$1"
  local found
  found=\$(find_review_file "\${iter}" 2>/dev/null || echo "")
  if [[ -z "\${found}" ]]; then
    echo "iterate"
    return
  fi
  grep -i "verdict:" "\${found}" 2>/dev/null | head -1 | \\
    sed 's/.*[Vv]erdict:[[:space:]]*//' | \\
    tr '[:upper:]' '[:lower:]' | tr -d '[:space:]' | tr -d '*'
}

# ---------------------------------------------------------------------------
# Main orchestration loop — each iteration executes the DAG layer by layer
# ---------------------------------------------------------------------------
log "Orchestrator started. max_iterations=\${MAX_ITERATIONS} lgtm_count=\${REVIEWER_LGTM_COUNT} cost_cap=\${COST_CAP} dag_layers=\${DAG_NUM_LAYERS}"

lgtm_count=0
iter=1

ORCH_STATE="\${FLEET_ROOT}/.orch-state.json"
if [[ -f "\${ORCH_STATE}" ]]; then
  iter=\$(jq -r '.current_iteration // 1' "\${ORCH_STATE}" 2>/dev/null || echo 1)
  lgtm_count=\$(jq -r '.lgtm_count // 0' "\${ORCH_STATE}" 2>/dev/null || echo 0)
  log "Resuming from state: iter=\${iter} lgtm_count=\${lgtm_count}"
fi

while true; do
  log "--- Iteration \${iter} ---"

  if [[ "\${iter}" -gt "\${MAX_ITERATIONS}" ]]; then
    stop_fleet "max_iterations (\${MAX_ITERATIONS}) reached after \${iter} iterations."
  fi

  if [[ "\${COST_CAP}" != "0" && "\${COST_CAP}" != "null" ]]; then
    cumulative=\$(get_cumulative_cost)
    if awk "BEGIN {exit !(\${cumulative} >= \${COST_CAP})}"; then
      stop_fleet "cost cap \${COST_CAP} reached (cumulative: \\\$\${cumulative})"
    fi
  fi

  if [[ -f "\${FLEET_ROOT}/.paused" ]]; then
    warn "Fleet is paused at start of iteration \${iter}. Waiting for resume..."
    while [[ -f "\${FLEET_ROOT}/.paused" ]]; do sleep 5; done
    log "Resumed."
  fi

  mkdir -p "\${FLEET_ROOT}/iterations/\${iter}"
  printf '{"current_iteration":%d,"lgtm_count":%d}\n' "\${iter}" "\${lgtm_count}" > "\${ORCH_STATE}"

  # Reset all workers for iteration 2+ (snapshot costs, clear state)
  if [[ "\${iter}" -gt 1 ]]; then
    reset_workers_for_iteration "\${iter}"
  fi

  # Execute the DAG layer by layer
  for layer in \$(seq 0 \$((DAG_NUM_LAYERS - 1))); do
    layer_workers=\$(dag_get_layer_workers "\${layer}" "\${FLEET_JSON}")
    [[ -z "\${layer_workers}" ]] && continue

    log "Spawning DAG layer \${layer}: \${layer_workers}"

    # Layer 0 on iteration 1 is already running (spawned by launch.sh)
    if [[ "\${layer}" -eq 0 && "\${iter}" -eq 1 ]]; then
      log "Layer 0 already running from launch"
    else
      for wid in \${layer_workers}; do
        dag_spawn_worker "\${wid}" "\${iter}"
      done
    fi

    # Wait for all workers in this layer to complete
    wait_for_layer_workers "\${layer_workers}"
    log "Layer \${layer} complete"

    # Check for displaced repos (builder cloned repo into fleet dir)
    check_displaced_repos "\${layer_workers}"
  done

  log "All DAG layers complete for iteration \${iter}"

  # Check for reviewer verdict (if reviewer exists)
  if [[ -n "\${REVIEWER_ID}" ]]; then
    wait_for_verdict "\${iter}"
    verdict=\$(read_verdict "\${iter}")
    log "Reviewer verdict for iteration \${iter}: \${verdict}"

    case "\${verdict}" in
      lgtm)
        lgtm_count=\$((lgtm_count + 1))
        success "LGTM (\${lgtm_count}/\${REVIEWER_LGTM_COUNT})"
        if [[ "\${lgtm_count}" -ge "\${REVIEWER_LGTM_COUNT}" ]]; then
          stop_fleet "reviewer approved \${lgtm_count} times — work is done!"
        fi
        ;;
      iterate)
        log "Reviewer says iterate. Starting iteration \$((iter + 1)) ..."
        lgtm_count=0
        ;;
      escalate)
        warn "Reviewer escalated — pausing for human input."
        touch "\${FLEET_ROOT}/.paused"
        echo "escalate" > "\${FLEET_ROOT}/.escalate-reason-iter\${iter}"
        while [[ -f "\${FLEET_ROOT}/.paused" ]]; do sleep 10; done
        log "Human cleared pause — resuming."
        ;;
      *)
        warn "Unknown verdict '\${verdict}' — treating as iterate."
        lgtm_count=0
        ;;
    esac
  fi

  iter=\$((iter + 1))
  mkdir -p "\${FLEET_ROOT}/iterations/\${iter}"
  printf '{"current_iteration":%d,"lgtm_count":%d}\n' "\${iter}" "\${lgtm_count}" > "\${ORCH_STATE}"
done
ORCH_EOF

chmod +x "${ORCH_SCRIPT}"
success "Generated orchestrator.sh"
info "  Stop conditions baked in: max_iterations=${MAX_ITERATIONS}, reviewer_lgtm_count=${REVIEWER_LGTM_COUNT}, cost_cap=${COST_CAP}"

# ---------------------------------------------------------------------------
# Dry run: print plan and exit
# ---------------------------------------------------------------------------
if [[ "${DRY_RUN}" -eq 1 ]]; then
  echo ""
  echo -e "${BOLD}[dry-run] Fleet plan for '${FLEET_NAME}'${NC}"
  echo "  Fleet root:    ${FLEET_ROOT}"
  echo "  Workers:       ${WORKER_COUNT}"
  echo "  Reviewer:      ${REVIEWER_ID:-none}"
  echo "  max_iterations=${MAX_ITERATIONS}  reviewer_lgtm_count=${REVIEWER_LGTM_COUNT}  cost_cap=${COST_CAP}"
  echo ""
  echo "  Workers to spawn:"
  jq -r '.workers[] | "    \(.id)  type=\(.type)  model=\(.model // "default")  budget=\(.max_budget_per_iter // "unset")"' "${FLEET_JSON}"
  echo ""
  echo "  Orchestrator: ${ORCH_SCRIPT}"
  echo "  Iteration dir: ${FLEET_ROOT}/iterations/1/"
  echo ""
  echo -e "  ${BOLD}[dry-run] No tmux sessions or claude processes spawned.${NC}"
  success "Dry run complete."
  exit 0
fi

# ---------------------------------------------------------------------------
# Register fleet
# ---------------------------------------------------------------------------
if declare -f registry_register >/dev/null 2>&1; then
  registry_register "${FLEET_ROOT}" "${FLEET_NAME}" "$$" || true
fi

# ---------------------------------------------------------------------------
# Create or reuse tmux session
# ---------------------------------------------------------------------------
TMUX_SESSION="${FLEET_NAME}"

if tmux has-session -t "${TMUX_SESSION}" 2>/dev/null; then
  info "tmux session '${TMUX_SESSION}' already exists — removing stale session"
  tmux kill-session -t "${TMUX_SESSION}" 2>/dev/null || true
fi

info "Creating tmux session: ${TMUX_SESSION}"
tmux new-session -d -s "${TMUX_SESSION}" -n "monitor" -x 220 -y 50
tmux send-keys -t "${TMUX_SESSION}:monitor" \
  "bash '${SCRIPT_DIR}/status.sh' '${FLEET_ROOT}' --watch" C-m

# ---------------------------------------------------------------------------
# Build INNER_CMD for every worker and save to .worker-cmd-<id>.sh
# Only spawn layer-0 workers now; layers 1+ are spawned by orchestrator.
# ---------------------------------------------------------------------------
info "Launching workers (layer 0 only; layers 1+ deferred to orchestrator) ..."

_seq=0
while IFS= read -r WORKER_ID; do
  [[ -z "${WORKER_ID}" ]] && continue
  _seq=$((_seq + 1))

  WORKER_TYPE=$(jq -r ".workers[] | select(.id == \"${WORKER_ID}\") | .type // \"read-only\"" "${FLEET_JSON}")
  WORKER_MODEL=$(jq -r ".workers[] | select(.id == \"${WORKER_ID}\") | .model // \"${DEFAULT_MODEL}\"" "${FLEET_JSON}")
  WORKER_PROVIDER=$(jq -r ".workers[] | select(.id == \"${WORKER_ID}\") | .provider // \"${DEFAULT_PROVIDER}\"" "${FLEET_JSON}")
  WORKER_REASONING_EFFORT=$(jq -r ".workers[] | select(.id == \"${WORKER_ID}\") | .reasoning_effort // \"${DEFAULT_REASONING_EFFORT}\"" "${FLEET_JSON}")
  MAX_TURNS=$(jq -r ".workers[] | select(.id == \"${WORKER_ID}\") | .max_turns // 0" "${FLEET_JSON}")
  MAX_BUDGET=$(jq -r ".workers[] | select(.id == \"${WORKER_ID}\") | .max_budget_per_iter // .max_budget_usd // 2.00" "${FLEET_JSON}")
  WORKER_TASK=$(jq -r ".workers[] | select(.id == \"${WORKER_ID}\") | .task // \"\"" "${FLEET_JSON}")

  WORKER_DIR="${FLEET_ROOT}/workers/${WORKER_ID}"
  WORKER_OUTPUT_DIR="${WORKER_DIR}/output"
  WORKER_PROMPT="${WORKER_DIR}/prompt.md"
  WORKER_SESSION_JSONL="${WORKER_DIR}/session.jsonl"

  mkdir -p "${WORKER_DIR}" "${WORKER_OUTPUT_DIR}"

  if [[ ! -f "${WORKER_PROMPT}" ]]; then
    warn "No prompt.md found for ${WORKER_ID} at ${WORKER_PROMPT} — skipping"
    continue
  fi

  DISALLOWED_TOOLS=$(get_disallowed_tools "${WORKER_TYPE}")
  CODEX_SANDBOX=$(jq -r ".workers[] | select(.id == \"${WORKER_ID}\") | .sandbox // \"\"" "${FLEET_JSON}")
  if [[ -z "${CODEX_SANDBOX}" || "${CODEX_SANDBOX}" == "null" ]]; then
    CODEX_SANDBOX=$(get_codex_sandbox "${WORKER_TYPE}")
  fi
  CODEX_EXTRA=$(get_codex_extra_flags "${WORKER_TYPE}")
  SESSION_NAME="iterative-${FLEET_NAME}-${WORKER_ID}"

  INNER_CMD=$(build_inner_cmd \
    --cwd "${FLEET_ROOT}" \
    --fleet-root "${FLEET_ROOT}" \
    --worker-id "${WORKER_ID}" \
    --worker-prompt "${WORKER_PROMPT}" \
    --worker-model "${WORKER_MODEL}" \
    --fallback-model "${FALLBACK_MODEL}" \
    --max-turns "${MAX_TURNS}" \
    --max-budget "${MAX_BUDGET}" \
    --session-name "${SESSION_NAME}" \
    --disallowed-tools "${DISALLOWED_TOOLS}" \
    --session-jsonl "${WORKER_SESSION_JSONL}" \
    --worker-dir "${WORKER_DIR}" \
    --provider "${WORKER_PROVIDER}" \
    --reasoning-effort "${WORKER_REASONING_EFFORT}" \
    --codex-sandbox "${CODEX_SANDBOX}" \
    --codex-extra-flags "${CODEX_EXTRA}" \
  )
  INNER_CMD+=" && touch '${WORKER_DIR}/.done' || touch '${WORKER_DIR}/.failed'"
  INNER_CMD+="; sleep 30"

  # Save command for ALL workers (orchestrator reads these to spawn per iteration)
  echo "${INNER_CMD}" > "${FLEET_ROOT}/.worker-cmd-${WORKER_ID}.sh"

  # Determine this worker's DAG layer
  WORKER_LAYER=$(dag_get_layer "${WORKER_ID}" "${FLEET_JSON}")

  if [[ "${WORKER_LAYER}" -gt 0 ]]; then
    # Layer 1+ — deferred to orchestrator
    success "  Deferred worker: ${WORKER_ID} (layer ${WORKER_LAYER}, spawned by orchestrator)"
    local_ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    cat > "${WORKER_DIR}/status.json" <<EOF
{
  "worker_id": "${WORKER_ID}",
  "status": "DEFERRED",
  "task": "${WORKER_TASK}",
  "step": "waiting-for-layer-$((WORKER_LAYER - 1))",
  "last_updated": "${local_ts}",
  "cost_usd": 0
}
EOF
  else
    # Layer 0 — spawn immediately; clear stale sentinels first
    rm -f "${WORKER_DIR}/.done" "${WORKER_DIR}/.failed" "${WORKER_DIR}/session.jsonl"
    tmux new-window -t "${TMUX_SESSION}" -n "${WORKER_ID}" \
      "bash -c \"${INNER_CMD}\""
    local_ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    cat > "${WORKER_DIR}/status.json" <<EOF
{
  "worker_id": "${WORKER_ID}",
  "status": "RUNNING",
  "task": "${WORKER_TASK}",
  "step": "launched",
  "last_updated": "${local_ts}",
  "cost_usd": 0
}
EOF
    success "  Spawned worker: ${WORKER_ID} (layer 0)"
  fi

  if [[ "${_seq}" -lt "${WORKER_COUNT}" ]]; then
    sleep "${LAUNCH_DELAY}"
  fi
done <<< "${WORKER_IDS}"

# ---------------------------------------------------------------------------
# Spawn orchestrator in tmux
# ---------------------------------------------------------------------------
info "Spawning orchestrator in tmux window 'orchestrator' ..."
tmux new-window -t "${TMUX_SESSION}" -n "orchestrator" \
  "bash '${ORCH_SCRIPT}'; echo '[orchestrator] exited'; sleep 60"

# ---------------------------------------------------------------------------
# Update fleet.json status
# ---------------------------------------------------------------------------
local_ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
tmp_fleet=$(mktemp "${FLEET_ROOT}/.tmp.fleet.XXXXXX")
jq --arg ts "${local_ts}" \
   '.status = "running" | .launched_at = $ts' \
   "${FLEET_JSON}" > "${tmp_fleet}"
mv "${tmp_fleet}" "${FLEET_JSON}"

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
echo ""
success "Fleet '${BOLD}${FLEET_NAME}${NC}${GREEN}' launched!"
echo ""
info "Attach:        ${BOLD}tmux attach -t ${TMUX_SESSION}${NC}"
info "Monitor:       ${BOLD}tmux attach -t ${TMUX_SESSION}:monitor${NC}"
info "Orchestrator:  ${BOLD}tmux attach -t ${TMUX_SESSION}:orchestrator${NC}"
info "Status:        ${BOLD}bash ${SCRIPT_DIR}/status.sh ${FLEET_ROOT}${NC}"
info "Pause:         ${BOLD}bash ${SCRIPT_DIR}/pause.sh ${FLEET_ROOT}${NC}"
info "Kill:          ${BOLD}bash ${SCRIPT_DIR}/kill.sh ${FLEET_ROOT} all${NC}"
echo ""
