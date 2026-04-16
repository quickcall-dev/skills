#!/usr/bin/env bash
# merge.sh — Worktree Fleet Merge Plan
#
# Prints a merge plan for all worker branches: files changed, line counts,
# potential conflicts. Does NOT auto-merge — the operator decides.
#
# Usage: merge.sh <fleet-root|fleet-name>

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
GRAY='\033[0;37m'
BOLD='\033[1m'
NC='\033[0m'

info()  { echo -e "${CYAN}[merge]${NC} $*"; }
warn()  { echo -e "${YELLOW}[merge]${NC} $*"; }
error() { echo -e "${RED}[merge]${NC} $*" >&2; }
die()   { error "$*"; exit 1; }

usage() {
  cat <<EOF
${BOLD}USAGE${NC}
  merge.sh <fleet-root|fleet-name>

${BOLD}DESCRIPTION${NC}
  Prints a merge plan showing, per worker branch:
    - Which files were changed
    - Lines added / deleted
    - Whether the branch is ahead of the base
    - Potential file-level conflicts with other branches

  This script NEVER auto-merges. The operator makes all merge decisions.
EOF
}

[[ "${1:-}" == "--help" || "${1:-}" == "-h" ]] && { usage; exit 0; }
[[ $# -lt 1 ]] && { error "Missing fleet-root"; usage; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/../lib"

if [[ -f "${LIB_DIR}/registry.sh" ]]; then
  # shellcheck disable=SC1091
  source "${LIB_DIR}/registry.sh"
  FLEET_ROOT="$(registry_resolve "${1}")" || { echo "Error: fleet not found: ${1}" >&2; exit 1; }
else
  FLEET_ROOT="$(realpath "${1}")"
fi

[[ ! -d "${FLEET_ROOT}" ]] && die "Fleet root does not exist: ${FLEET_ROOT}"
FLEET_JSON="${FLEET_ROOT}/fleet.json"
[[ ! -f "${FLEET_JSON}" ]] && die "fleet.json not found at ${FLEET_JSON}"

command -v git &>/dev/null || die "git is required"
command -v jq  &>/dev/null || die "jq is required"

GIT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || die "Not inside a git repo"
BASE_BRANCH=$(git -C "${GIT_ROOT}" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")

FLEET_NAME=$(jq -r '.fleet_name // "fleet"' "${FLEET_JSON}")
WORKER_COUNT=$(jq '.workers | length' "${FLEET_JSON}")

echo ""
echo -e "${BOLD}=== Worktree Fleet Merge Plan ===${NC}"
echo -e "Fleet:      ${CYAN}${FLEET_NAME}${NC}"
echo -e "Fleet root: ${FLEET_ROOT}"
echo -e "Base:       ${BOLD}${BASE_BRANCH}${NC}"
echo -e "Generated:  $(date -u +"%Y-%m-%d %H:%M:%S UTC")"
echo ""

# Collect all files changed per branch (for conflict detection)
declare -A BRANCH_FILES  # branch -> space-separated list of changed files

for i in $(seq 0 $((WORKER_COUNT - 1))); do
  wid=$(jq -r ".workers[${i}].id" "${FLEET_JSON}")
  branch=$(jq -r ".workers[${i}].branch // \"\"" "${FLEET_JSON}")
  task=$(jq -r ".workers[${i}].task // \"\"" "${FLEET_JSON}")
  wt_path="${FLEET_ROOT}/worktrees/${wid}"
  log="${FLEET_ROOT}/workers/${wid}/session.jsonl"

  echo -e "${BOLD}── Worker: ${wid}${NC}"
  echo -e "   Branch: ${CYAN}${branch}${NC}"
  echo -e "   Task:   ${task}"

  # Worker completion status
  if [[ -f "${log}" && -s "${log}" ]]; then
    last_type=$(tail -1 "${log}" 2>/dev/null | jq -r '.type // ""' 2>/dev/null || echo "")
    last_subtype=$(tail -1 "${log}" 2>/dev/null | jq -r '.subtype // ""' 2>/dev/null || echo "")
    if [[ "${last_type}" == "result" && "${last_subtype}" == "success" ]]; then
      echo -e "   Status: ${GREEN}DONE${NC}"
    elif [[ "${last_type}" == "result" ]]; then
      echo -e "   Status: ${RED}FAILED (${last_subtype})${NC}"
    else
      echo -e "   Status: ${YELLOW}RUNNING / INCOMPLETE${NC}"
    fi
  else
    echo -e "   Status: ${GRAY}NOT STARTED${NC}"
  fi

  # Check if branch exists
  if ! git -C "${GIT_ROOT}" rev-parse --verify "${branch}" &>/dev/null; then
    warn "   Branch '${branch}' does not exist in git yet"
    echo ""
    continue
  fi

  # Diff stats vs base
  if git -C "${GIT_ROOT}" rev-parse --verify "${BASE_BRANCH}" &>/dev/null; then
    diff_stat=$(git -C "${GIT_ROOT}" diff --stat "${BASE_BRANCH}...${branch}" 2>/dev/null || echo "(no diff available)")
    ahead=$(git -C "${GIT_ROOT}" rev-list --count "${BASE_BRANCH}..${branch}" 2>/dev/null || echo "?")
    behind=$(git -C "${GIT_ROOT}" rev-list --count "${branch}..${BASE_BRANCH}" 2>/dev/null || echo "?")
    echo -e "   Commits: ${GREEN}+${ahead}${NC} ahead, ${YELLOW}-${behind}${NC} behind ${BASE_BRANCH}"

    if [[ -n "${diff_stat}" && "${diff_stat}" != "(no diff available)" ]]; then
      echo "   Files changed:"
      git -C "${GIT_ROOT}" diff --name-status "${BASE_BRANCH}...${branch}" 2>/dev/null | \
        while IFS=$'\t' read -r status_code file_path; do
          case "${status_code}" in
            A) echo -e "     ${GREEN}+ ${file_path}${NC} (added)" ;;
            M) echo -e "     ${YELLOW}~ ${file_path}${NC} (modified)" ;;
            D) echo -e "     ${RED}- ${file_path}${NC} (deleted)" ;;
            R*) echo -e "     ${CYAN}> ${file_path}${NC} (renamed)" ;;
            *) echo -e "     ${GRAY}? ${file_path}${NC} (${status_code})" ;;
          esac
        done

      # Summary stat line
      ins_del=$(git -C "${GIT_ROOT}" diff --shortstat "${BASE_BRANCH}...${branch}" 2>/dev/null || echo "")
      [[ -n "${ins_del}" ]] && echo -e "   Summary: ${ins_del}"

      # Store file list for conflict detection
      changed_files=$(git -C "${GIT_ROOT}" diff --name-only "${BASE_BRANCH}...${branch}" 2>/dev/null | tr '\n' ' ')
      BRANCH_FILES["${branch}"]="${changed_files}"
    else
      echo -e "   ${GRAY}No changes vs ${BASE_BRANCH}${NC}"
      BRANCH_FILES["${branch}"]=""
    fi
  else
    echo -e "   ${GRAY}Cannot diff: base branch '${BASE_BRANCH}' not found${NC}"
    BRANCH_FILES["${branch}"]=""
  fi

  echo ""
done

# ---------------------------------------------------------------------------
# Cross-branch conflict detection
# ---------------------------------------------------------------------------
echo -e "${BOLD}=== Potential File Conflicts ===${NC}"
echo "(Files touched by more than one branch — review before merging)"
echo ""

# Invert: file -> list of branches that touch it
declare -A FILE_BRANCHES
for branch in "${!BRANCH_FILES[@]}"; do
  for f in ${BRANCH_FILES[${branch}]}; do
    if [[ -n "${FILE_BRANCHES[${f}]+_}" ]]; then
      FILE_BRANCHES["${f}"]="${FILE_BRANCHES[${f}]} ${branch}"
    else
      FILE_BRANCHES["${f}"]="${branch}"
    fi
  done
done

conflict_found=0
for f in "${!FILE_BRANCHES[@]}"; do
  branches="${FILE_BRANCHES[${f}]}"
  # Count unique branches
  branch_count=$(echo "${branches}" | tr ' ' '\n' | sort -u | wc -l)
  if [[ "${branch_count}" -gt 1 ]]; then
    echo -e "  ${RED}CONFLICT${NC}: ${f}"
    echo "${branches}" | tr ' ' '\n' | sort -u | while IFS= read -r b; do
      [[ -n "${b}" ]] && echo "    touched by: ${b}"
    done
    conflict_found=$((conflict_found + 1))
  fi
done

if [[ "${conflict_found}" -eq 0 ]]; then
  echo -e "  ${GREEN}No file-level conflicts detected.${NC}"
fi

echo ""
echo -e "${BOLD}=== Merge Instructions ===${NC}"
echo ""
echo "This script does NOT auto-merge. Choose your strategy:"
echo ""
echo "  Option A — merge each branch in sequence:"
for i in $(seq 0 $((WORKER_COUNT - 1))); do
  branch=$(jq -r ".workers[${i}].branch // \"?\"" "${FLEET_JSON}")
  echo "    git merge ${branch}"
done
echo ""
echo "  Option B — cherry-pick specific commits from each branch"
echo "  Option C — squash-merge: git merge --squash <branch>"
echo "  Option D — abandon a branch: git branch -d <branch>"
echo ""
echo "After merging, run cleanup:"
echo "  bash $(dirname "${BASH_SOURCE[0]}")/cleanup.sh ${FLEET_ROOT} --force"
echo ""
