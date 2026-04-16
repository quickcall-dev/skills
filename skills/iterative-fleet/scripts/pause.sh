#!/usr/bin/env bash
# pause.sh — Pause an iterative fleet at next iteration boundary
#
# Touches ${FLEET_ROOT}/.paused — the orchestrator checks this flag at
# each iteration boundary and pauses when it finds the file.
# Workers are NOT killed — they run to completion.
#
# Usage: pause.sh <fleet-root>

set -euo pipefail

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

info()    { echo -e "${CYAN}[pause]${NC} $*"; }
success() { echo -e "${GREEN}[pause]${NC} $*"; }
warn()    { echo -e "${YELLOW}[pause]${NC} $*"; }
error()   { echo -e "${RED}[pause]${NC} $*" >&2; }
die()     { error "$*"; exit 1; }

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  echo "Usage: pause.sh <fleet-root>"
  echo "  Pauses the orchestrator at next iteration boundary."
  echo "  Workers continue running to completion."
  echo "  Resume with: resume.sh <fleet-root>"
  exit 0
fi

[[ $# -lt 1 ]] && { error "Missing fleet-root"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/registry.sh
if [[ -f "${SCRIPT_DIR}/../lib/registry.sh" ]]; then
  # shellcheck disable=SC1091
  source "${SCRIPT_DIR}/../lib/registry.sh"
  FLEET_ROOT="$(registry_resolve "${1}")" || die "fleet not found: ${1}"
else
  FLEET_ROOT="$(realpath "${1}")"
fi

[[ ! -d "${FLEET_ROOT}" ]] && die "Fleet root does not exist: ${FLEET_ROOT}"
[[ ! -f "${FLEET_ROOT}/fleet.json" ]] && die "fleet.json not found in ${FLEET_ROOT}"

FLEET_NAME=$(jq -r '.fleet_name // "fleet"' "${FLEET_ROOT}/fleet.json" 2>/dev/null || echo "fleet")

if [[ -f "${FLEET_ROOT}/.paused" ]]; then
  warn "Fleet '${FLEET_NAME}' is already paused."
  exit 0
fi

touch "${FLEET_ROOT}/.paused"

# Also update fleet.json status
local_ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
if [[ -f "${FLEET_ROOT}/fleet.json" ]]; then
  tmp=$(mktemp "${FLEET_ROOT}/.tmp.fleet.XXXXXX")
  jq --arg ts "${local_ts}" \
     '.status = "paused" | .paused_at = $ts' \
     "${FLEET_ROOT}/fleet.json" > "${tmp}"
  mv "${tmp}" "${FLEET_ROOT}/fleet.json"
fi

success "Fleet '${BOLD}${FLEET_NAME}${NC}${GREEN}' paused."
info "The orchestrator will pause at the next iteration boundary."
info "Workers already running will complete their current iteration."
info "Resume with: ${BOLD}bash ${SCRIPT_DIR}/resume.sh ${FLEET_ROOT}${NC}"
