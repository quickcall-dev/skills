#!/usr/bin/env bash
# launch.sh — Fleet Orchestrator Launcher
#
# Reads fleet.json from the given fleet root directory, creates a tmux session,
# and launches all workers with staggered concurrency control.
#
# Usage: launch.sh <fleet-root>
#        launch.sh --help

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

# ---------------------------------------------------------------------------
# macOS / bash 3.2 compatibility
# ---------------------------------------------------------------------------
if [[ "${BASH_VERSINFO[0]:-0}" -lt 4 ]]; then
  warn "bash ${BASH_VERSION} detected. bash 4+ recommended. Running with compatibility fallbacks."
fi

NO_FLOCK=0
if ! command -v flock &>/dev/null; then
  NO_FLOCK=1
  warn "flock not found. Using pidfile-based locking fallback."
fi

# Usage: try_flock <fd> <pidfile> [mode]
# mode: n = non-blocking (default), x = blocking
try_flock() {
  local _fd="$1"
  local _pidfile="$2"
  local _mode="${3:-n}"
  if [[ "${NO_FLOCK}" -eq 0 ]]; then
    if [[ "${_mode}" == "n" ]]; then
      flock -n "${_fd}"
    else
      flock -x "${_fd}"
    fi
  else
    if [[ -f "${_pidfile}" ]]; then
      local _pid
      _pid=$(cat "${_pidfile}" 2>/dev/null || echo "")
      if [[ -n "${_pid}" ]] && kill -0 "${_pid}" 2>/dev/null; then
        return 1
      fi
    fi
    echo "$$" > "${_pidfile}"
    return 0
  fi
}

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------
usage() {
  cat <<EOF
${BOLD}USAGE${NC}
  launch.sh <fleet-root>
  launch.sh --help

${BOLD}DESCRIPTION${NC}
  Reads fleet.json from <fleet-root>, creates a tmux session named after the
  fleet, and launches each worker in its own tmux window with staggered delays
  and max-concurrent concurrency control.

${BOLD}ARGUMENTS${NC}
  fleet-root    Path to the fleet root directory containing fleet.json

${BOLD}FLEET.JSON CONFIG FIELDS${NC}
  fleet_name              Name used for the tmux session
  config.max_concurrent   Max simultaneously running workers (default: 5)
  config.model            Default model for workers (default: sonnet)
  config.fallback_model   Fallback model on overload (default: haiku)
  workers[]               Array of worker definitions

${BOLD}WORKER FIELDS${NC}
  id          Worker identifier (e.g. worker-01)
  type        Worker type: read-only | write | code-run | research | reviewer | orchestrator
  model       Per-worker model override (falls back to config.model)
  task        Task description passed as --name label

${BOLD}WORKER TYPES & DISALLOWED TOOLS${NC}
  read-only    Bash, Edit, Write, Agent, WebFetch, WebSearch
  write        Bash, Agent, WebFetch, WebSearch
  code-run     Agent, WebFetch, WebSearch
  research     Bash, Edit, Agent
  reviewer     Bash, Edit, Agent, WebFetch, WebSearch
  orchestrator Agent, WebFetch, WebSearch, Edit

${BOLD}EXAMPLES${NC}
  launch.sh ~/.claude/fleets/research-fleet
  launch.sh ./my-fleet
EOF
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

FORCE_RELAUNCH=0
POSITIONAL=()
for arg in "$@"; do
  case "${arg}" in
    --force-relaunch) FORCE_RELAUNCH=1 ;;
    *) POSITIONAL+=("${arg}") ;;
  esac
done
set -- "${POSITIONAL[@]}"

if [[ $# -lt 1 ]]; then
  error "Missing required argument: fleet-root"
  echo ""
  usage
  exit 1
fi

HOOKS_DIR="${SCRIPT_DIR}/../hooks"

FLEET_ROOT="${1}"
FLEET_ROOT="$(realpath "${FLEET_ROOT}")"

# ---------------------------------------------------------------------------
# Validate fleet root and fleet.json
# ---------------------------------------------------------------------------
if [[ ! -d "${FLEET_ROOT}" ]]; then
  die "Fleet root does not exist: ${FLEET_ROOT}"
fi

FLEET_JSON="${FLEET_ROOT}/fleet.json"
if [[ ! -f "${FLEET_JSON}" ]]; then
  die "fleet.json not found at: ${FLEET_JSON}"
fi

# ---------------------------------------------------------------------------
# Fleet-root .gitignore — prevent log artifacts from polluting git status
# ---------------------------------------------------------------------------
GITIGNORE="${FLEET_ROOT}/.gitignore"
if [[ ! -f "${GITIGNORE}" ]]; then
  cat > "${GITIGNORE}" <<'EOF'
# Fleet-generated artifacts — keep repo clean
*.jsonl
*.out
*.out.last
EOF
fi

# ---------------------------------------------------------------------------
# Single-launcher lock — prevents the "4 wedged launch.sh processes" scenario
# from problems.md #3. Second invocation exits cleanly with a clear pointer
# at the live pid.
# ---------------------------------------------------------------------------
LAUNCH_LOCK="${FLEET_ROOT}/.launch.lock"
LAUNCH_PID_FILE="${FLEET_ROOT}/.launch.pid"
exec 8>"${LAUNCH_LOCK}"
if ! try_flock 8 "${LAUNCH_PID_FILE}" n; then
  existing_pid="$(cat "${LAUNCH_PID_FILE}" 2>/dev/null || echo unknown)"
  echo "ERROR: another launch.sh is already active on this fleet (pid ${existing_pid})" >&2
  echo "       fleet root: ${FLEET_ROOT}" >&2
  echo "       if you believe this is stale, remove ${LAUNCH_LOCK} and retry" >&2
  exit 2
fi
echo "$$" > "${LAUNCH_PID_FILE}"
trap 'rm -f "${LAUNCH_PID_FILE}"' EXIT

# P4.3: register this fleet in the shared name→root registry so kill/view/feed
# can resolve by fleet_name instead of requiring the absolute path.
# shellcheck source=../lib/registry.sh
if [[ -f "${SCRIPT_DIR}/../lib/registry.sh" ]]; then
  # shellcheck disable=SC1091
  source "${SCRIPT_DIR}/../lib/registry.sh"
fi

# Unconditional startup banner so background launches are not invisible
# (problems.md #2). Goes to stdout regardless of whether anyone is attached.
echo "[launch.sh] pid=$$ fleet_root=${FLEET_ROOT} started_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"

if ! command -v jq &>/dev/null; then
  die "jq is required but not installed. Install with: sudo apt-get install jq"
fi

if ! command -v tmux &>/dev/null; then
  die "tmux is required but not installed. Install with: sudo apt-get install tmux"
fi

# ---------------------------------------------------------------------------
# Parse fleet.json
# ---------------------------------------------------------------------------
info "Reading fleet.json from: ${FLEET_ROOT}"

FLEET_NAME=$(jq -r '.fleet_name // "fleet"' "${FLEET_JSON}")
FLEET_ID=$(jq -r '.fleet_id // .fleet_name // "fleet"' "${FLEET_JSON}")
MAX_CONCURRENT=$(jq -r '.config.max_concurrent // 5' "${FLEET_JSON}")
DEFAULT_MODEL=$(jq -r '.config.model // "sonnet"' "${FLEET_JSON}")
FALLBACK_MODEL=$(jq -r '.config.fallback_model // "haiku"' "${FLEET_JSON}")
DEFAULT_PROVIDER=$(jq -r '.config.provider // "claude"' "${FLEET_JSON}")
DEFAULT_REASONING_EFFORT=$(jq -r '.config.reasoning_effort // ""' "${FLEET_JSON}")
LAUNCH_DELAY=$(jq -r '.config.launch_delay_seconds // 3' "${FLEET_JSON}")
MAX_BUDGET_FLEET=$(jq -r 'if (.config.max_budget_fleet == null or .config.max_budget_fleet == "null" or .config.max_budget_fleet == 0) then "0" else (.config.max_budget_fleet | tostring) end' "${FLEET_JSON}")
KEEP_PANES_OPEN=$(jq -r '.config.keep_panes_open // false' "${FLEET_JSON}")
RECORD=$(jq -r 'if .config.record == true then "true" else "false" end' "${FLEET_JSON}")

WORKER_COUNT=$(jq '.workers | length' "${FLEET_JSON}")

# Validate fleet.json inputs against shell injection
validate_fleet_id "fleet_name" "${FLEET_NAME}"
validate_fleet_id "fleet_id" "${FLEET_ID}"
validate_fleet_id "model" "${DEFAULT_MODEL}"
validate_fleet_id "fallback_model" "${FALLBACK_MODEL}"
validate_fleet_id "provider" "${DEFAULT_PROVIDER}"
for _wid in $(jq -r '.workers[].id' "${FLEET_JSON}"); do
  validate_fleet_id "worker_id" "${_wid}"
done

# Validate required CLI tools based on provider
if [[ "${DEFAULT_PROVIDER}" == "codex" ]]; then
  command -v codex &>/dev/null || die "codex CLI is required but not found in PATH"
elif [[ "${DEFAULT_PROVIDER}" == "pi" ]]; then
  command -v pi &>/dev/null || die "pi CLI is required but not found in PATH"
else
  command -v claude &>/dev/null || die "claude CLI is required but not found in PATH"
fi

info "Fleet: ${BOLD}${FLEET_NAME}${NC} (${WORKER_COUNT} workers, max_concurrent=${MAX_CONCURRENT})"
info "Provider: ${DEFAULT_PROVIDER} | Models: ${DEFAULT_MODEL} / fallback: ${FALLBACK_MODEL}"

# Topological sort workers by depends_on (P2.1). Kahn's algorithm in python.
# MUST run before tmux session creation so a cycle errors out cleanly without
# leaving orphan tmux state behind (test scenario G).
TOPO_ORDER=$(python3 -c '
import json, sys, collections
with open(sys.argv[1]) as f:
    data = json.load(f)
workers = data.get("workers", [])
ids = [w["id"] for w in workers]
idset = set(ids)
deps = {w["id"]: [d for d in (w.get("depends_on") or []) if d in idset] for w in workers}
indeg = {wid: 0 for wid in ids}
rev = collections.defaultdict(list)
for wid, ds in deps.items():
    for d in ds:
        indeg[wid] += 1
        rev[d].append(wid)
# BFS-layered: emit ALL currently-ready nodes (preserving array order)
# before promoting their downstream successors. This ensures all dep-free
# workers spawn in the first wave instead of being delayed by an earlier
# dependent in the array (problems.md #1, scenario E).
out = []
current = sorted([wid for wid in ids if indeg[wid] == 0], key=lambda w: ids.index(w))
while current:
    out.extend(current)
    next_layer = []
    for n in current:
        for m in rev[n]:
            indeg[m] -= 1
            if indeg[m] == 0:
                next_layer.append(m)
    current = sorted(next_layer, key=lambda w: ids.index(w))
if len(out) != len(ids):
    remaining = [wid for wid in ids if wid not in out]
    sys.stderr.write("CYCLE:" + ",".join(remaining) + "\n")
    sys.exit(2)
print("\n".join(out))
' "${FLEET_JSON}") || die "fleet.json has a depends_on cycle — see CYCLE line on stderr above"

# P4.3: register name→root mapping (no-op if registry helper unavailable)
if declare -f registry_register >/dev/null 2>&1; then
  registry_register "${FLEET_ROOT}" "${FLEET_NAME}" "$$" || true
fi

# ---------------------------------------------------------------------------
# Create tmux session
# ---------------------------------------------------------------------------
TMUX_SESSION="${FLEET_NAME}"

if tmux has-session -t "${TMUX_SESSION}" 2>/dev/null; then
  existing_worker_windows=$(tmux list-windows -t "${TMUX_SESSION}" -F '#W' 2>/dev/null | grep -Fxv 'monitor' || true)
  live_worker_procs=0
  if [[ -d "${FLEET_ROOT}/workers" ]]; then
    if pgrep -f "FLEET_ROOT=${FLEET_ROOT} " >/dev/null 2>&1 \
       || pgrep -f "fleet-${FLEET_NAME}-" >/dev/null 2>&1; then
      live_worker_procs=1
    fi
  fi
  if [[ -n "${existing_worker_windows}" && "${live_worker_procs}" -eq 1 ]]; then
    if [[ "${FORCE_RELAUNCH}" -eq 1 ]]; then
      warn "--force-relaunch: tearing down live fleet '${FLEET_NAME}' via kill.sh"
      bash "${SCRIPT_DIR}/kill.sh" "${FLEET_ROOT}" all --force || true
    else
      error "fleet ${FLEET_NAME} is already running — use kill.sh ${FLEET_ROOT} all --force to tear it down first, or pass --force-relaunch"
      exit 3
    fi
  else
    info "tmux session '${TMUX_SESSION}' is a stale husk — removing it"
    tmux kill-session -t "${TMUX_SESSION}" 2>/dev/null || true
  fi
fi

info "Creating tmux session: ${TMUX_SESSION}"

# ---------------------------------------------------------------------------
# Create fleet-level directory structure (must exist before tmux log)
# ---------------------------------------------------------------------------
mkdir -p "${FLEET_ROOT}/workers"
mkdir -p "${FLEET_ROOT}/directives"
mkdir -p "${FLEET_ROOT}/shared"
mkdir -p "${FLEET_ROOT}/logs"

# ---------------------------------------------------------------------------
# tmux operation logger — every tmux call goes through this so we can trace
# failures that would otherwise be swallowed silently.
# ---------------------------------------------------------------------------
TMUX_LOG="${FLEET_ROOT}/logs/tmux-ops.log"
tmux_run() {
  # Usage: tmux_run <label> tmux <args...>
  local label="$1"; shift
  local _rc=0
  local _stderr
  _stderr=$("$@" 2>&1) || _rc=$?
  local _ts
  _ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  if [[ ${_rc} -eq 0 ]]; then
    echo "[${_ts}] OK   ${label}: $*" >> "${TMUX_LOG}"
  else
    echo "[${_ts}] FAIL ${label}: $* | rc=${_rc} | stderr=${_stderr}" >> "${TMUX_LOG}"
  fi
  # After any tmux op, verify the session still exists
  if ! tmux has-session -t "${TMUX_SESSION}" 2>/dev/null; then
    echo "[${_ts}] DEAD session ${TMUX_SESSION} gone after: ${label}" >> "${TMUX_LOG}"
  fi
  if [[ -n "${_stderr}" && ${_rc} -ne 0 ]]; then
    echo "${_stderr}" >&2
  fi
  return ${_rc}
}

# Create the session with a monitor window (index 0)
tmux_run "new-session" tmux new-session -d -s "${TMUX_SESSION}" -n "monitor" -x 220 -y 50
# Run the live status dashboard inside the monitor pane so attaching to it
# actually shows something. Without this the pane is just an idle bash prompt.
tmux_run "send-keys:monitor" tmux send-keys -t "${TMUX_SESSION}:monitor" \
  "bash '${SCRIPT_DIR}/status.sh' '${FLEET_ROOT}' --watch" C-m

# Status is derived from session.jsonl — no hooks needed.

# ---------------------------------------------------------------------------
# Helper: check if session.jsonl has a terminal event (provider-agnostic)
#   Claude:  "type":"result"
#   Codex:   "type":"turn.completed" or "type":"turn.failed"
# ---------------------------------------------------------------------------
has_terminal_event() {
  local jsonl="$1"
  local last_type
  last_type=$(tail -1 "${jsonl}" 2>/dev/null | jq -r '.type' 2>/dev/null || echo "")
  # Claude / Codex terminal events
  [[ "${last_type}" == "result" || "${last_type}" == "turn.completed" || "${last_type}" == "turn.failed" ]] && return 0
  # Pi: assistant message with stopReason == "stop"
  if [[ "${last_type}" == "message" ]]; then
    local role stop_reason
    role=$(tail -1 "${jsonl}" 2>/dev/null | jq -r '.message.role // empty' 2>/dev/null || echo "")
    stop_reason=$(tail -1 "${jsonl}" 2>/dev/null | jq -r '.message.stopReason // empty' 2>/dev/null || echo "")
    [[ "${role}" == "assistant" && "${stop_reason}" == "stop" ]] && return 0
  fi
  return 1
}

# ---------------------------------------------------------------------------
# Helper: count active (non-completed) workers by checking session.jsonl
# ---------------------------------------------------------------------------
count_active_workers() {
  local active=0
  local worker_ids
  worker_ids=$(jq -r '.workers[].id' "${FLEET_JSON}" 2>/dev/null)

  for wid in $worker_ids; do
    local worker_dir="${FLEET_ROOT}/workers/${wid}"
    local jsonl="${worker_dir}/session.jsonl"
    local status_file="${worker_dir}/status.json"

    # If no session.jsonl yet, worker hasn't started
    [[ -f "${jsonl}" ]] || continue

    # Check if worker has a terminal event (completed)
    if ! has_terminal_event "${jsonl}"; then
      # Also check status.json for DONE/FAILED/KILLED
      if [[ -f "${status_file}" ]]; then
        local status
        status=$(jq -r '.status // ""' "${status_file}" 2>/dev/null || echo "")
        if [[ "${status}" == "DONE" || "${status}" == "FAILED" || "${status}" == "KILLED" ]]; then
          continue
        fi
      fi
      active=$((active + 1))
    fi
  done

  echo "${active}"
}

# ---------------------------------------------------------------------------
# Helper: sum cost from all completed workers' session.jsonl
# Claude: total_cost_usd from result event
# Codex:  estimate from turn.completed usage tokens (no cost field)
# ---------------------------------------------------------------------------
get_fleet_spend() {
  local total=0
  local worker_ids
  worker_ids=$(jq -r '.workers[].id' "${FLEET_JSON}" 2>/dev/null)

  for wid in $worker_ids; do
    local jsonl="${FLEET_ROOT}/workers/${wid}/session.jsonl"
    [[ -f "${jsonl}" ]] || continue
    local cost="0"
    # Try Claude format first (has total_cost_usd)
    if grep -q '"type":"result"' "${jsonl}" 2>/dev/null; then
      cost=$(grep -m1 '"type":"result"' "${jsonl}" 2>/dev/null \
             | jq -r '.total_cost_usd // 0' 2>/dev/null || echo "0")
    elif grep -q '"type":"turn.completed"' "${jsonl}" 2>/dev/null; then
      # Codex: estimate cost from token usage (rough: $0.50/1M input, $2/1M output for gpt-5.4-mini)
      cost=$(grep '"type":"turn.completed"' "${jsonl}" 2>/dev/null | tail -1 | python3 -c "
import sys, json
line = sys.stdin.readline().strip()
if not line: print('0'); sys.exit()
ev = json.loads(line)
u = ev.get('usage', {})
inp = u.get('input_tokens', 0)
outp = u.get('output_tokens', 0)
# Conservative estimate for codex models
c = (inp * 2.0 + outp * 8.0) / 1_000_000.0
print(f'{c:.6f}')
" 2>/dev/null || echo "0")
    elif tail -1 "${jsonl}" 2>/dev/null | jq -e '.type == \"message\" and .message.role == \"assistant\" and .message.stopReason == \"stop\"' >/dev/null 2>&1; then
      # Pi: cost may be 0 for some providers (kimi). Extract tokens and estimate.
      cost=$(tail -1 "${jsonl}" 2>/dev/null | python3 -c "
import sys, json
line = sys.stdin.readline().strip()
if not line: print('0'); sys.exit()
ev = json.loads(line)
u = ev.get('message', {}).get('usage', {})
# Try explicit cost first (anthropic provider)
cost_val = u.get('cost', {}).get('total', 0)
if cost_val and float(cost_val) > 0:
    print(f'{float(cost_val):.6f}')
    sys.exit()
# Fallback: estimate from tokens (kimi provider)
inp = u.get('input', 0)
outp = u.get('output', 0)
cache = u.get('cacheRead', 0)
# Kimi pricing: $3/M input, $15/M output, $0.30/M cache read
c = (inp * 3.0 + outp * 15.0 + cache * 0.30) / 1_000_000.0
print(f'{c:.6f}')
" 2>/dev/null || echo "0")
    fi
    total=$(awk "BEGIN {printf \"%.6f\", ${total} + ${cost}}")
  done

  echo "${total}"
}

# ---------------------------------------------------------------------------
# Helper: check fleet budget; returns 1 if cap exceeded
# ---------------------------------------------------------------------------
check_fleet_budget() {
  [[ "${MAX_BUDGET_FLEET}" == "0" || -z "${MAX_BUDGET_FLEET}" ]] && return 0
  local spend
  spend=$(get_fleet_spend)
  if awk "BEGIN {exit !(${spend} >= ${MAX_BUDGET_FLEET})}"; then
    warn "Fleet budget cap exceeded: \$${spend} >= \$${MAX_BUDGET_FLEET}. Stopping further launches."
    return 1
  fi
  return 0
}

# ---------------------------------------------------------------------------
# Helper: wait until all depends_on workers have a result event
# ---------------------------------------------------------------------------
wait_for_dependencies() {
  local worker_idx="$1"
  local deps
  deps=$(jq -r ".workers[${worker_idx}].depends_on // [] | .[]" "${FLEET_JSON}" 2>/dev/null)

  [[ -z "${deps}" ]] && return 0

  while true; do
    local pending=()
    for dep_id in $deps; do
      local dep_jsonl="${FLEET_ROOT}/workers/${dep_id}/session.jsonl"
      if [[ -f "${dep_jsonl}" ]] && has_terminal_event "${dep_jsonl}"; then
        : # dependency done
      else
        pending+=("${dep_id}")
      fi
    done

    if [[ "${#pending[@]}" -eq 0 ]]; then
      # All deps complete — check subtypes for non-success (Claude only)
      for dep_id in $deps; do
        local dep_jsonl="${FLEET_ROOT}/workers/${dep_id}/session.jsonl"
        local last_type
        last_type=$(tail -1 "${dep_jsonl}" 2>/dev/null | jq -r '.type' 2>/dev/null || echo "")
        if [[ "${last_type}" == "result" ]]; then
          local subtype
          subtype=$(tail -1 "${dep_jsonl}" 2>/dev/null | jq -r '.subtype // "success"' 2>/dev/null || echo "success")
          if [[ "${subtype}" != "success" ]]; then
            warn "Dependency '${dep_id}' completed with subtype '${subtype}' — launching dependent worker anyway"
          fi
        elif [[ "${last_type}" == "turn.failed" ]]; then
          warn "Dependency '${dep_id}' failed (codex turn.failed) — launching dependent worker anyway"
        fi
      done
      return 0
    fi

    info "Waiting for dependencies: $(IFS=', '; echo "${pending[*]}")"

    # Also check budget while waiting
    check_fleet_budget || return 2

    sleep 10
  done
}

# ---------------------------------------------------------------------------
# Build id->index map (bash 3.2-compatible parallel arrays)
# ---------------------------------------------------------------------------
WORKER_IDX_IDS=()
WORKER_IDX_INDICES=()

_worker_idx() {
  local _id="$1"
  local _n="${#WORKER_IDX_IDS[@]}"
  local _i
  for ((_i = 0; _i < _n; _i++)); do
    if [[ "${WORKER_IDX_IDS[_i]}" == "${_id}" ]]; then
      echo "${WORKER_IDX_INDICES[_i]}"
      return 0
    fi
  done
  echo ""
  return 1
}

for _j in $(seq 0 $((WORKER_COUNT - 1))); do
  _wid=$(jq -r ".workers[${_j}].id" "${FLEET_JSON}")
  WORKER_IDX_IDS+=("${_wid}")
  WORKER_IDX_INDICES+=("${_j}")
done

# ---------------------------------------------------------------------------
# Pre-generate ALL worker scripts upfront.
#
# Critical for fleets with dependent workers: if launch.sh gets killed
# (timeout, SSH disconnect, etc.), every worker already has its .run.sh
# so recovery only needs tmux new-window + send-keys — no script
# regeneration required.
# ---------------------------------------------------------------------------
_pre_generate_all_scripts() {
  info "Pre-generating .run.sh scripts for all ${WORKER_COUNT} workers ..."
  while IFS= read -r TOPO_WID; do
    [[ -z "${TOPO_WID}" ]] && continue
    local i
    i="$(_worker_idx "${TOPO_WID}")"
    local _wid _type _model _provider _effort _turns _budget _task
    _wid=$(jq -r ".workers[${i}].id" "${FLEET_JSON}")
    _type=$(jq -r ".workers[${i}].type // \"read-only\"" "${FLEET_JSON}")
    _model=$(jq -r ".workers[${i}].model // \"${DEFAULT_MODEL}\"" "${FLEET_JSON}")
    _provider=$(jq -r ".workers[${i}].provider // \"${DEFAULT_PROVIDER}\"" "${FLEET_JSON}")
    _effort=$(jq -r ".workers[${i}].reasoning_effort // \"${DEFAULT_REASONING_EFFORT}\"" "${FLEET_JSON}")
    _turns=$(jq -r ".workers[${i}].max_turns // 0" "${FLEET_JSON}")
    _budget=$(jq -r ".workers[${i}].max_budget_usd // 1.00" "${FLEET_JSON}")
    _task=$(jq -r ".workers[${i}].task // \"\"" "${FLEET_JSON}")

    local _wdir="${FLEET_ROOT}/workers/${_wid}"
    local _prompt="${_wdir}/prompt.md"
    local _jsonl="${_wdir}/session.jsonl"
    local _status="${_wdir}/status.json"

    mkdir -p "${_wdir}/output"

    # Skip if no prompt.md — nothing to run
    [[ -f "${_prompt}" ]] || continue

    # Write PENDING status.json
    local _ts
    _ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local _tmp
    _tmp=$(mktemp "${_wdir}/.tmp.status.XXXXXX")
    cat > "${_tmp}" <<EOF
{
  "worker_id": "${_wid}",
  "status": "PENDING",
  "task": "${_task}",
  "step": "waiting to launch",
  "last_updated": "${_ts}",
  "session_id": null,
  "cost_usd": 0,
  "turns_used": 0,
  "restarts": 0
}
EOF
    mv "${_tmp}" "${_status}"

    # Build tool restrictions
    local _pi_tools="" _dis="" _codex_sb="" _codex_ex=""
    if [[ "${_provider}" == "pi" ]]; then
      _pi_tools=$(get_pi_tools "${_type}")
    else
      _dis=$(get_disallowed_tools "${_type}")
    fi
    _codex_sb=$(get_codex_sandbox "${_type}")
    _codex_ex=$(get_codex_extra_flags "${_type}")

    local _sname="fleet-${FLEET_NAME}-${_wid}"

    # build_inner_cmd reads PI_TOOLS from current shell context
    local PI_TOOLS="${_pi_tools}"
    local _inner
    _inner=$(build_inner_cmd \
      --cwd "${FLEET_ROOT}" \
      --fleet-root "${FLEET_ROOT}" \
      --worker-id "${_wid}" \
      --worker-prompt "${_prompt}" \
      --worker-model "${_model}" \
      --fallback-model "${FALLBACK_MODEL}" \
      --max-turns "${_turns}" \
      --max-budget "${_budget}" \
      --session-name "${_sname}" \
      --disallowed-tools "${_dis}" \
      --session-jsonl "${_jsonl}" \
      --worker-dir "${_wdir}" \
      --provider "${_provider}" \
      --reasoning-effort "${_effort}" \
      --codex-sandbox "${_codex_sb}" \
      --codex-extra-flags "${_codex_ex}" \
    )
    if [[ "${KEEP_PANES_OPEN}" == "true" ]]; then
      _inner+="; read"
    else
      _inner+="; touch '${_wdir}/.done'; sleep \${KEEP_PANE_OPEN_SECONDS:-30}"
    fi

    local _runner="${_wdir}/.run.sh"
    echo "#!/bin/bash" > "${_runner}"
    printf '%s\n' "${_inner}" >> "${_runner}"
    chmod +x "${_runner}"
  done <<< "${TOPO_ORDER}"
  success "All worker scripts pre-generated."
}

# ---------------------------------------------------------------------------
# Core launch loop (spawn workers in topo order)
# ---------------------------------------------------------------------------
_launch_workers() {
  local _seq=0
  while IFS= read -r TOPO_WID; do
    [[ -z "${TOPO_WID}" ]] && continue
    local i
    i="$(_worker_idx "${TOPO_WID}")"
    _seq=$((_seq + 1))

    local WORKER_ID WORKER_TYPE WORKER_MODEL WORKER_PROVIDER
    local WORKER_REASONING_EFFORT MAX_TURNS MAX_BUDGET WORKER_TASK
    WORKER_ID=$(jq -r ".workers[${i}].id" "${FLEET_JSON}")
    WORKER_TYPE=$(jq -r ".workers[${i}].type // \"read-only\"" "${FLEET_JSON}")
    WORKER_MODEL=$(jq -r ".workers[${i}].model // \"${DEFAULT_MODEL}\"" "${FLEET_JSON}")
    WORKER_PROVIDER=$(jq -r ".workers[${i}].provider // \"${DEFAULT_PROVIDER}\"" "${FLEET_JSON}")
    WORKER_REASONING_EFFORT=$(jq -r ".workers[${i}].reasoning_effort // \"${DEFAULT_REASONING_EFFORT}\"" "${FLEET_JSON}")
    MAX_TURNS=$(jq -r ".workers[${i}].max_turns // 0" "${FLEET_JSON}")
    MAX_BUDGET=$(jq -r ".workers[${i}].max_budget_usd // 1.00" "${FLEET_JSON}")
    WORKER_TASK=$(jq -r ".workers[${i}].task // \"\"" "${FLEET_JSON}")

    local WORKER_DIR="${FLEET_ROOT}/workers/${WORKER_ID}"
    local WORKER_PROMPT="${WORKER_DIR}/prompt.md"
    local WORKER_SESSION_JSONL="${WORKER_DIR}/session.jsonl"
    local WORKER_STATUS_JSON="${WORKER_DIR}/status.json"
    local RUNNER_SCRIPT="${WORKER_DIR}/.run.sh"

    # Skip if no prompt.md (already warned during pre-gen)
    [[ -f "${WORKER_PROMPT}" ]] || continue

    # Check fleet budget before waiting / launching
    check_fleet_budget || break

    # Wait for depends_on workers to complete
    wait_for_dependencies "${i}"
    local dep_wait_rc=$?
    if [[ "${dep_wait_rc}" -eq 2 ]]; then
      break
    fi

    # Enforce max_concurrent: wait for a slot
    while true; do
      local ACTIVE
      ACTIVE=$(count_active_workers)
      if [[ "${ACTIVE}" -lt "${MAX_CONCURRENT}" ]]; then
        break
      fi
      warn "Concurrency limit reached (${ACTIVE}/${MAX_CONCURRENT}). Waiting 10s for a slot..."
      sleep 10
    done

    # Check budget again after waiting for concurrency slot
    check_fleet_budget || break

    # Re-derive spawn command (recording wrapper may differ)
    local WORKER_RECORDING="${WORKER_DIR}/${WORKER_ID}.cast"
    local TMUX_SPAWN_CMD
    if [[ "${RECORD}" == "true" ]] && command -v asciinema &>/dev/null; then
      TMUX_SPAWN_CMD="asciinema rec '${WORKER_RECORDING}' --overwrite -c '${RUNNER_SCRIPT}'"
    else
      TMUX_SPAWN_CMD="bash '${RUNNER_SCRIPT}'"
    fi

    info "Launching ${BOLD}${WORKER_ID}${NC} (provider=${WORKER_PROVIDER}, type=${WORKER_TYPE}, model=${WORKER_MODEL})"

    # P0.1: per-worker spawn lock + tmux window dedupe + terminal-result check.
    local WORKER_SPAWN_LOCK="${WORKER_DIR}/.launch.lock"
    (
      exec 9>"${WORKER_SPAWN_LOCK}"
      local WORKER_SPAWN_PID="${WORKER_DIR}/.spawn.pid"
      if ! try_flock 9 "${WORKER_SPAWN_PID}" n; then
        echo "SKIP_LOCK"
        exit 0
      fi
      if ! tmux has-session -t "${TMUX_SESSION}" 2>/dev/null; then
        echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] DEAD session ${TMUX_SESSION} gone before spawn of ${WORKER_ID}" >> "${TMUX_LOG}"
        echo "FAIL_SESSION_DEAD"
        exit 1
      fi
      if tmux list-windows -t "${TMUX_SESSION}" -F '#W' 2>/dev/null | grep -Fxq "${WORKER_ID}"; then
        echo "SKIP_WINDOW"
        exit 0
      fi
      if [[ -s "${WORKER_SESSION_JSONL}" ]] && (
        grep -q '"type":"result"' "${WORKER_SESSION_JSONL}" 2>/dev/null ||
        grep -q '"type":"turn.completed"' "${WORKER_SESSION_JSONL}" 2>/dev/null ||
        grep -q '"stopReason":"stop"' "${WORKER_SESSION_JSONL}" 2>/dev/null
      ); then
        echo "SKIP_RESULT"
        exit 0
      fi
      if [[ -s "${WORKER_SESSION_JSONL}" ]]; then
        mv "${WORKER_SESSION_JSONL}" "${WORKER_SESSION_JSONL}.$(date +%s).bak"
      fi
      echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] PRE  new-window ${WORKER_ID} cmd=[${TMUX_SPAWN_CMD}]" >> "${TMUX_LOG}"
      local _nw_stderr
      _nw_stderr=$(tmux new-window -t "${TMUX_SESSION}" -n "${WORKER_ID}" \
        "${TMUX_SPAWN_CMD}" 2>&1) || {
        echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] FAIL new-window ${WORKER_ID}: rc=$? stderr=${_nw_stderr}" >> "${TMUX_LOG}"
        echo "FAIL_NEW_WINDOW"
        exit 1
      }
      echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] OK   new-window ${WORKER_ID}" >> "${TMUX_LOG}"
      sleep 0.3
      local _post_windows
      _post_windows=$(tmux list-windows -t "${TMUX_SESSION}" -F '#W' 2>/dev/null || echo "SESSION_GONE")
      echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] POST new-window ${WORKER_ID} windows=[${_post_windows}]" >> "${TMUX_LOG}"
      if ! tmux has-session -t "${TMUX_SESSION}" 2>/dev/null; then
        echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] DEAD session ${TMUX_SESSION} gone AFTER new-window ${WORKER_ID}" >> "${TMUX_LOG}"
        echo "FAIL_SESSION_DIED"
        exit 1
      fi
      echo "SPAWNED"
    ) > "${WORKER_DIR}/.spawn.out" 2>&1 || true
    local _spawn_result
    _spawn_result=$(tail -1 "${WORKER_DIR}/.spawn.out" 2>/dev/null || echo "")
    mv "${WORKER_DIR}/.spawn.out" "${WORKER_DIR}/.spawn.out.last" 2>/dev/null || true
    case "${_spawn_result}" in
      SKIP_LOCK)
        info "worker ${WORKER_ID} spawn lock held by another process — skipping"
        continue ;;
      SKIP_WINDOW)
        info "worker ${WORKER_ID} already has a tmux window — skipping"
        continue ;;
      SKIP_RESULT)
        info "worker ${WORKER_ID} already has a terminal result — skipping"
        continue ;;
      SPAWNED) ;;
      FAIL_SESSION_DEAD|FAIL_NEW_WINDOW|FAIL_SESSION_DIED)
        error "worker ${WORKER_ID} spawn failed: ${_spawn_result} — see ${TMUX_LOG}"
        continue ;;
      *)
        warn "worker ${WORKER_ID} spawn produced unexpected output: ${_spawn_result}" ;;
    esac

    # Update status to RUNNING
    local local_ts
    local_ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local tmp_status
    tmp_status=$(mktemp "${WORKER_DIR}/.tmp.status.XXXXXX")
    cat > "${tmp_status}" <<EOF
{
  "worker_id": "${WORKER_ID}",
  "status": "RUNNING",
  "task": "${WORKER_TASK}",
  "step": "launched",
  "last_updated": "${local_ts}",
  "session_id": null,
  "cost_usd": 0,
  "turns_used": 0,
  "restarts": 0
}
EOF
    mv "${tmp_status}" "${WORKER_STATUS_JSON}"

    success "  Window created: ${TMUX_SESSION}:${WORKER_ID}"

    # Update fleet.json worker status
    local tmp_fleet
    tmp_fleet=$(mktemp "${FLEET_ROOT}/.tmp.fleet.XXXXXX")
    jq --arg id "${WORKER_ID}" \
       --arg ts "${local_ts}" \
       --arg sname "fleet-${FLEET_NAME}-${WORKER_ID}" \
       '(.workers[] | select(.id == $id)) |= . + {
         "status": "running",
         "session_name": $sname,
         "started_at": $ts
       }' "${FLEET_JSON}" > "${tmp_fleet}"
    mv "${tmp_fleet}" "${FLEET_JSON}"

    # Check fleet budget after launching this worker
    check_fleet_budget || break

    # Staggered delay (skip after last worker)
    if [[ "${_seq}" -lt "${WORKER_COUNT}" ]]; then
      info "Waiting ${LAUNCH_DELAY}s before next worker..."
      sleep "${LAUNCH_DELAY}"
    fi
  done <<< "${TOPO_ORDER}"

  # Update fleet.json overall status
  local local_ts
  local_ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  local tmp_fleet
  tmp_fleet=$(mktemp "${FLEET_ROOT}/.tmp.fleet.XXXXXX")
  jq --arg ts "${local_ts}" \
     '.status = "running" | .launched_at = $ts' \
     "${FLEET_JSON}" > "${tmp_fleet}"
  mv "${tmp_fleet}" "${FLEET_JSON}"

  echo ""
  success "Fleet '${BOLD}${FLEET_NAME}${NC}${GREEN}' launched successfully!"
  echo ""
  info "Attach to session:  ${BOLD}tmux attach -t ${TMUX_SESSION}${NC}"
  info "Monitor window:     ${BOLD}tmux attach -t ${TMUX_SESSION}:monitor${NC}"
  info "Kill fleet:         ${BOLD}kill.sh ${FLEET_ROOT} all${NC}"
  echo ""
}

# ---------------------------------------------------------------------------
# Main: pre-generate scripts, then launch (fork supervisor if deps exist)
# ---------------------------------------------------------------------------
_pre_generate_all_scripts

# Detect if any worker has dependencies
HAS_DEPS=$(jq '[.workers[] | select(.depends_on | length > 0)] | length' "${FLEET_JSON}")

if [[ "${HAS_DEPS}" -gt 0 ]]; then
  # Fork a background supervisor so the parent can exit immediately.
  # This prevents timeouts (SSH, cron, CI) from killing the orchestrator
  # while it waits for long-running dependencies.
  (
    # Fully detach from parent terminal to survive parent exit.
    # SIGHUP is ignored; stdout/stderr are redirected to a log file
    # so SIGPIPE cannot kill us when the parent's pipe/pty closes.
    trap '' HUP
    exec >"${FLEET_ROOT}/logs/supervisor.log" 2>&1
    # Re-acquire flock in child so parent release doesn't matter
    exec 8>"${LAUNCH_LOCK}"
    try_flock 8 "${LAUNCH_PID_FILE}" x
    echo "${BASHPID}" > "${LAUNCH_PID_FILE}"
    trap 'rm -f "${LAUNCH_PID_FILE}"' EXIT
    _launch_workers
  ) &
  SUPERVISOR_PID=$!
  # -h = mark job to NOT receive SIGHUP when this shell exits
  disown -h ${SUPERVISOR_PID} 2>/dev/null || true

  success "Fleet supervisor forked to background (pid ${SUPERVISOR_PID})"
  info "First-wave workers launching now. Dependent workers auto-launch when deps complete."
  info "Attach:  tmux attach -t ${TMUX_SESSION}"
  info "Status:  bash ${SCRIPT_DIR}/status.sh ${FLEET_ROOT} --watch"
  info "Kill:    bash ${SCRIPT_DIR}/kill.sh ${FLEET_ROOT} all"
  echo ""
  exit 0
else
  _launch_workers
fi
