#!/usr/bin/env bash
# launch.sh — Autoresearch Fleet Launcher
#
# Parses fleet.json, validates problem files, generates orchestrator.sh,
# spawns in tmux. The orchestrator loops: spawn agent → wait → check
# plateau → loop. Agent handles everything (edit, eval, git, results.tsv).
#
# Usage: launch.sh <fleet-root> [--dry-run]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/../lib"

source "${LIB_DIR}/logging.sh"
LOG_PREFIX="autoresearch"

if [[ -f "${LIB_DIR}/registry.sh" ]]; then
  source "${LIB_DIR}/registry.sh"
fi

# ---------------------------------------------------------------------------
usage() {
  cat <<EOF
${BOLD}USAGE${NC}
  launch.sh <fleet-root> [--dry-run]

${BOLD}DESCRIPTION${NC}
  Reads fleet.json, validates problem files (mutable file, eval harness,
  program.md), generates orchestrator.sh, and spawns it in tmux.

  The orchestrator runs the Karpathy autoresearch loop: spawn an AI agent
  each iteration, the agent edits one file, evals, keeps or discards,
  and repeats. Plateau-triggered web search breaks through ceilings.

${BOLD}FLAGS${NC}
  --dry-run   Validate and generate orchestrator.sh without spawning
EOF
}

# ---------------------------------------------------------------------------
# Args
# ---------------------------------------------------------------------------
[[ "${1:-}" == "--help" || "${1:-}" == "-h" ]] && { usage; exit 0; }

DRY_RUN=0
POSITIONAL=()
for arg in "$@"; do
  case "${arg}" in
    --dry-run) DRY_RUN=1 ;;
    *) POSITIONAL+=("${arg}") ;;
  esac
done
set -- "${POSITIONAL[@]:-}"

[[ $# -lt 1 ]] && { error "Missing fleet-root"; echo ""; usage; exit 1; }

FLEET_ROOT="$(realpath "${1}")"
FLEET_JSON="${FLEET_ROOT}/fleet.json"

# ---------------------------------------------------------------------------
# Validate
# ---------------------------------------------------------------------------
[[ ! -d "${FLEET_ROOT}" ]] && die "Fleet root does not exist: ${FLEET_ROOT}"
[[ ! -f "${FLEET_JSON}" ]] && die "fleet.json not found: ${FLEET_JSON}"
command -v jq &>/dev/null || die "jq is required"
command -v tmux &>/dev/null || die "tmux is required"

# ---------------------------------------------------------------------------
# Parse fleet.json
# ---------------------------------------------------------------------------
info "Reading fleet.json from: ${FLEET_ROOT}"

FLEET_NAME=$(jq -r '.fleet_name // "autoresearch"' "${FLEET_JSON}")
MODEL=$(jq -r '.config.model // "sonnet"' "${FLEET_JSON}")
FALLBACK_MODEL=$(jq -r '.config.fallback_model // "haiku"' "${FLEET_JSON}")
PROVIDER=$(jq -r '.config.provider // "claude"' "${FLEET_JSON}")
BUDGET_PER_ITER=$(jq -r '.config.budget_per_iter // 1.00' "${FLEET_JSON}")

# Validate fleet.json inputs against shell injection
validate_fleet_id "fleet_name" "${FLEET_NAME}"
validate_fleet_id "model" "${MODEL}"
validate_fleet_id "fallback_model" "${FALLBACK_MODEL}"
validate_fleet_id "provider" "${PROVIDER}"
MAX_TURNS=$(jq -r '.config.max_turns // 0' "${FLEET_JSON}")

EVAL_CMD=$(jq -r '.problem.eval_command // ""' "${FLEET_JSON}")
METRIC_DIR=$(jq -r '.problem.metric_direction // "minimize"' "${FLEET_JSON}")
METRIC_REGEX=$(jq -r '.problem.metric_regex // ""' "${FLEET_JSON}")
RESULTS_FILE=$(jq -r '.problem.results_file // "results.tsv"' "${FLEET_JSON}")
PROGRAM_MD=$(jq -r '.problem.program_md // "program.md"' "${FLEET_JSON}")
WORKDIR=$(jq -r '.problem.workdir // ""' "${FLEET_JSON}")

MAX_ITERATIONS=$(jq -r '.stop_when.max_iterations // 50' "${FLEET_JSON}")
COST_CAP=$(jq -r '.stop_when.cost_cap_usd // 0' "${FLEET_JSON}")

SEARCH_ENABLED=$(jq -r '.search.enabled // true' "${FLEET_JSON}")
PLATEAU_THRESHOLD=$(jq -r '.search.plateau_threshold // 3' "${FLEET_JSON}")

# Resolve workdir: defaults to fleet root if not set
if [[ -z "${WORKDIR}" || "${WORKDIR}" == "null" ]]; then
  WORKDIR="${FLEET_ROOT}"
else
  WORKDIR="$(realpath "${WORKDIR}")"
fi

# Validate required fields
[[ -z "${EVAL_CMD}" ]] && die "problem.eval_command is required in fleet.json"

# Validate workdir exists
[[ ! -d "${WORKDIR}" ]] && die "Working directory not found: ${WORKDIR}"

# Validate program.md exists (check workdir first, then fleet root)
PROGRAM_MD_PATH=""
if [[ -f "${WORKDIR}/${PROGRAM_MD}" ]]; then
  PROGRAM_MD_PATH="${WORKDIR}/${PROGRAM_MD}"
elif [[ -f "${FLEET_ROOT}/${PROGRAM_MD}" ]]; then
  PROGRAM_MD_PATH="${FLEET_ROOT}/${PROGRAM_MD}"
else
  die "program.md not found in ${WORKDIR} or ${FLEET_ROOT}"
fi

# Validate provider CLI
if [[ "${DRY_RUN}" -eq 0 ]]; then
  if [[ "${PROVIDER}" == "codex" ]]; then
    command -v codex &>/dev/null || die "codex CLI not found"
  elif [[ "${PROVIDER}" == "pi" ]]; then
    command -v pi &>/dev/null || die "pi CLI not found"
  else
    command -v claude &>/dev/null || die "claude CLI not found"
  fi
fi

info "Fleet:     ${BOLD}${FLEET_NAME}${NC}"
info "Model:     ${MODEL} (fallback: ${FALLBACK_MODEL})"
info "Provider:  ${PROVIDER}"
info "Workdir:   ${WORKDIR}"
info "Problem:   ${EVAL_CMD} (${METRIC_DIR})"
if [[ -n "${METRIC_REGEX}" ]]; then
  info "Metric:    extracted via regex: ${METRIC_REGEX}"
fi
info "Stop:      max_iterations=${MAX_ITERATIONS}, cost_cap=\$${COST_CAP}"
info "Search:    enabled=${SEARCH_ENABLED}, plateau_threshold=${PLATEAU_THRESHOLD}"

# ---------------------------------------------------------------------------
# Create directories
# ---------------------------------------------------------------------------
mkdir -p "${FLEET_ROOT}/logs"

# Init git if needed (in workdir, not fleet root)
if [[ ! -d "${WORKDIR}/.git" ]] && ! git -C "${WORKDIR}" rev-parse --git-dir &>/dev/null; then
  info "Initializing git repo in ${WORKDIR}..."
  (cd "${WORKDIR}" && git init && git add -A && git commit -m "autoresearch: initial state")
fi

# Init results.tsv if needed (in workdir — agent writes here)
RESULTS_PATH="${WORKDIR}/${RESULTS_FILE}"
if [[ ! -f "${RESULTS_PATH}" ]]; then
  printf 'commit\tmetric\tstatus\tdescription\n' > "${RESULTS_PATH}"
  info "Created ${RESULTS_FILE} with header"
fi

# ---------------------------------------------------------------------------
# Generate orchestrator.sh
# ---------------------------------------------------------------------------
ORCH_SCRIPT="${FLEET_ROOT}/orchestrator.sh"
info "Generating orchestrator.sh ..."

cat > "${ORCH_SCRIPT}" <<'ORCH_EOF'
#!/usr/bin/env bash
set -euo pipefail
ORCH_EOF

# Bake config into orchestrator
cat >> "${ORCH_SCRIPT}" <<EOF
# --- Baked config (generated by launch.sh) ---
FLEET_ROOT="${FLEET_ROOT}"
FLEET_JSON="${FLEET_JSON}"
FLEET_NAME="${FLEET_NAME}"
WORKDIR="${WORKDIR}"
RESULTS_FILE="${RESULTS_PATH}"
EVAL_CMD="${EVAL_CMD}"
PROGRAM_MD="${PROGRAM_MD}"
PROGRAM_MD_PATH="${PROGRAM_MD_PATH}"
METRIC_DIR="${METRIC_DIR}"
METRIC_REGEX="${METRIC_REGEX}"
MAX_ITERATIONS=${MAX_ITERATIONS}
COST_CAP=${COST_CAP}
BUDGET_PER_ITER=${BUDGET_PER_ITER}
MAX_TURNS=${MAX_TURNS}
PLATEAU_THRESHOLD=${PLATEAU_THRESHOLD}
SEARCH_ENABLED=${SEARCH_ENABLED}
MODEL="${MODEL}"
FALLBACK_MODEL="${FALLBACK_MODEL}"
PROVIDER="${PROVIDER}"
TMUX_SESSION="${FLEET_NAME}"
LIB_DIR="${LIB_DIR}"
POLL_INTERVAL=5
EOF

cat >> "${ORCH_SCRIPT}" <<'ORCH_BODY'

# Source shared worker-spawn library
source "${LIB_DIR}/worker-spawn.sh"

# --- Helpers ---
log()  { echo "[orch $(date -u +%H:%M:%S)] $*"; }
warn() { echo "[orch $(date -u +%H:%M:%S)] WARN: $*"; }

count_trailing_discards() {
  [[ -f "${RESULTS_FILE}" ]] || { echo 0; return; }
  tail -n +2 "${RESULTS_FILE}" | tac | \
    awk -F'\t' 'tolower($3) != "discard" && tolower($3) != "crash" {exit} {count++} END {print count+0}'
}

_read_session_cost() {
  local jsonl="$1"
  [[ -f "${jsonl}" ]] || { echo "0"; return; }
  # Prefer result event (has exact cost from API)
  if grep -q '"type":"result"' "${jsonl}" 2>/dev/null; then
    grep '"type":"result"' "${jsonl}" 2>/dev/null | tail -1 | \
      jq -r '.total_cost_usd // 0' 2>/dev/null || echo "0"
  elif tail -1 "${jsonl}" 2>/dev/null | jq -e '.type == \"message\" and .message.role == \"assistant\" and .message.stopReason == \"stop\"' >/dev/null 2>&1; then
    # Pi: cost may be 0 for kimi — estimate from tokens
    tail -1 "${jsonl}" 2>/dev/null | python3 -c "
import sys, json
line = sys.stdin.readline().strip()
if not line: print('0'); sys.exit()
ev = json.loads(line)
u = ev.get('message', {}).get('usage', {})
cost_val = u.get('cost', {}).get('total', 0)
if cost_val and float(cost_val) > 0:
    print(f'{float(cost_val):.6f}')
    sys.exit()
inp = u.get('input', 0)
outp = u.get('output', 0)
cache = u.get('cacheRead', 0)
c = (inp * 3.0 + outp * 15.0 + cache * 0.30) / 1_000_000.0
print(f'{c:.6f}')
" 2>/dev/null || echo "0"
  else
    # Sum usage from assistant messages (estimate from token counts)
    python3 -c "
import json, sys
total = 0.0
# Model pricing per million tokens: {input, cache_read, cache_create, output}
PRICING = {
    'haiku':  (0.80, 0.08, 1.00, 4.00),
    'sonnet': (3.00, 0.30, 3.75, 15.00),
    'opus':   (15.00, 1.50, 18.75, 75.00),
}
def get_pricing(model_id):
    for k, v in PRICING.items():
        if k in (model_id or ''):
            return v
    return PRICING['sonnet']  # default

for line in open(sys.argv[1]):
    line = line.strip()
    if not line: continue
    try:
        ev = json.loads(line)
        if ev.get('type') != 'assistant': continue
        msg = ev.get('message', {})
        u = msg.get('usage', {})
        if not u: continue
        model = msg.get('model', '')
        inp_p, cache_r_p, cache_c_p, out_p = get_pricing(model)
        inp = u.get('input_tokens', 0)
        outp = u.get('output_tokens', 0)
        cache_read = u.get('cache_read_input_tokens', 0)
        cache_create = u.get('cache_creation_input_tokens', 0)
        cost = (inp * inp_p + cache_read * cache_r_p + cache_create * cache_c_p + outp * out_p) / 1_000_000.0
        total += cost
    except: pass
print(f'{total:.6f}')
" "${jsonl}" 2>/dev/null || echo "0"
  fi
}

get_total_cost() {
  local total=0
  for jsonl in "${FLEET_ROOT}"/logs/session-iter-*.jsonl; do
    [[ -f "${jsonl}" ]] || continue
    local cost
    cost=$(_read_session_cost "${jsonl}")
    total=$(awk "BEGIN {printf \"%.2f\", ${total} + ${cost}}")
  done
  echo "${total}"
}

get_best_metric() {
  [[ -f "${RESULTS_FILE}" ]] || return
  local kept
  kept=$(tail -n +2 "${RESULTS_FILE}" | awk -F'\t' 'tolower($3) == "keep" {print $2}')
  [[ -z "${kept}" ]] && return
  if [[ "${METRIC_DIR}" == "minimize" ]]; then
    echo "${kept}" | sort -g | head -1
  else
    echo "${kept}" | sort -rg | head -1
  fi
}

get_iteration_count() {
  [[ -f "${RESULTS_FILE}" ]] || { echo 0; return; }
  local count
  count=$(tail -n +2 "${RESULTS_FILE}" | wc -l)
  echo "${count}"
}

stop_fleet() {
  log "STOPPING: $1"
  local ts; ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  if [[ -f "${FLEET_JSON}" ]]; then
    local tmp; tmp=$(mktemp "${FLEET_ROOT}/.tmp.fleet.XXXXXX")
    jq --arg ts "${ts}" --arg reason "$1" \
       '.status = "completed" | .completed_at = $ts | .stop_reason = $reason' \
       "${FLEET_JSON}" > "${tmp}"
    mv "${tmp}" "${FLEET_JSON}"
  fi
  printf '{"current_iteration":%d,"status":"completed","stop_reason":"%s"}\n' \
    "${iter}" "$1" > "${ORCH_STATE}"
  exit 0
}

# --- Main loop ---
log "Orchestrator started."
log "  max_iterations=${MAX_ITERATIONS} cost_cap=\$${COST_CAP}"
log "  plateau_threshold=${PLATEAU_THRESHOLD} search=${SEARCH_ENABLED}"
log "  model=${MODEL} provider=${PROVIDER} budget_per_iter=\$${BUDGET_PER_ITER}"

ORCH_STATE="${FLEET_ROOT}/.orch-state.json"
iter=1
if [[ -f "${ORCH_STATE}" ]]; then
  saved_iter=$(jq -r '.current_iteration // 1' "${ORCH_STATE}" 2>/dev/null || echo 1)
  saved_status=$(jq -r '.status // "running"' "${ORCH_STATE}" 2>/dev/null || echo "running")
  if [[ "${saved_status}" == "completed" ]]; then
    log "Fleet already completed. Delete .orch-state.json to restart."
    exit 0
  fi
  iter=${saved_iter}
  log "Resuming from iter=${iter}"
fi

cd "${WORKDIR}"

while true; do
  log "=== Iteration ${iter} ==="

  # Stop: max iterations
  if [[ ${iter} -gt ${MAX_ITERATIONS} ]]; then
    stop_fleet "max_iterations (${MAX_ITERATIONS}) reached"
  fi

  # Stop: cost cap
  if [[ "${COST_CAP}" != "0" && "${COST_CAP}" != "null" ]]; then
    total_cost=$(get_total_cost)
    if awk "BEGIN {exit !(${total_cost} >= ${COST_CAP})}"; then
      stop_fleet "cost cap \$${COST_CAP} reached (total: \$${total_cost})"
    fi
  fi

  # Pause
  if [[ -f "${FLEET_ROOT}/.paused" ]]; then
    warn "Paused. Waiting for resume..."
    while [[ -f "${FLEET_ROOT}/.paused" ]]; do sleep 5; done
    log "Resumed."
  fi

  # Plateau detection (done in bash, NOT by LLM — critical lesson from experiment 009)
  trailing=$(count_trailing_discards)
  is_search=false
  if [[ "${SEARCH_ENABLED}" == "true" && ${trailing} -ge ${PLATEAU_THRESHOLD} ]]; then
    is_search=true
    log "PLATEAU: ${trailing} consecutive discards → search mode"
  else
    log "Normal mode (${trailing} trailing discards)"
  fi

  # Save state
  best=$(get_best_metric)
  total_cost=$(get_total_cost)
  printf '{"current_iteration":%d,"trailing_discards":%d,"is_search":%s,"best_metric":"%s","total_cost":"%s","status":"running"}\n' \
    "${iter}" "${trailing}" "${is_search}" "${best:-n/a}" "${total_cost}" > "${ORCH_STATE}"

  # Build prompt
  PROMPT="You are an autonomous research agent. Read ${PROGRAM_MD_PATH} for full instructions. "
  PROMPT+="This is iteration ${iter}. Read ${RESULTS_FILE} to see what has been tried. "
  PROMPT+="Make ONE change to the codebase, commit it, run ${EVAL_CMD}, "
  PROMPT+="and update ${RESULTS_FILE}. Keep or revert based on the result. "

  if [[ -n "${METRIC_REGEX}" && "${METRIC_REGEX}" != "null" ]]; then
    PROMPT+="Extract the metric from eval output using this pattern: ${METRIC_REGEX} "
  fi

  if [[ "${is_search}" == "true" ]]; then
    PROMPT+="PLATEAU DETECTED: the last ${trailing} experiments were all discard/crash. "
    PROMPT+="You MUST search the web before coding. Do this: "
    PROMPT+="1. Read ${RESULTS_FILE} to understand what has been tried and failed. "
    PROMPT+="2. Use WebSearch to find new optimization techniques for this problem. "
    PROMPT+="3. Based on what you find, implement a NEW approach in the codebase. "
    PROMPT+="4. Prefix your ${RESULTS_FILE} description with [search]. "
    PROMPT+="5. Commit, eval, keep or revert as usual. "
  fi

  PROMPT+="Be concise — just do the work, no preamble."

  # Write prompt to temp file (build_inner_cmd reads from file, not stdin)
  prompt_file="${FLEET_ROOT}/logs/.prompt-iter-${iter}.md"
  echo "${PROMPT}" > "${prompt_file}"

  # Session log for this iteration
  session_jsonl="${FLEET_ROOT}/logs/session-iter-${iter}.jsonl"
  rm -f "${session_jsonl}"

  # Build extra flags for search mode
  codex_extra=""
  [[ "${is_search}" == "true" ]] && codex_extra="-c 'web_search=\"live\"'"

  # Pi tool allowlist (all built-ins + web search tools if needed)
  PI_TOOLS="read,bash,edit,write,grep,find,ls"
  [[ "${is_search}" == "true" ]] && PI_TOOLS="read,bash,edit,write,grep,find,ls,web_search,fetch_content,code_search,get_search_content"

  # Build command via shared lib/worker-spawn.sh
  log "Spawning ${PROVIDER} agent (model=${MODEL}, budget=\$${BUDGET_PER_ITER})..."

  AGENT_CMD=$(build_inner_cmd \
    --cwd "${WORKDIR}" \
    --fleet-root "${FLEET_ROOT}" \
    --worker-id "autoresearch-iter-${iter}" \
    --worker-prompt "${prompt_file}" \
    --worker-model "${MODEL}" \
    --fallback-model "${FALLBACK_MODEL}" \
    --max-turns "${MAX_TURNS}" \
    --max-budget "${BUDGET_PER_ITER}" \
    --session-name "autoresearch-${FLEET_NAME}-iter-${iter}" \
    --disallowed-tools "" \
    --session-jsonl "${session_jsonl}" \
    --worker-dir "${FLEET_ROOT}/logs" \
    --provider "${PROVIDER}" \
    --codex-sandbox "workspace-write" \
    --codex-extra-flags "${codex_extra}" \
    --extra-exports "PI_TOOLS=${PI_TOOLS}" \
  )

  # For search mode with claude provider, inject --tools default (enables WebSearch)
  # For Pi provider, build_inner_cmd already handles --tools via PI_TOOLS
  if [[ "${is_search}" == "true" && "${PROVIDER}" == "claude" ]]; then
    AGENT_CMD=$(printf '%s\n' "${AGENT_CMD}" | sed 's/claude -p/claude -p --tools default/')
  fi

  agent_rc=0
  bash -c "${AGENT_CMD}" || agent_rc=$?

  if [[ ${agent_rc} -ne 0 ]]; then
    warn "Agent exited with rc=${agent_rc}"
  fi

  # Post-iteration summary
  best=$(get_best_metric)
  total_cost=$(get_total_cost)
  new_trailing=$(count_trailing_discards)
  total_iters=$(get_iteration_count)
  log "Iter ${iter} done. Best: ${best:-n/a} | Cost: \$${total_cost} | Results: ${total_iters} rows | Trailing discards: ${new_trailing}"

  iter=$((iter + 1))
done
ORCH_BODY

chmod +x "${ORCH_SCRIPT}"
success "Generated orchestrator.sh"

# ---------------------------------------------------------------------------
# Dry run: stop here
# ---------------------------------------------------------------------------
if [[ "${DRY_RUN}" -eq 1 ]]; then
  success "Dry run complete. Orchestrator generated at: ${ORCH_SCRIPT}"
  info "To launch: bash ${SCRIPT_DIR}/launch.sh ${FLEET_ROOT}"
  exit 0
fi

# ---------------------------------------------------------------------------
# Spawn in tmux
# ---------------------------------------------------------------------------
TMUX_SESSION="${FLEET_NAME}"

# Kill stale session
tmux has-session -t "${TMUX_SESSION}" 2>/dev/null && {
  warn "Killing stale tmux session '${TMUX_SESSION}'"
  tmux kill-session -t "${TMUX_SESSION}" 2>/dev/null || true
}

info "Spawning tmux session '${TMUX_SESSION}' ..."
tmux new-session -d -s "${TMUX_SESSION}" -n "monitor" -x 220 -y 50
tmux send-keys -t "${TMUX_SESSION}:monitor" \
  "bash '${SCRIPT_DIR}/status.sh' '${FLEET_ROOT}' --watch" C-m

tmux new-window -t "${TMUX_SESSION}" -n "orchestrator" \
  "bash '${ORCH_SCRIPT}'; echo '[orchestrator] exited — press any key'; read -r"

# Register in fleet registry
if type -t registry_register &>/dev/null; then
  registry_register "${FLEET_ROOT}" "${FLEET_NAME}" $$
  info "Registered in fleet registry as '${FLEET_NAME}'"
fi

# Update fleet.json
local_ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
tmp_fleet=$(mktemp "${FLEET_ROOT}/.tmp.fleet.XXXXXX")
jq --arg ts "${local_ts}" \
   '.status = "running" | .launched_at = $ts' \
   "${FLEET_JSON}" > "${tmp_fleet}"
mv "${tmp_fleet}" "${FLEET_JSON}"

echo ""
success "Autoresearch fleet '${BOLD}${FLEET_NAME}${NC}${GREEN}' launched!"
echo ""
info "Attach:        ${BOLD}tmux attach -t ${TMUX_SESSION}${NC}"
info "Monitor:       ${BOLD}tmux attach -t ${TMUX_SESSION}:monitor${NC}"
info "Orchestrator:  ${BOLD}tmux attach -t ${TMUX_SESSION}:orchestrator${NC}"
info "Status:        ${BOLD}bash ${SCRIPT_DIR}/status.sh ${FLEET_ROOT}${NC}"
info "Pause:         ${BOLD}bash ${SCRIPT_DIR}/pause.sh ${FLEET_ROOT}${NC}"
info "Kill:          ${BOLD}bash ${SCRIPT_DIR}/kill.sh ${FLEET_ROOT}${NC}"
echo ""
