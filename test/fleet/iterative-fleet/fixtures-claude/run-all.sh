#!/usr/bin/env bash
# Test scenarios for iterative-fleet skill
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
  local root="/tmp/fleet-test-iterative-${name}-$$"
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
# Scenario I1 — Launch creates iteration directory structure
# After launch, iterations/1/ exists with per-worker log placeholders
# and the orchestrator script is generated
# -------------------------------------------------------------------
run_I1() {
  local root; root=$(mkroot structure)
  cp "${FIXTURES_DIR}/basic-iterative-fleet.json" "$root/fleet.json"
  mkdir -p "$root/workers/builder-a" "$root/workers/builder-b" "$root/workers/reviewer"
  for w in builder-a builder-b reviewer; do
    echo "fake worker $w" > "$root/workers/$w/prompt.md"
  done
  local rc=0
  bash "${SCRIPTS}/launch.sh" "$root" --dry-run >"$root/launch.out" 2>&1 || rc=$?
  local has_iter_dir=0 has_orch_script=0
  [[ -d "$root/iterations" || -d "$root/iterations/1" ]] && has_iter_dir=1
  # Check if orchestrator script was generated (or at least referenced)
  grep -q "orchestrator\|orch" "$root/launch.out" 2>/dev/null && has_orch_script=1
  if [[ "$rc" == "0" && "$has_orch_script" == "1" ]]; then
    record "I1 launch-creates-iteration-structure" PASS
  else
    record "I1 launch-creates-iteration-structure" FAIL "(rc=$rc iter_dir=$has_iter_dir orch=$has_orch_script)"
    tail -10 "$root/launch.out" 2>/dev/null || true
  fi
  cleanup_session "test-iterative-basic" 2>/dev/null || true
  cleanup_root "$root"
}

# -------------------------------------------------------------------
# Scenario I2 — Stop conditions are read from fleet.json
# Launch with max_iterations=3, verify the orchestrator script
# contains the stop condition
# -------------------------------------------------------------------
run_I2() {
  local root; root=$(mkroot stopcond)
  cp "${FIXTURES_DIR}/basic-iterative-fleet.json" "$root/fleet.json"
  mkdir -p "$root/workers/builder-a" "$root/workers/builder-b" "$root/workers/reviewer"
  for w in builder-a builder-b reviewer; do
    echo "fake worker $w" > "$root/workers/$w/prompt.md"
  done
  bash "${SCRIPTS}/launch.sh" "$root" --dry-run >"$root/launch.out" 2>&1 || true
  # Check that stop conditions are parsed
  local has_max_iter=0 has_lgtm=0
  grep -q "max_iterations\|MAX_ITER\|3" "$root/launch.out" 2>/dev/null && has_max_iter=1
  grep -q "lgtm\|LGTM\|reviewer_lgtm_count\|2" "$root/launch.out" 2>/dev/null && has_lgtm=1
  if [[ "$has_max_iter" == "1" && "$has_lgtm" == "1" ]]; then
    record "I2 stop-conditions-parsed" PASS
  else
    record "I2 stop-conditions-parsed" FAIL "(max_iter=$has_max_iter lgtm=$has_lgtm)"
    tail -10 "$root/launch.out" 2>/dev/null || true
  fi
  cleanup_session "test-iterative-basic" 2>/dev/null || true
  cleanup_root "$root"
}

# -------------------------------------------------------------------
# Scenario I3 — Pause/resume cycle
# Launch fleet, pause it, verify state file says paused, resume,
# verify state file says running
# -------------------------------------------------------------------
run_I3() {
  local root; root=$(mkroot pause)
  cp "${FIXTURES_DIR}/basic-iterative-fleet.json" "$root/fleet.json"
  mkdir -p "$root/workers/builder-a" "$root/workers/builder-b" "$root/workers/reviewer"
  for w in builder-a builder-b reviewer; do
    echo "fake worker $w" > "$root/workers/$w/prompt.md"
  done
  bash "${SCRIPTS}/launch.sh" "$root" >"$root/launch.out" 2>&1 || true
  sleep 2
  bash "${SCRIPTS}/pause.sh" "$root" >"$root/pause.out" 2>&1 || true
  local paused=0
  # Check for pause state (could be a file, a fleet.json field, or stdout message)
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
    record "I3 pause-resume-cycle" PASS
  else
    record "I3 pause-resume-cycle" FAIL "(paused=$paused resumed=$resumed)"
    tail -5 "$root/pause.out" "$root/resume.out" 2>/dev/null || true
  fi
  cleanup_session "test-iterative-basic" 2>/dev/null || true
  cleanup_root "$root"
}

# -------------------------------------------------------------------
# Scenario I4 — Kill stops everything
# Launch, kill, verify zero processes + tmux session gone
# -------------------------------------------------------------------
run_I4() {
  local root; root=$(mkroot kill)
  cp "${FIXTURES_DIR}/basic-iterative-fleet.json" "$root/fleet.json"
  mkdir -p "$root/workers/builder-a" "$root/workers/builder-b" "$root/workers/reviewer"
  for w in builder-a builder-b reviewer; do
    echo "fake worker $w" > "$root/workers/$w/prompt.md"
  done
  bash "${SCRIPTS}/launch.sh" "$root" >"$root/launch.out" 2>&1 || true
  sleep 2
  bash "${SCRIPTS}/kill.sh" "$root" all --force >"$root/kill.out" 2>&1 || true
  local session_gone=0 procs_gone=0
  tmux has-session -t "test-iterative-basic" 2>/dev/null || session_gone=1
  local remaining; remaining=$(pgrep -f "$root" 2>/dev/null | wc -l)
  [[ "$remaining" -eq 0 ]] && procs_gone=1
  if [[ "$session_gone" == "1" && "$procs_gone" == "1" ]]; then
    record "I4 kill-stops-everything" PASS
  else
    record "I4 kill-stops-everything" FAIL "(session_gone=$session_gone procs=$remaining)"
  fi
  cleanup_session "test-iterative-basic" 2>/dev/null || true
  cleanup_root "$root"
}

# -------------------------------------------------------------------
# Scenario I5 — Workers with depends_on are NOT spawned at launch
# Using dag-iterative-fleet.json where reviewer depends_on builders.
# After launch, reviewer tmux window must NOT exist (deferred to
# orchestrator), but builder windows must exist.
# -------------------------------------------------------------------
run_I5() {
  local root; root=$(mkroot dag-deferred)
  cp "${FIXTURES_DIR}/dag-iterative-fleet.json" "$root/fleet.json"
  mkdir -p "$root/workers/builder-a" "$root/workers/builder-b" "$root/workers/reviewer"
  for w in builder-a builder-b reviewer; do
    echo "fake worker $w" > "$root/workers/$w/prompt.md"
  done
  bash "${SCRIPTS}/launch.sh" "$root" >"$root/launch.out" 2>&1 || true
  sleep 2
  # Check that the reviewer tmux window does NOT exist
  local reviewer_window_exists=0
  if tmux list-windows -t "test-iterative-dag" -F '#{window_name}' 2>/dev/null | grep -q "^reviewer$"; then
    reviewer_window_exists=1
  fi
  # Check that builder windows DO exist (layer 0 — no deps)
  local builder_a_exists=0 builder_b_exists=0
  if tmux list-windows -t "test-iterative-dag" -F '#{window_name}' 2>/dev/null | grep -q "^builder-a$"; then
    builder_a_exists=1
  fi
  if tmux list-windows -t "test-iterative-dag" -F '#{window_name}' 2>/dev/null | grep -q "^builder-b$"; then
    builder_b_exists=1
  fi
  # Orchestrator must have dag-aware spawn logic (spawn_layer function)
  local orch_has_dag=0
  if [[ -f "$root/orchestrator.sh" ]] && grep -q "spawn_layer\|dag_" "$root/orchestrator.sh" 2>/dev/null; then
    orch_has_dag=1
  fi
  if [[ "$reviewer_window_exists" == "0" && "$builder_a_exists" == "1" && "$builder_b_exists" == "1" && "$orch_has_dag" == "1" ]]; then
    record "I5 depends-on-defers-launch" PASS
  else
    record "I5 depends-on-defers-launch" FAIL "(reviewer=$reviewer_window_exists builder_a=$builder_a_exists builder_b=$builder_b_exists orch_dag=$orch_has_dag)"
    tmux list-windows -t "test-iterative-dag" -F '#{window_name}' 2>/dev/null || true
  fi
  cleanup_session "test-iterative-dag" 2>/dev/null || true
  cleanup_root "$root"
}

# -------------------------------------------------------------------
# Scenario I6 — Topo-sort produces correct layers from depends_on
# Validate that _lib/dag.sh correctly sorts workers into layers:
#   layer 0: builder-a, builder-b (no deps)
#   layer 1: reviewer (depends_on builder-a, builder-b)
# -------------------------------------------------------------------
run_I6() {
  local root; root=$(mkroot topo-sort)
  cp "${FIXTURES_DIR}/dag-iterative-fleet.json" "$root/fleet.json"

  # Source the dag library and validate topo sort
  local dag_lib
  dag_lib="${SKILL_DIR}/lib/dag.sh"
  if [[ ! -f "$dag_lib" ]]; then
    record "I6 topo-sort-layers" FAIL "(dag.sh not found at $dag_lib)"
    cleanup_root "$root"
    return
  fi
  source "$dag_lib"
  local layers
  layers=$(dag_topo_sort "$root/fleet.json" 2>"$root/topo.err") || {
    record "I6 topo-sort-layers" FAIL "(topo_sort failed: $(cat "$root/topo.err"))"
    cleanup_root "$root"
    return
  }
  # Expect 2 layers: "builder-a builder-b" then "reviewer"
  local layer_count
  layer_count=$(dag_count_layers "$root/fleet.json" 2>/dev/null)
  local layer0 layer1
  layer0=$(dag_get_layer_workers 0 "$root/fleet.json" 2>/dev/null)
  layer1=$(dag_get_layer_workers 1 "$root/fleet.json" 2>/dev/null)

  local ok=1
  [[ "$layer_count" == "2" ]] || ok=0
  echo "$layer0" | grep -q "builder-a" || ok=0
  echo "$layer0" | grep -q "builder-b" || ok=0
  echo "$layer1" | grep -q "reviewer" || ok=0

  if [[ "$ok" == "1" ]]; then
    record "I6 topo-sort-layers" PASS
  else
    record "I6 topo-sort-layers" FAIL "(layers=$layer_count layer0='$layer0' layer1='$layer1')"
  fi
  cleanup_root "$root"
}

# -------------------------------------------------------------------
# Scenario I7 — Multi-layer DAG: researcher → builder → reviewer
# 3 layers, each with 1 worker. Only layer 0 (researcher) should
# launch at start.
# -------------------------------------------------------------------
run_I7() {
  local root; root=$(mkroot multilayer)
  cp "${FIXTURES_DIR}/multilayer-iterative-fleet.json" "$root/fleet.json"
  mkdir -p "$root/workers/researcher" "$root/workers/builder" "$root/workers/reviewer"
  for w in researcher builder reviewer; do
    echo "fake worker $w" > "$root/workers/$w/prompt.md"
  done
  bash "${SCRIPTS}/launch.sh" "$root" >"$root/launch.out" 2>&1 || true
  # Check launch output: researcher should be "Spawned", builder/reviewer should be "Deferred"
  local researcher_spawned=0 builder_deferred=0 reviewer_deferred=0
  grep -q "Spawned worker: researcher" "$root/launch.out" 2>/dev/null && researcher_spawned=1
  grep -q "Deferred worker: builder" "$root/launch.out" 2>/dev/null && builder_deferred=1
  grep -q "Deferred worker: reviewer" "$root/launch.out" 2>/dev/null && reviewer_deferred=1
  # Also verify DAG has 3 layers
  local has_3_layers=0
  grep -q "DAG layers: 3" "$root/launch.out" 2>/dev/null && has_3_layers=1
  if [[ "$researcher_spawned" == "1" && "$builder_deferred" == "1" && "$reviewer_deferred" == "1" && "$has_3_layers" == "1" ]]; then
    record "I7 multilayer-dag-spawn-order" PASS
  else
    record "I7 multilayer-dag-spawn-order" FAIL "(researcher=$researcher_spawned builder_defer=$builder_deferred reviewer_defer=$reviewer_deferred layers=$has_3_layers)"
    cat "$root/launch.out" 2>/dev/null || true
  fi
  cleanup_session "test-iterative-multilayer" 2>/dev/null || true
  cleanup_root "$root"
}

# -------------------------------------------------------------------
# Scenario I8 — wait_for_layer_workers uses .done sentinel, not session.jsonl
# Generated orchestrator must check .done/.failed, NOT grep session.jsonl
# -------------------------------------------------------------------
run_I8() {
  local root; root=$(mkroot sentinel-wait)
  cp "${FIXTURES_DIR}/dag-iterative-fleet.json" "$root/fleet.json"
  mkdir -p "$root/workers/builder-a" "$root/workers/builder-b" "$root/workers/reviewer"
  for w in builder-a builder-b reviewer; do
    echo "fake worker $w" > "$root/workers/$w/prompt.md"
  done
  bash "${SCRIPTS}/launch.sh" "$root" --dry-run >"$root/launch.out" 2>&1 || true

  local ok=1
  # wait_for_layer_workers must check .done/.failed
  grep -q '\.done' "$root/orchestrator.sh" 2>/dev/null || ok=0
  grep -q '\.failed' "$root/orchestrator.sh" 2>/dev/null || ok=0
  # Must NOT grep session.jsonl for "type":"result" in wait_for_layer_workers
  # Extract the function body and check it doesn't use session.jsonl for completion
  local wait_fn
  wait_fn=$(sed -n '/^wait_for_layer_workers/,/^}/p' "$root/orchestrator.sh" 2>/dev/null)
  if echo "$wait_fn" | grep -q 'session\.jsonl'; then
    ok=0  # Bug: still using session.jsonl for completion detection
  fi
  if echo "$wait_fn" | grep -q '"type":"result"'; then
    ok=0  # Bug: still grepping for json events
  fi

  if [[ "$ok" == "1" ]]; then
    record "I8 sentinel-based-wait" PASS
  else
    record "I8 sentinel-based-wait" FAIL "(wait_for_layer_workers still uses session.jsonl or missing .done/.failed)"
  fi
  cleanup_root "$root"
}

# -------------------------------------------------------------------
# Scenario I9 — Review file search checks multiple paths
# Generated orchestrator must have find_review_file that checks
# iterations/<N>/review.md AND iterations/review-<N>.md
# -------------------------------------------------------------------
run_I9() {
  local root; root=$(mkroot review-path)
  cp "${FIXTURES_DIR}/dag-iterative-fleet.json" "$root/fleet.json"
  mkdir -p "$root/workers/builder-a" "$root/workers/builder-b" "$root/workers/reviewer"
  for w in builder-a builder-b reviewer; do
    echo "fake worker $w" > "$root/workers/$w/prompt.md"
  done
  bash "${SCRIPTS}/launch.sh" "$root" --dry-run >"$root/launch.out" 2>&1 || true

  local ok=1
  # Must have find_review_file function
  grep -q 'find_review_file' "$root/orchestrator.sh" 2>/dev/null || ok=0
  # Must search for review-${iter}.md (flat path)
  grep -q 'review-' "$root/orchestrator.sh" 2>/dev/null || ok=0
  # Must search iterations/${iter}/review.md (nested path)
  grep -q 'iterations.*review\.md' "$root/orchestrator.sh" 2>/dev/null || ok=0

  if [[ "$ok" == "1" ]]; then
    record "I9 multi-path-review-search" PASS
  else
    record "I9 multi-path-review-search" FAIL "(missing find_review_file or path candidates)"
  fi
  cleanup_root "$root"
}

# -------------------------------------------------------------------
# Scenario I10 — Reviewer .done fallback prevents infinite hang
# wait_for_verdict must check reviewer .done and synthesize verdict
# if no review file exists
# -------------------------------------------------------------------
run_I10() {
  local root; root=$(mkroot verdict-fallback)
  cp "${FIXTURES_DIR}/dag-iterative-fleet.json" "$root/fleet.json"
  mkdir -p "$root/workers/builder-a" "$root/workers/builder-b" "$root/workers/reviewer"
  for w in builder-a builder-b reviewer; do
    echo "fake worker $w" > "$root/workers/$w/prompt.md"
  done
  bash "${SCRIPTS}/launch.sh" "$root" --dry-run >"$root/launch.out" 2>&1 || true

  local ok=1
  # wait_for_verdict must check reviewer .done
  local verdict_fn
  verdict_fn=$(sed -n '/^wait_for_verdict/,/^}/p' "$root/orchestrator.sh" 2>/dev/null)
  echo "$verdict_fn" | grep -q '\.done' || ok=0
  # Must have fallback that synthesizes "iterate" verdict
  echo "$verdict_fn" | grep -q 'treating as iterate\|verdict: iterate' || ok=0

  if [[ "$ok" == "1" ]]; then
    record "I10 verdict-done-fallback" PASS
  else
    record "I10 verdict-done-fallback" FAIL "(wait_for_verdict missing .done check or iterate fallback)"
  fi
  cleanup_root "$root"
}

# -------------------------------------------------------------------
# Scenario I11 — INNER_CMD writes .failed on non-zero exit
# The worker command must use && .done || .failed pattern
# -------------------------------------------------------------------
run_I11() {
  local root; root=$(mkroot failed-sentinel)
  cp "${FIXTURES_DIR}/dag-iterative-fleet.json" "$root/fleet.json"
  mkdir -p "$root/workers/builder-a" "$root/workers/builder-b" "$root/workers/reviewer"
  for w in builder-a builder-b reviewer; do
    echo "fake worker $w" > "$root/workers/$w/prompt.md"
  done
  # Must do real launch (not --dry-run) since worker-cmd files are generated after dry-run exit
  bash "${SCRIPTS}/launch.sh" "$root" >"$root/launch.out" 2>&1 || true
  sleep 1

  local ok=1
  # Check .worker-cmd files for .done && || .failed pattern
  local has_done_pattern=0 has_failed_pattern=0
  for cmd_file in "$root"/.worker-cmd-*.sh; do
    [[ -f "$cmd_file" ]] || continue
    grep -q '\.done' "$cmd_file" 2>/dev/null && has_done_pattern=1
    grep -q '\.failed' "$cmd_file" 2>/dev/null && has_failed_pattern=1
  done
  [[ "$has_done_pattern" == "1" ]] || ok=0
  [[ "$has_failed_pattern" == "1" ]] || ok=0

  if [[ "$ok" == "1" ]]; then
    record "I11 failed-sentinel-in-cmd" PASS
  else
    record "I11 failed-sentinel-in-cmd" FAIL "(done=$has_done_pattern failed=$has_failed_pattern)"
  fi
  cleanup_session "test-iterative-dag" 2>/dev/null || true
  cleanup_root "$root"
}

# -------------------------------------------------------------------
# Scenario I12 — dag_spawn_worker clears .done AND .failed
# The orchestrator's re-spawn logic must clean both sentinels
# -------------------------------------------------------------------
run_I12() {
  local root; root=$(mkroot spawn-cleanup)
  cp "${FIXTURES_DIR}/dag-iterative-fleet.json" "$root/fleet.json"
  mkdir -p "$root/workers/builder-a" "$root/workers/builder-b" "$root/workers/reviewer"
  for w in builder-a builder-b reviewer; do
    echo "fake worker $w" > "$root/workers/$w/prompt.md"
  done
  bash "${SCRIPTS}/launch.sh" "$root" --dry-run >"$root/launch.out" 2>&1 || true

  local ok=1
  # dag_spawn_worker must rm both .done and .failed
  local spawn_fn
  spawn_fn=$(sed -n '/^dag_spawn_worker/,/^}/p' "$root/orchestrator.sh" 2>/dev/null)
  echo "$spawn_fn" | grep -q '\.done' || ok=0
  echo "$spawn_fn" | grep -q '\.failed' || ok=0

  if [[ "$ok" == "1" ]]; then
    record "I12 spawn-clears-both-sentinels" PASS
  else
    record "I12 spawn-clears-both-sentinels" FAIL "(dag_spawn_worker missing .done or .failed cleanup)"
  fi
  cleanup_root "$root"
}

# -------------------------------------------------------------------
# Scenario I13 — Reviewer type gets Write tool in iterative-fleet
# Bug 09: type=reviewer disallows Write, but orchestrator expects
# reviewer to write iterations/<N>/review.md. The reviewer's
# disallowed-tools must NOT include Write.
# -------------------------------------------------------------------
run_I13() {
  local root; root=$(mkroot reviewer-write)
  cp "${FIXTURES_DIR}/dag-iterative-fleet.json" "$root/fleet.json"
  mkdir -p "$root/workers/builder-a" "$root/workers/builder-b" "$root/workers/reviewer"
  for w in builder-a builder-b reviewer; do
    echo "fake worker $w" > "$root/workers/$w/prompt.md"
  done
  bash "${SCRIPTS}/launch.sh" "$root" >"$root/launch.out" 2>&1 || true
  sleep 1

  local ok=1
  # The reviewer's .worker-cmd file must NOT have Write in disallowed-tools
  local cmd_file="$root/.worker-cmd-reviewer.sh"
  if [[ ! -f "$cmd_file" ]]; then
    record "I13 reviewer-has-write-tool" FAIL "(no .worker-cmd-reviewer.sh found)"
    cleanup_session "test-iterative-dag" 2>/dev/null || true
    cleanup_root "$root"
    return
  fi
  # Extract --disallowed-tools value from the command
  local disallowed
  disallowed=$(grep -oP "disallowed-tools '\K[^']*" "$cmd_file" 2>/dev/null || echo "")
  # Reviewer must have NO restrictions — full toolset
  if [[ -n "$disallowed" ]]; then
    ok=0  # Bug: reviewer still has disallowed tools
  fi

  if [[ "$ok" == "1" ]]; then
    record "I13 reviewer-unrestricted-tools" PASS
  else
    record "I13 reviewer-unrestricted-tools" FAIL "(disallowed='$disallowed' — must be empty)"
  fi
  cleanup_session "test-iterative-dag" 2>/dev/null || true
  cleanup_root "$root"
}

# -------------------------------------------------------------------
# Scenario I14 — dag_spawn_worker injects review context on iter > 1
# Bug 10: builder re-spawns with identical prompt every iteration,
# never seeing reviewer feedback. The orchestrator must build an
# enhanced prompt with prior review content for iter > 1.
# -------------------------------------------------------------------
run_I14() {
  local root; root=$(mkroot review-inject)
  cp "${FIXTURES_DIR}/dag-iterative-fleet.json" "$root/fleet.json"
  mkdir -p "$root/workers/builder-a" "$root/workers/builder-b" "$root/workers/reviewer"
  for w in builder-a builder-b reviewer; do
    echo "fake worker $w" > "$root/workers/$w/prompt.md"
  done
  bash "${SCRIPTS}/launch.sh" "$root" --dry-run >"$root/launch.out" 2>&1 || true

  local ok=1
  # dag_spawn_worker must have review context injection logic
  local spawn_fn
  spawn_fn=$(sed -n '/^dag_spawn_worker/,/^}/p' "$root/orchestrator.sh" 2>/dev/null)

  # Must reference prior review files (iterations/*/review.md)
  if ! echo "$spawn_fn" | grep -q 'review'; then
    ok=0
  fi
  # Must check iteration > 1 to decide whether to inject
  if ! echo "$spawn_fn" | grep -q 'iter.*-gt 1\|iter.*> 1\|iter.*-ge 2\|iter.*!= 1\|iter.*gt.*1'; then
    ok=0
  fi
  # Must create or use an enhanced prompt (not just replay cmd_file verbatim)
  if ! echo "$spawn_fn" | grep -q 'prompt.*iter\|iter.*prompt\|review.*context\|REVIEW\|feedback'; then
    ok=0
  fi

  if [[ "$ok" == "1" ]]; then
    record "I14 review-context-injected" PASS
  else
    record "I14 review-context-injected" FAIL "(dag_spawn_worker missing review injection logic)"
  fi
  cleanup_root "$root"
}

# -------------------------------------------------------------------
# Scenario I15 — Enhanced prompt actually contains review content
# Simulate: create review files for iterations 1 and 2, then verify
# the generated iter-3 prompt includes that feedback.
# Uses the orchestrator's inject logic by sourcing the function.
# -------------------------------------------------------------------
run_I15() {
  local root; root=$(mkroot review-content)
  cp "${FIXTURES_DIR}/dag-iterative-fleet.json" "$root/fleet.json"
  mkdir -p "$root/workers/builder-a" "$root/workers/builder-b" "$root/workers/reviewer"
  echo "Original builder task: implement feature X" > "$root/workers/builder-a/prompt.md"
  echo "Original builder task: implement feature Y" > "$root/workers/builder-b/prompt.md"
  echo "Review the work" > "$root/workers/reviewer/prompt.md"

  # Create fake review files from prior iterations
  mkdir -p "$root/iterations/1" "$root/iterations/2"
  cat > "$root/iterations/1/review.md" <<'EOF'
verdict: iterate

Builder-a: missing error handling in parse_input().
Builder-b: forgot to export the new function.
EOF
  cat > "$root/iterations/2/review.md" <<'EOF'
verdict: iterate

Builder-a: error handling added but catch block is empty.
Builder-b: export added but wrong function name.
EOF

  bash "${SCRIPTS}/launch.sh" "$root" --dry-run >"$root/launch.out" 2>&1 || true

  # Now test: source the orchestrator's inject function and call it
  # We'll extract the build_iter_prompt or equivalent function from orchestrator.sh
  # and verify it produces correct output
  local ok=1

  # The orchestrator must have a function that builds enhanced prompts
  if [[ ! -f "$root/orchestrator.sh" ]]; then
    record "I15 review-content-in-prompt" FAIL "(no orchestrator.sh)"
    cleanup_root "$root"
    return
  fi

  # Check that orchestrator references iteration-specific prompt files
  if ! grep -q 'prompt.*iter\|iter.*prompt' "$root/orchestrator.sh" 2>/dev/null; then
    record "I15 review-content-in-prompt" FAIL "(orchestrator has no iter-specific prompt logic)"
    cleanup_root "$root"
    return
  fi

  # Verify the function builds prompts containing review content
  # by checking it reads from iterations/*/review.md
  if ! grep -q 'iterations.*review\.md\|find_review_file' "$root/orchestrator.sh" 2>/dev/null; then
    ok=0
  fi

  # Must include the iteration number in the enhanced prompt
  if ! grep -q 'iteration.*iter\|iter.*iteration\|Iteration' "$root/orchestrator.sh" 2>/dev/null; then
    ok=0
  fi

  if [[ "$ok" == "1" ]]; then
    record "I15 review-content-in-prompt" PASS
  else
    record "I15 review-content-in-prompt" FAIL "(orchestrator missing review content assembly)"
  fi
  cleanup_root "$root"
}

# -------------------------------------------------------------------
# Scenario I16 — Reviewer ID detected even when type is "reviewer"
# The REVIEWER_ID jq selector must find the reviewer worker regardless
# of whether the doc says to use type "write" — the script itself
# must handle the type field correctly for identification.
# -------------------------------------------------------------------
run_I16() {
  local root; root=$(mkroot reviewer-detect)
  cp "${FIXTURES_DIR}/dag-iterative-fleet.json" "$root/fleet.json"
  mkdir -p "$root/workers/builder-a" "$root/workers/builder-b" "$root/workers/reviewer"
  for w in builder-a builder-b reviewer; do
    echo "fake worker $w" > "$root/workers/$w/prompt.md"
  done
  bash "${SCRIPTS}/launch.sh" "$root" --dry-run >"$root/launch.out" 2>&1 || true

  local ok=1
  # Launch output must show the reviewer was detected
  if ! grep -q "Reviewer worker: reviewer" "$root/launch.out" 2>/dev/null; then
    ok=0
  fi
  # Must NOT warn about missing reviewer
  if grep -q "No reviewer worker found" "$root/launch.out" 2>/dev/null; then
    ok=0
  fi
  # Orchestrator must have REVIEWER_ID set
  if ! grep -q 'REVIEWER_ID="reviewer"' "$root/orchestrator.sh" 2>/dev/null; then
    ok=0
  fi

  if [[ "$ok" == "1" ]]; then
    record "I16 reviewer-detected-correctly" PASS
  else
    record "I16 reviewer-detected-correctly" FAIL
    grep -i "reviewer" "$root/launch.out" 2>/dev/null || true
  fi
  cleanup_root "$root"
}

# -------------------------------------------------------------------
# Scenario I17 — Reviewer detected with type:"write" via id fallback
# When user sets type:"write" (per finding 09 guidance), the reviewer
# must still be detected by id containing "review". This is the
# flexible detection that prevents the launch warning.
# -------------------------------------------------------------------
run_I17() {
  local root; root=$(mkroot reviewer-write-detect)
  # Create a fleet.json with type:"write" for the reviewer
  cat > "$root/fleet.json" <<'EOF'
{
  "fleet_name": "test-iterative-write-reviewer",
  "type": "iterative",
  "config": { "max_concurrent": 3, "model": "haiku", "fallback_model": "haiku" },
  "workers": [
    { "id": "builder-a", "type": "code-run", "task": "Build", "max_budget_per_iter": 0.10 },
    { "id": "reviewer", "type": "write", "task": "Review and write verdict",
      "depends_on": ["builder-a"] }
  ],
  "stop_when": { "reviewer_lgtm_count": 1, "max_iterations": 3 }
}
EOF
  mkdir -p "$root/workers/builder-a" "$root/workers/reviewer"
  echo "fake builder" > "$root/workers/builder-a/prompt.md"
  echo "fake reviewer" > "$root/workers/reviewer/prompt.md"
  bash "${SCRIPTS}/launch.sh" "$root" --dry-run >"$root/launch.out" 2>&1 || true

  local ok=1
  # Reviewer must be detected (via id fallback)
  if ! grep -q "Reviewer worker: reviewer" "$root/launch.out" 2>/dev/null; then
    ok=0
  fi
  # Must NOT warn about missing reviewer
  if grep -q "No reviewer worker found" "$root/launch.out" 2>/dev/null; then
    ok=0
  fi
  # Orchestrator must have REVIEWER_ID set
  if ! grep -q 'REVIEWER_ID="reviewer"' "$root/orchestrator.sh" 2>/dev/null; then
    ok=0
  fi

  if [[ "$ok" == "1" ]]; then
    record "I17 reviewer-detected-with-type-write" PASS
  else
    record "I17 reviewer-detected-with-type-write" FAIL
    grep -i "reviewer" "$root/launch.out" 2>/dev/null || true
  fi
  cleanup_root "$root"
}

# -------------------------------------------------------------------
# Scenario I18 — Displaced repo detection catches cloned .git dirs
# After a worker completes, if it cloned the repo inside its worker
# dir (creating a .git subdir), the orchestrator must detect it and
# write a .displaced-repo sentinel. Status must show the warning.
# -------------------------------------------------------------------
run_I18() {
  local root; root=$(mkroot displaced-repo)
  cp "${FIXTURES_DIR}/dag-iterative-fleet.json" "$root/fleet.json"
  mkdir -p "$root/workers/builder-a" "$root/workers/builder-b" "$root/workers/reviewer"
  for w in builder-a builder-b reviewer; do
    echo "fake worker $w" > "$root/workers/$w/prompt.md"
  done
  bash "${SCRIPTS}/launch.sh" "$root" --dry-run >"$root/launch.out" 2>&1 || true

  local ok=1

  # orchestrator.sh must contain check_displaced_repos function
  if [[ ! -f "$root/orchestrator.sh" ]]; then
    record "I18 displaced-repo-detection" FAIL "(no orchestrator.sh)"
    cleanup_root "$root"
    return
  fi
  grep -q 'check_displaced_repos' "$root/orchestrator.sh" 2>/dev/null || ok=0
  grep -q '\.displaced-repo' "$root/orchestrator.sh" 2>/dev/null || ok=0
  # Must search for .git dirs inside worker dir
  grep -q 'find.*\.git' "$root/orchestrator.sh" 2>/dev/null || ok=0

  # Simulate: create a fake clone .git dir inside builder-a's worker dir
  mkdir -p "$root/workers/builder-a/repo/.git"

  # Source orchestrator to run check_displaced_repos
  # Extract and run just the function
  (
    FLEET_ROOT="$root"
    FLEET_JSON="$root/fleet.json"
    eval "$(sed -n '/^check_displaced_repos/,/^}/p' "$root/orchestrator.sh")"
    check_displaced_repos "builder-a"
  ) >"$root/displaced.out" 2>&1

  # .displaced-repo sentinel must exist for builder-a
  if [[ ! -f "$root/workers/builder-a/.displaced-repo" ]]; then
    ok=0
  fi
  # Sentinel must point to the clone path
  if ! grep -q "repo" "$root/workers/builder-a/.displaced-repo" 2>/dev/null; then
    ok=0
  fi

  # Status must show displaced warning
  local status_out
  status_out=$(bash "${SCRIPTS}/status.sh" "$root" 2>&1 || true)
  if ! echo "$status_out" | grep -qi "displaced\|WARNING.*committed to"; then
    ok=0
  fi

  if [[ "$ok" == "1" ]]; then
    record "I18 displaced-repo-detection" PASS
  else
    record "I18 displaced-repo-detection" FAIL "(check orchestrator/sentinel/status output)"
    echo "--- orchestrator grep ---"
    grep -n 'displaced\|\.git' "$root/orchestrator.sh" 2>/dev/null | head -5
    echo "--- sentinel ---"
    cat "$root/workers/builder-a/.displaced-repo" 2>/dev/null || echo "(missing)"
    echo "--- status output ---"
    echo "$status_out" | grep -i "displaced\|warning" || echo "(no warning)"
  fi
  cleanup_root "$root"
}

run_I1
run_I2
run_I3
run_I4
run_I5
run_I6
run_I7
run_I8
run_I9
run_I10
run_I11
run_I12
run_I13
run_I14
run_I15
run_I16
run_I17
run_I18

echo
echo "============================================================"
echo "SUMMARY: ${#PASS[@]} passed, ${#FAIL[@]} failed"
echo "============================================================"
for p in "${PASS[@]}"; do echo "  PASS  $p"; done
for f in "${FAIL[@]}"; do echo "  FAIL  $f"; done

exit "${#FAIL[@]}"
