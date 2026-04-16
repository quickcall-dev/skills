#!/usr/bin/env bash
# run-all.sh — codex provider equivalent of dag-fleet fixture tests.
# Drives scenarios CE, CG, CK, CL, CQ using fake-codex shim + provider:"codex" fleet.json.
#
# Usage:
#   run-all.sh <fleet-skill-dir>
#
# Where <fleet-skill-dir> is the path to skills/dag-fleet
#
# Exit code = number of failed scenarios.

set -u

if [[ $# -ne 1 ]]; then
  echo "usage: run-all.sh <fleet-skill-dir>" >&2
  exit 99
fi

SKILL_DIR="$(cd "$1" && pwd)"
SCRIPTS="${SKILL_DIR}/scripts"
FIXTURES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

for s in launch.sh kill.sh status.sh report.sh relaunch-worker.sh; do
  [[ -f "${SCRIPTS}/${s}" ]] || { echo "missing ${SCRIPTS}/${s}" >&2; exit 99; }
done

# Activate fake codex shim ahead of the real CLI.
export PATH="${FIXTURES_DIR}/shim:${PATH}"
if [[ "$(command -v codex)" != "${FIXTURES_DIR}/shim/codex" ]]; then
  echo "WARN: PATH override failed, codex resolves to $(command -v codex)" >&2
fi

PASS=()
FAIL=()

record() {
  local name="$1" status="$2" note="${3:-}"
  if [[ "$status" == "PASS" ]]; then
    PASS+=("$name")
    echo -e "\033[0;32m[PASS]\033[0m $name ${note}"
  else
    FAIL+=("$name")
    echo -e "\033[0;31m[FAIL]\033[0m $name ${note}"
  fi
}

cleanup_session() {
  local sess="$1"
  tmux has-session -t "$sess" 2>/dev/null && tmux kill-session -t "$sess" 2>/dev/null || true
}

cleanup_root() {
  local root="$1"
  pkill -f "FLEET_ROOT=${root}" 2>/dev/null || true
  sleep 1
  rm -rf "$root"
}

mkroot() {
  local tag="$1"
  local root="/tmp/fleet-test-codex-${tag}-$$"
  rm -rf "$root"
  mkdir -p "$root"
  echo "$root"
}

# -------------------------------------------------------------------
# Scenario CE — topo sort first wave (codex provider)
# Same as E but fleet.json has provider:"codex", shim emits codex JSONL
# -------------------------------------------------------------------
run_CE() {
  local root; root=$(mkroot dag-CE)
  bash "${FIXTURES_DIR}/setup-fleet.sh" dag "$root" >/dev/null
  bash "${SCRIPTS}/launch.sh" "$root" >"$root/launch.out" 2>&1 &
  local lpid=$!
  sleep 8
  local windows; windows=$(tmux list-windows -t fleet-test-dag-codex -F '#W' 2>/dev/null | grep -vx monitor | sort | tr '\n' ',' || true)
  if [[ "$windows" == *"a,"* && "$windows" == *"b,"* && "$windows" == *"d,"* && "$windows" == *"e,"* ]]; then
    record "CE topo-sort-first-wave (codex)" PASS "($windows)"
  else
    record "CE topo-sort-first-wave (codex)" FAIL "(got: $windows)"
    tail -5 "$root/launch.out" 2>/dev/null || true
  fi
  wait "$lpid" 2>/dev/null || true
  cleanup_session fleet-test-dag-codex
  cleanup_root "$root"
}

# -------------------------------------------------------------------
# Scenario CG — topo cycle detection (codex provider)
# -------------------------------------------------------------------
run_CG() {
  local root; root=$(mkroot cycle-CG)
  bash "${FIXTURES_DIR}/setup-fleet.sh" cycle "$root" >/dev/null
  bash "${SCRIPTS}/launch.sh" "$root" >"$root/launch.out" 2>&1
  local rc=$?
  local has_cycle_msg=0
  grep -q 'CYCLE:' "$root/launch.out" && has_cycle_msg=1
  local has_session=0
  tmux has-session -t fleet-test-cycle-codex 2>/dev/null && has_session=1
  if [[ "$rc" != "0" && "$has_cycle_msg" == "1" && "$has_session" == "0" ]]; then
    record "CG topo-cycle-detection (codex)" PASS
  else
    record "CG topo-cycle-detection (codex)" FAIL "(rc=$rc cycle_msg=$has_cycle_msg session=$has_session)"
    tail -10 "$root/launch.out" 2>/dev/null || true
  fi
  cleanup_session fleet-test-cycle-codex
  cleanup_root "$root"
}

# -------------------------------------------------------------------
# Scenario CK — pane auto-close .done sentinel (codex provider)
# Verify workers complete and .done files are created with codex JSONL
# -------------------------------------------------------------------
run_CK() {
  local root; root=$(mkroot completion-CK)
  bash "${FIXTURES_DIR}/setup-fleet.sh" completion "$root" >/dev/null
  bash "${SCRIPTS}/launch.sh" "$root" >"$root/launch.out" 2>&1 &
  local lpid=$!
  wait "$lpid" 2>/dev/null || true
  sleep 40
  local dones; dones=$(ls "$root"/workers/*/.done 2>/dev/null | wc -l)
  local remaining; remaining=$({ tmux list-windows -t fleet-test-completion-codex -F '#W' 2>/dev/null | grep -vxc monitor || true; } | head -1); remaining=${remaining:-0}
  if [[ "$dones" == "3" && "$remaining" == "0" ]]; then
    record "CK pane-auto-close .done sentinel (codex)" PASS
  else
    record "CK pane-auto-close .done sentinel (codex)" FAIL "(dones=$dones remaining=$remaining)"
  fi
  cleanup_session fleet-test-completion-codex
  cleanup_root "$root"
}

# -------------------------------------------------------------------
# Scenario CL — wedged-launcher fleet lock (codex provider)
# -------------------------------------------------------------------
run_CL() {
  local root; root=$(mkroot dag-CL)
  bash "${FIXTURES_DIR}/setup-fleet.sh" dag "$root" >/dev/null
  bash "${SCRIPTS}/launch.sh" "$root" >"$root/launch1.out" 2>&1 &
  local lpid=$!
  sleep 3
  bash "${SCRIPTS}/launch.sh" "$root" >"$root/launch2.out" 2>&1
  local rc=$?
  local pid_file_ok=0
  [[ -f "$root/.launch.pid" ]] && [[ "$(cat "$root/.launch.pid")" == "$lpid" ]] && pid_file_ok=1
  if [[ "$rc" == "2" && "$pid_file_ok" == "1" ]]; then
    record "CL wedged-launcher fleet lock (codex)" PASS
  else
    record "CL wedged-launcher fleet lock (codex)" FAIL "(rc=$rc pid_ok=$pid_file_ok)"
    tail -5 "$root/launch2.out" 2>/dev/null || true
  fi
  wait "$lpid" 2>/dev/null || true
  cleanup_session fleet-test-dag-codex
  cleanup_root "$root"
}

# -------------------------------------------------------------------
# Scenario CJSONL — codex JSONL events in session.jsonl
# Verify the shim's codex events are written and parseable by status.sh
# -------------------------------------------------------------------
run_CJSONL() {
  local root; root=$(mkroot completion-CJSONL)
  bash "${FIXTURES_DIR}/setup-fleet.sh" completion "$root" >/dev/null
  bash "${SCRIPTS}/launch.sh" "$root" >"$root/launch.out" 2>&1 &
  local lpid=$!
  wait "$lpid" 2>/dev/null || true
  # Wait for workers to finish
  local waited=0
  while [[ $waited -lt 30 ]]; do
    local done_count=0
    for w in w1 w2 w3; do
      if [[ -f "$root/workers/$w/session.jsonl" ]] \
         && grep -q '"type":"turn.completed"' "$root/workers/$w/session.jsonl" 2>/dev/null; then
        done_count=$((done_count+1))
      fi
    done
    [[ "$done_count" == "3" ]] && break
    sleep 2; waited=$((waited+2))
  done
  # Verify codex JSONL events
  local has_thread=0 has_turn_completed=0 has_item=0
  local jsonl="$root/workers/w1/session.jsonl"
  if [[ -f "$jsonl" ]]; then
    grep -q '"type":"thread.started"' "$jsonl" && has_thread=1
    grep -q '"type":"turn.completed"' "$jsonl" && has_turn_completed=1
    grep -q '"type":"item.completed"' "$jsonl" && has_item=1
  fi
  # Verify status.sh can parse it
  local status_ok=0
  bash "${SCRIPTS}/status.sh" "$root" --json >"$root/status.out" 2>&1 && status_ok=1
  if [[ "$has_thread" == "1" && "$has_turn_completed" == "1" && "$has_item" == "1" && "$status_ok" == "1" ]]; then
    record "CJSONL codex-jsonl-events-parseable" PASS
  else
    record "CJSONL codex-jsonl-events-parseable" FAIL "(thread=$has_thread turn_completed=$has_turn_completed item=$has_item status_ok=$status_ok)"
    [[ -f "$jsonl" ]] && head -5 "$jsonl" || echo "(no session.jsonl)"
  fi
  cleanup_session fleet-test-completion-codex
  cleanup_root "$root"
}

# -------------------------------------------------------------------
# Scenario CSTATUS — status.sh reports DONE for codex workers
# -------------------------------------------------------------------
run_CSTATUS() {
  local root; root=$(mkroot completion-CSTATUS)
  bash "${FIXTURES_DIR}/setup-fleet.sh" completion "$root" >/dev/null
  bash "${SCRIPTS}/launch.sh" "$root" >"$root/launch.out" 2>&1 &
  local lpid=$!
  wait "$lpid" 2>/dev/null || true
  # Wait for pane auto-close (default 30s sleep after .done) + extra buffer
  # so pgrep no longer finds descendant wrapper processes
  sleep 40
  local status_json
  status_json=$(bash "${SCRIPTS}/status.sh" "$root" --json 2>/dev/null || echo '{}')
  local done_count
  done_count=$(echo "$status_json" | python3 -c "
import sys, json
data = json.loads(sys.stdin.read())
workers = data.get('workers', [])
done = sum(1 for w in workers if w.get('status') == 'DONE')
print(done)
" 2>/dev/null || echo "0")
  if [[ "$done_count" == "3" ]]; then
    record "CSTATUS status.sh-reports-done-for-codex" PASS "(3/3 DONE)"
  else
    record "CSTATUS status.sh-reports-done-for-codex" FAIL "(done=$done_count/3)"
    echo "$status_json" | head -20
  fi
  cleanup_session fleet-test-completion-codex
  cleanup_root "$root"
}

# -------------------------------------------------------------------
# Scenario CC_FLAG — Codex -C flag uses git repo root, not fleet dir
# Bug 11: -C points to $FLEET_ROOT, but under workspace-write sandbox
# that makes the fleet dir the writable boundary. Builders can't write
# to repo files outside the fleet dir. Fix: resolve git repo root.
# -------------------------------------------------------------------
run_CC_FLAG() {
  # Create a fake git repo with fleet dir nested inside
  local repo; repo="/tmp/fleet-test-codex-cflag-$$"
  mkdir -p "$repo/src"
  git -C "$repo" init -q
  git -C "$repo" commit --allow-empty -m "init" -q

  local fleet_root="$repo/docs/fleet-root"
  bash "${FIXTURES_DIR}/setup-fleet.sh" completion "$fleet_root" >/dev/null
  # Patch fleet.json to use codex provider
  local tmp; tmp=$(mktemp)
  jq '.config.provider = "codex" | .config.model = "gpt-5.4-mini"' "$fleet_root/fleet.json" > "$tmp" && mv "$tmp" "$fleet_root/fleet.json"

  bash "${SCRIPTS}/launch.sh" "$fleet_root" >"$fleet_root/launch.out" 2>&1 &
  local lpid=$!
  sleep 4
  wait "$lpid" 2>/dev/null || true

  local ok=1
  for cmd_file in "$fleet_root"/.worker-cmd-*.sh; do
    [[ -f "$cmd_file" ]] || continue
    local c_flag
    c_flag=$(grep -oP "\-C '\\K[^']*" "$cmd_file" 2>/dev/null || echo "")
    [[ -z "$c_flag" ]] && continue
    # -C must be repo root, not fleet dir
    if [[ "$c_flag" == "$fleet_root" ]]; then
      ok=0
    fi
    if [[ "$c_flag" != "$repo" ]]; then
      ok=0
    fi
  done

  if [[ "$ok" == "1" ]]; then
    record "CC_FLAG codex-C-flag-uses-repo-root" PASS
  else
    record "CC_FLAG codex-C-flag-uses-repo-root" FAIL "(-C should be $repo)"
    for f in "$fleet_root"/.worker-cmd-*.sh; do
      echo "  -C: $(grep -oP "\-C '\\K[^']*" "$f" 2>/dev/null)" 2>/dev/null || true
    done
  fi
  cleanup_session fleet-test-completion-codex
  rm -rf "$repo" 2>/dev/null || true
}

# -------------------------------------------------------------------
# Scenario CC_NOGIT — Codex -C falls back when no git repo
# -------------------------------------------------------------------
run_CC_NOGIT() {
  local root; root=$(mkroot cflag-nogit)
  bash "${FIXTURES_DIR}/setup-fleet.sh" completion "$root" >/dev/null
  local tmp; tmp=$(mktemp)
  jq '.config.provider = "codex" | .config.model = "gpt-5.4-mini"' "$root/fleet.json" > "$tmp" && mv "$tmp" "$root/fleet.json"

  bash "${SCRIPTS}/launch.sh" "$root" >"$root/launch.out" 2>&1 &
  local lpid=$!
  sleep 4
  wait "$lpid" 2>/dev/null || true

  local ok=1
  for cmd_file in "$root"/.worker-cmd-*.sh; do
    [[ -f "$cmd_file" ]] || continue
    local c_flag
    c_flag=$(grep -oP "\-C '\\K[^']*" "$cmd_file" 2>/dev/null || echo "")
    [[ -z "$c_flag" ]] && continue
    if [[ "$c_flag" != "$root" ]]; then
      ok=0
    fi
  done

  if [[ "$ok" == "1" ]]; then
    record "CC_NOGIT codex-C-fallback-no-git" PASS
  else
    record "CC_NOGIT codex-C-fallback-no-git" FAIL
  fi
  cleanup_session fleet-test-completion-codex
  cleanup_root "$root"
}

run_CE
run_CG
run_CK
run_CL
run_CJSONL
run_CSTATUS
run_CC_FLAG
run_CC_NOGIT

echo
echo "============================================================"
echo "CODEX DAG-FLEET SUMMARY: ${#PASS[@]} passed, ${#FAIL[@]} failed"
echo "============================================================"
for p in "${PASS[@]}"; do echo "  PASS  $p"; done
for f in "${FAIL[@]}"; do echo "  FAIL  $f"; done

exit "${#FAIL[@]}"
