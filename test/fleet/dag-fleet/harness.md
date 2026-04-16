# Fleet Orchestrator — Test Harness

Reusable directive for testing the fleet skill after any code change. Designed for an **outer-judge / inner-haiku-Claude** loop: the outer agent (you, reading this) drives an inner Claude in a tmux session, sends it fleet commands in natural language, and judges results by inspecting filesystem + `ps` + tmux state directly.

> **Hard rule.** Only touch tmux sessions named `skill-test-fleet` and `fleet`. Never kill, attach to, or send keys to any other session. Run `tmux list-sessions` before destructive ops and verify your target.

---

## 0. Prerequisites

```bash
which tmux asciinema claude jq python3 && echo OK
ls /home/sagar/skills/skills/dag-fleet/scripts/ | wc -l   # expect 10
```

If global `~/.claude/skills/dag-fleet/scripts/` is missing (problem #11 in the wild), that's fine — the harness uses an isolated copy.

---

## 1. One-time setup per test run

```bash
# 1a. Fresh test dir + skill copy
TEST_DIR=/tmp/fleet-test-skill-test-fleet
rm -rf "$TEST_DIR"
mkdir -p "$TEST_DIR/.claude/skills"
cp -r /home/sagar/skills/skills/dag-fleet "$TEST_DIR/.claude/skills/dag-fleet"
chmod +x "$TEST_DIR/.claude/skills/dag-fleet/scripts/"*.sh

# 1b. Verify outer session name is free
tmux has-session -t skill-test-fleet 2>/dev/null && echo "ABORT — session exists" || echo OK

# 1c. Snapshot tmux sessions you must NOT touch
tmux list-sessions -F '#{session_name}' | tee /tmp/protected-sessions.txt
```

---

## 2. Spawn inner Claude

```bash
tmux new-session -d -s skill-test-fleet -n claude -x 220 -y 50
tmux send-keys -t skill-test-fleet:claude \
  "cd $TEST_DIR && asciinema rec recording.cast --overwrite -c 'claude --dangerously-skip-permissions --model haiku'" Enter
sleep 8
tmux capture-pane -p -t skill-test-fleet:claude | tail -10   # confirm Claude prompt is up
```

If you see `❯` and `Haiku 4.5`, you're good.

---

## 3. Sending commands to inner Claude

Inner Claude has no `/fleet` slash command (none installed globally), so you drive it in **natural language** referencing the local skill path. Pattern:

```bash
PROMPT='Run bash .claude/skills/dag-fleet/scripts/<script>.sh <args>. Show me the output.'
tmux send-keys -t skill-test-fleet:claude -- "$PROMPT"
sleep 1
tmux send-keys -t skill-test-fleet:claude Enter
sleep 20   # wait for inner Claude to act
tmux capture-pane -p -t skill-test-fleet:claude | tail -40
```

The `--` is essential — without it, prompts starting with `-` are parsed as flags.

---

## 4. The 4 reproducer scenarios (run these against the current build, judge each)

Each scenario maps to one or more `problems.md` issues. After every Phase 0/1 code change, re-run all 4 — they should flip from FAIL to PASS without regressing the others.

### Scenario A — silent-liveness inversion (#4, #7, #17)

**Goal:** prove that `status.sh` reflects actual worker state, including descendant subprocesses.

```bash
# 4a.1 — launch 3 echo-loop workers via inner Claude
PROMPT='Use the fleet skill at .claude/skills/fleet to launch a fleet at /tmp/fleet-test-skill-test-fleet/fleet. 3 code-run workers, claude-haiku-4-5 model, max_turns 5, max_budget_usd 0.05. Tasks: echo-01 runs `for i in $(seq 1 100); do echo "echo-01 line $i BEFORE-STEER" >> output/lines.txt; sleep 2; done`. echo-02 same with echo-02. echo-03 same with echo-03. Then run launch.sh.'
tmux send-keys -t skill-test-fleet:claude -- "$PROMPT"; sleep 1; tmux send-keys -t skill-test-fleet:claude Enter
sleep 30
```

```bash
# 4a.2 — judge directly (do NOT trust inner Claude's report)
wc -l /tmp/fleet-test-skill-test-fleet/fleet/workers/*/output/lines.txt
ps -ef | grep -F BEFORE-STEER | grep -v grep | wc -l   # expect 3 bash loops
```

```bash
# 4a.3 — ask inner Claude to run status.sh
PROMPT='Run bash .claude/skills/dag-fleet/scripts/status.sh /tmp/fleet-test-skill-test-fleet/fleet'
tmux send-keys -t skill-test-fleet:claude -- "$PROMPT"; sleep 1; tmux send-keys -t skill-test-fleet:claude Enter
sleep 15
tmux capture-pane -p -t skill-test-fleet:claude | tail -25
```

**PASS criteria** (all must hold):
- `status.sh` reports workers as RUNNING (not DONE) while `ps -ef | grep BEFORE-STEER` shows live loops
- `status.sh` cost column reflects something non-zero only for actual claude usage; subprocess work doesn't fake DONE
- After the bash loops complete naturally (~200s), `status.sh` then reports DONE and `lines.txt` has 100 lines each

**Current baseline (broken):** workers reported DONE within 60s while loops at line ~40/100. (Findings #1, #2 in test-results-baseline.md.)

### Scenario B — monitor pane shows live status (P1.1)

```bash
tmux capture-pane -p -t fleet:monitor
```

**PASS:** dashboard rendered (worker table, costs, summary line).
**Current baseline:** bare bash prompt, blank pane.

### Scenario C — steer preserves tool grants (#6)

Run scenario A first so a worker exists, then:

```bash
PROMPT='Run bash .claude/skills/dag-fleet/scripts/steer.sh /tmp/fleet-test-skill-test-fleet/fleet echo-01 "Change marker to AFTER-STEER instead of BEFORE-STEER and continue the loop"'
tmux send-keys -t skill-test-fleet:claude -- "$PROMPT"; sleep 1; tmux send-keys -t skill-test-fleet:claude Enter
sleep 30

# Judge: compare command lines
ps -ef | grep -F "fleet-fleet-echo-01" | grep -v grep
```

**PASS:** the steered claude command line contains the **same** `--disallowed-tools` set as the original launch (or none, if launch had none for this worker type).
**Current baseline:** steered command has `--disallowed-tools 'Agent,WebFetch,WebSearch'` injected; original had none. (Finding #3.)

Also verify cleanliness of the marker transition:

```bash
grep -c BEFORE-STEER /tmp/fleet-test-skill-test-fleet/fleet/workers/echo-01/output/lines.txt
grep -c AFTER-STEER  /tmp/fleet-test-skill-test-fleet/fleet/workers/echo-01/output/lines.txt
tail -20 /tmp/fleet-test-skill-test-fleet/fleet/workers/echo-01/output/lines.txt
```

**PASS:** all BEFORE lines first, then all AFTER, no interleaving (confirms steer killed the prior process group).

### Scenario D — kill all leaves zero orphans (#17)

After scenarios A and C have a fleet running:

```bash
PROMPT='Run bash .claude/skills/dag-fleet/scripts/kill.sh /tmp/fleet-test-skill-test-fleet/fleet all --force'
tmux send-keys -t skill-test-fleet:claude -- "$PROMPT"; sleep 1; tmux send-keys -t skill-test-fleet:claude Enter
sleep 15

# Judge: enumerate ALL descendants of the test dir, regardless of parent
ps -ef | grep -F /tmp/fleet-test-skill-test-fleet | grep -v grep | grep -v 'asciinema rec recording'
tmux has-session -t fleet 2>/dev/null && echo "FAIL: fleet session still up" || echo "tmux gone OK"
```

**PASS:** zero matching processes, fleet tmux session destroyed, `kill.sh` exits 0.
**Current baseline:** 1 of 3 orphans survives, reparented to PID 1, still writing to `lines.txt`. `kill.sh` reports success anyway. (Finding #4.)

---

## 5. Per-Phase-item additional scenarios

When you implement a specific Phase item from `implementation-plan.md`, also run its targeted check:

| Phase item | Quick test |
|--|--|
| P0.1 per-worker spawn lock | After scenario A is running, re-run `launch.sh` from a second shell. Expect: every worker logs "already has a tmux window — skipping", no second claude PID per worker, `session.jsonl` files untouched. |
| P0.2 fleet launcher lock | Run `launch.sh` twice in parallel from two shells. Second exits 2 with the lock message; `cat $FLEET_ROOT/.launch.pid` matches the live one. |
| P0.3 verified workers terminal | Mid-run, `mv verify.sh verify.sh.bak`. Next orchestrator tick must NOT re-mark completed workers FAILED. |
| P0.4 missing-script pause | Continue from P0.3. Orchestrator logs one infra-paused warn line/min, heartbeat file keeps updating, no crash, exit code stays 0. |
| P1.3 liveness lines in status.sh | After killing the orchestrator manually, next `status.sh` tick shows a red orchestrator line within 60s. |
| P2.1 topo sort | Use a fleet.json with workers `[a, b, c-deps-on-a, d, e]`, `max_concurrent=4`. First wave must launch `{a, b, d, e}`, not `{a, b}`. |
| P2.2 per-worker stuck threshold | Add a worker that does `sleep 200` mid-task. Must not be auto-restarted under research-default threshold. |
| P3.1 completion sentinel | Let a healthy 2-worker fleet finish. Expect `${FLEET_ROOT}/COMPLETE` exists, `fleet.json.status == "completed"`, orchestrator exits 0, hook fires if configured. |

---

## 5a. Fake-worker scenarios E–L (fixture-driven, no real claude)

These scenarios exercise the Phase 0/2/3 fixes that Scenarios A–D can't reach
(they need DAG shapes, orchestrator runs, mid-run script removal, completion,
etc.). They all use the fake-claude shim at `test/fixtures/shim/claude` and
the fleet.json fixtures next to it — see `test/fixtures/README.md` for the
design.

**Activation (once per shell):**

```bash
FIXTURES=/home/sagar/skills/test/fleet/dag-fleet/fixtures-claude
SKILL=/home/sagar/skills/skills/dag-fleet
export PATH="${FIXTURES}/shim:${PATH}"
command -v claude   # must print ${FIXTURES}/shim/claude
```

All scenarios launch under `/tmp/fleet-test-fixtures-*` and use distinctive
tmux session names (`fleet-test-dag`, `fleet-test-stuck`, `fleet-test-completion`,
`fleet-test-cycle`) so they never collide with the A–D `fleet` session.

`test/fixtures/run-all.sh` drives E–L in sequence with per-scenario cleanup and
a summary table; use it for the normal path. The blocks below document each
scenario for manual runs and for debugging when `run-all.sh` fails.

---

### Scenario E — topo sort first wave (P2.1, problems #1)

**Setup:**
```bash
ROOT=/tmp/fleet-test-fixtures-E
rm -rf "$ROOT"; mkdir -p "$ROOT"
bash "$FIXTURES/setup-fleet.sh" dag "$ROOT"
```

**Run:**
```bash
bash "$SKILL/scripts/launch.sh" "$ROOT" >"$ROOT/launch.out" 2>&1 &
sleep 3
tmux list-windows -t fleet-test-dag -F '#W'
```

**Pass:** first wave contains `a`, `b`, `d`, `e` within ~2 seconds (plus `monitor`). `c` and `f` must be absent (they have deps). Verifies topo sort lets 4 independent workers start in parallel even though `c` sits between them in array order.

**Cleanup:** `tmux kill-session -t fleet-test-dag 2>/dev/null; pkill -f "FLEET_ROOT=$ROOT"; rm -rf "$ROOT"`

Addresses `problems.md` #1. Verifies `implementation-plan.md` P2.1.

---

### Scenario F — per-worker spawn lock (P0.1, problems #13, #14)

The cleanest per-worker-lock test is blocked by #19's whole-fleet refuse-clobber: a second `launch.sh` exits 3 before ever touching the spawn lock. So this scenario runs the second `launch.sh` on a live fleet, expects exit 3, and asserts that no `session.jsonl.*.bak` files are rotated and live worker jsonl mtimes are unchanged — proving no second spawn path fired.

**Setup:** same as E.

**Run:**
```bash
bash "$SKILL/scripts/launch.sh" "$ROOT" >"$ROOT/launch.out" 2>&1 &
LPID=$!
sleep 6
before=$(stat -c '%Y' "$ROOT/workers/b/session.jsonl")
bash "$SKILL/scripts/launch.sh" "$ROOT" >"$ROOT/relaunch.out" 2>&1
echo "rc=$?"
after=$(stat -c '%Y' "$ROOT/workers/b/session.jsonl")
ls "$ROOT/workers/b/"*.bak 2>/dev/null | wc -l
```

**Pass:** `rc=3`, `before == after`, zero `.bak` files. Proves no existing live worker was respawned. (True per-worker-lock stress — deleting a single worker dir mid-run and re-running launch — remains manual and needs #19 to add a `--allow-heal` escape hatch; tracked as a follow-up.)

**Cleanup:** `kill $LPID 2>/dev/null; tmux kill-session -t fleet-test-dag; pkill -f "FLEET_ROOT=$ROOT"; rm -rf "$ROOT"`

Addresses `problems.md` #13, #14. Verifies `implementation-plan.md` P0.1.

---

### Scenario G — topo cycle detection (P2.1)

**Setup:**
```bash
ROOT=/tmp/fleet-test-fixtures-G
rm -rf "$ROOT"; mkdir -p "$ROOT"
bash "$FIXTURES/setup-fleet.sh" cycle "$ROOT"
```

**Run:**
```bash
bash "$SKILL/scripts/launch.sh" "$ROOT" >"$ROOT/launch.out" 2>&1
echo "rc=$?"
grep CYCLE "$ROOT/launch.out"
tmux has-session -t fleet-test-cycle 2>/dev/null && echo FAIL || echo "no session OK"
```

**Pass:** nonzero exit, `CYCLE:a,b` (or `CYCLE:b,a`) on stderr captured in `launch.out`, no `fleet-test-cycle` tmux session created, no orphan claude/bash procs.

**Cleanup:** `rm -rf "$ROOT"`

Addresses `problems.md` #1 (cycle corner case). Verifies `implementation-plan.md` P2.1.

---

### Scenario H — verified-set terminal + missing-script pause (P0.3, P0.4, problems #11, #12)

**Setup:**
```bash
ROOT=/tmp/fleet-test-fixtures-H
rm -rf "$ROOT"; mkdir -p "$ROOT"
bash "$FIXTURES/setup-fleet.sh" completion "$ROOT"
```

**Run:**
```bash
bash "$SKILL/scripts/launch.sh" "$ROOT" >"$ROOT/launch.out" 2>&1
# Wait for workers to finish (sleep 3 tasks + launch delay)
sleep 15
bash "$SKILL/scripts/orchestrate.sh" "$ROOT" --interval 5 >"$ROOT/orch.out" 2>&1 &
OPID=$!
sleep 10
# Simulate mid-run script vanish (problems #11)
mv "$SKILL/scripts/verify.sh" "$SKILL/scripts/verify.sh.bak"
sleep 20
mv "$SKILL/scripts/verify.sh.bak" "$SKILL/scripts/verify.sh"
sleep 10
kill $OPID 2>/dev/null
grep -c 'max verify retries' "$ROOT/orch.out"
grep -c 'infra_paused\|infra paused\|infrastructure' "$ROOT/orch.out"
```

**Pass:** `max verify retries` count stays low (≤ 3 total across the whole run — one per already-verified worker, not repeated every tick). Orchestrator logs at most one infra-paused warn line per 60s during the missing-script window. No new FAILED markings of already-verified workers. After verify.sh is restored, completion path still fires.

**Cleanup:**
```bash
mv "$SKILL/scripts/verify.sh.bak" "$SKILL/scripts/verify.sh" 2>/dev/null || true
kill $OPID 2>/dev/null || true
tmux kill-session -t fleet-test-completion 2>/dev/null
pkill -f "FLEET_ROOT=$ROOT"; rm -rf "$ROOT"
```

Addresses `problems.md` #11, #12. Verifies `implementation-plan.md` P0.3, P0.4.

---

### Scenario I — per-worker stuck threshold + restart cap (P2.2, problems #5)

**Setup:**
```bash
ROOT=/tmp/fleet-test-fixtures-I
rm -rf "$ROOT"; mkdir -p "$ROOT"
bash "$FIXTURES/setup-fleet.sh" stuck "$ROOT"
```

**Run:**
```bash
bash "$SKILL/scripts/launch.sh" "$ROOT" >"$ROOT/launch.out" 2>&1 &
LPID=$!
sleep 5
bash "$SKILL/scripts/orchestrate.sh" "$ROOT" --interval 10 --stuck-threshold 30 >"$ROOT/orch.out" 2>&1 &
OPID=$!
sleep 90
kill $OPID $LPID 2>/dev/null
grep -c 'fast.*restart\|fast.*STUCK' "$ROOT/orch.out"
grep -c 'slow.*restart\|slow.*STUCK' "$ROOT/orch.out"
pgrep -af -- '-steered' | grep -c fleet-test-stuck || true
```

**Pass:** `fast` worker (has `stuck_threshold_seconds: 60`) restarted at most once; `slow` worker (default threshold) restarted at most once. `.restart-count` file caps further detections to log-only. Orchestrator never logs more than one restart action per worker.

**Cleanup:** `kill $OPID $LPID 2>/dev/null; tmux kill-session -t fleet-test-stuck 2>/dev/null; pkill -f "FLEET_ROOT=$ROOT"; rm -rf "$ROOT"`

Addresses `problems.md` #5. Verifies `implementation-plan.md` P2.2.

---

### Scenario J — completion sentinel + hook (P3.1, problems #16)

**Setup:**
```bash
ROOT=/tmp/fleet-test-fixtures-J
rm -rf "$ROOT"; mkdir -p "$ROOT"
bash "$FIXTURES/setup-fleet.sh" completion "$ROOT"
```

**Run:**
```bash
bash "$SKILL/scripts/launch.sh" "$ROOT" >"$ROOT/launch.out" 2>&1
sleep 10
bash "$SKILL/scripts/orchestrate.sh" "$ROOT" --interval 5 >"$ROOT/orch.out" 2>&1 &
OPID=$!
# Wait up to 90s for COMPLETE sentinel
for i in $(seq 1 18); do [[ -f "$ROOT/COMPLETE" ]] && break; sleep 5; done
wait $OPID; echo "orch_exit=$?"
test -f "$ROOT/COMPLETE" && echo "COMPLETE ok"
jq -r '.status' "$ROOT/fleet.json"
test -f "$ROOT/.hook-fired" && echo "hook fired ok"
```

**Pass:** `${ROOT}/COMPLETE` exists with summary text, `jq -r .status fleet.json` prints `completed`, `${ROOT}/.hook-fired` exists (hook wrote it via `touch "${FLEET_ROOT}/.hook-fired"`), orchestrator exits 0.

**Cleanup:** `tmux kill-session -t fleet-test-completion 2>/dev/null; pkill -f "FLEET_ROOT=$ROOT"; rm -rf "$ROOT"`

Addresses `problems.md` #16. Verifies `implementation-plan.md` P3.1.

---

### Scenario K — pane auto-close `.done` sentinel (P3.2, problems #17)

**Setup:**
```bash
ROOT=/tmp/fleet-test-fixtures-K
rm -rf "$ROOT"; mkdir -p "$ROOT"
bash "$FIXTURES/setup-fleet.sh" completion "$ROOT"
```

**Run:**
```bash
KEEP_PANE_OPEN_SECONDS=5 bash "$SKILL/scripts/launch.sh" "$ROOT" >"$ROOT/launch.out" 2>&1
sleep 25  # tasks are sleep 3; +5s keep-open; +buffer
ls "$ROOT"/workers/*/.done
tmux list-windows -t fleet-test-completion -F '#W' 2>/dev/null | grep -vx monitor | wc -l
ps -ef | grep -F "$ROOT" | grep -v grep | wc -l
```

**Pass:** every `${ROOT}/workers/*/.done` exists (3 files), zero non-monitor worker windows remain in `fleet-test-completion` within `KEEP_PANE_OPEN_SECONDS+5` seconds of completion, zero zombie claude/bash procs under the root.

**Cleanup:** `tmux kill-session -t fleet-test-completion 2>/dev/null; rm -rf "$ROOT"`

Addresses `problems.md` #17. Verifies `implementation-plan.md` P3.2.

---

### Scenario L — wedged-launcher fleet lock (P0.2, problems #3)

**Setup:**
```bash
ROOT=/tmp/fleet-test-fixtures-L
rm -rf "$ROOT"; mkdir -p "$ROOT"
bash "$FIXTURES/setup-fleet.sh" dag "$ROOT"
```

**Run:**
```bash
bash "$SKILL/scripts/launch.sh" "$ROOT" >"$ROOT/launch1.out" 2>&1 &
LPID=$!
sleep 3
bash "$SKILL/scripts/launch.sh" "$ROOT" >"$ROOT/launch2.out" 2>&1
echo "rc=$?"     # expect 2
cat "$ROOT/.launch.pid"   # expect $LPID
grep -F "already active" "$ROOT/launch2.out" || grep -F "already" "$ROOT/launch2.out"
wait $LPID
```

**Pass:** second invocation exits **2** (launcher-lock refusal, not 3 refuse-clobber), `.launch.pid` contains the first launcher's pid, first launcher proceeds to completion normally. This specifically tests P0.2's `flock` on `.launch.lock`, not #19's whole-fleet refuse-clobber — the DAG fixture has dependencies so the first launcher parks in `wait_for_dependencies` briefly, giving the second invocation a window to hit the lock.

**Cleanup:** `tmux kill-session -t fleet-test-dag 2>/dev/null; pkill -f "FLEET_ROOT=$ROOT"; rm -rf "$ROOT"`

Addresses `problems.md` #3. Verifies `implementation-plan.md` P0.2.

---

### Running the whole E–L matrix

```bash
bash /home/sagar/skills/test/fleet/dag-fleet/fixtures-claude/run-all.sh \
     /home/sagar/skills/skills/dag-fleet
echo "failures=$?"
```

The runner cleans up between scenarios and prints a pass/fail table. It does NOT bail on first failure — every scenario runs.

---

## 6. Cleanup (always run between scenarios + at the end)

```bash
# Kill the worker fleet if any
tmux has-session -t fleet 2>/dev/null && tmux kill-session -t fleet
# Sweep orphans
pkill -f "/tmp/fleet-test-skill-test-fleet" 2>/dev/null || true
sleep 1
# Verify
ps -ef | grep -F /tmp/fleet-test-skill-test-fleet | grep -v grep | grep -v asciinema | wc -l   # expect 0
# Confirm protected sessions still alive
diff <(tmux list-sessions -F '#{session_name}' | grep -vE '^(skill-test-fleet|fleet)$' | sort) \
     <(grep -vE '^(skill-test-fleet|fleet)$' /tmp/protected-sessions.txt | sort)
# (empty diff = nothing was touched)
```

At the very end of a test session:

```bash
tmux kill-session -t skill-test-fleet
rm -rf /tmp/fleet-test-skill-test-fleet
```

---

## 7. Recording the run (optional but useful)

The setup in §2 already wraps inner Claude in `asciinema rec recording.cast`. After the run:

```bash
# Which scripts did inner Claude actually invoke?
asciinema cat /tmp/fleet-test-skill-test-fleet/recording.cast 2>/dev/null \
  | grep -oE 'scripts/[a-z-]+\.sh' | sort -u
# Expect after a full run: launch, status, view, feed, steer, add-worker, kill, report
```

Replay if you need to see what happened: `asciinema play /tmp/fleet-test-skill-test-fleet/recording.cast -s 2`.

---

## 8. Judging principle

**Never trust the inner Claude's success messages.** They reflect what the script *printed*, not what *happened*. Every PASS in §4 and §5 is judged by direct filesystem / `ps` / tmux inspection from the outer shell. The whole point of the harness is that the skill's own status reports are exactly what's broken (Finding #1, #4) — using them to judge themselves is circular.

Standard judging tools (in priority order):
1. `ps -ef | grep -F <test_dir>` — ground truth for "is anything still running"
2. `wc -l <output_files>` and content `tail` — ground truth for "did the work happen"
3. `tmux list-windows -t fleet` — ground truth for "is the topology what we asked for"
4. `jq` over `session.jsonl` — for cost / event reconstruction
5. inner Claude's stdout — last, only as a sanity cross-check

---

## 9. Adding a new test

When you reproduce a new bug or want a regression check:
1. Add a numbered scenario to §4 or §5 with: setup commands, the action (sent to inner Claude), the **judge** commands run from outer shell, and the PASS criterion phrased as a positive assertion.
2. Cross-reference the corresponding `problems.md` issue number and `implementation-plan.md` Phase item.
3. Update `test-results-baseline.md` with the current PASS/FAIL status so post-fix runs have a diff target.
