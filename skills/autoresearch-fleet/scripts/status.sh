#!/usr/bin/env bash
# status.sh — Autoresearch Fleet status dashboard
#
# Shows: iteration, best metric, plateau state, results.tsv tail, cost.
#
# Usage: status.sh <fleet-root> [--watch] [--json]

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
GRAY='\033[0;37m'
BOLD='\033[1m'
NC='\033[0m'

[[ "${1:-}" == "--help" || "${1:-}" == "-h" ]] && {
  echo "Usage: status.sh <fleet-root> [--watch] [--json]"
  exit 0
}
[[ $# -lt 1 ]] && { echo "Error: missing fleet-root" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/../lib/registry.sh" ]]; then
  source "${SCRIPT_DIR}/../lib/registry.sh"
  FLEET_ROOT="$(registry_resolve "${1}")" || { echo "Error: fleet not found: ${1}" >&2; exit 1; }
else
  FLEET_ROOT="$(realpath "${1}")"
fi
shift

OPT_JSON=false
OPT_WATCH=false
for arg in "$@"; do
  case "$arg" in
    --json)  OPT_JSON=true ;;
    --watch) OPT_WATCH=true ;;
  esac
done

[[ ! -d "${FLEET_ROOT}" ]] && { echo "Error: ${FLEET_ROOT} does not exist" >&2; exit 1; }
FLEET_JSON="${FLEET_ROOT}/fleet.json"

show_status() {
  local now
  now=$(date +%s)

  local fleet_name iter trailing is_search best_metric total_cost status
  fleet_name=$(jq -r '.fleet_name // "autoresearch"' "${FLEET_JSON}" 2>/dev/null || echo "autoresearch")
  local results_file workdir results_path
  results_file=$(jq -r '.problem.results_file // "results.tsv"' "${FLEET_JSON}" 2>/dev/null || echo "results.tsv")
  workdir=$(jq -r '.problem.workdir // ""' "${FLEET_JSON}" 2>/dev/null || echo "")
  [[ -z "${workdir}" || "${workdir}" == "null" ]] && workdir="${FLEET_ROOT}"
  results_path="${workdir}/${results_file}"
  local metric_dir
  metric_dir=$(jq -r '.problem.metric_direction // "minimize"' "${FLEET_JSON}" 2>/dev/null || echo "minimize")
  local plateau_threshold
  plateau_threshold=$(jq -r '.search.plateau_threshold // 3' "${FLEET_JSON}" 2>/dev/null || echo 3)

  # Read orchestrator state
  iter=0; trailing=0; is_search=false; best_metric="n/a"; total_cost="0.00"; status="pending"
  if [[ -f "${FLEET_ROOT}/.orch-state.json" ]]; then
    iter=$(jq -r '.current_iteration // 0' "${FLEET_ROOT}/.orch-state.json" 2>/dev/null || echo 0)
    trailing=$(jq -r '.trailing_discards // 0' "${FLEET_ROOT}/.orch-state.json" 2>/dev/null || echo 0)
    is_search=$(jq -r '.is_search // false' "${FLEET_ROOT}/.orch-state.json" 2>/dev/null || echo false)
    best_metric=$(jq -r '.best_metric // "n/a"' "${FLEET_ROOT}/.orch-state.json" 2>/dev/null || echo "n/a")
    total_cost=$(jq -r '.total_cost // "0.00"' "${FLEET_ROOT}/.orch-state.json" 2>/dev/null || echo "0.00")
    status=$(jq -r '.status // "running"' "${FLEET_ROOT}/.orch-state.json" 2>/dev/null || echo "running")
  fi

  local is_paused=false
  [[ -f "${FLEET_ROOT}/.paused" ]] && is_paused=true

  # Count results
  local total_results=0 keeps=0 discards=0 crashes=0
  if [[ -f "${results_path}" ]]; then
    total_results=$(tail -n +2 "${results_path}" | wc -l | tr -d ' ')
    keeps=$(tail -n +2 "${results_path}" | awk -F'\t' 'tolower($3) == "keep"' | wc -l | tr -d ' ')
    discards=$(tail -n +2 "${results_path}" | awk -F'\t' 'tolower($3) == "discard"' | wc -l | tr -d ' ')
    crashes=$(tail -n +2 "${results_path}" | awk -F'\t' 'tolower($3) == "crash"' | wc -l | tr -d ' ')
  fi

  # Compute best from results.tsv directly (more current than orch state)
  if [[ -f "${results_path}" && ${total_results} -gt 0 ]]; then
    local fresh_best
    if [[ "${metric_dir}" == "minimize" ]]; then
      fresh_best=$(tail -n +2 "${results_path}" | awk -F'\t' 'tolower($3) == "keep" {print $2}' | sort -g | head -1)
    else
      fresh_best=$(tail -n +2 "${results_path}" | awk -F'\t' 'tolower($3) == "keep" {print $2}' | sort -rg | head -1)
    fi
    [[ -n "${fresh_best}" ]] && best_metric="${fresh_best}"
  fi

  # Elapsed time
  local elapsed_str="n/a"
  local launched_at
  launched_at=$(jq -r '.launched_at // ""' "${FLEET_JSON}" 2>/dev/null || echo "")
  if [[ -n "${launched_at}" ]]; then
    local launch_epoch
    launch_epoch=$(date -d "${launched_at}" +%s 2>/dev/null || echo "0")
    if [[ ${launch_epoch} -gt 0 ]]; then
      local elapsed=$((now - launch_epoch))
      if [[ $elapsed -lt 60 ]]; then
        elapsed_str="${elapsed}s"
      elif [[ $elapsed -lt 3600 ]]; then
        elapsed_str="$((elapsed / 60))m $((elapsed % 60))s"
      else
        elapsed_str="$((elapsed / 3600))h $((elapsed % 3600 / 60))m"
      fi
    fi
  fi

  if [[ "$OPT_JSON" == "true" ]]; then
    printf '{"fleet":"%s","iteration":%d,"best_metric":"%s","total_cost":"%s","results":%d,"keeps":%d,"discards":%d,"crashes":%d,"trailing_discards":%d,"is_search":%s,"status":"%s","paused":%s}\n' \
      "${fleet_name}" "${iter}" "${best_metric}" "${total_cost}" \
      "${total_results}" "${keeps}" "${discards}" "${crashes}" \
      "${trailing}" "${is_search}" "${status}" "${is_paused}"
    return
  fi

  # Header
  echo -e "${BOLD}Autoresearch Fleet — $(date -u +"%Y-%m-%d %H:%M:%S UTC")${NC}"
  echo -e "Fleet:    ${CYAN}${fleet_name}${NC}  root: ${FLEET_ROOT}"

  local status_color="${GREEN}"
  [[ "${status}" == "completed" ]] && status_color="${CYAN}"
  $is_paused && status_color="${YELLOW}" && status="paused"
  echo -e "Status:   ${status_color}${status}${NC}  Elapsed: ${BOLD}${elapsed_str}${NC}"
  echo ""

  # Metrics
  echo -e "${BOLD}Progress:${NC}"
  echo -e "  Iteration:         ${BOLD}${iter}${NC}"
  echo -e "  Best metric:       ${BOLD}${CYAN}${best_metric}${NC} (${metric_dir})"
  echo -e "  Total cost:        ${BOLD}\$${total_cost}${NC}"
  echo -e "  Results:           ${total_results} total — ${GREEN}${keeps} kept${NC}, ${YELLOW}${discards} discarded${NC}, ${RED}${crashes} crashed${NC}"

  # Plateau indicator
  local plateau_bar=""
  for ((p=0; p<plateau_threshold; p++)); do
    if [[ $p -lt $trailing ]]; then
      plateau_bar+="${RED}X${NC}"
    else
      plateau_bar+="${GRAY}.${NC}"
    fi
  done
  local search_label=""
  [[ "${is_search}" == "true" ]] && search_label=" ${YELLOW}[SEARCH MODE]${NC}"
  echo -e "  Plateau:           [${plateau_bar}] ${trailing}/${plateau_threshold}${search_label}"

  # Last activity from current iteration's session log
  local current_log="${FLEET_ROOT}/logs/session-iter-${iter}.jsonl"
  local last_msg="—"
  local last_activity="—"
  if [[ -f "${current_log}" && -s "${current_log}" ]]; then
    local mtime
    mtime=$(stat -c %Y "${current_log}" 2>/dev/null || stat -f %m "${current_log}" 2>/dev/null || echo "$now")
    local ago=$((now - mtime))
    if [[ $ago -lt 60 ]]; then last_activity="${ago}s ago"
    elif [[ $ago -lt 3600 ]]; then last_activity="$((ago / 60))m ago"
    else last_activity="$((ago / 3600))h $((ago % 3600 / 60))m ago"
    fi

    last_msg=$(tail -5 "${current_log}" 2>/dev/null | python3 -c '
import sys, json
last = None
for line in sys.stdin:
    line = line.strip()
    if not line: continue
    try: ev = json.loads(line)
    except Exception: continue
    t = ev.get("type")
    if t == "result":
        st = ev.get("subtype","")
        last = ("ok " if st == "success" else "err ") + (st or "result")
    elif t == "assistant":
        msg = ev.get("message") or {}
        for c in (msg.get("content") or []):
            if c.get("type") == "tool_use":
                last = "tool: " + c.get("name",""); break
            if c.get("type") == "text" and c.get("text","").strip():
                last = c["text"].strip().replace("\n"," ")[:70]; break
print(last or "—")
' 2>/dev/null || echo "—")
    [[ -z "$last_msg" ]] && last_msg="—"
  fi
  echo -e "  Last activity:     ${last_activity}  ${CYAN}${last_msg}${NC}"
  echo ""

  # Results tail
  echo -e "${BOLD}Recent Results:${NC}"
  if [[ -f "${results_path}" && ${total_results} -gt 0 ]]; then
    # Header
    printf "  ${BOLD}${CYAN}%-9s  %-14s  %-9s  %-s${NC}\n" "COMMIT" "METRIC" "STATUS" "DESCRIPTION"
    printf "  ${BOLD}"; printf '─%.0s' $(seq 1 80); printf "${NC}\n"
    # Last 10 rows
    tail -n +2 "${results_path}" | tail -10 | while IFS=$'\t' read -r commit metric rstatus desc; do
      local color="${GRAY}"
      case "$(echo "${rstatus}" | tr '[:upper:]' '[:lower:]')" in
        keep)    color="${GREEN}" ;;
        discard) color="${YELLOW}" ;;
        crash)   color="${RED}" ;;
      esac
      printf "  ${color}%-9s  %-14s  %-9s  %-s${NC}\n" \
        "${commit:0:9}" "${metric:0:14}" "${rstatus:0:9}" "${desc:0:45}"
    done
  else
    echo -e "  ${GRAY}(no results yet)${NC}"
  fi
  echo ""

  # Per-iteration cost breakdown (last 5)
  echo -e "${BOLD}Recent Iteration Costs:${NC}"
  local found_costs=0
  for jsonl in $(ls -1 "${FLEET_ROOT}"/logs/session-iter-*.jsonl 2>/dev/null | sort -t- -k3 -n | tail -5); do
    [[ -f "${jsonl}" ]] || continue
    local iter_num cost_val
    iter_num=$(basename "${jsonl}" | sed 's/session-iter-\(.*\)\.jsonl/\1/')
    cost_val=$(grep '"type":"result"' "${jsonl}" 2>/dev/null | tail -1 | \
      jq -r '.total_cost_usd // 0' 2>/dev/null || echo "0")
    cost_val=$(awk "BEGIN {printf \"%.2f\", ${cost_val}}")
    printf "  iter %-4s  \$%s\n" "${iter_num}" "${cost_val}"
    found_costs=1
  done
  [[ ${found_costs} -eq 0 ]] && echo -e "  ${GRAY}(no session logs yet)${NC}"

  echo ""
  echo -e "${BOLD}$(printf '─%.0s' {1..80})${NC}"
}

if [[ "$OPT_WATCH" == "true" ]]; then
  trap 'echo ""; exit 0' INT TERM
  while true; do
    clear
    show_status
    sleep 5
  done
else
  show_status
fi
