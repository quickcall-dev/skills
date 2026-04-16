#!/usr/bin/env bash
# kill.sh — Kill an iterative fleet (operator's hard stop)
#
# Kills the tmux session (workers + orchestrator), sweeps orphan subprocesses,
# and unregisters from the fleet registry.
#
# Usage: kill.sh <fleet-root> <worker-id|all> [--force]
#        kill.sh --help

set -euo pipefail

# shellcheck source=../lib/registry.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/registry.sh"

# ---------------------------------------------------------------------------
# Colors
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
info()    { echo -e "${CYAN}[kill]${NC} $*"; }
success() { echo -e "${GREEN}[kill]${NC} $*"; }
warn()    { echo -e "${YELLOW}[kill]${NC} $*"; }
error()   { echo -e "${RED}[kill]${NC} $*" >&2; }
die()     { error "$*"; exit 1; }

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------
usage() {
  cat <<EOF
${BOLD}USAGE${NC}
  kill.sh <fleet-root> <worker-id|all> [--force]
  kill.sh --help

${BOLD}DESCRIPTION${NC}
  Kill an individual iterative fleet worker or the entire fleet.

  For "all":
    - Kills the entire tmux session (workers + orchestrator)
    - Sweeps orphan subprocesses under the fleet root
    - Marks fleet as killed in fleet.json
    - Unregisters from the shared registry

  For individual worker-id:
    - Kills the worker's tmux window
    - Marks worker status as KILLED

${BOLD}FLAGS${NC}
  --force   Skip completion check and kill regardless of status
EOF
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
FORCE=false
POSITIONAL=()
for arg in "$@"; do
  case "${arg}" in
    --help|-h) usage; exit 0 ;;
    --force|-f) FORCE=true ;;
    *) POSITIONAL+=("${arg}") ;;
  esac
done
set -- "${POSITIONAL[@]:-}"

if [[ $# -lt 2 ]]; then
  error "Missing required arguments."
  echo ""
  usage
  exit 1
fi

FLEET_ROOT="$(registry_resolve "${1}")" || die "fleet not found: ${1}"
TARGET="${2}"

# ---------------------------------------------------------------------------
# Validate
# ---------------------------------------------------------------------------
[[ ! -d "${FLEET_ROOT}" ]] && die "Fleet root does not exist: ${FLEET_ROOT}"

FLEET_JSON="${FLEET_ROOT}/fleet.json"
[[ ! -f "${FLEET_JSON}" ]] && die "fleet.json not found: ${FLEET_JSON}"

command -v jq &>/dev/null || die "jq is required but not installed"

FLEET_NAME=$(jq -r '.fleet_name // "fleet"' "${FLEET_JSON}")
TMUX_SESSION="${FLEET_NAME}"

# ---------------------------------------------------------------------------
# Kill entire fleet
# ---------------------------------------------------------------------------
if [[ "${TARGET}" == "all" ]]; then
  info "Killing entire iterative fleet: ${TMUX_SESSION}"

  # Remove pause flag so the orchestrator doesn't get confused
  rm -f "${FLEET_ROOT}/.paused" 2>/dev/null || true

  if tmux has-session -t "${TMUX_SESSION}" 2>/dev/null; then
    tmux kill-session -t "${TMUX_SESSION}"
    success "tmux session '${TMUX_SESSION}' killed"
  else
    info "tmux session '${TMUX_SESSION}' not found — already dead"
  fi

  # Sweep orphan subprocesses
  info "Sweeping orphan subprocesses under ${FLEET_ROOT}"
  orphans=$(pgrep -f "${FLEET_ROOT}" 2>/dev/null | grep -v "^$$\$" || true)
  if [[ -n "${orphans}" ]]; then
    echo "${orphans}" | xargs -r kill -9 2>/dev/null || true
    sleep 0.5
  fi

  # Verify zero survivors
  remaining=$(pgrep -f "${FLEET_ROOT}" 2>/dev/null | grep -v "^$$\$" || true)
  if [[ -n "${remaining}" ]]; then
    warn "WARNING: $(echo "${remaining}" | wc -l) process(es) still alive after sweep:"
    ps -o pid=,cmd= -p ${remaining} 2>/dev/null | sed 's/^/  /' >&2 || true
  else
    success "No orphan subprocesses remain"
  fi

  # Mark all non-terminal workers as KILLED
  local_ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  WORKERS_DIR="${FLEET_ROOT}/workers"
  if [[ -d "${WORKERS_DIR}" ]]; then
    for worker_dir in "${WORKERS_DIR}"/*/; do
      [[ -d "${worker_dir}" ]] || continue
      status_file="${worker_dir}status.json"
      [[ -f "${status_file}" ]] || continue
      current_status=$(jq -r '.status // ""' "${status_file}" 2>/dev/null || echo "")
      if [[ "${current_status}" == "DONE" || "${current_status}" == "FAILED" || "${current_status}" == "KILLED" ]]; then
        continue
      fi
      worker_id=$(jq -r '.worker_id // ""' "${status_file}" 2>/dev/null || echo "unknown")
      tmp_status=$(mktemp "${worker_dir}.tmp.status.XXXXXX")
      jq --arg ts "${local_ts}" \
         '.status = "KILLED" | .step = "killed by fleet kill-all" | .last_updated = $ts' \
         "${status_file}" > "${tmp_status}"
      mv "${tmp_status}" "${status_file}"
      info "  Marked ${worker_id} as KILLED"
    done
  fi

  # Update fleet.json
  local_ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  tmp_fleet=$(mktemp "${FLEET_ROOT}/.tmp.fleet.XXXXXX")
  jq --arg ts "${local_ts}" \
     '.status = "killed" | .killed_at = $ts' \
     "${FLEET_JSON}" > "${tmp_fleet}"
  mv "${tmp_fleet}" "${FLEET_JSON}"

  # Unregister from shared registry
  registry_unregister "${FLEET_NAME}" 2>/dev/null || true

  success "Fleet '${FLEET_NAME}' killed."
  exit 0
fi

# ---------------------------------------------------------------------------
# Kill individual worker
# ---------------------------------------------------------------------------
WORKER_ID="${TARGET}"
WORKER_DIR="${FLEET_ROOT}/workers/${WORKER_ID}"
WORKER_STATUS_JSON="${WORKER_DIR}/status.json"
WORKER_SESSION_JSONL="${WORKER_DIR}/session.jsonl"

[[ ! -d "${WORKER_DIR}" ]] && die "Worker directory not found: ${WORKER_DIR}"

# Check if already completed (unless --force)
if [[ "${FORCE}" == false ]]; then
  if [[ -f "${WORKER_STATUS_JSON}" ]]; then
    current_status=$(jq -r '.status // ""' "${WORKER_STATUS_JSON}" 2>/dev/null || echo "")
    if [[ "${current_status}" == "DONE" || "${current_status}" == "FAILED" || "${current_status}" == "KILLED" ]]; then
      warn "Worker ${WORKER_ID} is already in ${current_status} status. Use --force to kill anyway."
      exit 0
    fi
  fi
  if [[ -f "${WORKER_SESSION_JSONL}" ]]; then
    last_type=$(tail -1 "${WORKER_SESSION_JSONL}" 2>/dev/null | jq -r '.type' 2>/dev/null || echo "")
    if [[ "${last_type}" == "result" ]]; then
      warn "Worker ${WORKER_ID} has already completed. Use --force to kill anyway."
      exit 0
    fi
  fi
fi

if tmux has-session -t "${TMUX_SESSION}" 2>/dev/null; then
  if tmux list-windows -t "${TMUX_SESSION}" -F '#{window_name}' 2>/dev/null | grep -q "^${WORKER_ID}$"; then
    info "Killing worker window ${WORKER_ID} ..."
    tmux kill-window -t "${TMUX_SESSION}:${WORKER_ID}" 2>/dev/null || true
    sleep 0.5
    pkill -9 -f "${FLEET_ROOT}/workers/${WORKER_ID}" 2>/dev/null || true
    success "Worker ${WORKER_ID} killed"
  else
    warn "tmux window '${WORKER_ID}' not found in session '${TMUX_SESSION}'"
  fi
else
  warn "tmux session '${TMUX_SESSION}' not found — fleet may not be running"
fi

# Update status.json
local_ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
if [[ -f "${WORKER_STATUS_JSON}" ]]; then
  tmp_status=$(mktemp "${WORKER_DIR}/.tmp.status.XXXXXX")
  jq --arg ts "${local_ts}" \
     '.status = "KILLED" | .step = "killed by kill.sh" | .last_updated = $ts' \
     "${WORKER_STATUS_JSON}" > "${tmp_status}"
  mv "${tmp_status}" "${WORKER_STATUS_JSON}"
else
  cat > "${WORKER_DIR}/status.json" <<EOF
{
  "worker_id": "${WORKER_ID}",
  "status": "KILLED",
  "step": "killed by kill.sh",
  "last_updated": "${local_ts}",
  "cost_usd": 0
}
EOF
fi

# Update fleet.json
local_ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
tmp_fleet=$(mktemp "${FLEET_ROOT}/.tmp.fleet.XXXXXX")
jq --arg id "${WORKER_ID}" \
   --arg ts "${local_ts}" \
   '(.workers[] | select(.id == $id)) |= . + {"status": "killed", "killed_at": $ts}' \
   "${FLEET_JSON}" > "${tmp_fleet}"
mv "${tmp_fleet}" "${FLEET_JSON}"

success "Worker ${BOLD}${WORKER_ID}${NC}${GREEN} killed."
