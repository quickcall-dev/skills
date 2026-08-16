#!/usr/bin/env bash
# kill.sh — Kill a fleet worker or the entire fleet
#
# For an individual worker: sends SIGTERM to the claude process, updates
# status.json to KILLED. Warns if the worker already completed.
# For "all": kills the entire tmux session.
#
# Usage: kill.sh <fleet-root> <worker-id|all>
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
# Usage
# ---------------------------------------------------------------------------
usage() {
  cat <<EOF
${BOLD}USAGE${NC}
  kill.sh <fleet-root> <worker-id|all> [--force]
  kill.sh --help

${BOLD}DESCRIPTION${NC}
  Kill an individual fleet worker or the entire tmux fleet session.

  For individual workers:
    - Checks if the worker has already completed (warns unless --force)
    - Sends SIGTERM to the claude process running in the worker's tmux window
    - Updates workers/<id>/status.json to KILLED

  For "all":
    - Kills the entire tmux session (all windows)
    - Updates fleet.json status to "killed"

${BOLD}ARGUMENTS${NC}
  fleet-root    Path to the fleet root directory containing fleet.json
  worker-id     ID of the worker to kill (e.g. worker-01), or "all"

${BOLD}FLAGS${NC}
  --force       Skip the completion check and kill regardless of status

${BOLD}EXAMPLES${NC}
  kill.sh ~/.claude/fleets/research-fleet worker-03
  kill.sh ~/.claude/fleets/research-fleet all
  kill.sh ~/.claude/fleets/research-fleet worker-01 --force
EOF
}

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
info()    { echo -e "${CYAN}[kill]${NC} $*"; }
success() { echo -e "${GREEN}[kill]${NC} $*"; }
warn()    { echo -e "${YELLOW}[kill]${NC} $*"; }
error()   { echo -e "${RED}[kill]${NC} $*" >&2; }
die()     { error "$*"; exit 1; }

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
FORCE=false

# Parse flags first
POSITIONAL=()
for arg in "$@"; do
  case "${arg}" in
    --help|-h)
      usage
      exit 0
      ;;
    --force|-f)
      FORCE=true
      ;;
    *)
      POSITIONAL+=("${arg}")
      ;;
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
if [[ ! -d "${FLEET_ROOT}" ]]; then
  die "Fleet root does not exist: ${FLEET_ROOT}"
fi

FLEET_JSON="${FLEET_ROOT}/fleet.json"
if [[ ! -f "${FLEET_JSON}" ]]; then
  die "fleet.json not found: ${FLEET_JSON}"
fi

if ! command -v jq &>/dev/null; then
  die "jq is required but not installed"
fi

FLEET_NAME=$(jq -r '.fleet_name // "fleet"' "${FLEET_JSON}")
TMUX_SESSION="${FLEET_NAME}"

# ---------------------------------------------------------------------------
# Kill entire fleet
# ---------------------------------------------------------------------------
if [[ "${TARGET}" == "all" ]]; then
  info "Killing entire fleet session: ${TMUX_SESSION}"

  if tmux has-session -t "${TMUX_SESSION}" 2>/dev/null; then
    tmux kill-session -t "${TMUX_SESSION}"
    success "tmux session '${TMUX_SESSION}' killed"
  else
    info "tmux session '${TMUX_SESSION}' not found — already dead"
  fi

  # Sweep any descendant processes still writing under the fleet's workers dir.
  # Without this, bash subprocesses spawned by Claude's Bash tool get reparented
  # to PID 1 when tmux dies and keep running silently (problems.md #17).
  # The pattern matches by full command line; we exclude our own PID for safety.
  info "Sweeping orphan subprocesses under ${FLEET_ROOT}/workers"
  orphans=$(pgrep -f "${FLEET_ROOT}/workers" 2>/dev/null | grep -v "^$$\$" || true)
  if [[ -n "${orphans}" ]]; then
    echo "${orphans}" | xargs -r kill -9 2>/dev/null || true
    sleep 0.5
  fi
  # Verify zero survivors before claiming success
  remaining=$(pgrep -f "${FLEET_ROOT}/workers" 2>/dev/null | grep -v "^$$\$" || true)
  if [[ -n "${remaining}" ]]; then
    warn "WARNING: $(echo "${remaining}" | wc -l) process(es) still alive after sweep:"
    ps -o pid=,cmd= -p ${remaining} 2>/dev/null | sed 's/^/  /' >&2 || true
  else
    success "No orphan subprocesses remain"
  fi

  # Update each worker's status.json to KILLED (if not already terminal)
  local_ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  WORKERS_DIR="${FLEET_ROOT}/workers"
  if [[ -d "${WORKERS_DIR}" ]]; then
    for worker_dir in "${WORKERS_DIR}"/*/; do
      [[ -d "${worker_dir}" ]] || continue
      status_file="${worker_dir}status.json"
      [[ -f "${status_file}" ]] || continue

      current_status=$(jq -r '.status // ""' "${status_file}" 2>/dev/null || echo "")
      # Don't overwrite already terminal statuses
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

  # Update fleet.json status
  local_ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  tmp_fleet=$(mktemp "${FLEET_ROOT}/.tmp.fleet.XXXXXX")
  jq --arg ts "${local_ts}" \
     '.status = "killed" | .killed_at = $ts' \
     "${FLEET_JSON}" > "${tmp_fleet}"
  mv "${tmp_fleet}" "${FLEET_JSON}"

  # P4.3: remove from shared fleet-name registry so the name doesn't resolve
  # to a now-dead fleet on the next kill/view/feed invocation.
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

if [[ ! -d "${WORKER_DIR}" ]]; then
  die "Worker directory not found: ${WORKER_DIR}"
fi

# Check if already completed (unless --force)
if [[ "${FORCE}" == false ]]; then
  current_status=""
  if [[ -f "${WORKER_STATUS_JSON}" ]]; then
    current_status=$(jq -r '.status // ""' "${WORKER_STATUS_JSON}" 2>/dev/null || echo "")
  fi

  # Also check session.jsonl for result event
  if [[ -f "${WORKER_SESSION_JSONL}" ]]; then
    last_type=$(tail -1 "${WORKER_SESSION_JSONL}" 2>/dev/null | jq -r '.type' 2>/dev/null || echo "")
    if [[ "${last_type}" == "result" ]]; then
      last_subtype=$(tail -1 "${WORKER_SESSION_JSONL}" 2>/dev/null | jq -r '.subtype // ""' 2>/dev/null || echo "")
      warn "Worker ${WORKER_ID} has already completed (result: ${last_subtype})."
      warn "Use --force to kill it anyway."
      exit 0
    fi
  fi

  if [[ "${current_status}" == "DONE" || "${current_status}" == "FAILED" ]]; then
    warn "Worker ${WORKER_ID} is already in ${current_status} status."
    warn "Use --force to kill it anyway."
    exit 0
  fi

  if [[ "${current_status}" == "KILLED" ]]; then
    warn "Worker ${WORKER_ID} is already in KILLED status."
    exit 0
  fi
fi

# Find the tmux window for this worker
WORKER_WINDOW="${WORKER_ID}"

if tmux has-session -t "${TMUX_SESSION}" 2>/dev/null; then
  # Check if the window exists
  if tmux list-windows -t "${TMUX_SESSION}" -F '#{window_name}' 2>/dev/null | grep -q "^${WORKER_WINDOW}$"; then
    info "Sending SIGTERM to claude process in window ${WORKER_WINDOW}..."

    # Get the PID of the process running in the pane (deepest child = claude)
    PANE_PID=$(tmux list-panes -t "${TMUX_SESSION}:${WORKER_WINDOW}" -F '#{pane_pid}' 2>/dev/null | head -1 || echo "")

    # Kill tmux window first (sends SIGHUP), then hunt orphans by path
    tmux kill-window -t "${TMUX_SESSION}:${WORKER_WINDOW}" 2>/dev/null || true
    sleep 1
    # Kill any surviving processes that reference this worker's paths
    WORKER_DIR_PATH="${FLEET_ROOT}/workers/${WORKER_ID}"
    pkill -9 -f "${WORKER_DIR_PATH}" 2>/dev/null || true
    pkill -9 -f "WORKER_ID='${WORKER_ID}'" 2>/dev/null || true
    sleep 1

    success "Worker ${WORKER_ID} and all subprocesses killed"
  else
    warn "tmux window '${WORKER_WINDOW}' not found in session '${TMUX_SESSION}'"
    warn "Worker may have already exited (its window closed after '; read' was confirmed)"
  fi
else
  warn "tmux session '${TMUX_SESSION}' not found — fleet may not be running"
fi

# ---------------------------------------------------------------------------
# Update status.json to KILLED
# ---------------------------------------------------------------------------
local_ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
if [[ -f "${WORKER_STATUS_JSON}" ]]; then
  tmp_status=$(mktemp "${WORKER_DIR}/.tmp.status.XXXXXX")
  jq --arg ts "${local_ts}" \
     '.status = "KILLED" | .step = "killed by kill.sh" | .last_updated = $ts' \
     "${WORKER_STATUS_JSON}" > "${tmp_status}"
  mv "${tmp_status}" "${WORKER_STATUS_JSON}"
else
  # Create a minimal status.json
  tmp_status=$(mktemp "${WORKER_DIR}/.tmp.status.XXXXXX")
  cat > "${tmp_status}" <<EOF
{
  "worker_id": "${WORKER_ID}",
  "status": "KILLED",
  "step": "killed by kill.sh",
  "last_updated": "${local_ts}",
  "session_id": null,
  "cost_usd": 0,
  "turns_used": 0
}
EOF
  mv "${tmp_status}" "${WORKER_STATUS_JSON}"
fi

# ---------------------------------------------------------------------------
# Update fleet.json for this worker
# ---------------------------------------------------------------------------
local_ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
tmp_fleet=$(mktemp "${FLEET_ROOT}/.tmp.fleet.XXXXXX")
jq --arg id "${WORKER_ID}" \
   --arg ts "${local_ts}" \
   '(.workers[] | select(.id == $id)) |= . + {
     "status": "killed",
     "killed_at": $ts
   }' "${FLEET_JSON}" > "${tmp_fleet}"
mv "${tmp_fleet}" "${FLEET_JSON}"

success "Worker ${BOLD}${WORKER_ID}${NC}${GREEN} killed and status updated to KILLED."
