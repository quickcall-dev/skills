#!/usr/bin/env bash
# setup-fake-iters.sh ROOT ITERS [--in-progress]
#
# Populate a fake iterative-fleet tree under ROOT with ITERS completed
# iterations. Each completed iter has iterations/{N}/workers/{a,b,c}/session.jsonl
# carrying a fake result event with total_cost_usd, plus iterations/{N}/review.md
# with verdict=iterate.
#
# --in-progress : also create workers/{a,b,c}/session.jsonl for an in-progress
#                 iter (ITERS+1) — mimics mid-iteration state.
set -euo pipefail

ROOT="${1:?usage: setup-fake-iters.sh ROOT ITERS [--in-progress]}"
ITERS="${2:?usage: setup-fake-iters.sh ROOT ITERS [--in-progress]}"
IN_PROGRESS=0
[[ "${3:-}" == "--in-progress" ]] && IN_PROGRESS=1

mkdir -p "${ROOT}"
cat >"${ROOT}/fleet.json" <<'JSON'
{
  "fleet_name": "iter-timing-test",
  "type": "iterative",
  "config": {"max_concurrent": 3, "model": "haiku", "provider": "claude"},
  "workers": [
    {"id": "tests",    "type": "code-run", "task": "t"},
    {"id": "impl",     "type": "code-run", "task": "i", "depends_on": ["tests"]},
    {"id": "reviewer", "type": "reviewer", "task": "r", "depends_on": ["impl"]}
  ],
  "stop_when": {"max_iterations": 10, "reviewer_lgtm_count": 1},
  "launched_at": "2026-04-20T10:00:00Z"
}
JSON

mkdir -p "${ROOT}/workers/tests" "${ROOT}/workers/impl" "${ROOT}/workers/reviewer"
for w in tests impl reviewer; do
  echo "fake $w prompt" >"${ROOT}/workers/${w}/prompt.md"
done

printf '{"current_iteration":%d,"lgtm_count":0,"status":"running"}\n' \
  "$((ITERS + IN_PROGRESS))" >"${ROOT}/.orch-state.json"

# Completed iterations — snapshots under iterations/{N}/workers/
n=1
while (( n <= ITERS )); do
  iter_dir="${ROOT}/iterations/${n}"
  mkdir -p "${iter_dir}/workers/tests" "${iter_dir}/workers/impl" "${iter_dir}/workers/reviewer"
  # tests worker — $0.02
  printf '{"type":"turn.started"}\n{"type":"result","subtype":"success","total_cost_usd":0.02}\n' \
    >"${iter_dir}/workers/tests/session.jsonl"
  # impl worker — $0.18
  printf '{"type":"turn.started"}\n{"type":"result","subtype":"success","total_cost_usd":0.18}\n' \
    >"${iter_dir}/workers/impl/session.jsonl"
  # reviewer — $0.04
  printf '{"type":"turn.started"}\n{"type":"result","subtype":"success","total_cost_usd":0.04}\n' \
    >"${iter_dir}/workers/reviewer/session.jsonl"
  # verdict
  echo "verdict: iterate" >"${iter_dir}/review.md"
  # offset mtimes so iter N has a distinct "duration" (N*60s span)
  # birth (ctime) = base, mtime = base + span
  base_ts=$(( 1713600000 + (n - 1) * 600 ))
  end_ts=$(( base_ts + n * 60 ))
  touch -d "@${base_ts}" "${iter_dir}/workers/tests/session.jsonl" 2>/dev/null || true
  touch -d "@${end_ts}"  "${iter_dir}/workers/impl/session.jsonl"  2>/dev/null || true
  touch -d "@${end_ts}"  "${iter_dir}/workers/reviewer/session.jsonl" 2>/dev/null || true
  n=$((n + 1))
done

# In-progress iter (session.jsonl still in workers/, not yet snapshot)
if (( IN_PROGRESS == 1 )); then
  printf '{"type":"turn.started"}\n' >"${ROOT}/workers/tests/session.jsonl"
  printf '{"type":"turn.started"}\n' >"${ROOT}/workers/impl/session.jsonl"
fi
