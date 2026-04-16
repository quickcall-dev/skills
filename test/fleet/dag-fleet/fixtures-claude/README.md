# test/fixtures — fake-worker fleet fixtures

All fixtures here use a **fake `claude` shim** (`shim/claude`) instead of the
real Anthropic CLI. The shim parses the subset of flags `launch.sh` passes,
drains the stdin prompt, runs a per-worker bash task from
`${FLEET_ROOT}/.fake-tasks/<worker_id>.sh`, then emits a stream-json
`assistant` event followed by a terminal `result` event — exactly what
`count_active_workers`, `orchestrate.sh`, `status.sh`, `verify.sh`, and
`report.sh` all key on.

This lets every Phase 0/2/3 scenario run in seconds with zero API spend.

## Activation

Prepend the shim directory to `PATH` so `command -v claude` resolves to the
shim rather than the real CLI:

```bash
export PATH="$(pwd)/test/fixtures/shim:$PATH"
command -v claude   # should print .../test/fixtures/shim/claude
```

`run-all.sh` does this automatically.

## Files

| File | Purpose | Used by scenarios |
|--|--|--|
| `shim/claude` | Fake claude CLI; reads `$WORKER_ID`, runs `.fake-tasks/<id>.sh`, emits stream-json. | All |
| `setup-fleet.sh` | Copies a fixture fleet.json into a target root, writes per-worker `prompt.md` and `.fake-tasks/<id>.sh`. | All |
| `dag-fleet.json` | 6 workers — `a,b,d,e` independent; `c` depends on `a`; `f` depends on everything. Tests topo sort + spawn lock. | E, F, L |
| `cycle-fleet.json` | 2 workers with mutual `depends_on`. Tests topo cycle detection. | G |
| `stuck-fleet.json` | 2 workers, one with `stuck_threshold_seconds: 60`, one slow. Tests per-worker stuck threshold + restart cap. | I |
| `completion-fleet.json` | 3 fast workers + `on_complete_hook` pointing at `hooks/notify.sh`. Tests verify-set, completion sentinel, hook, pane auto-close. | H, J, K |
| `hooks/notify.sh` | `on_complete_hook` target — touches `${FLEET_ROOT}/.hook-fired`. | J |
| `run-all.sh` | Driver: runs scenarios E–L in sequence, isolated, summary table at end. | — |

## Cross-reference

Each scenario is documented in `../harness.md` §5a. See that file for exact
command sequences, pass criteria, and cleanup blocks. Each scenario header
links back to `../../problems.md` issue numbers and
`../../implementation-plan.md` Phase items.
