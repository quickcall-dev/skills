#!/usr/bin/env bash
# report.sh — Autoresearch completion report
#
# Generates a markdown report: results.tsv summary, best metric,
# cost breakdown, iteration history, stop reason.
#
# Usage: report.sh <fleet-root> [--output report.md]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/../lib/registry.sh" ]]; then
  source "${SCRIPT_DIR}/../lib/registry.sh"
fi

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

info()  { echo -e "${CYAN}[report]${NC} $*" >&2; }
die()   { echo -e "${RED}[report]${NC} $*" >&2; exit 1; }

usage() {
  cat <<EOF
${BOLD}USAGE${NC}
  report.sh <fleet-root> [--output report.md]

${BOLD}DESCRIPTION${NC}
  Generates a markdown report summarizing the autoresearch run.
  Output goes to stdout unless --output is specified.
EOF
}

OUTPUT_FILE=""
POSITIONAL=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --output)  OUTPUT_FILE="$2"; shift 2 ;;
    --output=*) OUTPUT_FILE="${1#--output=}"; shift ;;
    *) POSITIONAL+=("$1"); shift ;;
  esac
done
set -- "${POSITIONAL[@]:-}"

[[ $# -lt 1 ]] && { usage; exit 1; }

FLEET_ROOT="$(realpath "${1}")"
if type -t registry_resolve &>/dev/null; then
  FLEET_ROOT="$(registry_resolve "${1}")" || die "fleet not found: ${1}"
fi

[[ -d "${FLEET_ROOT}" ]] || die "Fleet root does not exist: ${FLEET_ROOT}"
FLEET_JSON="${FLEET_ROOT}/fleet.json"
[[ -f "${FLEET_JSON}" ]] || die "fleet.json not found"

command -v jq &>/dev/null || die "jq required"

# Parse config
FLEET_NAME=$(jq -r '.fleet_name // "autoresearch"' "${FLEET_JSON}")
EVAL_CMD=$(jq -r '.problem.eval_command // "n/a"' "${FLEET_JSON}")
METRIC_DIR=$(jq -r '.problem.metric_direction // "minimize"' "${FLEET_JSON}")
WORKDIR=$(jq -r '.problem.workdir // ""' "${FLEET_JSON}")
[[ -z "${WORKDIR}" || "${WORKDIR}" == "null" ]] && WORKDIR="${FLEET_ROOT}"
MODEL=$(jq -r '.config.model // "n/a"' "${FLEET_JSON}")
STOP_REASON=$(jq -r '.stop_reason // "n/a"' "${FLEET_JSON}")
LAUNCHED_AT=$(jq -r '.launched_at // "n/a"' "${FLEET_JSON}")

# Results file
RESULTS_FILE=$(jq -r '.problem.results_file // "results.tsv"' "${FLEET_JSON}")
RESULTS_PATH="${WORKDIR}/${RESULTS_FILE}"

# Count results
TOTAL=0; KEEPS=0; DISCARDS=0; CRASHES=0
BEST_METRIC="n/a"; BEST_COMMIT="n/a"; BEST_DESC="n/a"

if [[ -f "${RESULTS_PATH}" ]]; then
  TOTAL=$(tail -n +2 "${RESULTS_PATH}" | wc -l | tr -d ' ')
  KEEPS=$(tail -n +2 "${RESULTS_PATH}" | awk -F'\t' 'tolower($3)=="keep"' | wc -l | tr -d ' ')
  DISCARDS=$(tail -n +2 "${RESULTS_PATH}" | awk -F'\t' 'tolower($3)=="discard"' | wc -l | tr -d ' ')
  CRASHES=$(tail -n +2 "${RESULTS_PATH}" | awk -F'\t' 'tolower($3)=="crash"' | wc -l | tr -d ' ')

  if [[ "${METRIC_DIR}" == "minimize" ]]; then
    BEST_LINE=$(tail -n +2 "${RESULTS_PATH}" | awk -F'\t' 'tolower($3)=="keep" {print}' | sort -t$'\t' -k2 -g | head -1)
  else
    BEST_LINE=$(tail -n +2 "${RESULTS_PATH}" | awk -F'\t' 'tolower($3)=="keep" {print}' | sort -t$'\t' -k2 -rg | head -1)
  fi
  if [[ -n "${BEST_LINE}" ]]; then
    BEST_COMMIT=$(echo "${BEST_LINE}" | cut -f1)
    BEST_METRIC=$(echo "${BEST_LINE}" | cut -f2)
    BEST_DESC=$(echo "${BEST_LINE}" | cut -f4)
  fi
fi

# Cost from session logs
TOTAL_COST=0
ITER_COUNT=0
for jsonl in "${FLEET_ROOT}"/logs/session-iter-*.jsonl; do
  [[ -f "${jsonl}" ]] || continue
  ITER_COUNT=$((ITER_COUNT + 1))
  if grep -q '"type":"result"' "${jsonl}" 2>/dev/null; then
    cost=$(grep '"type":"result"' "${jsonl}" 2>/dev/null | tail -1 | \
      jq -r '.total_cost_usd // 0' 2>/dev/null || echo "0")
  else
    cost=$(python3 -c "
import json, sys
total = 0.0
PRICING = {'haiku':(0.80,0.08,1.00,4.00),'sonnet':(3.00,0.30,3.75,15.00),'opus':(15.00,1.50,18.75,75.00)}
def get_pricing(m):
    for k,v in PRICING.items():
        if k in (m or ''): return v
    return PRICING['sonnet']
for line in open(sys.argv[1]):
    try:
        ev=json.loads(line.strip())
        if ev.get('type')!='assistant': continue
        msg=ev.get('message',{}); u=msg.get('usage',{})
        if not u: continue
        ip,crp,ccp,op=get_pricing(msg.get('model',''))
        total+=(u.get('input_tokens',0)*ip+u.get('cache_read_input_tokens',0)*crp+u.get('cache_creation_input_tokens',0)*ccp+u.get('output_tokens',0)*op)/1e6
    except: pass
print(f'{total:.6f}')
" "${jsonl}" 2>/dev/null || echo "0")
  fi
  TOTAL_COST=$(awk "BEGIN {printf \"%.2f\", ${TOTAL_COST} + ${cost}}")
done

# Elapsed
ELAPSED="n/a"
if [[ "${LAUNCHED_AT}" != "n/a" ]]; then
  launch_epoch=$(date -d "${LAUNCHED_AT}" +%s 2>/dev/null || echo 0)
  if [[ ${launch_epoch} -gt 0 ]]; then
    last_log=$(ls -1t "${FLEET_ROOT}"/logs/session-iter-*.jsonl 2>/dev/null | head -1)
    if [[ -n "${last_log}" ]]; then
      end_epoch=$(stat -c %Y "${last_log}" 2>/dev/null || echo "${launch_epoch}")
      secs=$((end_epoch - launch_epoch))
      if [[ $secs -lt 60 ]]; then ELAPSED="${secs}s"
      elif [[ $secs -lt 3600 ]]; then ELAPSED="$((secs/60))m $((secs%60))s"
      else ELAPSED="$((secs/3600))h $((secs%3600/60))m"
      fi
    fi
  fi
fi

REPORT_TS=$(date -u +"%Y-%m-%d %H:%M:%S UTC")

# Build report
{
  echo "# Autoresearch Report: ${FLEET_NAME}"
  echo ""
  echo "**Generated**: ${REPORT_TS}"
  echo "**Model**: ${MODEL}"
  echo "**Eval**: \`${EVAL_CMD}\` (${METRIC_DIR})"
  echo "**Workdir**: \`${WORKDIR}\`"
  echo "**Duration**: ${ELAPSED}"
  echo "**Stop reason**: ${STOP_REASON}"
  echo ""

  echo "## Summary"
  echo ""
  echo "| Metric | Value |"
  echo "|--------|-------|"
  echo "| Best metric | **${BEST_METRIC}** |"
  echo "| Best commit | \`${BEST_COMMIT}\` |"
  echo "| Best description | ${BEST_DESC} |"
  echo "| Total experiments | ${TOTAL} |"
  echo "| Kept | ${KEEPS} |"
  echo "| Discarded | ${DISCARDS} |"
  echo "| Crashed | ${CRASHES} |"
  echo "| Orchestrator iterations | ${ITER_COUNT} |"
  echo "| Total cost | \$${TOTAL_COST} |"
  echo ""

  echo "## Results History"
  echo ""
  if [[ -f "${RESULTS_PATH}" && ${TOTAL} -gt 0 ]]; then
    echo "| # | Commit | Metric | Status | Description |"
    echo "|---|--------|--------|--------|-------------|"
    local_n=0
    tail -n +2 "${RESULTS_PATH}" | while IFS=$'\t' read -r commit metric status desc; do
      local_n=$((local_n + 1))
      echo "| ${local_n} | \`${commit}\` | ${metric} | ${status} | ${desc} |"
    done
    echo ""
  else
    echo "_No results recorded._"
    echo ""
  fi

  echo "## Per-Iteration Cost"
  echo ""
  echo "| Iteration | Cost |"
  echo "|-----------|------|"
  for jsonl in $(ls -1 "${FLEET_ROOT}"/logs/session-iter-*.jsonl 2>/dev/null | sort -t- -k3 -n); do
    [[ -f "${jsonl}" ]] || continue
    iter_num=$(basename "${jsonl}" | sed 's/session-iter-\(.*\)\.jsonl/\1/')
    cost=$(grep '"type":"result"' "${jsonl}" 2>/dev/null | tail -1 | \
      jq -r '.total_cost_usd // 0' 2>/dev/null || echo "0")
    cost=$(awk "BEGIN {printf \"%.2f\", ${cost}}")
    echo "| ${iter_num} | \$${cost} |"
  done
  echo ""

} | if [[ -n "${OUTPUT_FILE}" ]]; then
  tee "${OUTPUT_FILE}"
  info "Report written to: ${OUTPUT_FILE}"
else
  cat
fi
