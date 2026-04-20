#!/usr/bin/env bash
# lib/worker-spawn.sh — shared INNER_CMD builder for worker spawning
#
# Supports two providers:
#   claude (default) — builds: cat prompt | claude -p --model X ...
#   codex            — builds: cat prompt | codex exec - -m X --json ...
#
# Usage:
#   source ../lib/worker-spawn.sh
#   INNER_CMD=$(build_inner_cmd \
#     --cwd "/path/to/workdir" \
#     --fleet-root "/path/to/fleet" \
#     --worker-id "worker-01" \
#     --worker-prompt "/path/to/prompt.md" \
#     --worker-model "sonnet" \
#     --fallback-model "haiku" \
#     [--max-turns 0] \
#     --max-budget 2.0 \
#     --session-name "fleet-myfleet-worker-01" \
#     --disallowed-tools "Agent,WebFetch,WebSearch" \
#     --session-jsonl "/path/to/session.jsonl" \
#     --worker-dir "/path/to/worker/dir" \
#     [--extra-exports "KEY=val KEY2=val2"] \
#     [--provider "codex"] \
#     [--reasoning-effort "medium"] \
#     [--codex-sandbox "workspace-write"] \
#     [--codex-extra-flags "-c 'web_search=\"live\"'"] \
#   )

# Validate that a value is safe for shell interpolation (alphanumeric, hyphens, underscores, dots)
validate_safe_id() {
  local label="$1" value="$2"
  if [[ ! "$value" =~ ^[a-zA-Z0-9._-]+$ ]]; then
    echo "FATAL: ${label} contains unsafe characters: '${value}'" >&2
    echo "  Only alphanumeric, hyphens, underscores, and dots are allowed." >&2
    return 1
  fi
}

build_inner_cmd() {
  local cwd="" fleet_root="" worker_id="" worker_prompt="" worker_model=""
  local fallback_model="" max_turns="" max_budget="" session_name=""
  local disallowed_tools="" session_jsonl="" worker_dir="" extra_exports=""
  local provider="claude" reasoning_effort="" codex_sandbox="" codex_extra_flags=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --cwd)               cwd="$2"; shift 2 ;;
      --fleet-root)        fleet_root="$2"; shift 2 ;;
      --worker-id)         worker_id="$2"; shift 2 ;;
      --worker-prompt)     worker_prompt="$2"; shift 2 ;;
      --worker-model)      worker_model="$2"; shift 2 ;;
      --fallback-model)    fallback_model="$2"; shift 2 ;;
      --max-turns)         max_turns="$2"; shift 2 ;;
      --max-budget)        max_budget="$2"; shift 2 ;;
      --session-name)      session_name="$2"; shift 2 ;;
      --disallowed-tools)  disallowed_tools="$2"; shift 2 ;;
      --session-jsonl)     session_jsonl="$2"; shift 2 ;;
      --worker-dir)        worker_dir="$2"; shift 2 ;;
      --extra-exports)     extra_exports="$2"; shift 2 ;;
      --provider)          provider="$2"; shift 2 ;;
      --reasoning-effort)  reasoning_effort="$2"; shift 2 ;;
      --codex-sandbox)     codex_sandbox="$2"; shift 2 ;;
      --codex-extra-flags) codex_extra_flags="$2"; shift 2 ;;
      *) shift ;;
    esac
  done

  # Validate inputs that get interpolated into shell commands
  validate_safe_id "worker-id" "${worker_id}" || return 1
  validate_safe_id "worker-model" "${worker_model}" || return 1
  [[ -n "${fallback_model}" ]] && { validate_safe_id "fallback-model" "${fallback_model}" || return 1; }
  [[ -n "${session_name}" ]] && { validate_safe_id "session-name" "${session_name}" || return 1; }

  local cmd="cd '${cwd}'"
  cmd+=" && unset CLAUDECODE 2>/dev/null || true"
  cmd+=" && export FLEET_ROOT='${fleet_root}'"
  cmd+=" && export WORKER_ID='${worker_id}'"
  cmd+=" && export WORKER_OUTPUT_DIR='${worker_dir}/output'"

  # Extra exports (e.g. WORKER_BRANCH for worktree-fleet)
  if [[ -n "${extra_exports}" ]]; then
    for kv in ${extra_exports}; do
      cmd+=" && export ${kv}"
    done
  fi

  if [[ "${provider}" == "codex" ]]; then
    _build_codex_cmd
  else
    _build_claude_cmd
  fi

  echo "${cmd}"
}

# ---------------------------------------------------------------------------
# Claude provider: cat prompt | claude -p --model X ...
# ---------------------------------------------------------------------------
_build_claude_cmd() {
  cmd+=" && cat '${worker_prompt}' | claude -p"
  cmd+=" --dangerously-skip-permissions"
  cmd+=" --output-format stream-json"
  cmd+=" --verbose"
  cmd+=" --model '${worker_model}'"
  if [[ "${worker_model}" != "${fallback_model}" ]]; then
    cmd+=" --fallback-model '${fallback_model}'"
  fi
  if [[ -n "${max_turns}" && "${max_turns}" != "0" ]]; then
    cmd+=" --max-turns ${max_turns}"
  fi
  cmd+=" --max-budget-usd ${max_budget}"
  cmd+=" --name '${session_name}'"
  if [[ -n "${reasoning_effort}" ]]; then
    cmd+=" --effort '${reasoning_effort}'"
  fi
  if [[ -n "${disallowed_tools}" ]]; then
    cmd+=" --disallowed-tools '${disallowed_tools}'"
  fi
  cmd+=" 2>&1 | tee '${session_jsonl}'"
}

# ---------------------------------------------------------------------------
# Codex provider: cat prompt | codex exec - -m X --json ...
# ---------------------------------------------------------------------------
_build_codex_cmd() {
  # Resolve git repo root for -C flag (writable sandbox boundary).
  # If cwd is inside a git repo, use the repo root so codex can write to all repo files.
  # Falls back to cwd if not in a git repo.
  local codex_project_root
  codex_project_root=$(git -C "${cwd}" rev-parse --show-toplevel 2>/dev/null || echo "${cwd}")

  cmd+=" && cat '${worker_prompt}' | codex exec -"
  cmd+=" -m '${worker_model}'"
  cmd+=" --json"
  cmd+=" --sandbox '${codex_sandbox:-workspace-write}'"
  cmd+=" -C '${codex_project_root}'"
  cmd+=" --ephemeral"
  cmd+=" --skip-git-repo-check"

  # Reasoning effort (codex-specific)
  if [[ -n "${reasoning_effort}" ]]; then
    cmd+=" -c 'model_reasoning_effort=\"${reasoning_effort}\"'"
  fi

  # Extra codex flags (e.g. web_search for research workers)
  if [[ -n "${codex_extra_flags}" ]]; then
    cmd+=" ${codex_extra_flags}"
  fi

  cmd+=" 2>&1 | tee '${session_jsonl}'"
}
