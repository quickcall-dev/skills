#!/usr/bin/env bash
# launch.sh — Worktree Fleet Launcher
#
# Reads fleet.json, validates target_files independence across workers,
# creates one git worktree per worker on its own branch, then spawns
# claude -p in a tmux window per worker.
#
# Usage:
#   launch.sh <fleet-root>            # validate + create worktrees + spawn
#   launch.sh <fleet-root> --dry-run  # validate only (exit 0 = OK, exit 2 = overlap)

set -euo pipefail

# ---------------------------------------------------------------------------
# Shared helpers
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/../lib"

# shellcheck source=../lib/logging.sh
source "${LIB_DIR}/logging.sh"
# shellcheck source=../lib/tools.sh
source "${LIB_DIR}/tools.sh"
# shellcheck source=../lib/worker-spawn.sh
source "${LIB_DIR}/worker-spawn.sh"

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------
usage() {
  cat <<EOF
${BOLD}USAGE${NC}
  launch.sh <fleet-root> [--dry-run]

${BOLD}DESCRIPTION${NC}
  Reads fleet.json from <fleet-root>, validates target_files independence
  across all workers, then creates one git worktree per worker on a fresh
  branch and spawns claude -p in a tmux window per worker.

${BOLD}FLAGS${NC}
  --dry-run   Validate independence only — no worktrees, no processes spawned.
              Exit 0 = all clear. Exit 2 = overlap detected.

${BOLD}FLEET.JSON FIELDS (worktree-fleet specific)${NC}
  workers[].target_files   Glob patterns this worker touches (required)
  workers[].branch         Git branch name for this worker's worktree (required)

${BOLD}WORKER TYPES & DISALLOWED TOOLS${NC}
  read-only    Bash, Edit, Write, Agent, WebFetch, WebSearch
  write        Bash, Agent, WebFetch, WebSearch
  code-run     Agent, WebFetch, WebSearch
  research     Bash, Edit, Agent
  reviewer     Bash, Edit, Agent, WebFetch, WebSearch
  orchestrator Agent, WebFetch, WebSearch, Edit
EOF
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage; exit 0
fi

DRY_RUN=0
POSITIONAL=()
for arg in "$@"; do
  case "${arg}" in
    --dry-run) DRY_RUN=1 ;;
    *) POSITIONAL+=("${arg}") ;;
  esac
done
set -- "${POSITIONAL[@]}"

if [[ $# -lt 1 ]]; then
  error "Missing required argument: fleet-root"
  echo ""; usage; exit 1
fi

FLEET_ROOT="${1}"
FLEET_ROOT="$(realpath "${FLEET_ROOT}")"

# ---------------------------------------------------------------------------
# Validate prerequisites
# ---------------------------------------------------------------------------
if [[ ! -d "${FLEET_ROOT}" ]]; then
  die "Fleet root does not exist: ${FLEET_ROOT}"
fi

FLEET_JSON="${FLEET_ROOT}/fleet.json"
if [[ ! -f "${FLEET_JSON}" ]]; then
  die "fleet.json not found at: ${FLEET_JSON}"
fi

command -v jq  &>/dev/null || die "jq is required but not installed"
command -v git &>/dev/null || die "git is required but not installed"
if [[ "${DRY_RUN}" -eq 0 ]]; then
  command -v tmux &>/dev/null || die "tmux is required but not installed"
fi

# ---------------------------------------------------------------------------
# Source registry helper (optional — graceful if absent)
# ---------------------------------------------------------------------------
if [[ -f "${LIB_DIR}/registry.sh" ]]; then
  # shellcheck disable=SC1091
  source "${LIB_DIR}/registry.sh"
fi

# ---------------------------------------------------------------------------
# Parse fleet.json
# ---------------------------------------------------------------------------
info "Reading fleet.json from: ${FLEET_ROOT}"

FLEET_NAME=$(jq -r '.fleet_name // "fleet"' "${FLEET_JSON}")
MAX_CONCURRENT=$(jq -r '.config.max_concurrent // 5' "${FLEET_JSON}")
DEFAULT_MODEL=$(jq -r '.config.model // "sonnet"' "${FLEET_JSON}")
FALLBACK_MODEL=$(jq -r '.config.fallback_model // "haiku"' "${FLEET_JSON}")
DEFAULT_PROVIDER=$(jq -r '.config.provider // "claude"' "${FLEET_JSON}")
DEFAULT_REASONING_EFFORT=$(jq -r '.config.reasoning_effort // ""' "${FLEET_JSON}")
LAUNCH_DELAY=$(jq -r '.config.launch_delay_seconds // 2' "${FLEET_JSON}")
WORKER_COUNT=$(jq '.workers | length' "${FLEET_JSON}")

# Validate fleet.json inputs against shell injection
validate_fleet_id "fleet_name" "${FLEET_NAME}"
validate_fleet_id "model" "${DEFAULT_MODEL}"
validate_fleet_id "fallback_model" "${FALLBACK_MODEL}"
validate_fleet_id "provider" "${DEFAULT_PROVIDER}"
for _wid in $(jq -r '.workers[].id' "${FLEET_JSON}"); do
  validate_fleet_id "worker_id" "${_wid}"
done

# Validate required CLI tools based on provider
if [[ "${DRY_RUN}" -eq 0 ]]; then
  if [[ "${DEFAULT_PROVIDER}" == "codex" ]]; then
    command -v codex &>/dev/null || die "codex CLI is required but not found in PATH"
  else
    command -v claude &>/dev/null || die "claude CLI is required but not found in PATH"
  fi
fi

info "Fleet: ${BOLD}${FLEET_NAME}${NC} (${WORKER_COUNT} workers, max_concurrent=${MAX_CONCURRENT})"

# ---------------------------------------------------------------------------
# Validate required per-worker fields
# ---------------------------------------------------------------------------
for i in $(seq 0 $((WORKER_COUNT - 1))); do
  wid=$(jq -r ".workers[${i}].id" "${FLEET_JSON}")
  branch=$(jq -r ".workers[${i}].branch // \"\"" "${FLEET_JSON}")
  tf_count=$(jq ".workers[${i}].target_files | length" "${FLEET_JSON}" 2>/dev/null || echo 0)
  if [[ -z "${branch}" || "${branch}" == "null" ]]; then
    die "Worker '${wid}' is missing required field: branch"
  fi
  if [[ "${tf_count}" -eq 0 ]]; then
    die "Worker '${wid}' is missing required field: target_files (must be a non-empty array)"
  fi
done

# ---------------------------------------------------------------------------
# Independence validation — check for overlapping target_files across workers
# ---------------------------------------------------------------------------
info "Validating target_files independence..."

OVERLAP_FOUND=0
OVERLAP_DETAILS=""

# Build list of (worker_id, normalized_file) pairs
# For each file, check if any other worker also claims it
# We do exact-string overlap on the declared globs (not glob expansion —
# the declared globs themselves must not share any literal path).
CONFLICT=$(python3 - "${FLEET_JSON}" <<'PYEOF'
import json, sys, fnmatch, itertools

with open(sys.argv[1]) as f:
    data = json.load(f)

workers = data.get("workers", [])

# For each worker, collect their target_files list
entries = []
for w in workers:
    wid = w.get("id", "?")
    tfs = w.get("target_files", [])
    entries.append((wid, tfs))

# Check every pair of workers for overlapping target_files patterns.
# Two patterns overlap if they share any literal path, OR if one pattern
# is identical to another, OR one fnmatch-matches the other (bidirectional).
conflicts = []
for (wid_a, tfs_a), (wid_b, tfs_b) in itertools.combinations(entries, 2):
    for pa in tfs_a:
        for pb in tfs_b:
            if pa == pb or fnmatch.fnmatch(pa, pb) or fnmatch.fnmatch(pb, pa):
                conflicts.append(f"{wid_a}:{pa} <-> {wid_b}:{pb}")

if conflicts:
    for c in conflicts:
        print(f"CONFLICT: {c}")
    sys.exit(2)
else:
    print("OK")
    sys.exit(0)
PYEOF
) || OVERLAP_FOUND=$?

if [[ "${OVERLAP_FOUND}" -ne 0 ]]; then
  error "Independence validation FAILED — overlapping target_files detected:"
  echo "${CONFLICT}" | grep "CONFLICT:" | while IFS= read -r line; do
    error "  ${line}"
  done
  error ""
  error "Two workers cannot touch the same file. Fix the task split before launching."
  error "Overlapping workers and their target_files are shown above."
  exit 2
fi

success "Independence validation passed — no overlap in target_files"

if [[ "${DRY_RUN}" -eq 1 ]]; then
  success "Dry-run complete — validated ${WORKER_COUNT} workers, no overlap detected"
  exit 0
fi

# ---------------------------------------------------------------------------
# Resolve the git repo root (worktrees must be created relative to it)
# ---------------------------------------------------------------------------
# Find the git root from FLEET_ROOT or cwd
GIT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || die "Not inside a git repository. worktree-fleet requires a git repo."
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")
info "Git root: ${GIT_ROOT} (current branch: ${CURRENT_BRANCH})"

# ---------------------------------------------------------------------------
# Create fleet directory structure
# ---------------------------------------------------------------------------
mkdir -p "${FLEET_ROOT}/workers"
mkdir -p "${FLEET_ROOT}/worktrees"
mkdir -p "${FLEET_ROOT}/logs"

# ---------------------------------------------------------------------------
# Register in fleet registry (if available)
# ---------------------------------------------------------------------------
if declare -f registry_register >/dev/null 2>&1; then
  registry_register "${FLEET_ROOT}" "${FLEET_NAME}" "$$" || true
fi

# ---------------------------------------------------------------------------
# Create tmux session
# ---------------------------------------------------------------------------
TMUX_SESSION="${FLEET_NAME}"

if tmux has-session -t "${TMUX_SESSION}" 2>/dev/null; then
  info "tmux session '${TMUX_SESSION}' exists — killing stale session"
  tmux kill-session -t "${TMUX_SESSION}" 2>/dev/null || true
fi

info "Creating tmux session: ${TMUX_SESSION}"
tmux new-session -d -s "${TMUX_SESSION}" -n "monitor" -x 220 -y 50
tmux send-keys -t "${TMUX_SESSION}:monitor" \
  "bash '${SCRIPT_DIR}/status.sh' '${FLEET_ROOT}'" C-m

# ---------------------------------------------------------------------------
# Phase 1: Create all git worktrees (independent of prompt.md availability)
# ---------------------------------------------------------------------------
info "Creating git worktrees for ${WORKER_COUNT} workers..."

for i in $(seq 0 $((WORKER_COUNT - 1))); do
  WORKER_ID=$(jq -r ".workers[${i}].id" "${FLEET_JSON}")
  WORKER_BRANCH=$(jq -r ".workers[${i}].branch" "${FLEET_JSON}")
  WORKER_TASK=$(jq -r ".workers[${i}].task // \"\"" "${FLEET_JSON}")
  WORKER_DIR="${FLEET_ROOT}/workers/${WORKER_ID}"
  WORKER_WORKTREE="${FLEET_ROOT}/worktrees/${WORKER_ID}"

  mkdir -p "${WORKER_DIR}/output"

  # Create initial status.json
  local_ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  cat > "${WORKER_DIR}/status.json" <<EOF
{
  "worker_id": "${WORKER_ID}",
  "branch": "${WORKER_BRANCH}",
  "worktree": "${WORKER_WORKTREE}",
  "status": "PENDING",
  "task": "${WORKER_TASK}",
  "last_updated": "${local_ts}"
}
EOF

  # Create git worktree on a new branch
  info "Creating worktree for ${WORKER_ID} on branch '${WORKER_BRANCH}'..."
  if git -C "${GIT_ROOT}" worktree list --porcelain 2>/dev/null | grep -q "^worktree ${WORKER_WORKTREE}$"; then
    warn "Worktree at ${WORKER_WORKTREE} already exists — skipping worktree creation"
  else
    # Create branch from current HEAD if it doesn't exist
    if git -C "${GIT_ROOT}" rev-parse --verify "${WORKER_BRANCH}" &>/dev/null; then
      warn "Branch '${WORKER_BRANCH}' already exists — adding worktree against it"
      git -C "${GIT_ROOT}" worktree add "${WORKER_WORKTREE}" "${WORKER_BRANCH}" 2>/dev/null || \
        die "Failed to create worktree for ${WORKER_ID}"
    else
      git -C "${GIT_ROOT}" worktree add -b "${WORKER_BRANCH}" "${WORKER_WORKTREE}" 2>/dev/null || \
        die "Failed to create worktree for ${WORKER_ID}"
    fi
  fi
  success "  Worktree: ${WORKER_WORKTREE} (branch: ${WORKER_BRANCH})"
done

# ---------------------------------------------------------------------------
# Phase 2: Spawn workers (skip those without prompt.md)
# ---------------------------------------------------------------------------
info "Spawning workers in tmux..."

_launch_seq=0
for i in $(seq 0 $((WORKER_COUNT - 1))); do
  _launch_seq=$((_launch_seq + 1))

  WORKER_ID=$(jq -r ".workers[${i}].id" "${FLEET_JSON}")
  WORKER_TYPE=$(jq -r ".workers[${i}].type // \"code-run\"" "${FLEET_JSON}")
  WORKER_MODEL=$(jq -r ".workers[${i}].model // \"${DEFAULT_MODEL}\"" "${FLEET_JSON}")
  WORKER_PROVIDER=$(jq -r ".workers[${i}].provider // \"${DEFAULT_PROVIDER}\"" "${FLEET_JSON}")
  WORKER_REASONING_EFFORT=$(jq -r ".workers[${i}].reasoning_effort // \"${DEFAULT_REASONING_EFFORT}\"" "${FLEET_JSON}")
  MAX_TURNS=$(jq -r ".workers[${i}].max_turns // 0" "${FLEET_JSON}")

  # Worktree workers always need Bash for git commit — override restrictive types (claude only)
  if [[ "${WORKER_PROVIDER}" != "codex" ]]; then
    if [[ "${WORKER_TYPE}" == "read-only" || "${WORKER_TYPE}" == "write" || "${WORKER_TYPE}" == "reviewer" ]]; then
      warn "Worker '${WORKER_ID}' type '${WORKER_TYPE}' disallows Bash — overriding to 'code-run' (worktree workers need git)"
      WORKER_TYPE="code-run"
    fi
  fi
  MAX_BUDGET=$(jq -r ".workers[${i}].max_budget_usd // 1.00" "${FLEET_JSON}")
  WORKER_TASK=$(jq -r ".workers[${i}].task // \"\"" "${FLEET_JSON}")
  WORKER_BRANCH=$(jq -r ".workers[${i}].branch" "${FLEET_JSON}")

  WORKER_DIR="${FLEET_ROOT}/workers/${WORKER_ID}"
  WORKER_PROMPT="${WORKER_DIR}/prompt.md"
  WORKER_SESSION_JSONL="${WORKER_DIR}/session.jsonl"
  WORKER_WORKTREE="${FLEET_ROOT}/worktrees/${WORKER_ID}"

  # Skip spawning if no prompt.md — worktree is already created above
  if [[ ! -f "${WORKER_PROMPT}" ]]; then
    warn "No prompt.md for ${WORKER_ID} at ${WORKER_PROMPT} — worktree created but not spawning worker"
    continue
  fi

  # Build INNER_CMD via shared helper
  DISALLOWED_TOOLS=$(get_disallowed_tools "${WORKER_TYPE}")
  CODEX_SANDBOX=$(get_codex_sandbox "${WORKER_TYPE}")
  CODEX_EXTRA=$(get_codex_extra_flags "${WORKER_TYPE}")
  SESSION_NAME="worktree-${FLEET_NAME}-${WORKER_ID}"

  INNER_CMD=$(build_inner_cmd \
    --cwd "${WORKER_WORKTREE}" \
    --fleet-root "${FLEET_ROOT}" \
    --worker-id "${WORKER_ID}" \
    --worker-prompt "${WORKER_PROMPT}" \
    --worker-model "${WORKER_MODEL}" \
    --fallback-model "${FALLBACK_MODEL}" \
    --max-turns "${MAX_TURNS}" \
    --max-budget "${MAX_BUDGET}" \
    --session-name "${SESSION_NAME}" \
    --disallowed-tools "${DISALLOWED_TOOLS}" \
    --session-jsonl "${WORKER_SESSION_JSONL}" \
    --worker-dir "${WORKER_DIR}" \
    --extra-exports "WORKER_BRANCH='${WORKER_BRANCH}'" \
    --provider "${WORKER_PROVIDER}" \
    --reasoning-effort "${WORKER_REASONING_EFFORT}" \
    --codex-sandbox "${CODEX_SANDBOX}" \
    --codex-extra-flags "${CODEX_EXTRA}" \
  )
  INNER_CMD+="; touch '${WORKER_DIR}/.done'; sleep 30"

  # Spawn tmux window
  tmux new-window -t "${TMUX_SESSION}" -n "${WORKER_ID}" \
    "bash -c \"${INNER_CMD}\""

  # Update status to RUNNING
  local_ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  cat > "${WORKER_DIR}/status.json" <<EOF
{
  "worker_id": "${WORKER_ID}",
  "branch": "${WORKER_BRANCH}",
  "worktree": "${WORKER_WORKTREE}",
  "status": "RUNNING",
  "task": "${WORKER_TASK}",
  "last_updated": "${local_ts}"
}
EOF

  success "  Spawned: ${TMUX_SESSION}:${WORKER_ID} (model=${WORKER_MODEL})"

  # Staggered delay
  if [[ "${_launch_seq}" -lt "${WORKER_COUNT}" ]]; then
    sleep "${LAUNCH_DELAY}"
  fi
done

# Update fleet.json overall status
local_ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
tmp_fleet=$(mktemp "${FLEET_ROOT}/.tmp.fleet.XXXXXX")
jq --arg ts "${local_ts}" \
   '.status = "running" | .launched_at = $ts' \
   "${FLEET_JSON}" > "${tmp_fleet}"
mv "${tmp_fleet}" "${FLEET_JSON}"

echo ""
success "Fleet '${BOLD}${FLEET_NAME}${NC}${GREEN}' launched!"
echo ""
info "Attach to session:  ${BOLD}tmux attach -t ${TMUX_SESSION}${NC}"
info "Status:             ${BOLD}bash ${SCRIPT_DIR}/status.sh ${FLEET_ROOT}${NC}"
info "Merge plan:         ${BOLD}bash ${SCRIPT_DIR}/merge.sh ${FLEET_ROOT}${NC}"
info "Cleanup:            ${BOLD}bash ${SCRIPT_DIR}/cleanup.sh ${FLEET_ROOT} --force${NC}"
echo ""
