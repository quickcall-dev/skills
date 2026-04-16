#!/usr/bin/env bash
# view.sh — View a specific iteration's session events
#
# Parses session-iter-N.jsonl for readable output: tool calls, text, results.
# With --follow, refreshes every 2s (useful for watching a live iteration).
#
# Usage: view.sh <fleet-root> <iteration> [--lines 30] [--follow]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/../lib/registry.sh" ]]; then
  source "${SCRIPT_DIR}/../lib/registry.sh"
fi

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; GRAY='\033[0;37m'; BOLD='\033[1m'; NC='\033[0m'

info()  { echo -e "${CYAN}[view]${NC} $*" >&2; }
warn()  { echo -e "${YELLOW}[view]${NC} $*" >&2; }
die()   { echo -e "${RED}[view]${NC} $*" >&2; exit 1; }

usage() {
  cat <<EOF
${BOLD}USAGE${NC}
  view.sh <fleet-root> <iteration> [--lines 30] [--follow]
  view.sh <fleet-root> latest [--follow]

${BOLD}DESCRIPTION${NC}
  Shows parsed session events for a specific iteration.
  Use "latest" to view the most recent iteration.

${BOLD}EXAMPLES${NC}
  view.sh /tmp/my-fleet 3
  view.sh /tmp/my-fleet latest --follow
  view.sh /tmp/my-fleet 5 --lines 50
EOF
}

LINES=30
FOLLOW=false
POSITIONAL=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --lines)   LINES="$2"; shift 2 ;;
    --follow|-f) FOLLOW=true; shift ;;
    *) POSITIONAL+=("$1"); shift ;;
  esac
done
set -- "${POSITIONAL[@]:-}"

[[ $# -lt 2 ]] && { usage; exit 1; }

FLEET_ROOT="$(realpath "${1}")"
if type -t registry_resolve &>/dev/null; then
  FLEET_ROOT="$(registry_resolve "${1}")" || die "fleet not found: ${1}"
fi
ITER_ARG="${2}"

[[ -d "${FLEET_ROOT}" ]] || die "Fleet root does not exist: ${FLEET_ROOT}"
FLEET_JSON="${FLEET_ROOT}/fleet.json"
FLEET_NAME=$(jq -r '.fleet_name // "autoresearch"' "${FLEET_JSON}" 2>/dev/null || echo "autoresearch")

# Resolve "latest" to highest iteration number
resolve_iter() {
  if [[ "${ITER_ARG}" == "latest" ]]; then
    ls -1 "${FLEET_ROOT}"/logs/session-iter-*.jsonl 2>/dev/null | \
      sed 's/.*session-iter-\(.*\)\.jsonl/\1/' | sort -n | tail -1
  else
    echo "${ITER_ARG}"
  fi
}

show_session() {
  local iter
  iter=$(resolve_iter)
  [[ -z "${iter}" ]] && { echo -e "${YELLOW}No session logs found.${NC}"; return; }

  local log="${FLEET_ROOT}/logs/session-iter-${iter}.jsonl"
  [[ -f "${log}" ]] || { echo -e "${YELLOW}No session log for iteration ${iter}.${NC}"; return; }

  local total_lines
  total_lines=$(wc -l < "${log}")

  echo -e "${BOLD}${CYAN}── Iteration ${iter} ── ${NC}${GRAY}(${total_lines} events, showing last ${LINES})${NC}"
  echo ""

  tail -"${LINES}" "${log}" 2>/dev/null | while IFS= read -r line; do
    local TYPE SUBTYPE TS
    TYPE=$(echo "${line}" | jq -r '.type // ""' 2>/dev/null || echo "")
    SUBTYPE=$(echo "${line}" | jq -r '.subtype // ""' 2>/dev/null || echo "")
    TS=$(echo "${line}" | jq -r '.timestamp // ""' 2>/dev/null | sed 's/T/ /;s/\..*//' || echo "")

    case "${TYPE}" in
      system)
        echo -e "${GRAY}[${TS}] system: ${SUBTYPE}${NC}"
        ;;
      assistant)
        local TOOLS TEXT
        TOOLS=$(echo "${line}" | jq -r '.message.content[]? | select(.type=="tool_use") | "  tool: \(.name)(\(.input | tostring | .[0:80]))"' 2>/dev/null || true)
        TEXT=$(echo "${line}" | jq -r '.message.content[]? | select(.type=="text") | .text' 2>/dev/null | head -3 || true)
        if [[ -n "${TOOLS}" ]]; then
          echo -e "${CYAN}[${TS}] assistant${NC}"
          echo "${TOOLS}" | while IFS= read -r t; do
            echo -e "  ${GREEN}${t}${NC}"
          done
        fi
        if [[ -n "${TEXT}" ]]; then
          echo -e "${CYAN}[${TS}] assistant:${NC} $(echo "${TEXT}" | head -c 200)"
        fi
        ;;
      tool)
        local TOOL_NAME CONTENT
        TOOL_NAME=$(echo "${line}" | jq -r '.tool_name // ""' 2>/dev/null || echo "")
        CONTENT=$(echo "${line}" | jq -r '.content // ""' 2>/dev/null | head -c 150 || true)
        echo -e "${GRAY}[${TS}] tool: ${TOOL_NAME}${NC}: ${CONTENT}"
        ;;
      result)
        local COST TURNS
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

if [[ "${FOLLOW}" == "true" ]]; then
  trap 'echo ""; exit 0' INT TERM
  while true; do
    clear
    echo -e "${BOLD}Fleet: ${FLEET_NAME}  $(date -u +"%H:%M:%S UTC")${NC}"
    echo ""
    show_session
    sleep 2
  done
else
  show_session
fi
