#!/usr/bin/env bash
# view.sh — Live worker pane capture
#
# Shows what a worker is doing RIGHT NOW by capturing its tmux pane.
# Falls back to parsed session.jsonl if the tmux window is gone.
#
# Usage: view.sh <fleet-root> <worker-id> [--lines 30] [--follow]
#        view.sh --help

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
GRAY='\033[0;37m'
BOLD='\033[1m'
NC='\033[0m'

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------
usage() {
  cat <<EOF
${BOLD}USAGE${NC}
  view.sh <fleet-root> <worker-id> [--lines 30] [--follow]
  view.sh --help

${BOLD}DESCRIPTION${NC}
  Captures the live tmux pane for the given worker. With --follow,
  refreshes every 2 seconds. If the tmux window is not found, falls back
  to showing the last N lines from session.jsonl parsed for readability.

${BOLD}ARGUMENTS${NC}
  fleet-root    Path to the fleet root directory containing fleet.json
  worker-id     ID of the worker to view (e.g. coder-01)

${BOLD}FLAGS${NC}
  --lines N     Number of lines to capture (default: 30)
  --follow      Refresh every 2 seconds (like watch)

${BOLD}EXAMPLES${NC}
  view.sh ~/.claude/fleets/my-fleet coder-01
  view.sh ~/.claude/fleets/my-fleet coder-01 --lines 50 --follow
EOF
}

# ---------------------------------------------------------------------------
# Logging helpers
# ---------------------------------------------------------------------------
info()  { echo -e "${CYAN}[view]${NC} $*" >&2; }
warn()  { echo -e "${YELLOW}[view]${NC} $*" >&2; }
error() { echo -e "${RED}[view]${NC} $*" >&2; }
die()   { error "$*"; exit 1; }

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
LINES=30
FOLLOW=false
POSITIONAL=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h)
      usage
      exit 0
      ;;
    --lines)
      [[ $# -lt 2 ]] && die "--lines requires a numeric argument"
      LINES="$2"
      shift 2
      ;;
    --lines=*)
      LINES="${1#--lines=}"
      shift
      ;;
    --follow|-f)
      FOLLOW=true
      shift
      ;;
    *)
      POSITIONAL+=("$1")
      shift
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
WORKER_ID="${2}"

# ---------------------------------------------------------------------------
# Validate
# ---------------------------------------------------------------------------
[[ -d "${FLEET_ROOT}" ]] || die "Fleet root does not exist: ${FLEET_ROOT}"

FLEET_JSON="${FLEET_ROOT}/fleet.json"
[[ -f "${FLEET_JSON}" ]] || die "fleet.json not found: ${FLEET_JSON}"

WORKER_DIR="${FLEET_ROOT}/workers/${WORKER_ID}"
[[ -d "${WORKER_DIR}" ]] || die "Worker directory not found: ${WORKER_DIR}"

command -v jq &>/dev/null || die "jq is required but not installed"

FLEET_NAME=$(jq -r '.fleet_name // "fleet"' "${FLEET_JSON}")

# ---------------------------------------------------------------------------
# Fallback: parse session.jsonl for readable output
# ---------------------------------------------------------------------------
show_jsonl_fallback() {
  local log="${WORKER_DIR}/session.jsonl"

  echo -e "${BOLD}${CYAN}── Worker: ${WORKER_ID} (session.jsonl fallback) ──${NC}"
  echo -e "${GRAY}tmux window not found — showing last ${LINES} events from session.jsonl${NC}"
  echo ""

  if [[ ! -f "${log}" || ! -s "${log}" ]]; then
    echo -e "${YELLOW}No session.jsonl found or it is empty.${NC}"
    return
  fi

  # Parse last N lines of jsonl for readability
  tail -"${LINES}" "${log}" 2>/dev/null | while IFS= read -r line; do
    TYPE=$(echo "${line}" | jq -r '.type // ""' 2>/dev/null || echo "")
    SUBTYPE=$(echo "${line}" | jq -r '.subtype // ""' 2>/dev/null || echo "")
    TS=$(echo "${line}" | jq -r '.timestamp // ""' 2>/dev/null | sed 's/T/ /;s/\..*//' || echo "")

    case "${TYPE}" in
      system)
        echo -e "${GRAY}[${TS}] system: ${SUBTYPE}${NC}"
        ;;
      assistant)
        # Extract tool uses and text
        TOOLS=$(echo "${line}" | jq -r '.message.content[]? | select(.type=="tool_use") | "  tool: \(.name)(\(.input | tostring | .[0:80]))"' 2>/dev/null || true)
        TEXT=$(echo "${line}" | jq -r '.message.content[]? | select(.type=="text") | .text' 2>/dev/null | head -3 || true)
        if [[ -n "${TOOLS}" ]]; then
          echo -e "${CYAN}[${TS}] assistant${NC}"
          echo "${TOOLS}" | while IFS= read -r t; do
            echo -e "  ${GREEN}${t}${NC}"
          done
        fi
        if [[ -n "${TEXT}" ]]; then
          echo -e "${CYAN}[${TS}] assistant text:${NC} $(echo "${TEXT}" | head -c 200)"
        fi
        ;;
      tool)
        TOOL_NAME=$(echo "${line}" | jq -r '.tool_name // ""' 2>/dev/null || echo "")
        CONTENT=$(echo "${line}" | jq -r '.content // ""' 2>/dev/null | head -c 150 || true)
        echo -e "${GRAY}[${TS}] tool result: ${TOOL_NAME}${NC}: ${CONTENT}"
        ;;
      result)
        COST=$(echo "${line}" | jq -r '.total_cost_usd // 0' 2>/dev/null || echo "0")
        COST=$(awk "BEGIN {printf \"%.2f\", ${COST}}")
        TURNS=$(echo "${line}" | jq -r '.num_turns // 0' 2>/dev/null || echo "0")
        if [[ "${SUBTYPE}" == "success" ]]; then
          echo -e "${GREEN}[${TS}] RESULT: ${SUBTYPE} — cost=\$${COST} turns=${TURNS}${NC}"
        else
          echo -e "${RED}[${TS}] RESULT: ${SUBTYPE} — cost=\$${COST} turns=${TURNS}${NC}"
        fi
        ;;
      *)
        [[ -n "${TYPE}" ]] && echo -e "${GRAY}[${TS}] ${TYPE}${NC}"
        ;;
    esac
  done
}

# ---------------------------------------------------------------------------
# Primary: capture tmux pane
# ---------------------------------------------------------------------------
show_tmux_pane() {
  local pane_target="${FLEET_NAME}:${WORKER_ID}"

  if ! tmux has-session -t "${FLEET_NAME}" 2>/dev/null; then
    warn "tmux session '${FLEET_NAME}' not found — using session.jsonl fallback"
    show_jsonl_fallback
    return
  fi

  if ! tmux list-windows -t "${FLEET_NAME}" -F '#{window_name}' 2>/dev/null | grep -q "^${WORKER_ID}$"; then
    warn "tmux window '${WORKER_ID}' not found in session '${FLEET_NAME}' — using session.jsonl fallback"
    show_jsonl_fallback
    return
  fi

  echo -e "${BOLD}${CYAN}── Worker: ${WORKER_ID} @ ${FLEET_NAME} ──${NC}"
  tmux capture-pane -t "${pane_target}" -p -S -"${LINES}"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
if [[ "${FOLLOW}" == "true" ]]; then
  trap 'echo ""; exit 0' INT TERM
  while true; do
    clear
    echo -e "${BOLD}Fleet: ${FLEET_NAME}  Worker: ${WORKER_ID}  $(date -u +"%H:%M:%S UTC")${NC}"
    echo ""
    show_tmux_pane
    sleep 2
  done
else
  show_tmux_pane
fi
