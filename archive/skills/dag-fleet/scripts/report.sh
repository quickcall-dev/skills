#!/usr/bin/env bash
# report.sh — Fleet completion report
#
# Generates a markdown report summarizing the fleet run: worker statuses,
# costs, durations, output files, and errors.
#
# Usage: report.sh <fleet-root> [--output report.md]
#        report.sh --help

set -euo pipefail

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
  report.sh <fleet-root> [--output report.md]
  report.sh --help

${BOLD}DESCRIPTION${NC}
  Generates a markdown report summarizing the fleet run.
  Output goes to stdout unless --output is specified.

${BOLD}ARGUMENTS${NC}
  fleet-root    Path to the fleet root directory containing fleet.json

${BOLD}FLAGS${NC}
  --output FILE  Write report to FILE instead of stdout

${BOLD}EXAMPLES${NC}
  report.sh ~/.claude/fleets/my-fleet
  report.sh ~/.claude/fleets/my-fleet --output /tmp/report.md
EOF
}

# ---------------------------------------------------------------------------
# Logging helpers (to stderr so they don't pollute stdout/report)
# ---------------------------------------------------------------------------
info()  { echo -e "${CYAN}[report]${NC} $*" >&2; }
warn()  { echo -e "${YELLOW}[report]${NC} $*" >&2; }
error() { echo -e "${RED}[report]${NC} $*" >&2; }
die()   { error "$*"; exit 1; }

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
OUTPUT_FILE=""
POSITIONAL=()

for arg in "$@"; do
  case "${arg}" in
    --help|-h)
      usage
      exit 0
      ;;
    *)
      POSITIONAL+=("${arg}")
      ;;
  esac
done

# Re-parse positional args with --output handling
set -- "${POSITIONAL[@]:-}"
POSITIONAL=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output)
      [[ $# -lt 2 ]] && die "--output requires a filename argument"
      OUTPUT_FILE="$2"
      shift 2
      ;;
    --output=*)
      OUTPUT_FILE="${1#--output=}"
      shift
      ;;
    *)
      POSITIONAL+=("$1")
      shift
      ;;
  esac
done

set -- "${POSITIONAL[@]:-}"

if [[ $# -lt 1 ]]; then
  error "Missing required argument: fleet-root"
  echo ""
  usage
  exit 1
fi

FLEET_ROOT="$(realpath "${1}")"

# ---------------------------------------------------------------------------
# Validate
# ---------------------------------------------------------------------------
[[ -d "${FLEET_ROOT}" ]] || die "Fleet root does not exist: ${FLEET_ROOT}"

FLEET_JSON="${FLEET_ROOT}/fleet.json"
[[ -f "${FLEET_JSON}" ]] || die "fleet.json not found: ${FLEET_JSON}"

command -v jq &>/dev/null || die "jq is required but not installed"

# ---------------------------------------------------------------------------
# Helper: format seconds as human-readable duration
# ---------------------------------------------------------------------------
format_duration() {
  local secs="${1:-0}"
  secs="${secs%%.*}"  # strip decimals
  if [[ "${secs}" -lt 60 ]]; then
    echo "${secs}s"
  elif [[ "${secs}" -lt 3600 ]]; then
    echo "$((secs / 60))m $((secs % 60))s"
  else
    echo "$((secs / 3600))h $(( (secs % 3600) / 60 ))m"
  fi
}

# ---------------------------------------------------------------------------
# Helper: ISO8601 to epoch (portable: try date -d, fallback python3)
# ---------------------------------------------------------------------------
iso_to_epoch() {
  local ts="$1"
  if date -d "${ts}" +%s 2>/dev/null; then
    return
  fi
  python3 -c "
import sys, datetime
s = '${ts}'.replace('Z','+00:00')
try:
    dt = datetime.datetime.fromisoformat(s)
    print(int(dt.timestamp()))
except Exception:
    print(0)
" 2>/dev/null || echo 0
}

# ---------------------------------------------------------------------------
# Parse fleet.json
# ---------------------------------------------------------------------------
FLEET_NAME=$(jq -r '.fleet_name // "fleet"' "${FLEET_JSON}")

# Worker IDs
mapfile -t WORKER_IDS < <(jq -r '.workers[].id // empty' "${FLEET_JSON}" 2>/dev/null)

if [[ ${#WORKER_IDS[@]} -eq 0 ]]; then
  # Fall back to workers/ subdirectories
  for d in "${FLEET_ROOT}/workers"/*/; do
    [[ -d "$d" ]] && WORKER_IDS+=("$(basename "$d")")
  done
fi

info "Found ${#WORKER_IDS[@]} workers in fleet '${FLEET_NAME}'"

# ---------------------------------------------------------------------------
# Collect per-worker data
# ---------------------------------------------------------------------------
TOTAL_COST=0
FLEET_START_EPOCH=0
FLEET_END_EPOCH=0

declare -A W_STATUS W_COST W_TURNS W_FILES W_DURATION W_SUBTYPE

for wid in "${WORKER_IDS[@]}"; do
  WDIR="${FLEET_ROOT}/workers/${wid}"
  LOG="${WDIR}/session.jsonl"

  W_STATUS[$wid]="PENDING"
  W_COST[$wid]="0"
  W_TURNS[$wid]="0"
  W_FILES[$wid]="0"
  W_DURATION[$wid]="n/a"
  W_SUBTYPE[$wid]=""

  if [[ ! -f "${LOG}" || ! -s "${LOG}" ]]; then
    continue
  fi

  # Last event
  LAST_LINE=$(tail -1 "${LOG}" 2>/dev/null || true)
  LAST_TYPE=$(echo "${LAST_LINE}" | jq -r '.type // ""' 2>/dev/null || echo "")
  LAST_SUBTYPE=$(echo "${LAST_LINE}" | jq -r '.subtype // ""' 2>/dev/null || echo "")

  if [[ "${LAST_TYPE}" == "result" ]]; then
    if [[ "${LAST_SUBTYPE}" == "success" ]]; then
      W_STATUS[$wid]="SUCCESS"
    else
      W_STATUS[$wid]="FAILED (${LAST_SUBTYPE})"
    fi
    W_SUBTYPE[$wid]="${LAST_SUBTYPE}"
    W_COST[$wid]=$(echo "${LAST_LINE}" | jq -r '.total_cost_usd // 0' 2>/dev/null || echo "0")
    W_COST[$wid]=$(awk "BEGIN {printf \"%.2f\", ${W_COST[$wid]}}")
    W_TURNS[$wid]=$(echo "${LAST_LINE}" | jq -r '.num_turns // 0' 2>/dev/null || echo "0")
  else
    W_STATUS[$wid]="RUNNING"
  fi

  # Accumulate total cost
  TOTAL_COST=$(awk "BEGIN {printf \"%.2f\", ${TOTAL_COST} + ${W_COST[$wid]:-0}}")

  # Duration: first event timestamp vs last event timestamp
  FIRST_LINE=$(head -1 "${LOG}" 2>/dev/null || true)
  FIRST_TS=$(echo "${FIRST_LINE}" | jq -r '.timestamp // ""' 2>/dev/null || echo "")
  LAST_TS=$(echo "${LAST_LINE}" | jq -r '.timestamp // ""' 2>/dev/null || echo "")

  if [[ -n "${FIRST_TS}" && -n "${LAST_TS}" ]]; then
    FIRST_EPOCH=$(iso_to_epoch "${FIRST_TS}")
    LAST_EPOCH=$(iso_to_epoch "${LAST_TS}")
    DUR_SECS=$(( LAST_EPOCH - FIRST_EPOCH ))
    W_DURATION[$wid]=$(format_duration "${DUR_SECS}")

    # Track fleet-wide start/end
    if [[ "${FLEET_START_EPOCH}" -eq 0 || "${FIRST_EPOCH}" -lt "${FLEET_START_EPOCH}" ]]; then
      FLEET_START_EPOCH="${FIRST_EPOCH}"
    fi
    if [[ "${LAST_EPOCH}" -gt "${FLEET_END_EPOCH}" ]]; then
      FLEET_END_EPOCH="${LAST_EPOCH}"
    fi
  fi

  # Count output files
  OUTPUT_DIR="${WDIR}/output"
  if [[ -d "${OUTPUT_DIR}" ]]; then
    FILE_COUNT=$(find "${OUTPUT_DIR}" -maxdepth 3 -type f 2>/dev/null | wc -l | tr -d ' ')
    W_FILES[$wid]="${FILE_COUNT}"
  fi
done

# Fleet total duration
if [[ "${FLEET_START_EPOCH}" -gt 0 && "${FLEET_END_EPOCH}" -gt 0 ]]; then
  FLEET_DURATION=$(format_duration $(( FLEET_END_EPOCH - FLEET_START_EPOCH )))
else
  FLEET_DURATION="unknown"
fi

REPORT_TS=$(date -u +"%Y-%m-%d %H:%M:%S UTC")

# ---------------------------------------------------------------------------
# Build report
# ---------------------------------------------------------------------------
{
  echo "# Fleet Report: ${FLEET_NAME}"
  echo ""
  echo "**Completed**: ${REPORT_TS}"
  echo "**Duration**: ${FLEET_DURATION}"
  echo "**Total Cost**: \$${TOTAL_COST}"
  echo ""
  echo "## Workers"
  echo ""
  echo "| Worker | Status | Files | Cost | Turns | Duration |"
  echo "|--------|--------|-------|------|-------|----------|"

  for wid in "${WORKER_IDS[@]}"; do
    COST_FMT="\$${W_COST[$wid]}"
    echo "| ${wid} | ${W_STATUS[$wid]} | ${W_FILES[$wid]} | ${COST_FMT} | ${W_TURNS[$wid]} | ${W_DURATION[$wid]} |"
  done

  echo ""
  echo "## Output Files"
  echo ""
  for wid in "${WORKER_IDS[@]}"; do
    OUTPUT_DIR="${FLEET_ROOT}/workers/${wid}/output"
    if [[ -d "${OUTPUT_DIR}" && -n "$(ls -A "${OUTPUT_DIR}" 2>/dev/null)" ]]; then
      echo "### ${wid}"
      echo ""
      while IFS= read -r fpath; do
        # Get file size
        FSIZE=$(stat -c%s "${fpath}" 2>/dev/null || stat -f%z "${fpath}" 2>/dev/null || echo "?")
        REL_PATH="${fpath#${FLEET_ROOT}/}"
        echo "- \`${REL_PATH}\` (${FSIZE} bytes)"
      done < <(find "${OUTPUT_DIR}" -type f 2>/dev/null | sort)
      echo ""
    fi
  done

  # Check if no output files at all
  HAS_OUTPUT=false
  for wid in "${WORKER_IDS[@]}"; do
    OUTPUT_DIR="${FLEET_ROOT}/workers/${wid}/output"
    if [[ -d "${OUTPUT_DIR}" && -n "$(ls -A "${OUTPUT_DIR}" 2>/dev/null)" ]]; then
      HAS_OUTPUT=true
      break
    fi
  done
  if [[ "${HAS_OUTPUT}" == "false" ]]; then
    echo "_No output files found._"
    echo ""
  fi

  echo "## Errors"
  echo ""
  HAS_ERRORS=false
  for wid in "${WORKER_IDS[@]}"; do
    SUBTYPE="${W_SUBTYPE[$wid]:-}"
    if [[ -n "${SUBTYPE}" && "${SUBTYPE}" != "success" ]]; then
      HAS_ERRORS=true
      echo "### ${wid} — ${W_STATUS[$wid]}"
      echo ""
      echo "**Result subtype**: \`${SUBTYPE}\`"
      echo ""

      # Include last few lines of session.jsonl for error context
      LOG="${FLEET_ROOT}/workers/${wid}/session.jsonl"
      if [[ -f "${LOG}" ]]; then
        LAST_RESULT=$(tail -1 "${LOG}" | jq -r '.result // .error // ""' 2>/dev/null || true)
        if [[ -n "${LAST_RESULT}" ]]; then
          echo "**Detail**:"
          echo ""
          echo '```'
          echo "${LAST_RESULT}"
          echo '```'
          echo ""
        fi
      fi

      # Include summary.md if it exists
      SUMMARY="${FLEET_ROOT}/workers/${wid}/summary.md"
      if [[ -f "${SUMMARY}" ]]; then
        echo "**Summary**:"
        echo ""
        cat "${SUMMARY}"
        echo ""
      fi
    fi
  done

  if [[ "${HAS_ERRORS}" == "false" ]]; then
    echo "_No errors — all workers completed successfully._"
    echo ""
  fi

} | if [[ -n "${OUTPUT_FILE}" ]]; then
  tee "${OUTPUT_FILE}"
  info "Report written to: ${OUTPUT_FILE}"
else
  cat
fi
