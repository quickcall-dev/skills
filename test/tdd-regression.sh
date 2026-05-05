#!/usr/bin/env bash
# tdd-regression.sh — verify fixes for:
#   1. fleet root .gitignore exists with correct patterns
#   2. no CLAUDE_SKILL_DIR in SKILL.md files (uses AGENTS_SKILLS_DIR)
#   3. pi fixtures use kimi-for-coding (cheaper test model)
#
# Run from repo root.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
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

# -------------------------------------------------------------------
# Test 1 — SKILL.md files must use AGENTS_SKILLS_DIR, not CLAUDE_SKILL_DIR
# -------------------------------------------------------------------
run_skill_dir_var() {
  local hits
  hits=$(grep -rln "CLAUDE_SKILL_DIR" \
    "$REPO_ROOT/skills/" \
    "$REPO_ROOT/.github/" \
    2>/dev/null | grep -v '/experiments/' | grep -v '/docs/experiments/' | wc -l)
  if [[ "$hits" == "0" ]]; then
    record "skill-dir-var-provider-agnostic" PASS
  else
    record "skill-dir-var-provider-agnostic" FAIL "($hits files still use CLAUDE_SKILL_DIR)"
    grep -rln "CLAUDE_SKILL_DIR" "$REPO_ROOT/skills/" "$REPO_ROOT/.github/" 2>/dev/null | grep -v '/experiments/'
  fi
}

# -------------------------------------------------------------------
# Test 2 — fleet launch creates .gitignore in fleet root
# -------------------------------------------------------------------
run_gitignore() {
  local root
  root="/tmp/fleet-test-gitignore-$$"
  rm -rf "$root"
  mkdir -p "$root"

  # Use pi fixture + fake shim so launch.sh is fast and non-destructive
  bash "$REPO_ROOT/test/fleet/dag-fleet/fixtures-pi/setup-fleet.sh" completion "$root" >/dev/null
  export PATH="$REPO_ROOT/test/fleet/dag-fleet/fixtures-pi/shim:${PATH}"
  bash "$REPO_ROOT/skills/dag-fleet/scripts/launch.sh" "$root" >"$root/launch.out" 2>&1 &
  local lpid=$!
  sleep 5

  if [[ -f "$root/.gitignore" ]]; then
    local has_jsonl has_out has_out_last
    has_jsonl=$(grep -c '^\*\.jsonl$' "$root/.gitignore" 2>/dev/null || echo 0)
    has_out=$(grep -c '^\*\.out$' "$root/.gitignore" 2>/dev/null || echo 0)
    has_out_last=$(grep -c '^\*\.out\.last$' "$root/.gitignore" 2>/dev/null || echo 0)
    if [[ "$has_jsonl" -ge 1 && "$has_out" -ge 1 && "$has_out_last" -ge 1 ]]; then
      record "fleet-gitignore-patterns" PASS
    else
      record "fleet-gitignore-patterns" FAIL "(jsonl=$has_jsonl out=$has_out out_last=$has_out_last)"
      cat "$root/.gitignore"
    fi
  else
    record "fleet-gitignore-exists" FAIL "(.gitignore missing after launch)"
  fi

  kill "$lpid" 2>/dev/null || true
  tmux kill-session -t fleet-test-completion-pi 2>/dev/null || true
  pkill -f "FLEET_ROOT=${root}" 2>/dev/null || true
  rm -rf "$root"
}

# -------------------------------------------------------------------
# Test 3 — pi fixtures use kimi-for-coding (not heavy kimi-k2-thinking)
# -------------------------------------------------------------------
run_pi_model() {
  local bad_models
  bad_models=$(grep -rn "kimi-k2-thinking\|k2p6" "$REPO_ROOT/test/fleet/dag-fleet/fixtures-pi/" 2>/dev/null | grep '\.json:' | wc -l)
  if [[ "$bad_models" == "0" ]]; then
    record "pi-fixture-model" PASS
  else
    record "pi-fixture-model" FAIL "($bad_models refs to heavy models in fixtures)"
    grep -rn "kimi-k2-thinking\|k2p6" "$REPO_ROOT/test/fleet/dag-fleet/fixtures-pi/" 2>/dev/null | grep '\.json:'
  fi
}

# -------------------------------------------------------------------
# Run
# -------------------------------------------------------------------
run_skill_dir_var
run_gitignore
run_pi_model

echo
echo "============================================================"
echo "SUMMARY: ${#PASS[@]} passed, ${#FAIL[@]} failed"
echo "============================================================"
for p in "${PASS[@]}"; do echo "  PASS  $p"; done
for f in "${FAIL[@]}"; do echo "  FAIL  $f"; done

exit "${#FAIL[@]}"
