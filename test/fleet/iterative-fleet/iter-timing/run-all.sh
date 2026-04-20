#!/usr/bin/env bash
# run-all.sh — iterative-fleet per-iteration timing tests.
#
# Usage: run-all.sh <iterative-fleet-skill-dir>
#
# Exit code = number of failed scenarios.
set -u

if [[ $# -ne 1 ]]; then
  echo "usage: run-all.sh <iterative-fleet-skill-dir>" >&2
  exit 99
fi

SKILL_DIR="$(cd "$1" && pwd)"
STATUS="${SKILL_DIR}/scripts/status.sh"
FIXTURES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP="${FIXTURES_DIR}/setup-fake-iters.sh"

[[ -f "${STATUS}" ]] || { echo "missing ${STATUS}" >&2; exit 99; }
[[ -f "${SETUP}" ]]  || { echo "missing ${SETUP}" >&2; exit 99; }

PASS=()
FAIL=()

record() {
  local name="$1" status="$2" note="${3:-}"
  if [[ "$status" == "PASS" ]]; then
    PASS+=("$name"); printf '\033[0;32m[PASS]\033[0m %s %s\n' "$name" "$note"
  else
    FAIL+=("$name"); printf '\033[0;31m[FAIL]\033[0m %s %s\n' "$name" "$note"
  fi
}

mkroot() {
  local tag="$1"
  local root="/tmp/fleet-test-iter-timing-${tag}-$$"
  rm -rf "$root"; mkdir -p "$root"; echo "$root"
}
cleanup_root() { rm -rf "$1" 2>/dev/null || true; }

strip_ansi() { sed $'s/\x1b\[[0-9;]*m//g'; }

# ---------- T1 — no iterations; header elapsed + no iter block ----------
run_T1() {
  local root; root=$(mkroot T1)
  bash "${SETUP}" "$root" 0
  local out; out=$(bash "${STATUS}" "$root" 2>&1 | strip_ansi)
  local fail=""
  grep -q "Per-iteration history" <<<"$out" && fail+="iter block shown without iterations; "
  grep -qE 'Elapsed:[[:space:]]' <<<"$out" || fail+="no fleet Elapsed in header; "
  [[ -z "$fail" ]] && record T1 PASS || record T1 FAIL "$fail"
  cleanup_root "$root"
}

# ---------- T2 — 1 completed iter ----------
run_T2() {
  local root; root=$(mkroot T2)
  bash "${SETUP}" "$root" 1
  local out; out=$(bash "${STATUS}" "$root" 2>&1 | strip_ansi)
  local fail=""
  grep -q "Per-iteration history" <<<"$out" || fail+="no iter block; "
  grep -qE '(^|[[:space:]])Iter 1([[:space:]]|:)' <<<"$out" || fail+="no Iter 1 row; "
  grep -q "tests" <<<"$out" || fail+="no tests worker; "
  grep -q "impl" <<<"$out"  || fail+="no impl worker; "
  grep -q "reviewer" <<<"$out" || fail+="no reviewer worker; "
  grep -qE '\$?0\.02' <<<"$out" || fail+="no tests cost; "
  grep -qE '\$?0\.18' <<<"$out" || fail+="no impl cost; "
  [[ -z "$fail" ]] && record T2 PASS || record T2 FAIL "$fail"
  cleanup_root "$root"
}

# ---------- T3 — 2 completed iters ----------
run_T3() {
  local root; root=$(mkroot T3)
  bash "${SETUP}" "$root" 2
  local out; out=$(bash "${STATUS}" "$root" 2>&1 | strip_ansi)
  local fail=""
  grep -qE '(^|[[:space:]])Iter 1([[:space:]]|:)' <<<"$out" || fail+="no Iter 1; "
  grep -qE '(^|[[:space:]])Iter 2([[:space:]]|:)' <<<"$out" || fail+="no Iter 2; "
  [[ -z "$fail" ]] && record T3 PASS || record T3 FAIL "$fail"
  cleanup_root "$root"
}

# ---------- T4 — 2 completed + 1 in-progress ----------
run_T4() {
  local root; root=$(mkroot T4)
  bash "${SETUP}" "$root" 2 --in-progress
  local out; out=$(bash "${STATUS}" "$root" 2>&1 | strip_ansi)
  local fail=""
  grep -qE '(^|[[:space:]])Iter 1([[:space:]]|:)' <<<"$out" || fail+="no Iter 1; "
  grep -qE '(^|[[:space:]])Iter 2([[:space:]]|:)' <<<"$out" || fail+="no Iter 2; "
  grep -qE 'Iter 3.*(in.progress|current)' <<<"$out" || fail+="no in-progress Iter 3; "
  [[ -z "$fail" ]] && record T4 PASS || record T4 FAIL "$fail"
  cleanup_root "$root"
}

# ---------- T5 — fleet elapsed in header ----------
run_T5() {
  local root; root=$(mkroot T5)
  bash "${SETUP}" "$root" 1
  # Ensure launched_at is recent-ish so elapsed isn't absurd/negative
  python3 - "$root" <<'PY' 2>/dev/null || true
import json, sys, datetime
p = sys.argv[1] + "/fleet.json"
d = json.load(open(p))
d["launched_at"] = (datetime.datetime.utcnow() - datetime.timedelta(minutes=5)).strftime("%Y-%m-%dT%H:%M:%SZ")
json.dump(d, open(p, "w"))
PY
  local out; out=$(bash "${STATUS}" "$root" 2>&1 | strip_ansi)
  local fail=""
  grep -qE 'Elapsed:[[:space:]]*[0-9]+' <<<"$out" || fail+="no Elapsed N; "
  [[ -z "$fail" ]] && record T5 PASS || record T5 FAIL "$fail"
  cleanup_root "$root"
}

chmod +x "${SETUP}"
for t in T1 T2 T3 T4 T5; do run_$t; done

echo
echo "Passed: ${#PASS[@]}"
echo "Failed: ${#FAIL[@]}"
exit ${#FAIL[@]}
