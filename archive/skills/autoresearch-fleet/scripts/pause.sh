#!/usr/bin/env bash
# pause.sh — Pause autoresearch fleet at next iteration boundary
#
# Usage: pause.sh <fleet-root>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/../lib/registry.sh" ]]; then
  source "${SCRIPT_DIR}/../lib/registry.sh"
fi

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'
RED='\033[0;31m'; BOLD='\033[1m'; NC='\033[0m'

info()    { echo -e "${CYAN}[pause]${NC} $*"; }
success() { echo -e "${GREEN}[pause]${NC} $*"; }
warn()    { echo -e "${YELLOW}[pause]${NC} $*"; }
die()     { echo -e "${RED}[pause]${NC} $*" >&2; exit 1; }

[[ "${1:-}" == "--help" || "${1:-}" == "-h" ]] && {
  echo "Usage: pause.sh <fleet-root>"
  exit 0
}
[[ $# -lt 1 ]] && { die "Missing fleet-root"; }

FLEET_ROOT="$(realpath "${1}")"
if type -t registry_resolve &>/dev/null; then
  FLEET_ROOT="$(registry_resolve "${1}")" || die "fleet not found: ${1}"
fi

[[ ! -d "${FLEET_ROOT}" ]] && die "Fleet root does not exist: ${FLEET_ROOT}"

FLEET_JSON="${FLEET_ROOT}/fleet.json"
FLEET_NAME=$(jq -r '.fleet_name // "autoresearch"' "${FLEET_JSON}" 2>/dev/null || echo "autoresearch")

if [[ -f "${FLEET_ROOT}/.paused" ]]; then
  warn "Fleet '${FLEET_NAME}' is already paused."
  exit 0
fi

touch "${FLEET_ROOT}/.paused"

local_ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
if [[ -f "${FLEET_JSON}" ]]; then
  tmp=$(mktemp "${FLEET_ROOT}/.tmp.fleet.XXXXXX")
  jq --arg ts "${local_ts}" '.status = "paused" | .paused_at = $ts' "${FLEET_JSON}" > "${tmp}"
  mv "${tmp}" "${FLEET_JSON}"
fi

success "Fleet '${BOLD}${FLEET_NAME}${NC}${GREEN}' paused."
info "Current iteration will complete. Next iteration will wait."
info "Resume: ${BOLD}bash ${SCRIPT_DIR}/resume.sh ${FLEET_ROOT}${NC}"
