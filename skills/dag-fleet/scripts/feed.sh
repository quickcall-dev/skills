#!/usr/bin/env bash
# feed.sh — Tail the fleet event log with optional filters
# Usage: feed.sh <fleet-root> [--agent ID] [--type EVENT_TYPE] [--follow]
#
# Reads logs/fleet.jsonl and pretty-prints events using jq.
# Supports filtering by agent_id and event type.
# Without --follow, shows the last 50 events.
# With --follow (-f), streams new events in real time.

set -euo pipefail

# shellcheck source=../lib/registry.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/registry.sh"

# ---------------------------------------------------------------------------
# ANSI colors
# ---------------------------------------------------------------------------
C_RESET='\033[0m'
C_BOLD='\033[1m'
C_GREEN='\033[32m'
C_YELLOW='\033[33m'
C_RED='\033[31m'
C_GRAY='\033[90m'
C_CYAN='\033[36m'
C_WHITE='\033[37m'
C_MAGENTA='\033[35m'

# Default number of tail lines when not following
DEFAULT_TAIL_LINES=50

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

usage() {
  cat <<EOF
Usage: feed.sh <fleet-root> [OPTIONS]

Tail the fleet event log with optional filters.

Arguments:
  fleet-root      Path to the fleet root directory (contains fleet.json)

Options:
  --agent ID      Filter events by agent_id / worker_id (e.g. worker-01)
  --type TYPE     Filter events by event type (e.g. tool_use, api_retry)
  --follow, -f    Stream new events live (like tail -f)
  --lines N       Show last N events (default: $DEFAULT_TAIL_LINES, ignored with --follow)
  --help          Show this help message

Event log file:
  <fleet-root>/logs/fleet.jsonl

Examples:
  feed.sh /tmp/my-fleet
  feed.sh /tmp/my-fleet --agent worker-03
  feed.sh /tmp/my-fleet --type api_retry
  feed.sh /tmp/my-fleet --follow
  feed.sh /tmp/my-fleet --follow --agent worker-01 --type tool_use
  feed.sh /tmp/my-fleet --lines 100 --agent worker-02
EOF
  exit 0
}

die() {
  echo -e "${C_RED}ERROR: $*${C_RESET}" >&2
  exit 1
}

# Check that jq is available
require_jq() {
  if ! command -v jq &>/dev/null; then
    die "jq is required but not found. Install it with: apt install jq  OR  brew install jq"
  fi
}

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------

FLEET_ROOT=""
FILTER_AGENT=""
FILTER_TYPE=""
OPT_FOLLOW=false
TAIL_LINES="$DEFAULT_TAIL_LINES"

i=1
while (( i <= $# )); do
  arg="${!i}"
  case "$arg" in
    --help|-h)
      usage
      ;;
    --agent)
      (( i++ ))
      (( i <= $# )) || die "--agent requires an argument"
      FILTER_AGENT="${!i}"
      ;;
    --type)
      (( i++ ))
      (( i <= $# )) || die "--type requires an argument"
      FILTER_TYPE="${!i}"
      ;;
    --lines)
      (( i++ ))
      (( i <= $# )) || die "--lines requires an argument"
      TAIL_LINES="${!i}"
      [[ "$TAIL_LINES" =~ ^[0-9]+$ ]] || die "--lines must be a positive integer"
      ;;
    --follow|-f)
      OPT_FOLLOW=true
      ;;
    -*)
      die "Unknown option: $arg. Use --help for usage."
      ;;
    *)
      if [[ -z "$FLEET_ROOT" ]]; then
        FLEET_ROOT="$arg"
      else
        die "Unexpected argument: $arg. Use --help for usage."
      fi
      ;;
  esac
  (( i++ ))
done

[[ -n "$FLEET_ROOT" ]] || die "fleet-root is required. Use --help for usage."
FLEET_ROOT="$(registry_resolve "$FLEET_ROOT")" || die "fleet not found: $FLEET_ROOT"

FLEET_LOG="$FLEET_ROOT/logs/fleet.jsonl"
WORKERS_DIR="$FLEET_ROOT/workers"

require_jq

# ---------------------------------------------------------------------------
# Build jq filter
# ---------------------------------------------------------------------------
# We compose jq select() conditions based on the filters requested.

build_jq_filter() {
  local agent_filter="$1"
  local type_filter="$2"

  local conditions=()

  if [[ -n "$agent_filter" ]]; then
    # Match agent_id or worker_id field
    conditions+=("(.agent_id == \"$agent_filter\" or .worker_id == \"$agent_filter\")")
  fi

  if [[ -n "$type_filter" ]]; then
    # Match event, type, or subtype field
    conditions+=(
      "(.event == \"$type_filter\" or .type == \"$type_filter\" or .subtype == \"$type_filter\")"
    )
  fi

  if (( ${#conditions[@]} == 0 )); then
    echo "."
  elif (( ${#conditions[@]} == 1 )); then
    echo "select(${conditions[0]})"
  else
    local combined
    combined=$(printf " and %s" "${conditions[@]}")
    combined="${combined:5}"  # strip leading " and "
    echo "select($combined)"
  fi
}

# ---------------------------------------------------------------------------
# Pretty-print formatter (jq + colorized output)
# ---------------------------------------------------------------------------
# We pipe through jq with a custom format string to produce human-readable
# colored output. Because jq does not output ANSI by default in non-TTY
# contexts, we handle coloring via a compact jq format string that uses
# plain text delimiters and then color with ANSI codes in the shell.
#
# Strategy: use jq to extract structured fields, then do final formatting
# in a small Python script so we get richer coloring without complex jq
# string handling.

JQ_PRETTY_SCRIPT=$(cat <<'JQ_EOF'
{
  ts:       (.ts // .timestamp // "?"),
  agent_id: (.agent_id // .worker_id // "fleet"),
  event:    (.event // .type // "?"),
  subtype:  (.subtype // ""),
  tool:     (.tool // ""),
  error:    (.error // ""),
  extra:    del(.ts, .timestamp, .agent_id, .worker_id, .event, .type, .subtype, .tool, .error)
}
JQ_EOF
)

PYTHON_FORMAT=$(cat <<'PYEOF'
import json, sys

RESET   = "\033[0m"
BOLD    = "\033[1m"
GREEN   = "\033[32m"
YELLOW  = "\033[33m"
RED     = "\033[31m"
GRAY    = "\033[90m"
CYAN    = "\033[36m"
WHITE   = "\033[37m"
MAGENTA = "\033[35m"

for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        ev = json.loads(line)
    except Exception:
        print(f"  {GRAY}{line}{RESET}")
        continue

    ts      = str(ev.get("ts") or "?")
    aid     = str(ev.get("agent_id") or "?")
    event   = str(ev.get("event") or "?")
    subtype = str(ev.get("subtype") or "")
    tool    = str(ev.get("tool") or "")
    error   = str(ev.get("error") or "")
    extra   = ev.get("extra") or {}

    # --- Event color ---
    if "fail" in event.lower() or "error" in event.lower() or error:
        event_col = RED
    elif "complete" in event.lower() or "done" in event.lower() or \
         (subtype and "success" in subtype.lower()):
        event_col = GREEN
    elif "stuck" in event.lower() or "blocked" in event.lower() or \
         "retry" in event.lower() or "rate_limit" in event.lower():
        event_col = YELLOW
    elif "tool" in event.lower():
        event_col = MAGENTA
    else:
        event_col = WHITE

    # --- Format label ---
    if subtype:
        label = f"{event}/{subtype}"
    else:
        label = event

    if tool:
        label += f"({tool})"

    # --- Extra fields (show up to 4 key=value pairs) ---
    skip_keys = {"ts","timestamp","agent_id","worker_id","event","type","subtype","tool","error"}
    extra_parts = []
    for k, v in list(extra.items())[:4]:
        if k in skip_keys:
            continue
        vstr = json.dumps(v) if not isinstance(v, str) else v
        # Truncate long values
        if len(vstr) > 60:
            vstr = vstr[:57] + "..."
        extra_parts.append(f"{GRAY}{k}{RESET}={CYAN}{vstr}{RESET}")

    extra_str = "  " + "  ".join(extra_parts) if extra_parts else ""
    if error:
        extra_str += f"  {RED}error={error}{RESET}"

    # --- Timestamp (show only last 19 chars for HH:MM:SS) ---
    ts_short = ts[-19:] if len(ts) > 19 else ts

    print(f"{GRAY}{ts_short}{RESET}  {CYAN}{aid:<15}{RESET}  {event_col}{label:<30}{RESET}{extra_str}")
PYEOF
)

# ---------------------------------------------------------------------------
# Header
# ---------------------------------------------------------------------------

print_header() {
  printf "${C_BOLD}${C_WHITE}Fleet Event Log${C_RESET}"
  [[ -n "$FILTER_AGENT" ]] && printf "  ${C_CYAN}agent=%s${C_RESET}" "$FILTER_AGENT"
  [[ -n "$FILTER_TYPE" ]]  && printf "  ${C_CYAN}type=%s${C_RESET}" "$FILTER_TYPE"
  printf "\n"
  printf "${C_GRAY}Log: %s${C_RESET}\n" "$FLEET_LOG"
  printf "${C_BOLD}%0.s─${C_RESET}" {1..80}
  printf "\n"
}

# ---------------------------------------------------------------------------
# Main execution
# ---------------------------------------------------------------------------

JQ_FILTER=$(build_jq_filter "$FILTER_AGENT" "$FILTER_TYPE")

# ---------------------------------------------------------------------------
# Helper: emit tagged lines from all worker session logs
# ---------------------------------------------------------------------------

# Print all worker session.jsonl lines tagged with agent_id
worker_logs_tagged() {
  local log worker_id
  for log in "$WORKERS_DIR"/*/session.jsonl; do
    [[ -f "$log" ]] || continue
    worker_id=$(basename "$(dirname "$log")")
    jq --arg id "$worker_id" '. + {agent_id: $id}' "$log" 2>/dev/null
  done
}

# Collect list of worker session.jsonl files
worker_log_files() {
  local log
  for log in "$WORKERS_DIR"/*/session.jsonl; do
    [[ -f "$log" ]] && printf '%s\n' "$log"
  done
}

if [[ -f "$FLEET_LOG" ]]; then
  # -------------------------------------------------------------------------
  # Primary path: use fleet.jsonl
  # -------------------------------------------------------------------------
  if $OPT_FOLLOW; then
    print_header
    printf "${C_GRAY}Following fleet.jsonl... (Ctrl+C to stop)${C_RESET}\n\n"
    trap 'printf "\n${C_GRAY}Feed stopped.${C_RESET}\n"; exit 0' INT TERM
    tail -f "$FLEET_LOG" \
      | jq --unbuffered -c "$JQ_FILTER | $JQ_PRETTY_SCRIPT" 2>/dev/null \
      | python3 -c "$PYTHON_FORMAT"
  else
    print_header
    printf "${C_GRAY}Showing last %d events${C_RESET}\n\n" "$TAIL_LINES"
    local_count=$(tail -n "$TAIL_LINES" "$FLEET_LOG" \
      | jq -c "select($JQ_FILTER)" 2>/dev/null \
      | wc -l || echo 0)
    tail -n "$TAIL_LINES" "$FLEET_LOG" \
      | jq -c "select($JQ_FILTER) | $JQ_PRETTY_SCRIPT" 2>/dev/null \
      | python3 -c "$PYTHON_FORMAT"
    printf "\n${C_BOLD}%0.s─${C_RESET}" {1..80}
    printf "\n"
    printf "${C_GRAY}%d events shown" "$local_count"
    [[ -n "$FILTER_AGENT" ]] && printf " (agent=%s)" "$FILTER_AGENT"
    [[ -n "$FILTER_TYPE" ]]  && printf " (type=%s)" "$FILTER_TYPE"
    printf "${C_RESET}\n"
  fi
else
  # -------------------------------------------------------------------------
  # Fallback path: merge individual worker session logs
  # -------------------------------------------------------------------------

  # Check that at least one worker log exists
  mapfile -t _worker_logs < <(worker_log_files)
  if (( ${#_worker_logs[@]} == 0 )); then
    die "Fleet log not found: $FLEET_LOG\nNo worker session logs found in: $WORKERS_DIR"
  fi

  printf "${C_GRAY}Reading from %d worker session log(s)${C_RESET}\n" \
    "${#_worker_logs[@]}" >&2

  if $OPT_FOLLOW; then
    print_header
    printf "${C_GRAY}Following worker logs... (Ctrl+C to stop)${C_RESET}\n\n"
    trap 'printf "\n${C_GRAY}Feed stopped.${C_RESET}\n"; exit 0' INT TERM

    # Tag each line with agent_id as it streams in
    # Use a named pipe + background tail -f per worker log, all feeding a single jq pipeline
    TMPFIFO=$(mktemp -u)
    mkfifo "$TMPFIFO"
    trap 'rm -f "$TMPFIFO"; printf "\n${C_GRAY}Feed stopped.${C_RESET}\n"; exit 0' INT TERM

    # Launch one tail -f per worker log, tagging lines with agent_id via awk
    for log in "${_worker_logs[@]}"; do
      worker_id=$(basename "$(dirname "$log")")
      tail -f "$log" | awk -v id="$worker_id" '
        {
          # Attempt to inject agent_id into each JSON line
          if (sub(/^\{/, "{\"agent_id\":\"" id "\",")) print
          else print
        }
      ' >> "$TMPFIFO" &
    done

    cat "$TMPFIFO" \
      | jq --unbuffered -c "$JQ_FILTER | $JQ_PRETTY_SCRIPT" 2>/dev/null \
      | python3 -c "$PYTHON_FORMAT"

    rm -f "$TMPFIFO"
  else
    print_header
    printf "${C_GRAY}Showing last %d events (merged from worker logs)${C_RESET}\n\n" "$TAIL_LINES"

    # Merge all worker logs, tag with agent_id, sort by ts field if present, then filter
    merged=$(worker_logs_tagged \
      | jq -c 'if .ts then . else . + {ts: ""} end' 2>/dev/null \
      | sort -t'"' -k4,4)  # sort on ts value (simple lexicographic sort on JSON string)

    local_count=$(printf '%s\n' "$merged" \
      | tail -n "$TAIL_LINES" \
      | jq -c "select($JQ_FILTER)" 2>/dev/null \
      | wc -l || echo 0)

    printf '%s\n' "$merged" \
      | tail -n "$TAIL_LINES" \
      | jq -c "select($JQ_FILTER) | $JQ_PRETTY_SCRIPT" 2>/dev/null \
      | python3 -c "$PYTHON_FORMAT"

    printf "\n${C_BOLD}%0.s─${C_RESET}" {1..80}
    printf "\n"
    printf "${C_GRAY}%d events shown (worker logs)" "$local_count"
    [[ -n "$FILTER_AGENT" ]] && printf " (agent=%s)" "$FILTER_AGENT"
    [[ -n "$FILTER_TYPE" ]]  && printf " (type=%s)" "$FILTER_TYPE"
    printf "${C_RESET}\n"
  fi
fi
