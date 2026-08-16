#!/usr/bin/env bash
# resume.sh — Resume a paused iterative fleet
#
# Removes ${FLEET_ROOT}/.paused — the orchestrator will continue
# on its next poll cycle.
#
# Usage: resume.sh <fleet-root>

set -euo pipefail

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

info()    { echo -e "${CYAN}[resume]${NC} $*"; }
success() { echo -e "${GREEN}[resume]${NC} $*"; }
warn()    { echo -e "${YELLOW}[resume]${NC} $*"; }
error()   { echo -e "${RED}[resume]${NC} $*" >&2; }
die()     { error "$*"; exit 1; }

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  echo "Usage: resume.sh <fleet-root>"
  echo "  Removes the .paused flag so the orchestrator continues."
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

if [[ ! -f "${FLEET_ROOT}/.paused" ]]; then
  warn "Fleet '${FLEET_NAME}' is not paused."
  exit 0
fi

rm -f "${FLEET_ROOT}/.paused"

# Update fleet.json status back to running
local_ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
if [[ -f "${FLEET_ROOT}/fleet.json" ]]; then
  tmp=$(mktemp "${FLEET_ROOT}/.tmp.fleet.XXXXXX")
  jq --arg ts "${local_ts}" \
     '.status = "running" | .resumed_at = $ts' \
     "${FLEET_ROOT}/fleet.json" > "${tmp}"
  mv "${tmp}" "${FLEET_ROOT}/fleet.json"
fi

success "Fleet '${BOLD}${FLEET_NAME}${NC}${GREEN}' resumed."
info "The orchestrator will continue on its next poll cycle."
info "Monitor: ${BOLD}bash ${SCRIPT_DIR}/status.sh ${FLEET_ROOT}${NC}"
