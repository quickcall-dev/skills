# Fleet Skill — Test Suites

Integration and fixture tests for all 3 fleet types, with separate test suites for **Claude** and **Codex** providers.

## Directory layout

```
test/fleet/
├── README.md                          ← you are here
├── dag-fleet/
│   ├── README.md                      # dag-fleet specific docs + harness.md
│   ├── harness.md                     # outer-judge harness for real Claude tests (A–D)
│   ├── fixtures-claude/               # fake claude CLI tests
│   │   ├── shim/claude                # fake claude emitting stream-json
│   │   ├── setup-fleet.sh             # prepare fleet root from fixture
│   │   ├── run-all.sh                 # scenarios E, F, G, K, L, Q
│   │   ├── dag-fleet.json             # 6-worker DAG (a→c, all→f)
│   │   ├── completion-fleet.json      # 3 fast workers, no deps
│   │   ├── cycle-fleet.json           # mutual cycle (a↔b)
│   │   └── hooks/notify.sh
│   └── fixtures-codex/                # fake codex CLI tests
│       ├── shim/codex                 # fake codex emitting codex JSONL
│       ├── setup-fleet.sh             # prepare fleet root from fixture
│       ├── run-all.sh                 # scenarios CE, CG, CK, CL, CJSONL, CSTATUS
│       ├── dag-fleet.json             # same DAG, provider:"codex"
│       ├── completion-fleet.json
│       ├── cycle-fleet.json
│       └── hooks/notify.sh
├── worktree-fleet/
│   ├── fixtures-claude/               # claude worktree tests
│   │   ├── run-all.sh                 # scenarios W1, W2, W3, W4
│   │   ├── independent-fleet.json     # 3 non-overlapping workers
│   │   └── overlapping-fleet.json     # 2 workers with file overlap
│   └── fixtures-codex/                # codex worktree tests
│       ├── run-all.sh                 # scenarios CW1, CW2, CW3
│       ├── independent-fleet.json     # same workers, provider:"codex"
│       └── overlapping-fleet.json
└── iterative-fleet/
    ├── fixtures-claude/               # claude iterative tests
    │   ├── run-all.sh                 # scenarios I1, I2, I3, I4
    │   └── basic-iterative-fleet.json # 2 builders + 1 reviewer
    └── fixtures-codex/                # codex iterative tests
        ├── run-all.sh                 # scenarios CI1, CI2, CI3, CI4, CI5
        └── basic-iterative-fleet.json # same workers, provider:"codex"
```

## Quick start

Run all codex tests:

```bash
# dag-fleet (uses fake codex shim, ~2 min)
bash test/fleet/dag-fleet/fixtures-codex/run-all.sh skills/dag-fleet

# worktree-fleet (dry-run tests, ~10s)
bash test/fleet/worktree-fleet/fixtures-codex/run-all.sh skills/worktree-fleet

# iterative-fleet (~15s)
bash test/fleet/iterative-fleet/fixtures-codex/run-all.sh skills/iterative-fleet
```

Run all claude tests:

```bash
bash test/fleet/dag-fleet/fixtures-claude/run-all.sh skills/dag-fleet
bash test/fleet/worktree-fleet/fixtures-claude/run-all.sh skills/worktree-fleet
bash test/fleet/iterative-fleet/fixtures-claude/run-all.sh skills/iterative-fleet
```

## Test scenarios

### dag-fleet

| Scenario | Claude | Codex | What it tests |
|----------|--------|-------|---------------|
| E / CE | topo-sort-first-wave | same | BFS-layered topo sort: a,b,d,e launch first, c waits on a, f waits on all |
| F | per-worker-spawn-lock | — | Refuse clobber: second launch.sh gets exit 3, existing workers untouched |
| G / CG | topo-cycle-detection | same | Mutual depends_on (a↔b) → exit nonzero with CYCLE: message, no tmux session |
| K / CK | pane-auto-close | same | .done sentinel created, tmux windows close after grace period |
| L / CL | wedged-launcher-lock | same | Parallel launch.sh → exit 2, .launch.pid points at first launcher |
| Q | relaunch-worker | — | Edit prompt.md + relaunch c: old jsonl rotated, others untouched |
| CJSONL | — | codex-jsonl-events | session.jsonl has thread.started, item.completed, turn.completed |
| CSTATUS | — | status-reports-done | status.sh --json reports all 3 workers as DONE |

### worktree-fleet

| Scenario | Claude | Codex | What it tests |
|----------|--------|-------|---------------|
| W1 / CW1 | independence-pass | same | --dry-run succeeds for non-overlapping target_files |
| W2 / CW2 | independence-reject | same | --dry-run fails with overlap message for shared files |
| W3 / CW3 | worktrees-created | provider-parsed | 3 worktrees created (claude) / no claude-not-found error (codex) |
| W4 | cleanup-removes | — | cleanup.sh --force removes all worktrees |

### iterative-fleet

| Scenario | Claude | Codex | What it tests |
|----------|--------|-------|---------------|
| I1 / CI1 | iteration-structure | same | --dry-run creates iterations/ dir, orchestrator.sh referenced |
| I2 / CI2 | stop-conditions | same | max_iterations + reviewer_lgtm_count parsed from fleet.json |
| I3 / CI3 | pause-resume | same | pause.sh creates .paused, resume.sh removes it |
| I4 / CI4 | kill-stops-all | same | kill.sh all --force: tmux session gone, zero procs |
| CI5 | — | orchestrator-codex-jsonl | Generated orchestrator.sh contains turn.completed/turn.failed checks |

## How the fake CLI shims work

Both shims avoid real API calls. They parse the same flags as the real CLI, drain stdin (the prompt), run the per-worker task script from `$FLEET_ROOT/.fake-tasks/$WORKER_ID.sh`, then emit provider-specific JSONL.

**`fixtures-claude/shim/claude`** emits:
```json
{"type":"assistant","message":{"model":"...","usage":{"input_tokens":100,"output_tokens":50}}}
{"type":"result","subtype":"success","total_cost_usd":0.0123,"num_turns":1}
```

**`fixtures-codex/shim/codex`** emits:
```json
{"type":"thread.started","thread_id":"fake-thread-..."}
{"type":"turn.started"}
{"type":"item.completed","item":{"id":"item_0","type":"agent_message","text":"..."}}
{"type":"turn.completed","usage":{"input_tokens":1000,"output_tokens":200,"cached_input_tokens":500}}
```

Both shims exit 0 always. Task failure is reflected in the terminal event (`subtype:"error"` for claude, `turn.failed` for codex).

## Judging principle

Never trust inner Claude/Codex success messages. Ground truth sources (in priority order):

1. `ps -ef | grep <test_dir>` — are processes alive?
2. `wc -l` / `cat` output files — did the worker produce output?
3. `tmux list-windows` — are tmux panes present/gone?
4. `jq` over `session.jsonl` — does the JSONL have the expected events?
5. `status.sh --json` — does the dashboard parse correctly?

## Adding new tests

1. Pick the fleet type and provider (claude or codex)
2. Add a fixture fleet.json if needed (or reuse existing)
3. Add a `run_XX()` function in the appropriate `run-all.sh`
4. Follow the pattern: `mkroot` → setup → run script → assert → `cleanup_root`
5. Use `record "XX description" PASS/FAIL` for the summary
