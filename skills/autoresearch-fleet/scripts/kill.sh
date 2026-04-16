#!/usr/bin/env bash
# kill.sh — Kill an autoresearch fleet
#
# Usage: kill.sh <fleet-root> [--force]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/../lib/registry.sh" ]]; then
  source "${SCRIPT_DIR}/../lib/registry.sh"
fi

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

info()    { echo -e "${CYAN}[kill]${NC} $*"; }
success() { echo -e "${GREEN}[kill]${NC} $*"; }
warn()    { echo -e "${YELLOW}[kill]${NC} $*"; }
error()   { echo -e "${RED}[kill]${NC} $*" >&2; }
die()     { error "$*"; exit 1; }

[[ "${1:-}" == "--help" || "${1:-}" == "-h" ]] && {
  echo "Usage: kill.sh <fleet-root> [--force]"
  exit 0
}
[[ $# -lt 1 ]] && { error "Missing fleet-root"; exit 1; }

FLEET_ROOT="$(realpath "${1}")"
if type -t registry_resolve &>/dev/null; then
  FLEET_ROOT="$(registry_resolve "${1}")" || die "fleet not found: ${1}"
fi

[[ ! -d "${FLEET_ROOT}" ]] && die "Fleet root does not exist: ${FLEET_ROOT}"

FLEET_JSON="${FLEET_ROOT}/fleet.json"
[[ ! -f "${FLEET_JSON}" ]] && die "fleet.json not found"

FLEET_NAME=$(jq -r '.fleet_name // "autoresearch"' "${FLEET_JSON}")
TMUX_SESSION="${FLEET_NAME}"

info "Killing autoresearch fleet: ${FLEET_NAME}"

rm -f "${FLEET_ROOT}/.paused" 2>/dev/null || true

if tmux has-session -t "${TMUX_SESSION}" 2>/dev/null; then
  tmux kill-session -t "${TMUX_SESSION}"
  success "tmux session '${TMUX_SESSION}' killed"
else
  info "tmux session '${TMUX_SESSION}' not found — already dead"
fi

# Sweep orphans
info "Sweeping orphan processes..."
orphans=$(pgrep -f "${FLEET_ROOT}" 2>/dev/null | grep -v "^$$\$" || true)
if [[ -n "${orphans}" ]]; then
  echo "${orphans}" | xargs -r kill -9 2>/dev/null || true
  sleep 0.5
fi

remaining=$(pgrep -f "${FLEET_ROOT}" 2>/dev/null | grep -v "^$$\$" || true)
if [[ -n "${remaining}" ]]; then
  warn "$(echo "${remaining}" | wc -l) process(es) still alive after sweep"
else
  success "No orphan processes remain"
fi

# Update fleet.json
local_ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
tmp=$(mktemp "${FLEET_ROOT}/.tmp.fleet.XXXXXX")
jq --arg ts "${local_ts}" \
   '.status = "killed" | .killed_at = $ts' \
   "${FLEET_JSON}" > "${tmp}"
mv "${tmp}" "${FLEET_JSON}"

# Update orch state
if [[ -f "${FLEET_ROOT}/.orch-state.json" ]]; then
  tmp=$(mktemp "${FLEET_ROOT}/.tmp.orch.XXXXXX")
  jq '.status = "killed"' "${FLEET_ROOT}/.orch-state.json" > "${tmp}"
  mv "${tmp}" "${FLEET_ROOT}/.orch-state.json"
fi

# Unregister
if type -t registry_unregister &>/dev/null; then
  registry_unregister "${FLEET_NAME}" 2>/dev/null || true
fi

success "Fleet '${FLEET_NAME}' killed."
