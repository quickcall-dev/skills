#!/usr/bin/env bash
# Test harness for the doc skill
# Usage: run-all.sh <skill-dir>
#   e.g. run-all.sh skills/doc
#
# Creates a temporary git repo, runs all doc commands against it,
# asserts on filesystem state. No API calls. Exit code = number of failures.

set -uo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: run-all.sh <doc-skill-dir>" >&2
  exit 99
fi

SKILL_DIR="$(cd "$1" && pwd)"
SCRIPTS="${SKILL_DIR}/scripts"

# Verify required scripts exist
for s in start.sh expt.sh plan.sh finding.sh ckpt.sh research.sh review.sh \
         learn.sh list.sh status.sh resume.sh _common.sh; do
  if [[ ! -f "${SCRIPTS}/$s" ]]; then
    echo "FATAL: missing ${SCRIPTS}/$s" >&2
    exit 99
  fi
done

# ---------------------------------------------------------------------------
# Test infrastructure
# ---------------------------------------------------------------------------
PASS=0
FAIL=0
RESULTS=()

record() {
  local name="$1" verdict="$2" detail="${3:-}"
  if [[ "$verdict" == "PASS" ]]; then
    echo -e "\033[0;32m[PASS]\033[0m $name $detail"
    PASS=$((PASS + 1))
  else
    echo -e "\033[0;31m[FAIL]\033[0m $name $detail"
    FAIL=$((FAIL + 1))
  fi
  RESULTS+=("$verdict  $name")
}

# Create isolated temp git repo
mkroot() {
  local tag="$1"
  local root
  root=$(mktemp -d "/tmp/doc-test-${tag}-$$-XXXXXX")
  git -C "$root" init -q
  git -C "$root" config user.email "test@test.com"
  git -C "$root" config user.name "Test"
  # Need at least one commit for git to work properly
  touch "$root/.gitkeep"
  git -C "$root" add . && git -C "$root" commit -q -m "init"
  echo "$root"
}

cleanup_root() {
  rm -rf "$1" 2>/dev/null
}

# ---------------------------------------------------------------------------
# D1: start.sh creates docs structure + experiment
# ---------------------------------------------------------------------------
run_D1() {
  local root; root=$(mkroot D1)
  cd "$root"
  local out
  out=$(bash "${SCRIPTS}/start.sh" "test investigation" 2>&1)
  local rc=$?

  local ok=1
  # Check exit code
  [[ $rc -ne 0 ]] && ok=0

  # Check docs/ structure created
  [[ -d "$root/docs/architecture" ]] || ok=0
  [[ -d "$root/docs/guides" ]] || ok=0
  [[ -d "$root/docs/learnings" ]] || ok=0
  [[ -d "$root/docs/experiments" ]] || ok=0

  # Check experiment created
  local expt_dir
  expt_dir=$(find "$root/docs/experiments" -maxdepth 1 -name "001-*" -type d | head -1)
  [[ -n "$expt_dir" ]] || ok=0

  if [[ -n "$expt_dir" ]]; then
    # Check subdirs
    [[ -d "$expt_dir/plans" ]] || ok=0
    [[ -d "$expt_dir/findings" ]] || ok=0
    [[ -d "$expt_dir/checkpoints" ]] || ok=0
    [[ -d "$expt_dir/research" ]] || ok=0
    [[ -d "$expt_dir/review" ]] || ok=0

    # Check .meta.json
    [[ -f "$expt_dir/.meta.json" ]] || ok=0
    if [[ -f "$expt_dir/.meta.json" ]]; then
      local status
      status=$(python3 -c "import json; m=json.load(open('$expt_dir/.meta.json')); print(m['status'])" 2>/dev/null)
      [[ "$status" == "planning" ]] || ok=0
    fi

    # Check experiment name slugified
    local base
    base=$(basename "$expt_dir")
    [[ "$base" == "001-test-investigation" ]] || ok=0
  fi

  if [[ $ok -eq 1 ]]; then
    record "D1 start-creates-structure" PASS
  else
    record "D1 start-creates-structure" FAIL "(dir=$expt_dir)"
  fi

  cd /tmp
  cleanup_root "$root"
}

# ---------------------------------------------------------------------------
# D2: expt.sh creates experiment without docs scaffold
# ---------------------------------------------------------------------------
run_D2() {
  local root; root=$(mkroot D2)
  cd "$root"
  # First create docs structure
  bash "${SCRIPTS}/start.sh" "first" >/dev/null 2>&1
  # Then create second experiment with expt.sh
  local out
  out=$(bash "${SCRIPTS}/expt.sh" "second experiment" 2>&1)
  local rc=$?

  local ok=1
  [[ $rc -ne 0 ]] && ok=0

  local expt_dir
  expt_dir=$(find "$root/docs/experiments" -maxdepth 1 -name "002-*" -type d | head -1)
  [[ -n "$expt_dir" ]] || ok=0
  if [[ -n "$expt_dir" ]]; then
    [[ -f "$expt_dir/.meta.json" ]] || ok=0
    local base; base=$(basename "$expt_dir")
    [[ "$base" == "002-second-experiment" ]] || ok=0
  fi

  if [[ $ok -eq 1 ]]; then
    record "D2 expt-creates-numbered" PASS
  else
    record "D2 expt-creates-numbered" FAIL
  fi

  cd /tmp
  cleanup_root "$root"
}

# ---------------------------------------------------------------------------
# D3: plan.sh creates numbered plan with frontmatter
# ---------------------------------------------------------------------------
run_D3() {
  local root; root=$(mkroot D3)
  cd "$root"
  bash "${SCRIPTS}/start.sh" "plan-test" >/dev/null 2>&1
  local out
  out=$(bash "${SCRIPTS}/plan.sh" 1 "migration strategy" 2>&1)
  local rc=$?

  local ok=1
  [[ $rc -ne 0 ]] && ok=0

  local plan_file
  plan_file=$(find "$root/docs/experiments/001-plan-test/plans" -name "01-*.md" -type f | head -1)
  [[ -n "$plan_file" ]] || ok=0

  if [[ -n "$plan_file" ]]; then
    # Check frontmatter has title
    grep -q 'title: "migration strategy"' "$plan_file" || ok=0
    # Check filename slug
    local base; base=$(basename "$plan_file")
    [[ "$base" == "01-migration-strategy.md" ]] || ok=0
  fi

  # Check meta updated
  local meta="$root/docs/experiments/001-plan-test/.meta.json"
  if [[ -f "$meta" ]]; then
    local count
    count=$(python3 -c "import json; print(json.load(open('$meta'))['plan_count'])" 2>/dev/null)
    [[ "$count" == "1" ]] || ok=0
  else
    ok=0
  fi

  if [[ $ok -eq 1 ]]; then
    record "D3 plan-creates-numbered-file" PASS
  else
    record "D3 plan-creates-numbered-file" FAIL "(file=$plan_file)"
  fi

  cd /tmp
  cleanup_root "$root"
}

# ---------------------------------------------------------------------------
# D4: finding.sh creates numbered finding
# ---------------------------------------------------------------------------
run_D4() {
  local root; root=$(mkroot D4)
  cd "$root"
  bash "${SCRIPTS}/start.sh" "finding-test" >/dev/null 2>&1
  bash "${SCRIPTS}/finding.sh" 1 "key insight" >/dev/null 2>&1
  local rc=$?

  local ok=1
  [[ $rc -ne 0 ]] && ok=0

  local file
  file=$(find "$root/docs/experiments/001-finding-test/findings" -name "01-key-insight.md" -type f | head -1)
  [[ -n "$file" ]] || ok=0
  [[ -n "$file" ]] && grep -q 'title: "key insight"' "$file" || ok=0

  # Meta updated
  local count
  count=$(python3 -c "import json; print(json.load(open('$root/docs/experiments/001-finding-test/.meta.json'))['finding_count'])" 2>/dev/null)
  [[ "$count" == "1" ]] || ok=0

  if [[ $ok -eq 1 ]]; then
    record "D4 finding-creates-file" PASS
  else
    record "D4 finding-creates-file" FAIL
  fi

  cd /tmp
  cleanup_root "$root"
}

# ---------------------------------------------------------------------------
# D5: ckpt.sh creates checkpoint
# ---------------------------------------------------------------------------
run_D5() {
  local root; root=$(mkroot D5)
  cd "$root"
  bash "${SCRIPTS}/start.sh" "ckpt-test" >/dev/null 2>&1
  local out
  out=$(bash "${SCRIPTS}/ckpt.sh" 1 "progress snapshot" 2>&1)
  local rc=$?

  local ok=1
  [[ $rc -ne 0 ]] && ok=0

  local file
  file=$(find "$root/docs/experiments/001-ckpt-test/checkpoints" -name "01-progress-snapshot.md" -type f | head -1)
  [[ -n "$file" ]] || ok=0
  [[ -n "$file" ]] && grep -q 'title: "progress snapshot"' "$file" || ok=0

  # Should print ACTION REQUIRED warning
  echo "$out" | grep -q "ACTION REQUIRED" || ok=0

  if [[ $ok -eq 1 ]]; then
    record "D5 ckpt-creates-file" PASS
  else
    record "D5 ckpt-creates-file" FAIL
  fi

  cd /tmp
  cleanup_root "$root"
}

# ---------------------------------------------------------------------------
# D6: research.sh creates prompt + response pair
# ---------------------------------------------------------------------------
run_D6() {
  local root; root=$(mkroot D6)
  cd "$root"
  bash "${SCRIPTS}/start.sh" "research-test" >/dev/null 2>&1
  bash "${SCRIPTS}/research.sh" 1 "api design" >/dev/null 2>&1
  local rc=$?

  local ok=1
  [[ $rc -ne 0 ]] && ok=0

  local prompt_file response_file
  prompt_file=$(find "$root/docs/experiments/001-research-test/research" -name "*prompt*api-design*" -type f | head -1)
  response_file=$(find "$root/docs/experiments/001-research-test/research" -name "*res*api-design*" -type f | head -1)
  [[ -n "$prompt_file" ]] || ok=0
  [[ -n "$response_file" ]] || ok=0

  # Meta updated
  local count
  count=$(python3 -c "import json; print(json.load(open('$root/docs/experiments/001-research-test/.meta.json'))['research_count'])" 2>/dev/null)
  [[ "$count" == "1" ]] || ok=0

  if [[ $ok -eq 1 ]]; then
    record "D6 research-creates-pair" PASS
  else
    record "D6 research-creates-pair" FAIL
  fi

  cd /tmp
  cleanup_root "$root"
}

# ---------------------------------------------------------------------------
# D7: review.sh creates review file
# ---------------------------------------------------------------------------
run_D7() {
  local root; root=$(mkroot D7)
  cd "$root"
  bash "${SCRIPTS}/start.sh" "review-test" >/dev/null 2>&1
  bash "${SCRIPTS}/review.sh" 1 "code quality" >/dev/null 2>&1
  local rc=$?

  local ok=1
  [[ $rc -ne 0 ]] && ok=0

  local file
  file=$(find "$root/docs/experiments/001-review-test/review" -name "*review*code-quality*" -type f | head -1)
  [[ -n "$file" ]] || ok=0
  [[ -n "$file" ]] && grep -q 'verdict: ""' "$file" || ok=0

  if [[ $ok -eq 1 ]]; then
    record "D7 review-creates-file" PASS
  else
    record "D7 review-creates-file" FAIL
  fi

  cd /tmp
  cleanup_root "$root"
}

# ---------------------------------------------------------------------------
# D8: learn.sh creates learning in domain dir + validates domain
# ---------------------------------------------------------------------------
run_D8() {
  local root; root=$(mkroot D8)
  cd "$root"
  bash "${SCRIPTS}/start.sh" "learn-test" >/dev/null 2>&1
  bash "${SCRIPTS}/learn.sh" 1 "skills" "directory convention" >/dev/null 2>&1
  local rc=$?

  local ok=1
  [[ $rc -ne 0 ]] && ok=0

  local file
  file=$(find "$root/docs/learnings/skills" -name "*directory-convention*" -type f | head -1)
  [[ -n "$file" ]] || ok=0
  [[ -n "$file" ]] && grep -q 'graduated_from:' "$file" || ok=0
  [[ -n "$file" ]] && grep -q 'domain: skills' "$file" || ok=0

  # Meta should be updated to "graduated"
  local status
  status=$(python3 -c "import json; print(json.load(open('$root/docs/experiments/001-learn-test/.meta.json'))['status'])" 2>/dev/null)
  [[ "$status" == "graduated" ]] || ok=0

  if [[ $ok -eq 1 ]]; then
    record "D8 learn-creates-in-domain" PASS
  else
    record "D8 learn-creates-in-domain" FAIL
  fi

  cd /tmp
  cleanup_root "$root"
}

# ---------------------------------------------------------------------------
# D9: learn.sh rejects invalid domain
# ---------------------------------------------------------------------------
run_D9() {
  local root; root=$(mkroot D9)
  cd "$root"
  bash "${SCRIPTS}/start.sh" "domain-test" >/dev/null 2>&1
  local out
  out=$(bash "${SCRIPTS}/learn.sh" 1 "invalid-domain" "test" 2>&1)
  local rc=$?

  if [[ $rc -ne 0 ]] && echo "$out" | grep -q "not a valid domain"; then
    record "D9 learn-rejects-invalid-domain" PASS
  else
    record "D9 learn-rejects-invalid-domain" FAIL "(rc=$rc)"
  fi

  cd /tmp
  cleanup_root "$root"
}

# ---------------------------------------------------------------------------
# D10: next_number increments correctly
# ---------------------------------------------------------------------------
run_D10() {
  local root; root=$(mkroot D10)
  cd "$root"
  bash "${SCRIPTS}/start.sh" "numbering" >/dev/null 2>&1
  bash "${SCRIPTS}/finding.sh" 1 "first" >/dev/null 2>&1
  bash "${SCRIPTS}/finding.sh" 1 "second" >/dev/null 2>&1
  bash "${SCRIPTS}/finding.sh" 1 "third" >/dev/null 2>&1

  local ok=1
  local dir="$root/docs/experiments/001-numbering/findings"
  [[ -f "$dir/01-first.md" ]] || ok=0
  [[ -f "$dir/02-second.md" ]] || ok=0
  [[ -f "$dir/03-third.md" ]] || ok=0

  # Meta count should be 3
  local count
  count=$(python3 -c "import json; print(json.load(open('$root/docs/experiments/001-numbering/.meta.json'))['finding_count'])" 2>/dev/null)
  [[ "$count" == "3" ]] || ok=0

  if [[ $ok -eq 1 ]]; then
    record "D10 numbering-increments" PASS
  else
    record "D10 numbering-increments" FAIL
  fi

  cd /tmp
  cleanup_root "$root"
}

# ---------------------------------------------------------------------------
# D11: slugify handles edge cases
# ---------------------------------------------------------------------------
run_D11() {
  local root; root=$(mkroot D11)
  cd "$root"
  bash "${SCRIPTS}/start.sh" "slug-test" >/dev/null 2>&1

  # Uppercase + spaces
  bash "${SCRIPTS}/plan.sh" 1 "My Big Plan" >/dev/null 2>&1
  # Underscores
  bash "${SCRIPTS}/finding.sh" 1 "some_finding_here" >/dev/null 2>&1
  # Special chars
  bash "${SCRIPTS}/ckpt.sh" 1 "v1.0 done!" >/dev/null 2>&1

  local ok=1
  [[ -f "$root/docs/experiments/001-slug-test/plans/01-my-big-plan.md" ]] || ok=0
  [[ -f "$root/docs/experiments/001-slug-test/findings/01-some-finding-here.md" ]] || ok=0
  [[ -f "$root/docs/experiments/001-slug-test/checkpoints/01-v10-done.md" ]] || ok=0

  if [[ $ok -eq 1 ]]; then
    record "D11 slugify-edge-cases" PASS
  else
    record "D11 slugify-edge-cases" FAIL
  fi

  cd /tmp
  cleanup_root "$root"
}

# ---------------------------------------------------------------------------
# D12: list.sh shows experiments
# ---------------------------------------------------------------------------
run_D12() {
  local root; root=$(mkroot D12)
  cd "$root"
  bash "${SCRIPTS}/start.sh" "alpha" >/dev/null 2>&1
  bash "${SCRIPTS}/start.sh" "beta" >/dev/null 2>&1

  local out
  out=$(bash "${SCRIPTS}/list.sh" 2>&1)

  local ok=1
  echo "$out" | grep -q "001-alpha" || ok=0
  echo "$out" | grep -q "002-beta" || ok=0
  echo "$out" | grep -q "planning" || ok=0

  if [[ $ok -eq 1 ]]; then
    record "D12 list-shows-experiments" PASS
  else
    record "D12 list-shows-experiments" FAIL
  fi

  cd /tmp
  cleanup_root "$root"
}

# ---------------------------------------------------------------------------
# D13: status.sh shows experiment details
# ---------------------------------------------------------------------------
run_D13() {
  local root; root=$(mkroot D13)
  cd "$root"
  bash "${SCRIPTS}/start.sh" "status-test" >/dev/null 2>&1
  bash "${SCRIPTS}/plan.sh" 1 "my plan" >/dev/null 2>&1
  bash "${SCRIPTS}/finding.sh" 1 "my finding" >/dev/null 2>&1

  local out
  out=$(bash "${SCRIPTS}/status.sh" 1 2>&1)

  local ok=1
  echo "$out" | grep -q "001-status-test" || ok=0
  echo "$out" | grep -q "Plans:.*1" || ok=0
  echo "$out" | grep -q "Findings:.*1" || ok=0

  if [[ $ok -eq 1 ]]; then
    record "D13 status-shows-details" PASS
  else
    record "D13 status-shows-details" FAIL
  fi

  cd /tmp
  cleanup_root "$root"
}

# ---------------------------------------------------------------------------
# D14: resume.sh outputs plan + checkpoint
# ---------------------------------------------------------------------------
run_D14() {
  local root; root=$(mkroot D14)
  cd "$root"
  bash "${SCRIPTS}/start.sh" "resume-test" >/dev/null 2>&1
  bash "${SCRIPTS}/plan.sh" 1 "the plan" >/dev/null 2>&1
  bash "${SCRIPTS}/ckpt.sh" 1 "checkpoint one" >/dev/null 2>&1

  local out
  out=$(bash "${SCRIPTS}/resume.sh" 1 2>&1)

  local ok=1
  echo "$out" | grep -q "Resuming experiment 1" || ok=0
  echo "$out" | grep -q "Latest plan:" || ok=0
  echo "$out" | grep -q "Latest checkpoint:" || ok=0

  if [[ $ok -eq 1 ]]; then
    record "D14 resume-outputs-context" PASS
  else
    record "D14 resume-outputs-context" FAIL
  fi

  cd /tmp
  cleanup_root "$root"
}

# ---------------------------------------------------------------------------
# D15: resolve_experiment rejects unknown index
# ---------------------------------------------------------------------------
run_D15() {
  local root; root=$(mkroot D15)
  cd "$root"
  bash "${SCRIPTS}/start.sh" "resolve-test" >/dev/null 2>&1

  local out
  out=$(bash "${SCRIPTS}/plan.sh" 99 "should fail" 2>&1)
  local rc=$?

  if [[ $rc -ne 0 ]] && echo "$out" | grep -q "no experiment matching"; then
    record "D15 resolve-rejects-unknown" PASS
  else
    record "D15 resolve-rejects-unknown" FAIL "(rc=$rc)"
  fi

  cd /tmp
  cleanup_root "$root"
}

# ---------------------------------------------------------------------------
# D16: cfg reads defaults.yaml correctly
# ---------------------------------------------------------------------------
run_D16() {
  local root; root=$(mkroot D16)
  cd "$root"
  bash "${SCRIPTS}/start.sh" "cfg-test" >/dev/null 2>&1

  # docs_root should be "docs"
  local docs_root
  docs_root=$(cd "$root" && python3 -c "
import yaml
with open('${SKILL_DIR}/config/defaults.yaml') as f:
    c = yaml.safe_load(f)
print(c.get('docs_root', ''))
" 2>/dev/null)

  local ok=1
  [[ "$docs_root" == "docs" ]] || ok=0
  # Verify docs/ was created (not something else)
  [[ -d "$root/docs" ]] || ok=0

  if [[ $ok -eq 1 ]]; then
    record "D16 cfg-reads-defaults" PASS
  else
    record "D16 cfg-reads-defaults" FAIL "(docs_root=$docs_root)"
  fi

  cd /tmp
  cleanup_root "$root"
}

# ---------------------------------------------------------------------------
# D17: multiple experiments number correctly
# ---------------------------------------------------------------------------
run_D17() {
  local root; root=$(mkroot D17)
  cd "$root"
  bash "${SCRIPTS}/start.sh" "first" >/dev/null 2>&1
  bash "${SCRIPTS}/expt.sh" "second" >/dev/null 2>&1
  bash "${SCRIPTS}/expt.sh" "third" >/dev/null 2>&1

  local ok=1
  [[ -d "$root/docs/experiments/001-first" ]] || ok=0
  [[ -d "$root/docs/experiments/002-second" ]] || ok=0
  [[ -d "$root/docs/experiments/003-third" ]] || ok=0

  if [[ $ok -eq 1 ]]; then
    record "D17 experiment-numbering-sequence" PASS
  else
    record "D17 experiment-numbering-sequence" FAIL
  fi

  cd /tmp
  cleanup_root "$root"
}

# ---------------------------------------------------------------------------
# D18: missing args produce usage errors
# ---------------------------------------------------------------------------
run_D18() {
  local root; root=$(mkroot D18)
  cd "$root"

  local ok=1
  bash "${SCRIPTS}/start.sh" 2>/dev/null && ok=0
  bash "${SCRIPTS}/plan.sh" 2>/dev/null && ok=0
  bash "${SCRIPTS}/finding.sh" 2>/dev/null && ok=0
  bash "${SCRIPTS}/ckpt.sh" 2>/dev/null && ok=0
  bash "${SCRIPTS}/research.sh" 2>/dev/null && ok=0
  bash "${SCRIPTS}/learn.sh" 2>/dev/null && ok=0

  if [[ $ok -eq 1 ]]; then
    record "D18 missing-args-exit-nonzero" PASS
  else
    record "D18 missing-args-exit-nonzero" FAIL
  fi

  cd /tmp
  cleanup_root "$root"
}

# ---------------------------------------------------------------------------
# D19: meta.json last_activity updates
# ---------------------------------------------------------------------------
run_D19() {
  local root; root=$(mkroot D19)
  cd "$root"
  bash "${SCRIPTS}/start.sh" "activity-test" >/dev/null 2>&1

  local meta="$root/docs/experiments/001-activity-test/.meta.json"
  local ts1
  ts1=$(python3 -c "import json; print(json.load(open('$meta'))['last_activity'])" 2>/dev/null)

  sleep 1
  bash "${SCRIPTS}/finding.sh" 1 "bump activity" >/dev/null 2>&1

  local ts2
  ts2=$(python3 -c "import json; print(json.load(open('$meta'))['last_activity'])" 2>/dev/null)

  if [[ "$ts1" != "$ts2" ]]; then
    record "D19 meta-last-activity-updates" PASS
  else
    record "D19 meta-last-activity-updates" FAIL "(ts1=$ts1 ts2=$ts2)"
  fi

  cd /tmp
  cleanup_root "$root"
}

# ---------------------------------------------------------------------------
# Run all
# ---------------------------------------------------------------------------
run_D1
run_D2
run_D3
run_D4
run_D5
run_D6
run_D7
run_D8
run_D9
run_D10
run_D11
run_D12
run_D13
run_D14
run_D15
run_D16
run_D17
run_D18
run_D19

echo ""
echo "============================================================"
echo "DOC SKILL SUMMARY: $PASS passed, $FAIL failed"
echo "============================================================"
for r in "${RESULTS[@]}"; do
  echo "  $r"
done

exit "$FAIL"
