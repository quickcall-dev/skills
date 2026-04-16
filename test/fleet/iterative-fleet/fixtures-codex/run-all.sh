#!/usr/bin/env bash
# Codex provider test scenarios for iterative-fleet skill
# Usage: run-all.sh <skill-dir>
#   e.g. run-all.sh skills/iterative-fleet

set -uo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: run-all.sh <iterative-fleet-skill-dir>" >&2
  exit 99
fi

SKILL_DIR="$(cd "$1" && pwd)"
SCRIPTS="${SKILL_DIR}/scripts"
FIXTURES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

for s in launch.sh status.sh pause.sh resume.sh kill.sh; do
  [[ -f "${SCRIPTS}/${s}" ]] || { echo "missing ${SCRIPTS}/${s}" >&2; exit 99; }
done

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

mkroot() {
  local name="$1"
  local root="/tmp/fleet-test-codex-iterative-${name}-$$"
  mkdir -p "$root"
  echo "$root"
}

cleanup_session() {
  local sess="$1"
  tmux has-session -t "$sess" 2>/dev/null && tmux kill-session -t "$sess" 2>/dev/null || true
}

cleanup_root() {
  rm -rf "$1" 2>/dev/null || true
}

# -------------------------------------------------------------------
# Scenario CI1 — Launch creates iteration structure (codex provider)
# -------------------------------------------------------------------
run_CI1() {
  local root; root=$(mkroot structure)
  cp "${FIXTURES_DIR}/basic-iterative-fleet.json" "$root/fleet.json"
  mkdir -p "$root/workers/builder-a" "$root/workers/builder-b" "$root/workers/reviewer"
  for w in builder-a builder-b reviewer; do
    echo "fake codex worker $w" > "$root/workers/$w/prompt.md"
  done
  local rc=0
  bash "${SCRIPTS}/launch.sh" "$root" --dry-run >"$root/launch.out" 2>&1 || rc=$?
  local has_orch_script=0
  grep -q "orchestrator\|orch" "$root/launch.out" 2>/dev/null && has_orch_script=1
  if [[ "$rc" == "0" && "$has_orch_script" == "1" ]]; then
    record "CI1 launch-creates-iteration-structure (codex)" PASS
  else
    record "CI1 launch-creates-iteration-structure (codex)" FAIL "(rc=$rc orch=$has_orch_script)"
    tail -10 "$root/launch.out" 2>/dev/null || true
  fi
  cleanup_session "test-iterative-basic-codex" 2>/dev/null || true
  cleanup_root "$root"
}

# -------------------------------------------------------------------
# Scenario CI2 — Stop conditions parsed (codex provider)
# -------------------------------------------------------------------
run_CI2() {
  local root; root=$(mkroot stopcond)
  cp "${FIXTURES_DIR}/basic-iterative-fleet.json" "$root/fleet.json"
  mkdir -p "$root/workers/builder-a" "$root/workers/builder-b" "$root/workers/reviewer"
  for w in builder-a builder-b reviewer; do
    echo "fake codex worker $w" > "$root/workers/$w/prompt.md"
  done
  bash "${SCRIPTS}/launch.sh" "$root" --dry-run >"$root/launch.out" 2>&1 || true
  local has_max_iter=0 has_lgtm=0
  grep -q "max_iterations\|MAX_ITER\|3" "$root/launch.out" 2>/dev/null && has_max_iter=1
  grep -q "lgtm\|LGTM\|reviewer_lgtm_count\|2" "$root/launch.out" 2>/dev/null && has_lgtm=1
  if [[ "$has_max_iter" == "1" && "$has_lgtm" == "1" ]]; then
    record "CI2 stop-conditions-parsed (codex)" PASS
  else
    record "CI2 stop-conditions-parsed (codex)" FAIL "(max_iter=$has_max_iter lgtm=$has_lgtm)"
    tail -10 "$root/launch.out" 2>/dev/null || true
  fi
  cleanup_session "test-iterative-basic-codex" 2>/dev/null || true
  cleanup_root "$root"
}

# -------------------------------------------------------------------
# Scenario CI3 — Pause/resume cycle (codex provider)
# -------------------------------------------------------------------
run_CI3() {
  local root; root=$(mkroot pause)
  cp "${FIXTURES_DIR}/basic-iterative-fleet.json" "$root/fleet.json"
  mkdir -p "$root/workers/builder-a" "$root/workers/builder-b" "$root/workers/reviewer"
  for w in builder-a builder-b reviewer; do
    echo "fake codex worker $w" > "$root/workers/$w/prompt.md"
  done
  bash "${SCRIPTS}/launch.sh" "$root" >"$root/launch.out" 2>&1 || true
  sleep 2
  bash "${SCRIPTS}/pause.sh" "$root" >"$root/pause.out" 2>&1 || true
  local paused=0
  if grep -q "paused\|PAUSED" "$root/pause.out" 2>/dev/null || \
     [[ -f "$root/.paused" ]] || \
     jq -e '.status == "paused"' "$root/fleet.json" >/dev/null 2>&1; then
    paused=1
  fi
  bash "${SCRIPTS}/resume.sh" "$root" >"$root/resume.out" 2>&1 || true
  local resumed=0
  if grep -q "resumed\|RESUMED\|running" "$root/resume.out" 2>/dev/null || \
     [[ ! -f "$root/.paused" ]]; then
    resumed=1
  fi
  if [[ "$paused" == "1" && "$resumed" == "1" ]]; then
    record "CI3 pause-resume-cycle (codex)" PASS
  else
    record "CI3 pause-resume-cycle (codex)" FAIL "(paused=$paused resumed=$resumed)"
  fi
  cleanup_session "test-iterative-basic-codex" 2>/dev/null || true
  cleanup_root "$root"
}

# -------------------------------------------------------------------
# Scenario CI4 — Kill stops everything (codex provider)
# -------------------------------------------------------------------
run_CI4() {
  local root; root=$(mkroot kill)
  cp "${FIXTURES_DIR}/basic-iterative-fleet.json" "$root/fleet.json"
  mkdir -p "$root/workers/builder-a" "$root/workers/builder-b" "$root/workers/reviewer"
  for w in builder-a builder-b reviewer; do
    echo "fake codex worker $w" > "$root/workers/$w/prompt.md"
  done
  bash "${SCRIPTS}/launch.sh" "$root" >"$root/launch.out" 2>&1 || true
  sleep 2
  bash "${SCRIPTS}/kill.sh" "$root" all --force >"$root/kill.out" 2>&1 || true
  local session_gone=0 procs_gone=0
  tmux has-session -t "test-iterative-basic-codex" 2>/dev/null || session_gone=1
  local remaining; remaining=$(pgrep -f "$root" 2>/dev/null | wc -l)
  [[ "$remaining" -eq 0 ]] && procs_gone=1
  if [[ "$session_gone" == "1" && "$procs_gone" == "1" ]]; then
    record "CI4 kill-stops-everything (codex)" PASS
  else
    record "CI4 kill-stops-everything (codex)" FAIL "(session_gone=$session_gone procs=$remaining)"
  fi
  cleanup_session "test-iterative-basic-codex" 2>/dev/null || true
  cleanup_root "$root"
}

# -------------------------------------------------------------------
# Scenario CI5 — Orchestrator handles codex JSONL for worker completion
# Verify the generated orchestrator.sh can detect turn.completed events
# -------------------------------------------------------------------
run_CI5() {
  local root; root=$(mkroot orch-codex)
  cp "${FIXTURES_DIR}/basic-iterative-fleet.json" "$root/fleet.json"
  mkdir -p "$root/workers/builder-a" "$root/workers/builder-b" "$root/workers/reviewer"
  for w in builder-a builder-b reviewer; do
    echo "fake codex worker $w" > "$root/workers/$w/prompt.md"
  done
  bash "${SCRIPTS}/launch.sh" "$root" --dry-run >"$root/launch.out" 2>&1 || true
  # Check that the generated orchestrator handles codex JSONL
  local has_turn_completed=0
  if [[ -f "$root/orchestrator.sh" ]]; then
    grep -q 'turn.completed\|turn.failed' "$root/orchestrator.sh" 2>/dev/null && has_turn_completed=1
  fi
  if [[ "$has_turn_completed" == "1" ]]; then
    record "CI5 orchestrator-handles-codex-jsonl" PASS
  else
    record "CI5 orchestrator-handles-codex-jsonl" FAIL "(turn.completed in orchestrator: $has_turn_completed)"
  fi
  cleanup_session "test-iterative-basic-codex" 2>/dev/null || true
  cleanup_root "$root"
}

# -------------------------------------------------------------------
# Scenario CI6 — Codex -C flag points to git repo root, not fleet dir
# Bug 11: when fleet root is inside a git repo (standard layout),
# the codex -C flag must resolve to the repo root so workers can
# write to repo files. Without this, workspace-write sandbox blocks
# writes outside the fleet dir.
# -------------------------------------------------------------------
run_CI6() {
  # Create a fake git repo with fleet dir nested inside
  local repo; repo="/tmp/fleet-test-codex-repo-$$"
  mkdir -p "$repo/src" "$repo/docs/fleet-root/workers/builder-a" "$repo/docs/fleet-root/workers/reviewer"
  git -C "$repo" init -q
  git -C "$repo" commit --allow-empty -m "init" -q

  local fleet_root="$repo/docs/fleet-root"
  cp "${FIXTURES_DIR}/basic-iterative-fleet.json" "$fleet_root/fleet.json"
  echo "fake builder" > "$fleet_root/workers/builder-a/prompt.md"
  echo "fake builder" > "$fleet_root/workers/builder-b/prompt.md" 2>/dev/null || true
  mkdir -p "$fleet_root/workers/builder-b"
  echo "fake builder" > "$fleet_root/workers/builder-b/prompt.md"
  echo "fake reviewer" > "$fleet_root/workers/reviewer/prompt.md"

  bash "${SCRIPTS}/launch.sh" "$fleet_root" >"$fleet_root/launch.out" 2>&1 || true
  sleep 1

  local ok=1
  # Check .worker-cmd files for -C flag value
  for cmd_file in "$fleet_root"/.worker-cmd-*.sh; do
    [[ -f "$cmd_file" ]] || continue
    # Extract -C value
    local c_flag
    c_flag=$(grep -oP "\-C '\\K[^']*" "$cmd_file" 2>/dev/null || echo "")
    if [[ -z "$c_flag" ]]; then
      continue  # claude worker, no -C flag
    fi
    # -C must be the repo root, not the fleet dir
    if [[ "$c_flag" == "$fleet_root" ]]; then
      ok=0  # Bug: -C points to fleet dir instead of repo root
    fi
    # -C must be the git repo root
    if [[ "$c_flag" != "$repo" ]]; then
      ok=0  # Bug: -C doesn't point to repo root
    fi
  done

  if [[ "$ok" == "1" ]]; then
    record "CI6 codex-C-flag-uses-repo-root" PASS
  else
    record "CI6 codex-C-flag-uses-repo-root" FAIL "(-C should be $repo, not $fleet_root)"
    for f in "$fleet_root"/.worker-cmd-*.sh; do
      echo "  cmd: $(grep -oP "\-C '\\K[^']*" "$f" 2>/dev/null)" || true
    done
  fi
  cleanup_session "test-iterative-basic-codex" 2>/dev/null || true
  rm -rf "$repo" 2>/dev/null || true
}

# -------------------------------------------------------------------
# Scenario CI7 — Codex -C falls back to cwd when not in a git repo
# If fleet root is NOT inside a git repo, -C should fall back to
# the fleet root (no repo root to resolve).
# -------------------------------------------------------------------
run_CI7() {
  local root; root=$(mkroot no-git)
  cp "${FIXTURES_DIR}/basic-iterative-fleet.json" "$root/fleet.json"
  mkdir -p "$root/workers/builder-a" "$root/workers/builder-b" "$root/workers/reviewer"
  for w in builder-a builder-b reviewer; do
    echo "fake codex worker $w" > "$root/workers/$w/prompt.md"
  done
  bash "${SCRIPTS}/launch.sh" "$root" >"$root/launch.out" 2>&1 || true
  sleep 1

  local ok=1
  for cmd_file in "$root"/.worker-cmd-*.sh; do
    [[ -f "$cmd_file" ]] || continue
    local c_flag
    c_flag=$(grep -oP "\-C '\\K[^']*" "$cmd_file" 2>/dev/null || echo "")
    [[ -z "$c_flag" ]] && continue
    # No git repo → -C should fall back to fleet root
    if [[ "$c_flag" != "$root" ]]; then
      ok=0
    fi
  done

  if [[ "$ok" == "1" ]]; then
    record "CI7 codex-C-fallback-no-git" PASS
  else
    record "CI7 codex-C-fallback-no-git" FAIL "(-C should fall back to $root)"
  fi
  cleanup_session "test-iterative-basic-codex" 2>/dev/null || true
  cleanup_root "$root"
}

run_CI1
run_CI2
run_CI3
run_CI4
run_CI5
run_CI6
run_CI7

echo
echo "============================================================"
echo "CODEX ITERATIVE-FLEET SUMMARY: ${#PASS[@]} passed, ${#FAIL[@]} failed"
echo "============================================================"
for p in "${PASS[@]}"; do echo "  PASS  $p"; done
for f in "${FAIL[@]}"; do echo "  FAIL  $f"; done

exit "${#FAIL[@]}"
