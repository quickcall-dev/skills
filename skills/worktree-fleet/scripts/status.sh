#!/usr/bin/env bash
# status.sh — Worktree Fleet Status
#
# Shows per-worktree progress, cost, and completion state derived
# from each worker's session.jsonl.
#
# Usage: status.sh <fleet-root|fleet-name> [--json]

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
GRAY='\033[0;37m'
BOLD='\033[1m'
NC='\033[0m'

usage() {
  echo "Usage: status.sh <fleet-root|fleet-name> [--json]"
  echo "  --json   Machine-readable JSON output"
  exit 0
}

[[ "${1:-}" == "--help" || "${1:-}" == "-h" ]] && usage
[[ $# -lt 1 ]] && { echo "Error: missing fleet-root"; usage; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/../lib"

# Source registry for name resolution
if [[ -f "${LIB_DIR}/registry.sh" ]]; then
  # shellcheck disable=SC1091
  source "${LIB_DIR}/registry.sh"
  FLEET_ROOT="$(registry_resolve "${1}")" || { echo "Error: fleet not found: ${1}" >&2; exit 1; }
else
  FLEET_ROOT="$(realpath "${1}")"
fi
shift

OPT_JSON=false
for arg in "$@"; do
  case "$arg" in
    --json) OPT_JSON=true ;;
  esac
done

[[ ! -d "${FLEET_ROOT}" ]] && { echo "Error: ${FLEET_ROOT} does not exist"; exit 1; }
FLEET_JSON="${FLEET_ROOT}/fleet.json"

# Resolve the log file for a worker.
# Pi workers write to .pi-sessions/*.jsonl while running; the session.jsonl
# symlink is only created after pi exits. For monitoring running workers we
# must fall back to the raw pi session file.
_resolve_log() {
  local wid="$1"
  local session_jsonl="${FLEET_ROOT}/workers/${wid}/session.jsonl"
  if [[ -f "$session_jsonl" && -s "$session_jsonl" ]]; then
    echo "$session_jsonl"
    return
  fi
  local pi_sessions="${FLEET_ROOT}/workers/${wid}/.pi-sessions"
  if [[ -d "$pi_sessions" ]]; then
    local newest
    newest=$(ls -t "$pi_sessions"/*.jsonl 2>/dev/null | head -1)
    if [[ -n "$newest" && -f "$newest" ]]; then
      echo "$newest"
      return
    fi
  fi
}

show_status() {
  local now
  now=$(date +%s)

  # Collect worker IDs from fleet.json or from workers/ dir
  local worker_ids=()
  if [[ -f "${FLEET_JSON}" ]]; then
    while IFS= read -r wid; do
      worker_ids+=("$wid")
    done < <(jq -r '.workers[].id // empty' "${FLEET_JSON}" 2>/dev/null)
  fi
  if [[ ${#worker_ids[@]} -eq 0 ]]; then
    for d in "${FLEET_ROOT}/workers"/*/; do
      [[ -d "$d" ]] && worker_ids+=("$(basename "$d")")
    done
  fi

  local total=0 running=0 done_count=0 failed=0 total_cost=0
  local id_w=12 branch_w=14

  # First pass: compute column widths
  for wid in "${worker_ids[@]}"; do
    (( ${#wid} > id_w )) && id_w=${#wid}
    if [[ -f "${FLEET_JSON}" ]]; then
      br=$(jq -r ".workers[] | select(.id==\"${wid}\") | .branch // \"?\"" "${FLEET_JSON}" 2>/dev/null)
      (( ${#br} > branch_w )) && branch_w=${#br}
    fi
  done

  # Fleet elapsed time from launched_at
  local elapsed_seconds=0 elapsed_str="n/a"
  if [[ -f "${FLEET_JSON}" ]]; then
    local launched_at
    launched_at=$(jq -r '.launched_at // empty' "${FLEET_JSON}" 2>/dev/null)
    if [[ -n "$launched_at" ]]; then
      local launch_epoch
      launch_epoch=$(date -d "$launched_at" +%s 2>/dev/null || echo 0)
      if [[ $launch_epoch -gt 0 ]]; then
        elapsed_seconds=$((now - launch_epoch))
        if [[ $elapsed_seconds -lt 60 ]]; then
          elapsed_str="${elapsed_seconds}s"
        elif [[ $elapsed_seconds -lt 3600 ]]; then
          elapsed_str="$((elapsed_seconds / 60))m $((elapsed_seconds % 60))s"
        else
          elapsed_str="$((elapsed_seconds / 3600))h $((elapsed_seconds % 3600 / 60))m"
        fi
      fi
    fi
  fi

  if [[ "${OPT_JSON}" == "true" ]]; then
    echo "{"
    printf '  "fleet_root": "%s",\n' "${FLEET_ROOT}"
    printf '  "timestamp": "%s",\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf '  "elapsed_seconds": %s,\n' "${elapsed_seconds}"
    echo '  "workers": ['
  else
    echo -e "${BOLD}Worktree Fleet Status — $(date -u +"%Y-%m-%d %H:%M:%S UTC")${NC}"
    echo -e "Fleet root: ${CYAN}${FLEET_ROOT}${NC}"
    [[ "$elapsed_str" != "n/a" ]] && echo -e "Elapsed: ${BOLD}${elapsed_str}${NC}"
    echo ""
    printf "${BOLD}${CYAN}%-${id_w}s  %-${branch_w}s  %-10s  %-10s  %-16s  %9s  %-s${NC}\n" \
      "ID" "BRANCH" "ELAPSED" "STATUS" "LAST ACTIVITY" "COST" "LAST MSG"
    printf "${BOLD}"; printf '─%.0s' $(seq 1 112); printf "${NC}\n"
  fi

  local first_json=true
  for wid in "${worker_ids[@]}"; do
    total=$((total + 1))
    local log
    log=$(_resolve_log "$wid")
    local status_file="${FLEET_ROOT}/workers/${wid}/status.json"
    local status="PENDING" branch="?" cost="0" ago_str="n/a" elapsed_str="n/a"

    if [[ -f "${FLEET_JSON}" ]]; then
      branch=$(jq -r ".workers[] | select(.id==\"${wid}\") | .branch // \"?\"" "${FLEET_JSON}" 2>/dev/null)
    fi

    # Read branch from status.json fallback
    if [[ "${branch}" == "?" && -f "${status_file}" ]]; then
      branch=$(jq -r '.branch // "?"' "${status_file}" 2>/dev/null || echo "?")
    fi

    if [[ -n "$log" && -f "$log" && -s "$log" ]]; then
      local last_type last_subtype
      last_type=$(tail -1 "${log}" 2>/dev/null | jq -r '.type // ""' 2>/dev/null || echo "")
      last_subtype=$(tail -1 "${log}" 2>/dev/null | jq -r '.subtype // ""' 2>/dev/null || echo "")

      if [[ "${last_type}" == "result" ]]; then
        if [[ "${last_subtype}" == "success" ]]; then
          status="DONE"; done_count=$((done_count + 1))
        else
          status="FAILED"; failed=$((failed + 1))
        fi
        cost=$(tail -1 "${log}" 2>/dev/null | jq -r '.total_cost_usd // 0' 2>/dev/null || echo "0")
        cost=$(awk "BEGIN {printf \"%.2f\", ${cost}}")
      elif [[ "${last_type}" == "turn.completed" ]]; then
        status="DONE"; done_count=$((done_count + 1))
        cost=$(tail -1 "${log}" 2>/dev/null | python3 -c "
import sys, json
line = sys.stdin.readline().strip()
if not line: print('0'); sys.exit()
ev = json.loads(line)
u = ev.get('usage', {})
c = (u.get('input_tokens',0) * 2.0 + u.get('output_tokens',0) * 8.0) / 1_000_000.0
print(f'{c:.2f}')
" 2>/dev/null || echo "0")
      elif [[ "${last_type}" == "turn.failed" ]]; then
        status="FAILED"; failed=$((failed + 1)); cost="0"
      elif [[ "${last_type}" == "message" ]]; then
        # Pi terminal or running event
        local role stop_reason
        role=$(tail -1 "${log}" 2>/dev/null | jq -r '.message.role // empty' 2>/dev/null || echo "")
        stop_reason=$(tail -1 "${log}" 2>/dev/null | jq -r '.message.stopReason // empty' 2>/dev/null || echo "")
        # Shared pi cost accumulator: sums usage from ALL assistant messages
        _pi_accumulate_cost() {
          python3 - "$1" <<'PYEOF' 2>/dev/null || echo "0"
import sys, json
log = sys.argv[1]
inp = outp = cache = 0
cost_total = 0.0
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
            if ev.get("type") == "message":
                msg = ev.get("message") or {}
                if msg.get("role") == "assistant":
                    u = msg.get("usage") or {}
                    c = u.get("cost", {}).get("total", 0)
                    if c and float(c) > 0:
                        cost_total += float(c)
                    else:
                        inp += int(u.get("input") or 0)
                        outp += int(u.get("output") or 0)
                        cache += int(u.get("cacheRead") or 0)
except Exception:
    pass
if cost_total > 0:
    print(f"{round(cost_total, 4)}")
else:
    cost = (inp * 3.0 + outp * 15.0 + cache * 0.30) / 1_000_000.0
    print(f"{round(cost, 4)}")
PYEOF
        }
        if [[ "$role" == "assistant" && "$stop_reason" == "stop" ]]; then
          status="DONE"; done_count=$((done_count + 1))
          cost=$(_pi_accumulate_cost "$log")
          [[ -z "$cost" ]] && cost="0"
        else
          status="RUNNING"; running=$((running + 1))
          cost=$(_pi_accumulate_cost "$log")
          [[ -z "$cost" ]] && cost="0"
        fi
      else
        status="RUNNING"; running=$((running + 1))
        # Estimate cost from streamed events (Claude + Codex)
        cost=$(python3 - "${log}" <<'PYEOF' 2>/dev/null || echo "0"
import json, sys
log = sys.argv[1]
inp = outp = 0
try:
    with open(log) as f:
        for line in f:
            line = line.strip()
            if not line: continue
            try: ev = json.loads(line)
            except: continue
            if ev.get("type") == "result":
                v = ev.get("total_cost_usd")
                if v is not None:
                    print(f"{round(float(v), 4)}")
                    sys.exit(0)
            if ev.get("type") == "assistant":
                u = (ev.get("message") or {}).get("usage") or {}
                inp += int(u.get("input_tokens") or 0)
                outp += int(u.get("output_tokens") or 0)
            if ev.get("type") == "turn.completed":
                u = ev.get("usage") or {}
                inp += int(u.get("input_tokens") or 0)
                outp += int(u.get("output_tokens") or 0)
except: pass
cost = (inp * 3.0 + outp * 15.0) / 1_000_000.0
print(f"{round(cost, 4)}")
PYEOF
)
        [[ -z "${cost}" ]] && cost="0"
      fi

      # Per-worker elapsed: file birth → last write = actual session duration
      local ctime mtime elapsed=0
      ctime=$(stat -c %W "${log}" 2>/dev/null || echo 0)
      [[ "$ctime" == "0" ]] && ctime=$(stat -c %Y "${log}" 2>/dev/null || echo "${now}")
      mtime=$(stat -c %Y "${log}" 2>/dev/null || stat -f %m "${log}" 2>/dev/null || echo "${now}")
      elapsed=$((mtime - ctime))
      [[ $elapsed -lt 0 ]] && elapsed=0
      if [[ $elapsed -lt 60 ]]; then
        elapsed_str="${elapsed}s"
      elif [[ $elapsed -lt 3600 ]]; then
        elapsed_str="$((elapsed / 60))m $((elapsed % 60))s"
      else
        elapsed_str="$((elapsed / 3600))h $((elapsed % 3600 / 60))m"
      fi

      # Last activity age
      local ago=$((now - mtime))
      if [[ $ago -lt 60 ]]; then
        ago_str="${ago}s ago"
      elif [[ $ago -lt 3600 ]]; then
        ago_str="$((ago / 60))m $((ago % 60))s ago"
      else
        ago_str="$((ago / 3600))h $((ago % 3600 / 60))m ago"
      fi

      # Accumulate cost
      total_cost=$(python3 -c "print(round(${total_cost} + ${cost:-0}, 4))" 2>/dev/null || echo "${total_cost}")
    fi

    # Last message snippet
    local last_msg=""
    if [[ -n "$log" && -f "$log" && -s "$log" ]]; then
      last_msg=$(tac "$log" 2>/dev/null | python3 -c '
import sys, json
for line in sys.stdin:
    line = line.strip()
    if not line: continue
    try: ev = json.loads(line)
    except: continue
    t = ev.get("type")
    if t == "result":
        st = ev.get("subtype", "")
        print(("done " if st == "success" else "fail ") + (st or "result"))
        break
    if t == "turn.completed":
        print("done")
        break
    if t == "turn.failed":
        err = (ev.get("error") or {}).get("message", "failed")[:50]
        print("fail " + err)
        break
    if t == "assistant":
        msg = ev.get("message") or {}
        for c in (msg.get("content") or []):
            if c.get("type") == "text" and c.get("text", "").strip():
                print(c["text"].strip().replace("\n", " "))
                break
            if c.get("type") == "tool_use":
                name = c.get("name", "?")
                inp = c.get("input") or {}
                hint = ""
                for k in ("file_path", "path", "command", "url", "pattern"):
                    if k in inp:
                        hint = " " + str(inp[k])[:40]
                        break
                print(f"{name}{hint}")
                break
        else: continue
        break
    if t == "item.completed":
        item = ev.get("item") or {}
        itype = item.get("type", "")
        if itype == "agent_message":
            txt = item.get("text", "").strip().replace("\n", " ")
            if txt: print(txt); break
        elif itype == "command_execution":
            print(item.get("command", "?")[:50]); break
        elif itype == "web_search":
            print("search: " + item.get("query", "")[:40]); break
' 2>/dev/null || true)
    fi
    [[ -z "${last_msg}" ]] && last_msg="—"
    local last_msg_short="${last_msg:0:55}"
    [[ ${#last_msg} -gt 55 ]] && last_msg_short="${last_msg_short}..."

    if [[ "${OPT_JSON}" == "true" ]]; then
      [[ "${first_json}" == "true" ]] && first_json=false || printf ",\n"
      local last_msg_json
      last_msg_json=$(printf '%s' "${last_msg_short}" | jq -Rs . 2>/dev/null || echo '""')
      printf '    {"id":"%s","branch":"%s","status":"%s","elapsed":"%s","last_activity":"%s","cost":%s,"last_msg":%s}' \
        "${wid}" "${branch}" "${status}" "${elapsed_str}" "${ago_str}" "${cost:-0}" "${last_msg_json}"
    else
      local color="${GRAY}"
      case "${status}" in
        RUNNING) color="${GREEN}" ;;
        DONE)    color="${GREEN}" ;;
        FAILED)  color="${RED}" ;;
        STUCK)   color="${YELLOW}" ;;
      esac
      local cost_fmt
      cost_fmt=$(printf '$%.2f' "${cost:-0}" 2>/dev/null || echo "\$${cost}")
      printf "${color}%-${id_w}s  %-${branch_w}s  %-10s  %-10s  %-16s  %9s  %-s${NC}\n" \
        "${wid}" "${branch}" "${elapsed_str}" "${status}" "${ago_str}" "${cost_fmt}" "${last_msg_short}"
    fi
  done

  if [[ "${OPT_JSON}" == "true" ]]; then
    echo ""
    echo "  ],"
    printf '  "summary": {"total":%s,"running":%s,"done":%s,"failed":%s,"total_cost":%s}\n' \
      "${total}" "${running}" "${done_count}" "${failed}" "${total_cost}"
    echo "}"
  else
    echo -e "${BOLD}$(printf '─%.0s' {1..100})${NC}"
    echo -e "${BOLD}Summary:${NC} Total: ${GRAY}${total}${NC}  Running: ${GREEN}${running}${NC}  Done: ${GREEN}${done_count}${NC}  Failed: ${RED}${failed}${NC}  Cost: ${CYAN}\$${total_cost}${NC}"
  fi
}

show_status
