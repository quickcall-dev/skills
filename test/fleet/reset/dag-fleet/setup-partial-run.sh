#!/usr/bin/env bash
# setup-partial-run.sh — write a realistic partially-run dag-fleet tree at $1.
# Used by reset-tests run-all.sh.
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: setup-partial-run.sh <fleet-root>" >&2
  exit 99
fi

ROOT="$1"
mkdir -p "${ROOT}"/{workers/a,workers/b,logs,directives,shared}
mkdir -p "${ROOT}/workers/a/output" "${ROOT}/workers/b/output"

cat >"${ROOT}/fleet.json" <<'JSON'
{
  "fleet_name": "reset-test-dag",
  "type": "dag",
  "config": {
    "max_concurrent": 2,
    "model": "haiku",
    "fallback_model": "haiku",
    "provider": "claude"
  },
  "workers": [
    {"id": "a", "type": "code-run", "task": "t1", "max_budget_usd": 0.10, "status": "completed", "started_at": "2026-04-20T10:00:00Z", "session_name": "reset-test-dag"},
    {"id": "b", "type": "code-run", "task": "t2", "max_budget_usd": 0.10, "status": "running", "started_at": "2026-04-20T10:01:00Z", "session_name": "reset-test-dag"}
  ],
  "status": "running",
  "launched_at": "2026-04-20T10:00:00Z"
}
JSON

echo '{"type":"result","total_cost_usd":0.001}' >"${ROOT}/workers/a/session.jsonl"
echo '{"status":"completed"}' >"${ROOT}/workers/a/status.json"
echo '#!/bin/bash' >"${ROOT}/workers/a/.run.sh"
: >"${ROOT}/workers/a/.done"
echo "prompt for a" >"${ROOT}/workers/a/prompt.md"

echo '{"type":"turn.started"}' >"${ROOT}/workers/b/session.jsonl"
echo '{"status":"running"}' >"${ROOT}/workers/b/status.json"
echo '#!/bin/bash' >"${ROOT}/workers/b/.run.sh"
echo "prompt for b" >"${ROOT}/workers/b/prompt.md"

echo "sample tmux log" >"${ROOT}/logs/tmux-ops.log"
: >"${ROOT}/.launch.lock"
echo "99999" >"${ROOT}/.launch.pid"
