#!/usr/bin/env bash
# test-compaction-terminal.sh — TDD regression for pi session compaction terminal detection
# Issue: when Pi compacts a session.jsonl, the last event is "compaction".
# dag-fleet status/dependency checks did not recognize it as terminal, so the
# worker was marked RUNNING/STUCK and blocked downstream dependents.
#
# Usage: run from repo root:
#   bash test/fleet/dag-fleet/test-compaction-terminal.sh

# Re-exec under Homebrew bash 4+ if available and current shell is older.
if [[ "${BASH_VERSINFO[0]}" -lt 4 ]] && [[ -x /opt/homebrew/bin/bash ]]; then
  exec /opt/homebrew/bin/bash "$0" "$@"
fi

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "${SCRIPT_DIR}/../../../skills/dag-fleet" && pwd)"
STATUS_SH="${SKILL_DIR}/scripts/status.sh"
DAG_SH="${SKILL_DIR}/lib/dag.sh"
LAUNCH_SH="${SKILL_DIR}/scripts/launch.sh"

for f in "$STATUS_SH" "$DAG_SH" "$LAUNCH_SH"; do
  [[ -f "$f" ]] || { echo "missing $f" >&2; exit 99; }
done

ROOT="/tmp/fleet-test-compaction-$$"
rm -rf "$ROOT"
mkdir -p "$ROOT/workers/w1/output"

cat > "$ROOT/fleet.json" <<'JSON'
{
  "fleet_name": "fleet-test-compaction",
  "max_concurrent": 1,
  "workers": [
    {
      "id": "w1",
      "task": "research",
      "provider": "pi",
      "model": "kimi-for-coding",
      "reasoning_effort": "medium",
      "max_budget_usd": 1.0
    },
    {
      "id": "w2",
      "task": "synthesis",
      "provider": "pi",
      "model": "kimi-for-coding",
      "reasoning_effort": "medium",
      "max_budget_usd": 1.0,
      "depends_on": ["w1"]
    }
  ]
}
JSON

cat > "$ROOT/workers/w1/session.jsonl" <<'JSONL'
{"type":"session","version":3,"id":"fake-session","timestamp":"2026-07-06T20:00:00Z","cwd":"/tmp"}
{"type":"message","id":"msg1","parentId":"mc1","timestamp":"2026-07-06T20:00:01Z","message":{"role":"assistant","content":[{"type":"text","text":"Task complete"}],"api":"anthropic-messages","provider":"fake-pi","model":"kimi-for-coding","usage":{"input":100,"output":50,"cacheRead":0,"cacheWrite":0,"totalTokens":150,"cost":{"input":0,"output":0,"cacheRead":0,"cacheWrite":0,"total":0}},"stopReason":"stop","timestamp":1783370401000}}
{"type":"compaction","id":"comp1","parentId":"msg1","timestamp":"2026-07-06T20:04:54Z","summary":"Fleet completed","firstKeptEntryId":"msg1","tokensBefore":150}
JSONL

PASS=0
FAIL=0

record() {
  local name="$1" status="$2"
  if [[ "$status" == "PASS" ]]; then
    PASS=$((PASS+1))
    echo -e "\033[0;32m[PASS]\033[0m $name"
  else
    FAIL=$((FAIL+1))
    echo -e "\033[0;31m[FAIL]\033[0m $name"
  fi
}

# Test 1: status.sh reports DONE for a session ending in compaction
status_done=$(bash "$STATUS_SH" "$ROOT" --json 2>/dev/null | jq -r '[.workers[] | select(.status == "DONE")] | length')
if [[ "$status_done" == "1" ]]; then
  record "status.sh compaction terminal => DONE" PASS
else
  record "status.sh compaction terminal => DONE" FAIL "(DONE count=$status_done)"
fi

# Test 2: dag_check_deps_done returns true for a dependency ending in compaction
if (
  # shellcheck source=/dev/null
  source "$DAG_SH"
  dag_check_deps_done "w2" "$ROOT" "$ROOT/fleet.json"
); then
  record "dag_check_deps_done compaction => true" PASS
else
  record "dag_check_deps_done compaction => true" FAIL
fi

# Test 3: launch.sh has_terminal_event recognizes compaction as terminal
if grep -qF '== "compaction" ]] && return 0' "$LAUNCH_SH" 2>/dev/null; then
  record "launch.sh has_terminal_event compaction check exists" PASS
else
  record "launch.sh has_terminal_event compaction check exists" FAIL
fi

rm -rf "$ROOT"

echo
echo "SUMMARY: $PASS passed, $FAIL failed"
exit "$FAIL"
