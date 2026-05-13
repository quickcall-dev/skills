#!/usr/bin/env bash
# reset.sh — reset a dag-fleet to re-launchable state.
#
# Usage:
#   reset.sh <FLEET_ROOT> [--soft|--hard] [--dry-run] [--yes] [--force]
#
# Levels:
#   --soft (default): archive workers/ + logs/ under archive/<ts>/, clear
#     launch flags, reset fleet.json status fields, kill tmux session.
#   --hard: DESTRUCTIVE — wipes workers/, logs/, archive/, directives/, shared/,
#     .cost-ledger.jsonl, results.tsv; reset fleet.json; unregister from fleet registry.
#     ALL logs and prior outputs are permanently deleted. Archive first if you need them:
#       cp -r <FLEET_ROOT>/logs/ <FLEET_ROOT>/archive-logs-backup/
#
# Flags:
#   --dry-run : print actions, touch nothing
#   --yes     : skip confirmation prompt (always assumed today — prompt TBD)
#   --force   : kill live worker processes and proceed (otherwise refuse)
#
# Exit codes:
#   0 success
#   1 bad input / missing fleet.json
#   2 live workers detected (use --force or kill.sh)
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/../lib"

# shellcheck source=/dev/null
source "${LIB_DIR}/registry.sh"
# shellcheck source=/dev/null
source "${LIB_DIR}/reset.sh"

die() { echo "[reset] $*" >&2; exit 1; }

[[ $# -ge 1 ]] || die "usage: reset.sh <FLEET_ROOT> [--soft|--hard] [--dry-run] [--yes] [--force]"

FLEET_ROOT_ARG="$1"; shift
LEVEL="soft"; DRY=""; YES=0; FORCE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --soft)    LEVEL="soft"; shift ;;
    --hard)    LEVEL="hard"; shift ;;
    --dry-run) DRY="--dry-run"; shift ;;
    --yes|-y)  YES=1; shift ;;
    --force)   FORCE=1; shift ;;
    *) die "unknown flag: $1" ;;
  esac
done

command -v jq >/dev/null 2>&1 || die "jq required"

FLEET_ROOT="$(cd "${FLEET_ROOT_ARG}" 2>/dev/null && pwd)" || die "not a directory: ${FLEET_ROOT_ARG}"
[[ -f "${FLEET_ROOT}/fleet.json" ]] || die "fleet.json not found in ${FLEET_ROOT}"

if (( FORCE == 0 )); then
  reset_check_live "${FLEET_ROOT}" || exit 2
else
  [[ "${DRY}" == "--dry-run" ]] || reset_kill_live "${FLEET_ROOT}"
fi

FLEET_NAME="$(jq -r '.fleet_name // ""' "${FLEET_ROOT}/fleet.json")"
if [[ -n "${FLEET_NAME}" && "${DRY}" != "--dry-run" ]]; then
  if command -v tmux >/dev/null 2>&1 && tmux has-session -t "${FLEET_NAME}" 2>/dev/null; then
    tmux kill-session -t "${FLEET_NAME}" 2>/dev/null || true
  fi
fi

echo "[reset] level=${LEVEL}${DRY:+ (dry-run)} root=${FLEET_ROOT}"

case "${LEVEL}" in
  soft)
    reset_clear_flags     "${FLEET_ROOT}" ${DRY:+--dry-run}
    reset_archive_outputs "${FLEET_ROOT}" ${DRY:+--dry-run}
    reset_fleet_json      "${FLEET_ROOT}" ${DRY:+--dry-run}
    ;;
  hard)
    if [[ "${DRY}" != "--dry-run" ]]; then
      echo "[reset] WARNING: --hard will PERMANENTLY DELETE all logs, outputs, and archives."
      echo "[reset]          If you need logs, archive them first: cp -r ${FLEET_ROOT}/logs/ ./backup-logs/"
    fi
    reset_clear_flags "${FLEET_ROOT}" ${DRY:+--dry-run}
    reset_hard_wipe   "${FLEET_ROOT}" ${DRY:+--dry-run}
    reset_fleet_json  "${FLEET_ROOT}" ${DRY:+--dry-run}
    if [[ "${DRY}" != "--dry-run" ]]; then
      reset_unregister_fleet "${FLEET_ROOT}"
    fi
    ;;
esac

echo "[reset] done."
