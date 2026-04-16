#!/usr/bin/env bash
# status.sh — Fleet status dashboard
# Derives all status from session.jsonl files (no hooks needed)
#
# Usage: status.sh <fleet-root> [--json] [--watch]

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
GRAY='\033[0;37m'
BOLD='\033[1m'
NC='\033[0m'

usage() {
  echo "Usage: status.sh <fleet-root> [--json] [--watch]"
  echo "  --json   Output machine-readable JSON"
  echo "  --watch  Refresh every 5 seconds"
  exit 0
}

[[ "${1:-}" == "--help" || "${1:-}" == "-h" ]] && usage
[[ $# -lt 1 ]] && { echo "Error: missing fleet-root"; usage; }

# P4.3: resolve fleet name → root via registry, falling back to literal path
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/../lib/registry.sh" ]]; then
  # shellcheck disable=SC1091
  source "${SCRIPT_DIR}/../lib/registry.sh"
  FLEET_ROOT="$(registry_resolve "${1}")" || { echo "Error: fleet not found: ${1}" >&2; exit 1; }
else
  FLEET_ROOT="$(realpath "${1}")"
fi
shift
OPT_JSON=false
OPT_WATCH=false
OPT_VERBOSE=false
for arg in "$@"; do
  case "$arg" in
    --json)    OPT_JSON=true ;;
    --watch)   OPT_WATCH=true ;;
    -v|--verbose) OPT_VERBOSE=true ;;
  esac
done

[[ ! -d "${FLEET_ROOT}" ]] && { echo "Error: ${FLEET_ROOT} does not exist"; exit 1; }
FLEET_JSON="${FLEET_ROOT}/fleet.json"

show_status() {
  local now
  now=$(date +%s)

  # Get worker list from fleet.json or from workers/ dir
  local worker_ids=()
  if [[ -f "$FLEET_JSON" ]]; then
    while IFS= read -r wid; do
      worker_ids+=("$wid")
    done < <(jq -r '.workers[].id // empty' "$FLEET_JSON" 2>/dev/null)
  fi
  if [[ ${#worker_ids[@]} -eq 0 ]]; then
    for d in "${FLEET_ROOT}/workers"/*/; do
      [[ -d "$d" ]] && worker_ids+=("$(basename "$d")")
    done
  fi

  local total=0 running=0 done_count=0 failed=0 stuck=0 total_cost=0

  # Compute column widths from actual data so long IDs/models don't overflow
  local id_w=2 model_w=5
  for _wid in "${worker_ids[@]}"; do
    (( ${#_wid} > id_w )) && id_w=${#_wid}
    if [[ -f "$FLEET_JSON" ]]; then
      local _m
      _m=$(jq -r "(.workers[] | select(.id==\"$_wid\") | .model) // .config.model // \"?\"" "$FLEET_JSON" 2>/dev/null)
      local _e
      _e=$(jq -r "(.workers[] | select(.id==\"$_wid\") | .reasoning_effort) // .config.reasoning_effort // empty" "$FLEET_JSON" 2>/dev/null)
      [[ -n "$_e" ]] && _m="${_m}(${_e})"
      (( ${#_m} > model_w )) && model_w=${#_m}
    fi
  done
  (( id_w < 12 )) && id_w=12
  (( model_w < 10 )) && model_w=10
  local rule_w=$(( id_w + model_w + 60 ))
  (( rule_w < 100 )) && rule_w=100

  if [[ "$OPT_JSON" == "true" ]]; then
    echo "{"
    echo "  \"fleet_root\": \"${FLEET_ROOT}\","
    echo "  \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\","
    echo "  \"workers\": ["
  else
    echo -e "${BOLD}Fleet Status — $(date -u +"%Y-%m-%d %H:%M:%S UTC")${NC}"
    echo -e "Fleet root: ${CYAN}${FLEET_ROOT}${NC}"
    echo ""
    printf "${BOLD}${CYAN}%-${id_w}s  %-10s  %-${model_w}s  %-16s  %9s  %7s  %-s${NC}\n" \
      "ID" "STATUS" "MODEL" "LAST ACTIVITY" "COST" "RETRIES" "LAST MSG"
    printf "${BOLD}"; printf '─%.0s' $(seq 1 "$rule_w"); printf "${NC}\n"
  fi

  local first_json=true
  for wid in "${worker_ids[@]}"; do
    total=$((total + 1))
    local log="${FLEET_ROOT}/workers/${wid}/session.jsonl"
    local status_file="${FLEET_ROOT}/workers/${wid}/status.json"
    local status="PENDING" model="?" task="" cost="0" retries=0 ago_str="n/a"

    # Get task/model from fleet.json
    if [[ -f "$FLEET_JSON" ]]; then
      task=$(jq -r ".workers[] | select(.id==\"$wid\") | .task // \"\"" "$FLEET_JSON" 2>/dev/null)
      model=$(jq -r "(.workers[] | select(.id==\"$wid\") | .model) // .config.model // \"?\"" "$FLEET_JSON" 2>/dev/null)
      local effort
      effort=$(jq -r "(.workers[] | select(.id==\"$wid\") | .reasoning_effort) // .config.reasoning_effort // empty" "$FLEET_JSON" 2>/dev/null)
      [[ -n "$effort" ]] && model="${model}(${effort})"
    fi

    if [[ -f "$log" && -s "$log" ]]; then
      # Derive status from session.jsonl last event
      local last_type last_subtype
      last_type=$(tail -1 "$log" 2>/dev/null | jq -r '.type // ""' 2>/dev/null || echo "")
      last_subtype=$(tail -1 "$log" 2>/dev/null | jq -r '.subtype // ""' 2>/dev/null || echo "")

      if [[ "$last_type" == "result" ]]; then
        # Claude terminal event
        if [[ "$last_subtype" == "success" ]]; then
          status="DONE"
          done_count=$((done_count + 1))
        else
          status="FAILED"
          failed=$((failed + 1))
        fi
        cost=$(tail -1 "$log" 2>/dev/null | jq -r '.total_cost_usd // 0' 2>/dev/null || echo "0")
        cost=$(awk "BEGIN {printf \"%.2f\", ${cost}}")
      elif [[ "$last_type" == "turn.completed" ]]; then
        # Codex terminal success event
        status="DONE"
        done_count=$((done_count + 1))
        # Codex has no total_cost_usd — estimate from token usage
        cost=$(tail -1 "$log" 2>/dev/null | python3 -c "
import sys, json
line = sys.stdin.readline().strip()
if not line: print('0'); sys.exit()
ev = json.loads(line)
u = ev.get('usage', {})
inp = u.get('input_tokens', 0)
outp = u.get('output_tokens', 0)
c = (inp * 2.0 + outp * 8.0) / 1_000_000.0
print(f'{c:.2f}')
" 2>/dev/null || echo "0")
      elif [[ "$last_type" == "turn.failed" ]]; then
        # Codex terminal failure event
        status="FAILED"
        failed=$((failed + 1))
        cost="0"
      else
        status="RUNNING"
        running=$((running + 1))
        # For RUNNING workers, estimate cost from partial token data.
        # Claude: prefer prior result event, else estimate from assistant events.
        # Codex: estimate from turn.completed events (multi-turn sessions).
        prior_result_cost=$(grep '"type":"result"' "$log" 2>/dev/null | tail -1 | jq -r '.total_cost_usd // empty' 2>/dev/null || true)
        if [[ -n "${prior_result_cost:-}" ]]; then
          cost="$prior_result_cost"
        else
          cost=$(python3 - "$log" "$model" <<'PYEOF' 2>/dev/null || echo "0"
import json, sys
log, model = sys.argv[1], sys.argv[2]
# Claude pricing
prices = {
  "claude-haiku-4-5":   (1.0,  5.0),
  "claude-sonnet-4-5":  (3.0, 15.0),
  "claude-sonnet-4-6":  (3.0, 15.0),
}
# Codex pricing (conservative estimates)
codex_prices = {
  "gpt-5.4":       (2.0,  8.0),
  "gpt-5.4-mini":  (0.5,  2.0),
  "gpt-5.3-codex": (2.0,  8.0),
}
in_p, out_p = 3.0, 15.0
# Check codex models first
for k, v in codex_prices.items():
    if k in model:
        in_p, out_p = v
        break
else:
    for k, v in prices.items():
        if k in model or k.split("-",2)[-1] in model:
            in_p, out_p = v
            break
    if "haiku" in model.lower():
        in_p, out_p = prices["claude-haiku-4-5"]
inp = outp = 0
try:
    with open(log) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                ev = json.loads(line)
            except Exception:
                continue
            # Claude: assistant events with usage
            if ev.get("type") == "assistant":
                u = (ev.get("message") or {}).get("usage") or {}
                inp += int(u.get("input_tokens") or 0)
                outp += int(u.get("output_tokens") or 0)
            # Codex: turn.completed events with usage
            elif ev.get("type") == "turn.completed":
                u = ev.get("usage") or {}
                inp += int(u.get("input_tokens") or 0)
                outp += int(u.get("output_tokens") or 0)
except Exception:
    pass
cost = (inp * in_p + outp * out_p) / 1_000_000.0
print(f"{round(cost, 4)}")
PYEOF
)
          [[ -z "$cost" ]] && cost="0"
        fi
      fi

      # Subprocess liveness check (problems.md #4, #17): the claude worker may
      # have exited (so session.jsonl ends with a result event) while bash
      # subprocesses spawned via the Bash tool keep running detached. If any
      # descendant is still alive under this worker's dir, the worker is NOT
      # actually done — override DONE/FAILED back to RUNNING.
      #
      # EXCEPT for stale wrappers: if session.jsonl ends in a terminal result
      # AND its mtime is > 30s old, the descendants are zombie panes (asciinema
      # + bash; read from pre-P3.2 launches), not live work. Trust the result
      # event in that case.
      worker_dir="${FLEET_ROOT}/workers/${wid}"
      local has_live_descendants=false
      if pgrep -f "${worker_dir}" >/dev/null 2>&1; then
        local _log_age=999999
        if [[ -f "$log" ]]; then
          local _log_mtime
          _log_mtime=$(stat -c %Y "$log" 2>/dev/null || stat -f %m "$log" 2>/dev/null || echo "$now")
          _log_age=$((now - _log_mtime))
        fi
        # Only count as "really running" if the result is non-terminal
        # OR something has touched the log in the last 30s.
        if [[ "$last_type" != "result" && "$last_type" != "turn.completed" && "$last_type" != "turn.failed" || $_log_age -lt 30 ]]; then
          has_live_descendants=true
          if [[ "$status" == "DONE" ]]; then
            status="RUNNING"
            done_count=$((done_count - 1))
            running=$((running + 1))
          elif [[ "$status" == "FAILED" ]]; then
            status="RUNNING"
            failed=$((failed - 1))
            running=$((running + 1))
          fi
        fi
      fi

      # Last activity from mtime
      local mtime
      mtime=$(stat -c %Y "$log" 2>/dev/null || stat -f %m "$log" 2>/dev/null || echo "$now")
      local ago=$((now - mtime))

      if [[ $ago -lt 60 ]]; then
        ago_str="${ago}s ago"
      elif [[ $ago -lt 3600 ]]; then
        ago_str="$((ago / 60))m $((ago % 60))s ago"
      else
        ago_str="$((ago / 3600))h $((ago % 3600 / 60))m ago"
      fi

      # Stuck detection: running but no activity for >90s.
      # Skip if descendant subprocesses are alive — claude may have exited but
      # bash subprocesses are still doing work and don't write to session.jsonl.
      if [[ "$status" == "RUNNING" && $ago -gt 90 && "$has_live_descendants" != "true" ]]; then
        status="STUCK"
        stuck=$((stuck + 1))
        running=$((running - 1))
      fi

      # Count retries
      retries=$(grep -c '"api_retry"' "$log" 2>/dev/null || true)
      retries=${retries:-0}
      retries=$(echo "$retries" | tr -d '[:space:]')

      # Accumulate cost
      total_cost=$(python3 -c "print(round($total_cost + ${cost:-0}, 4))" 2>/dev/null || echo "$total_cost")
    fi

    # Latest activity snippet — assistant text, tool_use name, or final result
    local last_msg=""
    if [[ -f "$log" && -s "$log" ]]; then
      last_msg=$(tac "$log" 2>/dev/null | python3 -c '
import sys, json
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        ev = json.loads(line)
    except Exception:
        continue
    t = ev.get("type")
    # Claude terminal event
    if t == "result":
        st = ev.get("subtype", "")
        print(("✓ " if st == "success" else "✗ ") + (st or "result"))
        break
    # Codex terminal events
    if t == "turn.completed":
        print("✓ done")
        break
    if t == "turn.failed":
        err = (ev.get("error") or {}).get("message", "failed")[:50]
        print("✗ " + err)
        break
    # Claude assistant message
    if t == "assistant":
        msg = ev.get("message") or {}
        for c in (msg.get("content") or []):
            if c.get("type") == "text" and c.get("text", "").strip():
                txt = c["text"].strip().replace("\n", " ")
                print(txt)
                break
            if c.get("type") == "tool_use":
                name = c.get("name", "?")
                inp = c.get("input") or {}
                hint = ""
                for k in ("file_path", "path", "command", "url", "pattern"):
                    if k in inp:
                        hint = " " + str(inp[k])[:40]
                        break
                print(f"🔧 {name}{hint}")
                break
        else:
            continue
        break
    # Codex item events (agent_message, command_execution, web_search)
    if t == "item.completed":
        item = ev.get("item") or {}
        itype = item.get("type", "")
        if itype == "agent_message":
            txt = item.get("text", "").strip().replace("\n", " ")
            if txt:
                print(txt)
                break
        elif itype == "command_execution":
            cmd = item.get("command", "?")[:50]
            print(f"🔧 {cmd}")
            break
        elif itype == "web_search":
            q = item.get("query", "search")[:40]
            print(f"🔍 {q}")
            break
' 2>/dev/null || true)
    fi
    [[ -z "$last_msg" ]] && last_msg="—"
    local last_msg_short="${last_msg:0:60}"
    [[ ${#last_msg} -gt 60 ]] && last_msg_short="${last_msg_short}…"

    if [[ "$OPT_JSON" == "true" ]]; then
      [[ "$first_json" == "true" ]] && first_json=false || printf ",\n"
      local last_msg_json
      last_msg_json=$(printf '%s' "$last_msg_short" | jq -Rs . 2>/dev/null || echo '""')
      printf '    {"id":"%s","status":"%s","model":"%s","last_activity":"%s","cost":%s,"retries":%s,"last_msg":%s}' \
        "$wid" "$status" "$model" "$ago_str" "${cost:-0}" "$retries" "$last_msg_json"
    else
      local color="$GRAY"
      case "$status" in
        RUNNING) color="$GREEN" ;;
        DONE)    color="$GREEN" ;;
        FAILED)  color="$RED" ;;
        STUCK)   color="$YELLOW" ;;
        BLOCKED) color="$YELLOW" ;;
      esac
      local cost_fmt
      cost_fmt=$(printf '$%.2f' "${cost:-0}" 2>/dev/null || echo "\$$cost")
      printf "${color}%-${id_w}s  %-10s  %-${model_w}s  %-16s  %9s  %7s  %-s${NC}\n" \
        "$wid" "$status" "$model" "$ago_str" "$cost_fmt" "$retries" "$last_msg_short"

      # -v: extra sub-line per worker — lines/tail/outputs (cribbed from temp-status.sh)
      if [[ "$OPT_VERBOSE" == "true" && -f "$log" ]]; then
        local v_lines v_tail v_outs
        v_lines=$(wc -l <"$log" 2>/dev/null | tr -d '[:space:]')
        v_tail=$(tail -1 "$log" 2>/dev/null | jq -r '"\(.type)/\(.subtype // "-")"' 2>/dev/null || echo "?")
        v_outs=$(ls "${worker_dir}/output/" 2>/dev/null | tr '\n' ' ' | sed 's/ *$//')
        [[ -z "$v_outs" ]] && v_outs="(none)"
        printf "${GRAY}    ↳ lines=%s  tail=%s  outputs=%s${NC}\n" "$v_lines" "$v_tail" "$v_outs"
      fi
    fi
  done

  # P1.3: launcher liveness
  local launcher_pid="" launcher_alive=false
  if [[ -f "${FLEET_ROOT}/.launch.pid" ]]; then
    launcher_pid=$(cat "${FLEET_ROOT}/.launch.pid" 2>/dev/null | tr -d '[:space:]')
    if [[ -n "$launcher_pid" ]] && kill -0 "$launcher_pid" 2>/dev/null; then
      launcher_alive=true
    fi
  fi

  # Export counts for watch loop auto-exit
  _FLEET_RUNNING=$((running + stuck))
  _FLEET_TOTAL=$total
  _FLEET_DONE=$((done_count + failed))

  if [[ "$OPT_JSON" == "true" ]]; then
    echo ""
    echo "  ],"
    echo "  \"summary\": {\"total\":$total,\"running\":$running,\"done\":$done_count,\"failed\":$failed,\"stuck\":$stuck,\"total_cost\":$total_cost},"
    printf '  "liveness": {"launcher_pid":%s,"launcher_alive":%s}\n' \
      "${launcher_pid:-null}" "$launcher_alive"
    echo "}"
  else
    echo -e "${BOLD}$(printf '─%.0s' {1..100})${NC}"
    echo -e "${BOLD}Fleet Summary:${NC} Total: ${GRAY}${total}${NC}  Running: ${GREEN}${running}${NC}  Done: ${GREEN}${done_count}${NC}  Failed: ${RED}${failed}${NC}  Stuck: ${YELLOW}${stuck}${NC}  Total Cost: ${CYAN}\$${total_cost}${NC}"

    if [[ "$launcher_alive" == "true" ]]; then
      echo -e "launcher: ${GREEN}alive${NC} (pid ${launcher_pid})"
    else
      echo -e "launcher: ${GRAY}dead${NC}"
    fi
  fi
}

_FLEET_RUNNING=0
_FLEET_TOTAL=0

if [[ "$OPT_WATCH" == "true" ]]; then
  trap 'echo ""; exit 0' INT TERM
  while true; do
    clear
    show_status
    # Auto-exit when every worker has a terminal status (done or failed).
    # IMPORTANT: don't use running==0 alone — PENDING workers (not yet
    # started, empty session.jsonl) also have running=0 but are NOT done.
    # Killing the session prematurely aborts the fleet.
    if [[ $_FLEET_TOTAL -gt 0 && $_FLEET_DONE -eq $_FLEET_TOTAL ]]; then
      echo ""
      echo -e "${BOLD}Fleet complete — cleaning up tmux session.${NC}"
      # Kill the tmux session (session name = fleet_name from fleet.json)
      local_session=$(jq -r '.fleet_name // ""' "${FLEET_ROOT}/fleet.json" 2>/dev/null)
      if [[ -n "$local_session" ]]; then
        tmux kill-session -t "$local_session" 2>/dev/null || true
      fi
      exit 0
    fi
    sleep 5
  done
else
  show_status
fi
