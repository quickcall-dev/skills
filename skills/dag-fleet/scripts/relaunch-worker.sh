#!/usr/bin/env bash
# relaunch-worker.sh — Selectively re-run a single worker in a live fleet.
#
# The "addendum workflow": edit workers/<id>/prompt.md to add 1-2 new sources
# or instructions, then run:
#
#   relaunch-worker.sh <fleet-name-or-root> <worker-id>
#
# Just that one worker spins up in a fresh tmux window in the existing fleet
# session, writing a new session.jsonl (the old one is rotated to .bak — never
# truncated in place, see problems.md #14). Other workers are untouched.
#
# REFUSES if:
#   - the worker is currently running (kill.sh first)
#   - the parent fleet's tmux session is dead (launch.sh --force-relaunch first)
#
# This script is the explicit operator-owned replacement for the auto-steering
# path; it does not try to be clever about mid-flight intervention.

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
  relaunch-worker.sh <fleet-name-or-root> <worker-id>
  relaunch-worker.sh --help

${BOLD}DESCRIPTION${NC}
  Re-run a single worker in an already-live fleet session. Intended for the
  "addendum" workflow where the operator edits workers/<id>/prompt.md to add
  new sources or refinements and wants just that worker to re-execute.

  Steps:
    1. Resolve fleet via registry_resolve
    2. Verify worker exists in fleet.json
    3. Require the fleet tmux session to be LIVE
    4. Refuse if the worker is currently running (exit 3)
    5. Rotate session.jsonl / status.json to .bak (never truncate in place)
    6. Sweep any zombie subprocesses under the worker dir
    7. Re-read workers/<id>/prompt.md and spawn a new tmux window
    8. Update fleet.json: started_at, status=running

${BOLD}REFUSES WHEN${NC}
  - worker currently running          (use kill.sh <fleet> <wid> first)
  - parent fleet tmux session dead    (use launch.sh --force-relaunch instead)

${BOLD}EXAMPLES${NC}
  relaunch-worker.sh fleet-test-dag c
  relaunch-worker.sh ~/.claude/fleets/research-fleet research-05
EOF
}

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
info()    { echo -e "${CYAN}[relaunch]${NC} $*"; }
success() { echo -e "${GREEN}[relaunch]${NC} $*"; }
warn()    { echo -e "${YELLOW}[relaunch]${NC} $*"; }
error()   { echo -e "${RED}[relaunch]${NC} $*" >&2; }
die()     { error "$*"; exit 1; }

# ---------------------------------------------------------------------------
# Arg parse
# ---------------------------------------------------------------------------
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage; exit 0
fi

if [[ $# -lt 2 ]]; then
  error "Missing required arguments."
  echo ""
  usage
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source registry helper if available (don't crash if absent)
if [[ -f "${SCRIPT_DIR}/../lib/registry.sh" ]]; then
  # shellcheck source=../lib/registry.sh disable=SC1091
  source "${SCRIPT_DIR}/../lib/registry.sh"
fi

# Optional cost helper
if [[ -f "${SCRIPT_DIR}/../lib/cost.sh" ]]; then
  # shellcheck disable=SC1091
  source "${SCRIPT_DIR}/../lib/cost.sh"
fi

if declare -f registry_resolve >/dev/null 2>&1; then
  FLEET_ROOT="$(registry_resolve "${1}")" || die "fleet not found: ${1}"
else
  [[ -d "${1}" ]] || die "fleet root not found: ${1}"
  FLEET_ROOT="$(realpath "${1}")"
fi

WORKER_ID="${2}"

command -v jq    >/dev/null 2>&1 || die "jq is required"
command -v tmux  >/dev/null 2>&1 || die "tmux is required"
command -v claude >/dev/null 2>&1 || die "claude CLI is required"

FLEET_JSON="${FLEET_ROOT}/fleet.json"
[[ -f "${FLEET_JSON}" ]] || die "fleet.json not found: ${FLEET_JSON}"

# ---------------------------------------------------------------------------
# Verify worker exists in fleet.json
# ---------------------------------------------------------------------------
WORKER_IDX=$(jq --arg id "${WORKER_ID}" \
  '[.workers[] | .id] | index($id)' "${FLEET_JSON}")
if [[ "${WORKER_IDX}" == "null" || -z "${WORKER_IDX}" ]]; then
  die "worker '${WORKER_ID}' not found in ${FLEET_JSON}"
fi

FLEET_NAME=$(jq -r '.fleet_name // "fleet"' "${FLEET_JSON}")
DEFAULT_MODEL=$(jq -r '.config.model // "sonnet"' "${FLEET_JSON}")
FALLBACK_MODEL=$(jq -r '.config.fallback_model // "haiku"' "${FLEET_JSON}")
KEEP_PANES_OPEN=$(jq -r '.config.keep_panes_open // false' "${FLEET_JSON}")
RECORD=$(jq -r 'if .config.record == true then "true" else "false" end' "${FLEET_JSON}")

TMUX_SESSION="${FLEET_NAME}"

# ---------------------------------------------------------------------------
# Require live fleet session. Judgment call: if the fleet tmux session is
# dead we REFUSE and tell the user to launch.sh --force-relaunch instead.
# This script is for selective re-runs on a LIVE fleet, not resurrection.
# ---------------------------------------------------------------------------
if ! tmux has-session -t "${TMUX_SESSION}" 2>/dev/null; then
  error "fleet ${FLEET_NAME} tmux session is dead — relaunch the whole fleet first"
  error "  try: launch.sh ${FLEET_ROOT} --force-relaunch"
  exit 3
fi

WORKER_DIR="${FLEET_ROOT}/workers/${WORKER_ID}"
WORKER_PROMPT="${WORKER_DIR}/prompt.md"
WORKER_SESSION_JSONL="${WORKER_DIR}/session.jsonl"
WORKER_STATUS_JSON="${WORKER_DIR}/status.json"

mkdir -p "${WORKER_DIR}/output"

# ---------------------------------------------------------------------------
# Refuse if worker is currently running (live tmux window OR live process)
# ---------------------------------------------------------------------------
live=0
if tmux list-windows -t "${TMUX_SESSION}" -F '#W' 2>/dev/null | grep -Fxq "${WORKER_ID}"; then
  live=1
fi
if [[ "${live}" -eq 0 ]]; then
  if pgrep -f "${WORKER_DIR}" >/dev/null 2>&1 \
     || pgrep -f "WORKER_ID='${WORKER_ID}'" >/dev/null 2>&1 \
     || pgrep -f "fleet-${FLEET_NAME}-${WORKER_ID}" >/dev/null 2>&1; then
    live=1
  fi
fi
if [[ "${live}" -eq 1 ]]; then
  error "worker ${WORKER_ID} is currently running — kill.sh ${FLEET_NAME} ${WORKER_ID} first, then relaunch-worker.sh"
  exit 3
fi

[[ -f "${WORKER_PROMPT}" ]] || die "prompt.md not found at ${WORKER_PROMPT}"

# ---------------------------------------------------------------------------
# Rotate session.jsonl / status.json to .bak (never truncate — problems.md #14)
# ---------------------------------------------------------------------------
ROTATE_TS=$(date +%s)
if [[ -s "${WORKER_SESSION_JSONL}" ]]; then
  mv "${WORKER_SESSION_JSONL}" "${WORKER_SESSION_JSONL}.${ROTATE_TS}.bak"
  info "rotated session.jsonl → session.jsonl.${ROTATE_TS}.bak"
fi
if [[ -s "${WORKER_STATUS_JSON}" ]]; then
  cp "${WORKER_STATUS_JSON}" "${WORKER_STATUS_JSON}.${ROTATE_TS}.bak"
fi

# ---------------------------------------------------------------------------
# Sweep zombie subprocesses under the worker dir (pattern from kill.sh)
# ---------------------------------------------------------------------------
orphans=$(pgrep -f "${WORKER_DIR}" 2>/dev/null | grep -v "^$$\$" || true)
if [[ -n "${orphans}" ]]; then
  info "sweeping $(echo "${orphans}" | wc -l) orphan process(es) under ${WORKER_DIR}"
  echo "${orphans}" | xargs -r kill -9 2>/dev/null || true
  sleep 0.5
fi
remaining=$(pgrep -f "${WORKER_DIR}" 2>/dev/null | grep -v "^$$\$" || true)
if [[ -n "${remaining}" ]]; then
  warn "some processes survived sweep: ${remaining}"
fi

# ---------------------------------------------------------------------------
# Read worker config
# ---------------------------------------------------------------------------
WORKER_TYPE=$(jq -r ".workers[${WORKER_IDX}].type // \"read-only\"" "${FLEET_JSON}")
WORKER_MODEL=$(jq -r ".workers[${WORKER_IDX}].model // \"${DEFAULT_MODEL}\"" "${FLEET_JSON}")
MAX_TURNS=$(jq -r ".workers[${WORKER_IDX}].max_turns // 0" "${FLEET_JSON}")
MAX_BUDGET=$(jq -r ".workers[${WORKER_IDX}].max_budget_usd // 1.00" "${FLEET_JSON}")
WORKER_TASK=$(jq -r ".workers[${WORKER_IDX}].task // \"\"" "${FLEET_JSON}")

# ---------------------------------------------------------------------------
# Disallowed tools per worker type
# MUST stay in sync with launch.sh get_disallowed_tools()
# ---------------------------------------------------------------------------
get_disallowed_tools() {
  local worker_type="$1"
  case "${worker_type}" in
    read-only)    echo "Bash,Edit,Write,Agent,WebFetch,WebSearch" ;;
    write)        echo "Bash,Agent,WebFetch,WebSearch" ;;
    code-run)     echo "Agent,WebFetch,WebSearch" ;;
    research)     echo "Bash,Edit,Agent" ;;
    reviewer)     echo "Bash,Edit,Agent,WebFetch,WebSearch" ;;
    orchestrator) echo "Agent,WebFetch,WebSearch,Edit" ;;
    *)
      warn "Unknown worker type '${worker_type}', using read-only restrictions"
      echo "Bash,Edit,Write,Agent,WebFetch,WebSearch"
      ;;
  esac
}
DISALLOWED_TOOLS=$(get_disallowed_tools "${WORKER_TYPE}")
SESSION_NAME="fleet-${FLEET_NAME}-${WORKER_ID}"

info "Relaunching ${BOLD}${WORKER_ID}${NC} (type=${WORKER_TYPE}, model=${WORKER_MODEL})"

# ---------------------------------------------------------------------------
# Build INNER_CMD — mirrors launch.sh's INNER_CMD section
# ---------------------------------------------------------------------------
INNER_CMD="cd '${FLEET_ROOT}'"
INNER_CMD+=" && unset CLAUDECODE 2>/dev/null || true"
INNER_CMD+=" && export FLEET_ROOT='${FLEET_ROOT}'"
INNER_CMD+=" && export WORKER_ID='${WORKER_ID}'"
INNER_CMD+=" && export WORKER_OUTPUT_DIR='${WORKER_DIR}/output'"
INNER_CMD+=" && cat '${WORKER_PROMPT}' | claude -p"
INNER_CMD+=" --dangerously-skip-permissions"
INNER_CMD+=" --output-format stream-json"
INNER_CMD+=" --verbose"
INNER_CMD+=" --model '${WORKER_MODEL}'"
if [[ "${WORKER_MODEL}" != "${FALLBACK_MODEL}" ]]; then
  INNER_CMD+=" --fallback-model '${FALLBACK_MODEL}'"
fi
INNER_CMD+=" --max-turns ${MAX_TURNS}"
INNER_CMD+=" --max-budget-usd ${MAX_BUDGET}"
INNER_CMD+=" --name '${SESSION_NAME}'"
INNER_CMD+=" --disallowed-tools '${DISALLOWED_TOOLS}'"
INNER_CMD+=" 2>&1 | tee '${WORKER_SESSION_JSONL}'"
if [[ "${KEEP_PANES_OPEN}" == "true" ]]; then
  INNER_CMD+="; read"
else
  INNER_CMD+="; touch '${WORKER_DIR}/.done'; sleep \${KEEP_PANE_OPEN_SECONDS:-30}"
fi

# Wrap in asciinema if enabled (config.record, default false) and available
WORKER_RECORDING="${WORKER_DIR}/${WORKER_ID}.relaunch.${ROTATE_TS}.cast"
if [[ "${RECORD}" == "true" ]] && command -v asciinema &>/dev/null; then
  RUNNER_SCRIPT="${WORKER_DIR}/.run.sh"
  echo "#!/bin/bash" > "${RUNNER_SCRIPT}"
  echo "${INNER_CMD}" >> "${RUNNER_SCRIPT}"
  chmod +x "${RUNNER_SCRIPT}"
  CLAUDE_CMD="asciinema rec '${WORKER_RECORDING}' --overwrite -c '${RUNNER_SCRIPT}'"
else
  CLAUDE_CMD="${INNER_CMD}"
fi

# ---------------------------------------------------------------------------
# Spawn tmux window (under per-worker spawn lock — problems.md #13/#14)
# If an old window with the same name lingers (rare — we already confirmed
# no live worker) kill it first so new-window doesn't collide.
# ---------------------------------------------------------------------------
if tmux list-windows -t "${TMUX_SESSION}" -F '#W' 2>/dev/null | grep -Fxq "${WORKER_ID}"; then
  tmux kill-window -t "${TMUX_SESSION}:${WORKER_ID}" 2>/dev/null || true
fi

WORKER_SPAWN_LOCK="${WORKER_DIR}/.launch.lock"
(
  exec 9>"${WORKER_SPAWN_LOCK}"
  if ! flock -n 9; then
    echo "SKIP_LOCK"
    exit 0
  fi
  tmux new-window -t "${TMUX_SESSION}" -n "${WORKER_ID}" \
    "bash -c \"${CLAUDE_CMD}\""
  echo "SPAWNED"
) > "${WORKER_DIR}/.spawn.out" 2>&1 || true
_spawn_result=$(tail -1 "${WORKER_DIR}/.spawn.out" 2>/dev/null || echo "")
rm -f "${WORKER_DIR}/.spawn.out"
case "${_spawn_result}" in
  SKIP_LOCK) die "another relaunch/launch is holding the spawn lock for ${WORKER_ID}" ;;
  SPAWNED)   ;;
  *)         warn "spawn produced unexpected output: ${_spawn_result}" ;;
esac

# ---------------------------------------------------------------------------
# Rewrite status.json → RUNNING
# ---------------------------------------------------------------------------
local_ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
tmp_status=$(mktemp "${WORKER_DIR}/.tmp.status.XXXXXX")
cat > "${tmp_status}" <<EOF
{
  "worker_id": "${WORKER_ID}",
  "status": "RUNNING",
  "task": "${WORKER_TASK}",
  "step": "relaunched",
  "last_updated": "${local_ts}",
  "session_id": null,
  "cost_usd": 0,
  "turns_used": 0,
  "restarts": 0
}
EOF
mv "${tmp_status}" "${WORKER_STATUS_JSON}"

# ---------------------------------------------------------------------------
# Update fleet.json entry: bump started_at, status=running
# ---------------------------------------------------------------------------
tmp_fleet=$(mktemp "${FLEET_ROOT}/.tmp.fleet.XXXXXX")
jq --arg id "${WORKER_ID}" \
   --arg ts "${local_ts}" \
   --arg sname "${SESSION_NAME}" \
   '(.workers[] | select(.id == $id)) |= . + {
     "status": "running",
     "session_name": $sname,
     "started_at": $ts
   }' "${FLEET_JSON}" > "${tmp_fleet}"
mv "${tmp_fleet}" "${FLEET_JSON}"

success "worker ${WORKER_ID} relaunched in tmux window ${TMUX_SESSION}:${WORKER_ID}"
