#!/usr/bin/env bash
# status.sh — Iterative Fleet status dashboard
#
# Shows current iteration, per-worker status, reviewer verdict history, cost.
#
# Usage: status.sh <fleet-root> [--watch] [--json]

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
GRAY='\033[0;37m'
BOLD='\033[1m'
NC='\033[0m'

usage() {
  echo "Usage: status.sh <fleet-root> [--watch] [--json]"
  exit 0
}

[[ "${1:-}" == "--help" || "${1:-}" == "-h" ]] && usage
[[ $# -lt 1 ]] && { echo "Error: missing fleet-root" >&2; usage; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/registry.sh
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
for arg in "$@"; do
  case "$arg" in
    --json)  OPT_JSON=true ;;
    --watch) OPT_WATCH=true ;;
  esac
done

[[ ! -d "${FLEET_ROOT}" ]] && { echo "Error: ${FLEET_ROOT} does not exist" >&2; exit 1; }
FLEET_JSON="${FLEET_ROOT}/fleet.json"

show_status() {
  local now
  now=$(date +%s)

  local fleet_name iter lgtm_count is_paused
  fleet_name=$(jq -r '.fleet_name // "fleet"' "${FLEET_JSON}" 2>/dev/null || echo "fleet")
  iter=1
  lgtm_count=0
  is_paused=false

  # Read orchestrator state
  if [[ -f "${FLEET_ROOT}/.orch-state.json" ]]; then
    iter=$(jq -r '.current_iteration // 1' "${FLEET_ROOT}/.orch-state.json" 2>/dev/null || echo 1)
    lgtm_count=$(jq -r '.lgtm_count // 0' "${FLEET_ROOT}/.orch-state.json" 2>/dev/null || echo 0)
  fi

  [[ -f "${FLEET_ROOT}/.paused" ]] && is_paused=true

  # Fleet elapsed time from launched_at
  local fleet_elapsed_str="n/a"
  local launched_at
  launched_at=$(jq -r '.launched_at // ""' "${FLEET_JSON}" 2>/dev/null || echo "")
  if [[ -n "${launched_at}" && "${launched_at}" != "null" ]]; then
    local launch_epoch
    launch_epoch=$(date -u -d "${launched_at}" +%s 2>/dev/null || echo "")
    if [[ -n "${launch_epoch}" ]]; then
      local fleet_elapsed=$((now - launch_epoch))
      if [[ $fleet_elapsed -lt 60 ]]; then
        fleet_elapsed_str="${fleet_elapsed}s"
      elif [[ $fleet_elapsed -lt 3600 ]]; then
        fleet_elapsed_str="$((fleet_elapsed / 60))m $((fleet_elapsed % 60))s"
      else
        fleet_elapsed_str="$((fleet_elapsed / 3600))h $((fleet_elapsed % 3600 / 60))m"
      fi
    fi
  fi

  if [[ "$OPT_JSON" == "false" ]]; then
    echo -e "${BOLD}Iterative Fleet — $(date -u +"%Y-%m-%d %H:%M:%S UTC")${NC}"
    echo -e "Fleet:  ${CYAN}${fleet_name}${NC}  root: ${FLEET_ROOT}"
    echo -e "Status: $(if $is_paused; then echo -e "${YELLOW}PAUSED${NC}"; else echo -e "${GREEN}running${NC}"; fi)  Current iteration: ${BOLD}${iter}${NC}  LGTM count: ${BOLD}${lgtm_count}${NC}  Elapsed: ${BOLD}${fleet_elapsed_str}${NC}"
    echo ""
  fi

  # Per-worker status
  local worker_ids=()
  if [[ -f "$FLEET_JSON" ]]; then
    while IFS= read -r wid; do
      worker_ids+=("$wid")
    done < <(jq -r '.workers[].id // empty' "$FLEET_JSON" 2>/dev/null)
  fi

  local total_cost=0

  if [[ "$OPT_JSON" == "false" ]]; then
    printf "${BOLD}${CYAN}%-18s  %-10s  %-10s  %-12s  %9s  %-s${NC}\n" \
      "WORKER" "STATUS" "ELAPSED" "LAST ACTIVITY" "COST" "LAST MSG"
    printf "${BOLD}"; printf '─%.0s' $(seq 1 100); printf "${NC}\n"
  else
    echo '{"workers":['
    local first_json=true
  fi

  for wid in "${worker_ids[@]}"; do
    local log="${FLEET_ROOT}/workers/${wid}/session.jsonl"
    local status="PENDING" cost="0" ago_str="n/a" last_msg="—" elapsed_str="—"

    if [[ -f "$log" && -s "$log" ]]; then
      # Compute total elapsed time (file birth → last modified)
      local ctime mtime
      ctime=$(stat -c %W "$log" 2>/dev/null || echo "0")
      # %W returns 0 if birth time unavailable, fall back to change time
      [[ "$ctime" == "0" ]] && ctime=$(stat -c %Y "$log" 2>/dev/null || echo "$now")
      mtime=$(stat -c %Y "$log" 2>/dev/null || echo "$now")
      local elapsed=$((mtime - ctime))
      if [[ $elapsed -lt 0 ]]; then elapsed=0; fi
      if [[ $elapsed -lt 60 ]]; then
        elapsed_str="${elapsed}s"
      elif [[ $elapsed -lt 3600 ]]; then
        elapsed_str="$((elapsed / 60))m $((elapsed % 60))s"
      else
        elapsed_str="$((elapsed / 3600))h $((elapsed % 3600 / 60))m"
      fi
      local last_type
      last_type=$(tail -1 "$log" 2>/dev/null | jq -r '.type // ""' 2>/dev/null || echo "")
      local last_subtype
      last_subtype=$(tail -1 "$log" 2>/dev/null | jq -r '.subtype // ""' 2>/dev/null || echo "")

      if [[ "$last_type" == "result" ]]; then
        if [[ "$last_subtype" == "success" ]]; then
          status="DONE"
        else
          status="FAILED"
        fi
        cost=$(tail -1 "$log" 2>/dev/null | jq -r '.total_cost_usd // 0' 2>/dev/null || echo "0")
        cost=$(awk "BEGIN {printf \"%.2f\", ${cost}}")
      elif [[ "$last_type" == "turn.completed" ]]; then
        status="DONE"
        cost=$(tail -1 "$log" 2>/dev/null | python3 -c "
import sys, json
line = sys.stdin.readline().strip()
if not line: print('0'); sys.exit()
ev = json.loads(line)
u = ev.get('usage', {})
c = (u.get('input_tokens',0) * 2.0 + u.get('output_tokens',0) * 8.0) / 1_000_000.0
print(f'{c:.2f}')
" 2>/dev/null || echo "0")
      elif [[ "$last_type" == "turn.failed" ]]; then
        status="FAILED"; cost="0"
      else
        status="RUNNING"
      fi

      local mtime
      mtime=$(stat -c %Y "$log" 2>/dev/null || stat -f %m "$log" 2>/dev/null || echo "$now")
      local ago=$((now - mtime))
      if [[ $ago -lt 60 ]]; then
        ago_str="${ago}s ago"
      elif [[ $ago -lt 3600 ]]; then
        ago_str="$((ago / 60))m ago"
      else
        ago_str="$((ago / 3600))h $((ago % 3600 / 60))m ago"
      fi

      last_msg=$(tail -5 "$log" 2>/dev/null | python3 -c '
import sys, json
for line in sys.stdin:
    line = line.strip()
    if not line: continue
    try:
        ev = json.loads(line)
    except Exception:
        continue
    t = ev.get("type")
    if t == "result":
        st = ev.get("subtype","")
        print(("ok " if st == "success" else "err ") + (st or "result"))
        break
    if t == "turn.completed":
        print("ok done"); break
    if t == "turn.failed":
        err = (ev.get("error") or {}).get("message", "failed")[:40]
        print("err " + err); break
    if t == "assistant":
        msg = ev.get("message") or {}
        for c in (msg.get("content") or []):
            if c.get("type") == "text" and c.get("text","").strip():
                txt = c["text"].strip().replace("\n"," ")
                print(txt[:60])
                break
    if t == "item.completed":
        item = ev.get("item") or {}
        if item.get("type") == "agent_message":
            txt = item.get("text","").strip().replace("\n"," ")
            if txt: print(txt[:60]); break
' 2>/dev/null || echo "—")
      [[ -z "$last_msg" ]] && last_msg="—"
    fi

    total_cost=$(awk "BEGIN {printf \"%.2f\", ${total_cost} + ${cost:-0}}")

    if [[ "$OPT_JSON" == "true" ]]; then
      [[ "$first_json" == "true" ]] && first_json=false || printf ",\n"
      printf '  {"id":"%s","status":"%s","cost":%s,"elapsed":"%s","last_activity":"%s"}' \
        "$wid" "$status" "${cost:-0}" "$elapsed_str" "$ago_str"
    else
      local color="$GRAY"
      case "$status" in
        RUNNING) color="$GREEN" ;;
        DONE)    color="$GREEN" ;;
        FAILED)  color="$RED" ;;
        STUCK)   color="$YELLOW" ;;
      esac
      printf "${color}%-18s  %-10s  %-10s  %-12s  %9s  %-s${NC}\n" \
        "$wid" "$status" "$elapsed_str" "$ago_str" "\$${cost:-0}" "${last_msg:0:40}"
    fi
  done

  # Per-iteration history — walk iterations/*/workers/*/session.jsonl.
  if [[ "$OPT_JSON" == "false" && -d "${FLEET_ROOT}/iterations" ]]; then
    _fmt_dur() {
      local s=$1
      [[ $s -lt 0 ]] && s=0
      if   [[ $s -lt 60 ]];   then printf '%ds'       "$s"
      elif [[ $s -lt 3600 ]]; then printf '%dm %ds'   $((s/60)) $((s%60))
      else                         printf '%dh %dm'   $((s/3600)) $((s%3600/60))
      fi
    }
    local iter_dirs=()
    while IFS= read -r d; do iter_dirs+=("$d"); done < <(
      find "${FLEET_ROOT}/iterations" -maxdepth 1 -mindepth 1 -type d \
        -regextype posix-extended -regex '.*/iterations/[0-9]+' 2>/dev/null \
      | sort -t/ -k999 -V
    )
    local shown_iter_header=0
    local N
    for itd in "${iter_dirs[@]}"; do
      N=$(basename "$itd")
      local wdir="${itd}/workers"
      [[ -d "$wdir" ]] || continue
      # Gather per-worker jsonls
      local worker_lines=()
      local iter_min=0 iter_max=0
      local any_worker=0
      for sess in "${wdir}"/*/session.jsonl; do
        [[ -f "$sess" ]] || continue
        any_worker=1
        local wid; wid=$(basename "$(dirname "$sess")")
        local ct mt
        ct=$(stat -c %W "$sess" 2>/dev/null || echo 0)
        [[ "$ct" == "0" ]] && ct=$(stat -c %Y "$sess" 2>/dev/null || echo 0)
        mt=$(stat -c %Y "$sess" 2>/dev/null || echo 0)
        local dur=$((mt - ct))
        [[ $dur -lt 0 ]] && dur=0
        (( iter_min == 0 || ct < iter_min )) && iter_min=$ct
        (( mt > iter_max )) && iter_max=$mt
        local cost
        cost=$(tail -1 "$sess" 2>/dev/null | jq -r '.total_cost_usd // 0' 2>/dev/null || echo 0)
        cost=$(awk "BEGIN {printf \"\$%.2f\", ${cost}}")
        worker_lines+=("${wid}: $(_fmt_dur "$dur") ${cost}")
      done
      (( any_worker == 0 )) && continue
      if (( shown_iter_header == 0 )); then
        echo ""
        echo -e "${BOLD}Per-iteration history:${NC}"
        shown_iter_header=1
      fi
      local iter_span=$((iter_max - iter_min))
      printf "  ${BOLD}Iter %s${NC}  %-10s   " "$N" "$(_fmt_dur "$iter_span")"
      local IFS_OLD=$IFS; IFS='|'
      local joined="${worker_lines[*]}"; joined="${joined//|/   }"
      IFS=$IFS_OLD
      echo "$joined"
    done

    # In-progress iter: workers/<id>/session.jsonl present but not yet
    # snapshot into iterations/<current>/workers/.
    local cur_iter_dir="${FLEET_ROOT}/iterations/${iter}/workers"
    local cur_in_progress=0
    for wid in "${worker_ids[@]}"; do
      local live="${FLEET_ROOT}/workers/${wid}/session.jsonl"
      if [[ -f "$live" && ! -f "${cur_iter_dir}/${wid}/session.jsonl" ]]; then
        cur_in_progress=1; break
      fi
    done
    if (( cur_in_progress == 1 )); then
      if (( shown_iter_header == 0 )); then
        echo ""; echo -e "${BOLD}Per-iteration history:${NC}"; shown_iter_header=1
      fi
      printf "  ${BOLD}Iter %s${NC}  ${YELLOW}(in-progress)${NC}\n" "$iter"
    fi
  fi

  # Displaced repo warnings
  if [[ "$OPT_JSON" == "false" ]]; then
    local has_displaced=0
    for wid in "${worker_ids[@]}"; do
      local displaced_file="${FLEET_ROOT}/workers/${wid}/.displaced-repo"
      if [[ -f "$displaced_file" ]]; then
        if [[ "$has_displaced" -eq 0 ]]; then
          echo ""
          echo -e "${BOLD}${YELLOW}Displaced Repo Warnings:${NC}"
          has_displaced=1
        fi
        while IFS= read -r clone_path; do
          [[ -z "$clone_path" ]] && continue
          printf "  ${YELLOW}WARNING: %s committed to %s, not to repo root${NC}\n" "$wid" "$clone_path"
        done < "$displaced_file"
      fi
    done
  fi

  # Reviewer verdict history
  if [[ "$OPT_JSON" == "false" ]]; then
    echo ""
    echo -e "${BOLD}Reviewer Verdict History:${NC}"
    local found_verdicts=0
    local v=1
    while [[ -d "${FLEET_ROOT}/iterations/${v}" ]]; do
      local review_file="${FLEET_ROOT}/iterations/${v}/review.md"
      if [[ -f "$review_file" ]]; then
        local verdict
        verdict=$(grep -i "verdict:" "$review_file" 2>/dev/null | head -1 | \
          sed 's/.*verdict:[[:space:]]*//' | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]' || echo "pending")
        local verdict_color="$GRAY"
        case "$verdict" in
          lgtm)     verdict_color="$GREEN" ;;
          iterate)  verdict_color="$YELLOW" ;;
          escalate) verdict_color="$RED" ;;
        esac
        printf "  iter %-3s  ${verdict_color}%s${NC}\n" "${v}:" "$verdict"
        found_verdicts=1
      else
        printf "  iter %-3s  ${GRAY}(pending)${NC}\n" "${v}:"
      fi
      v=$((v + 1))
    done
    [[ "$found_verdicts" -eq 0 ]] && echo -e "  ${GRAY}(no verdicts yet)${NC}"

    echo ""
    echo -e "${BOLD}$(printf '─%.0s' {1..100})${NC}"
    echo -e "${BOLD}Total cost:${NC} ${CYAN}\$${total_cost}${NC}"
    if $is_paused; then
      echo -e "${YELLOW}Fleet is paused. Run pause.sh/resume.sh to control.${NC}"
    fi
  else
    echo ""
    echo "],"
    printf '"iteration":%d,"lgtm_count":%d,"paused":%s,"total_cost":%s\n' \
      "$iter" "$lgtm_count" "$is_paused" "$total_cost"
    echo "}"
  fi
}

if [[ "$OPT_WATCH" == "true" ]]; then
  trap 'echo ""; exit 0' INT TERM
  while true; do
    clear
    show_status
    sleep 5
  done
else
  show_status
fi
