#!/usr/bin/env bash
# run-all.sh — TDD tests for dag-fleet reset.sh.
#
# Usage:
#   run-all.sh <dag-fleet-skill-dir>
#
# Exit code = number of failed scenarios.
set -u

if [[ $# -ne 1 ]]; then
  echo "usage: run-all.sh <dag-fleet-skill-dir>" >&2
  exit 99
fi

SKILL_DIR="$(cd "$1" && pwd)"
RESET="${SKILL_DIR}/scripts/reset.sh"
FIXTURES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP="${FIXTURES_DIR}/setup-partial-run.sh"

[[ -f "${SETUP}" ]] || { echo "missing ${SETUP}" >&2; exit 99; }

PASS=()
FAIL=()

record() {
  local name="$1" status="$2" note="${3:-}"
  if [[ "$status" == "PASS" ]]; then
    PASS+=("$name")
    printf '\033[0;32m[PASS]\033[0m %s %s\n' "$name" "$note"
  else
    FAIL+=("$name")
    printf '\033[0;31m[FAIL]\033[0m %s %s\n' "$name" "$note"
  fi
}

mkroot() {
  local tag="$1"
  local root="/tmp/fleet-test-reset-${tag}-$$"
  rm -rf "$root"; mkdir -p "$root"
  echo "$root"
}

cleanup_root() {
  local root="$1"
  pkill -f "FLEET_ROOT=${root}" 2>/dev/null || true
  sleep 0.3
  rm -rf "$root"
}

check_reset_exists() {
  if [[ ! -x "${RESET}" ]]; then
    echo "NOTE: reset.sh missing at ${RESET} (expected during red phase)"
    return 1
  fi
  return 0
}

# ---------- R1 — --dry-run ----------
run_R1() {
  local root; root=$(mkroot R1)
  bash "${SETUP}" "$root"
  if ! check_reset_exists; then record R1 FAIL "reset.sh missing"; cleanup_root "$root"; return; fi

  local out rc
  out=$(bash "${RESET}" "$root" --dry-run --yes 2>&1); rc=$?

  local fail=""
  (( rc == 0 )) || fail+="exit=$rc; "
  [[ -d "${root}/workers/a" ]] || fail+="workers/a gone; "
  [[ -f "${root}/.launch.lock" ]] || fail+=".launch.lock gone; "
  grep -q '"status": "running"' "${root}/fleet.json" || fail+="fleet.json mutated; "
  grep -qi 'would' <<<"$out" || fail+="no 'would' preview; "

  [[ -z "$fail" ]] && record R1 PASS || record R1 FAIL "$fail"
  cleanup_root "$root"
}

# ---------- R2 — --soft ----------
run_R2() {
  local root; root=$(mkroot R2)
  bash "${SETUP}" "$root"
  if ! check_reset_exists; then record R2 FAIL "reset.sh missing"; cleanup_root "$root"; return; fi

  local rc; bash "${RESET}" "$root" --soft --yes >/dev/null 2>&1; rc=$?

  local fail=""
  (( rc == 0 )) || fail+="exit=$rc; "
  [[ -f "${root}/workers/a/prompt.md" ]] || fail+="prompt.md for a gone; "
  [[ -f "${root}/workers/b/prompt.md" ]] || fail+="prompt.md for b gone; "
  [[ ! -f "${root}/workers/a/session.jsonl" ]] || fail+="session.jsonl a still present; "
  [[ ! -f "${root}/workers/a/status.json" ]] || fail+="status.json a still present; "
  [[ ! -d "${root}/logs" ]] || fail+="logs/ still present; "
  [[ ! -f "${root}/.launch.lock" ]] || fail+=".launch.lock still present; "
  [[ ! -f "${root}/.launch.pid" ]] || fail+=".launch.pid still present; "
  # archive dir exist with subdirs
  local archive_count
  archive_count=$(find "${root}/archive" -maxdepth 2 -mindepth 2 -type d 2>/dev/null | wc -l)
  (( archive_count >= 1 )) || fail+="archive/<ts>/ not created; "
  # fleet.json: status removed, per-worker status removed
  if command -v jq >/dev/null 2>&1; then
    local s; s=$(jq -r '.status // "absent"' "${root}/fleet.json")
    [[ "$s" == "absent" ]] || fail+="fleet.status=$s; "
    local w; w=$(jq -r '.workers[0].status // "absent"' "${root}/fleet.json")
    [[ "$w" == "absent" ]] || fail+="worker[0].status=$w; "
  fi

  [[ -z "$fail" ]] && record R2 PASS || record R2 FAIL "$fail"
  cleanup_root "$root"
}

# ---------- R3 — --hard ----------
run_R3() {
  local root; root=$(mkroot R3)
  bash "${SETUP}" "$root"
  if ! check_reset_exists; then record R3 FAIL "reset.sh missing"; cleanup_root "$root"; return; fi

  local reg; reg=$(mktemp)
  printf '[{"name":"reset-test-dag","root":"%s","started_at":"2026-04-20T10:00:00Z","pid":12345}]' "$root" >"$reg"

  local rc; FLEET_REGISTRY_PATH="$reg" bash "${RESET}" "$root" --hard --yes >/dev/null 2>&1; rc=$?

  local fail=""
  (( rc == 0 )) || fail+="exit=$rc; "
  [[ -f "${root}/workers/a/prompt.md" ]] || fail+="prompt.md for a gone; "
  [[ -f "${root}/workers/b/prompt.md" ]] || fail+="prompt.md for b gone; "
  [[ ! -f "${root}/workers/a/session.jsonl" ]] || fail+="session.jsonl a still present; "
  [[ ! -d "${root}/logs" ]] || fail+="logs/ still present; "
  [[ ! -d "${root}/archive" ]] || fail+="archive/ still present; "
  [[ -f "${root}/fleet.json" ]] || fail+="fleet.json missing; "
  if command -v jq >/dev/null 2>&1; then
    local n; n=$(jq -r '.workers | length' "${root}/fleet.json" 2>/dev/null || echo X)
    [[ "$n" == "2" ]] || fail+="workers count=$n; "
  fi
  # registry unregistered
  if command -v jq >/dev/null 2>&1; then
    local found; found=$(jq --arg n reset-test-dag '[.[] | select(.name==$n)] | length' "$reg")
    [[ "$found" == "0" ]] || fail+="registry entry remains; "
  fi

  rm -f "$reg"
  [[ -z "$fail" ]] && record R3 PASS || record R3 FAIL "$fail"
  cleanup_root "$root"
}

# ---------- R4 — idempotent --soft ----------
run_R4() {
  local root; root=$(mkroot R4)
  mkdir -p "$root"
  cat >"${root}/fleet.json" <<'JSON'
{"fleet_name":"idem","type":"dag","config":{"model":"haiku","provider":"claude"},"workers":[]}
JSON
  if ! check_reset_exists; then record R4 FAIL "reset.sh missing"; cleanup_root "$root"; return; fi

  local rc; bash "${RESET}" "$root" --soft --yes >/dev/null 2>&1; rc=$?
  local fail=""
  (( rc == 0 )) || fail+="exit=$rc; "
  [[ ! -d "${root}/archive" ]] || fail+="archive/ created unexpectedly; "
  [[ -z "$fail" ]] && record R4 PASS || record R4 FAIL "$fail"
  cleanup_root "$root"
}

# ---------- R5 — live process refuse ----------
run_R5() {
  local root; root=$(mkroot R5)
  bash "${SETUP}" "$root"
  if ! check_reset_exists; then record R5 FAIL "reset.sh missing"; cleanup_root "$root"; return; fi

  bash -c "export FLEET_ROOT='$root' ; sleep 30 ; :" &
  local bg=$!
  sleep 0.3

  local out rc
  out=$(bash "${RESET}" "$root" --soft --yes 2>&1); rc=$?

  kill "$bg" 2>/dev/null || true
  wait "$bg" 2>/dev/null || true

  local fail=""
  (( rc == 2 )) || fail+="exit=$rc (want 2); "
  grep -qi 'live\|running\|kill' <<<"$out" || fail+="no live-process msg; "

  [[ -z "$fail" ]] && record R5 PASS || record R5 FAIL "$fail"
  cleanup_root "$root"
}

# ---------- R6 — --force kills live ----------
run_R6() {
  local root; root=$(mkroot R6)
  bash "${SETUP}" "$root"
  if ! check_reset_exists; then record R6 FAIL "reset.sh missing"; cleanup_root "$root"; return; fi

  bash -c "export FLEET_ROOT='$root' ; sleep 60 ; :" &
  local bg=$!
  sleep 0.3

  local rc; bash "${RESET}" "$root" --soft --yes --force >/dev/null 2>&1; rc=$?

  local fail=""
  (( rc == 0 )) || fail+="exit=$rc; "
  kill -0 "$bg" 2>/dev/null && fail+="bg process alive; "
  kill "$bg" 2>/dev/null || true
  wait "$bg" 2>/dev/null || true

  [[ -z "$fail" ]] && record R6 PASS || record R6 FAIL "$fail"
  cleanup_root "$root"
}

# ---------- R7 — missing fleet.json ----------
run_R7() {
  local root; root=$(mkroot R7)
  mkdir -p "$root"
  if ! check_reset_exists; then record R7 FAIL "reset.sh missing"; cleanup_root "$root"; return; fi

  local out rc; out=$(bash "${RESET}" "$root" --soft --yes 2>&1); rc=$?

  local fail=""
  (( rc == 1 )) || fail+="exit=$rc (want 1); "
  grep -qi 'fleet.json' <<<"$out" || fail+="no fleet.json error msg; "

  [[ -z "$fail" ]] && record R7 PASS || record R7 FAIL "$fail"
  cleanup_root "$root"
}

for t in R1 R2 R3 R4 R5 R6 R7; do run_$t; done

echo
echo "Passed: ${#PASS[@]}"
echo "Failed: ${#FAIL[@]}"
exit ${#FAIL[@]}
