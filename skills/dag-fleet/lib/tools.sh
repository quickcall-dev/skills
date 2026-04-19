#!/usr/bin/env bash
# lib/tools.sh — shared tool-restriction mapping per worker type
#
# Claude workers use --disallowed-tools (per-tool granularity).
# Codex workers use --sandbox modes + -c config overrides.

# ---------------------------------------------------------------------------
# Claude: disallowed tools per worker type
# ---------------------------------------------------------------------------
get_disallowed_tools() {
  local worker_type="$1"
  case "${worker_type}" in
    read-only)    echo "Bash,Edit,Write,Agent,WebFetch,WebSearch" ;;
    write)        echo "Bash,Agent,WebFetch,WebSearch" ;;
    code-run)     echo "Agent,WebFetch,WebSearch" ;;
    research)     echo "Bash,Edit,Agent" ;;
    reviewer)     echo "" ;;
    orchestrator) echo "Agent,WebFetch,WebSearch,Edit" ;;
    *)
      warn "Unknown worker type '${worker_type}', using read-only restrictions"
      echo "Bash,Edit,Write,Agent,WebFetch,WebSearch"
      ;;
  esac
}

# ---------------------------------------------------------------------------
# Codex: sandbox mode per worker type
#   read-only         = can read files, no shell writes
#   workspace-write   = can read/write files + run shell in workspace
#   danger-full-access = unrestricted (avoid)
#
# NOTE: read-only blocks ALL file writes including output.
# Workers that produce output files must use workspace-write.
# ---------------------------------------------------------------------------
get_codex_sandbox() {
  local worker_type="$1"
  case "${worker_type}" in
    read-only)    echo "read-only" ;;
    write)        echo "workspace-write" ;;
    code-run)     echo "workspace-write" ;;
    research)     echo "workspace-write" ;;
    reviewer)     echo "workspace-write" ;;
    orchestrator) echo "workspace-write" ;;
    *)
      warn "Unknown worker type '${worker_type}', using read-only sandbox"
      echo "read-only"
      ;;
  esac
}

# ---------------------------------------------------------------------------
# Codex: extra -c config flags per worker type
# Returns space-separated -c flags (empty string if none needed).
# ---------------------------------------------------------------------------
get_codex_extra_flags() {
  local worker_type="$1"
  local net_flag="-c 'sandbox_workspace_write.network_access=true'"
  case "${worker_type}" in
    research)              echo "-c 'web_search=\"live\"' ${net_flag}" ;;
    write|code-run|reviewer|orchestrator) echo "${net_flag}" ;;
    *)                     echo "" ;;
  esac
}
