#!/usr/bin/env bash
# cleanup.sh — Worktree Fleet Cleanup
#
# Removes git worktrees for all workers and sweeps orphan claude processes.
# Requires --force to prevent accidental removal.
#
# Usage: cleanup.sh <fleet-root|fleet-name> --force

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info()    { echo -e "${CYAN}[cleanup]${NC} $*"; }
success() { echo -e "${GREEN}[cleanup]${NC} $*"; }
warn()    { echo -e "${YELLOW}[cleanup]${NC} $*"; }
error()   { echo -e "${RED}[cleanup]${NC} $*" >&2; }
die()     { error "$*"; exit 1; }

usage() {
  cat <<EOF
${BOLD}USAGE${NC}
  cleanup.sh <fleet-root|fleet-name> --force

${BOLD}DESCRIPTION${NC}
  Removes all git worktrees created by launch.sh for this fleet.
  Sweeps orphan claude processes referencing this fleet root.
  --force is required to prevent accidental removal.
  Unregisters the fleet from the fleet registry.
EOF
}

[[ "${1:-}" == "--help" || "${1:-}" == "-h" ]] && { usage; exit 0; }
[[ $# -lt 1 ]] && { error "Missing fleet-root"; usage; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/../lib"

# Source registry
if [[ -f "${LIB_DIR}/registry.sh" ]]; then
  # shellcheck disable=SC1091
  source "${LIB_DIR}/registry.sh"
  FLEET_ROOT="$(registry_resolve "${1}")" || { echo "Error: fleet not found: ${1}" >&2; exit 1; }
else
  FLEET_ROOT="$(realpath "${1}")"
fi
shift

FORCE=0
for arg in "$@"; do
  case "${arg}" in
    --force) FORCE=1 ;;
  esac
done

if [[ "${FORCE}" -eq 0 ]]; then
  error "cleanup.sh requires --force to prevent accidental worktree removal."
  error "  cleanup.sh ${FLEET_ROOT} --force"
  exit 1
fi

[[ ! -d "${FLEET_ROOT}" ]] && die "Fleet root does not exist: ${FLEET_ROOT}"

FLEET_JSON="${FLEET_ROOT}/fleet.json"
FLEET_NAME="unknown"
if [[ -f "${FLEET_JSON}" ]]; then
  FLEET_NAME=$(jq -r '.fleet_name // "unknown"' "${FLEET_JSON}" 2>/dev/null || echo "unknown")
fi

command -v git &>/dev/null || die "git is required but not installed"

info "Cleaning up fleet: ${BOLD}${FLEET_NAME}${NC}"
info "Fleet root: ${FLEET_ROOT}"

# ---------------------------------------------------------------------------
# Sweep orphan processes referencing this fleet root
# ---------------------------------------------------------------------------
info "Sweeping orphan processes..."
orphan_pids=$(pgrep -f "${FLEET_ROOT}" 2>/dev/null || true)
if [[ -n "${orphan_pids}" ]]; then
  for pid in ${orphan_pids}; do
    # Skip self and parent
    [[ "${pid}" == "$$" || "${pid}" == "${PPID}" ]] && continue
    if kill -0 "${pid}" 2>/dev/null; then
      warn "  Killing orphan pid ${pid}"
      kill -TERM "${pid}" 2>/dev/null || true
    fi
  done
  sleep 1
  # SIGKILL any survivors
  for pid in ${orphan_pids}; do
    [[ "${pid}" == "$$" || "${pid}" == "${PPID}" ]] && continue
    if kill -0 "${pid}" 2>/dev/null; then
      warn "  Force-killing pid ${pid}"
      kill -KILL "${pid}" 2>/dev/null || true
    fi
  done
else
  info "  No orphan processes found."
fi

# ---------------------------------------------------------------------------
# Kill tmux session if present
# ---------------------------------------------------------------------------
if command -v tmux &>/dev/null && tmux has-session -t "${FLEET_NAME}" 2>/dev/null; then
  info "Killing tmux session: ${FLEET_NAME}"
  tmux kill-session -t "${FLEET_NAME}" 2>/dev/null || true
fi

# ---------------------------------------------------------------------------
# Remove git worktrees
# ---------------------------------------------------------------------------
GIT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || {
  warn "Not inside a git repo — skipping git worktree removal"
  GIT_ROOT=""
}

WT_REMOVED=0
WT_FAILED=0

WORKTREES_DIR="${FLEET_ROOT}/worktrees"
if [[ -d "${WORKTREES_DIR}" ]]; then
  for wt_path in "${WORKTREES_DIR}"/*/; do
    [[ -d "${wt_path}" ]] || continue
    worker_id=$(basename "${wt_path}")
    wt_abs=$(realpath "${wt_path}")
    info "Removing worktree: ${wt_abs} (worker: ${worker_id})"

    if [[ -n "${GIT_ROOT}" ]]; then
      if git -C "${GIT_ROOT}" worktree list --porcelain 2>/dev/null | grep -q "^worktree ${wt_abs}$"; then
        if git -C "${GIT_ROOT}" worktree remove --force "${wt_abs}" 2>/dev/null; then
          success "  Removed worktree: ${wt_abs}"
          WT_REMOVED=$((WT_REMOVED + 1))
        else
          warn "  git worktree remove failed for ${wt_abs} — removing directory directly"
          rm -rf "${wt_abs}" 2>/dev/null || true
          git -C "${GIT_ROOT}" worktree prune 2>/dev/null || true
          WT_REMOVED=$((WT_REMOVED + 1))
        fi
      else
        warn "  Worktree not registered with git at ${wt_abs} — removing directory"
        rm -rf "${wt_abs}" 2>/dev/null || true
        WT_REMOVED=$((WT_REMOVED + 1))
      fi
    else
      rm -rf "${wt_abs}" 2>/dev/null || true
      WT_REMOVED=$((WT_REMOVED + 1))
    fi
  done
fi

# Prune any dangling worktree metadata
if [[ -n "${GIT_ROOT}" ]]; then
  git -C "${GIT_ROOT}" worktree prune 2>/dev/null || true
fi

# ---------------------------------------------------------------------------
# Unregister from fleet registry
# ---------------------------------------------------------------------------
if declare -f registry_unregister >/dev/null 2>&1; then
  registry_unregister "${FLEET_NAME}" 2>/dev/null || true
  info "Unregistered '${FLEET_NAME}' from fleet registry."
fi

echo ""
if [[ "${WT_FAILED}" -eq 0 ]]; then
  success "Cleanup complete — removed ${WT_REMOVED} worktree(s)."
else
  warn "Cleanup partial — removed ${WT_REMOVED}, failed ${WT_FAILED}. Check above for details."
fi
