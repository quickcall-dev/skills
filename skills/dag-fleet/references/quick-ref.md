# dag-fleet Quick Reference

## Lifecycle

```mermaid
flowchart TD
    A[Write fleet.json] --> B[Write workers/{id}/prompt.md]
    B --> C[launch.sh fleet-root]
    C --> D{topo sort}
    D --> E[Wave 1: independent workers run in parallel]
    E --> F{dependencies met?}
    F -- yes --> G[Wave 2: dependent workers start]
    F -- no --> F
    G --> H[status.sh to monitor]
    H --> I{worker done?}
    I -- stuck/wrong --> J[kill.sh fleet worker-id]
    J --> K[edit prompt.md]
    K --> L[relaunch-worker.sh fleet worker-id]
    L --> H
    I -- all done --> M[report.sh fleet-root]
```

## Scripts

| Script | Args | Description |
|--------|------|-------------|
| `launch.sh` | `<fleet-root>` | Topo-sort workers, create tmux session, spawn all workers |
| `status.sh` | `<fleet> [-v] [--watch] [--json]` | Show live status, cost, last message per worker |
| `kill.sh` | `<fleet> <worker-id>\|all [--force]` | Stop one worker or tear down entire fleet |
| `relaunch-worker.sh` | `<fleet> <worker-id>` | Re-run one worker after editing its prompt.md |
| `report.sh` | `<fleet-root>` | Generate markdown summary of completed fleet |
| `view.sh` | `<fleet> <worker-id>` | Capture a worker's current tmux pane content |
| `feed.sh` | `<fleet> [--agent <id>]` | Stream unified event feed across all workers |

Scripts accept either an absolute fleet-root path or a fleet name (from `~/.claude/fleet-registry.json`).

**Utility:** `python3 ${CLAUDE_SKILL_DIR}/lib/dag-viz.py <fleet.json> [--mermaid]` — preview DAG structure in terminal or as mermaid diagram.

## Worker Types

| Type | Disallowed Tools | Use For | Can write files? |
|------|-----------------|---------|-----------------|
| `read-only` | Bash, Edit, Write, Agent, WebFetch, WebSearch | Pure analysis, output via session text only | **NO** |
| `write` | Bash, Agent, WebFetch, WebSearch | **Synthesizers**, doc writers, any output-producing worker | YES |
| `code-run` | Agent, WebFetch, WebSearch | Build/test workers (typical default) | YES |
| `research` | Bash, Edit, Agent | Web research + writing findings | YES |
| `reviewer` | Bash, Edit, Agent, WebFetch, WebSearch | Review + verdict writing (Read + Write only) | YES |
| `orchestrator` | Agent, WebFetch, WebSearch, Edit | Coordinate via Bash, no direct edits | YES (Bash) |

## Minimal fleet.json

```json
{
  "fleet_name": "my-fleet",
  "config": {
    "max_budget_fleet": 2.00
  },
  "workers": [
    {
      "id": "researcher",
      "type": "research",
      "task": "Research X and write findings to output/findings.md",
      "model": "claude-sonnet-4-6",
      "max_turns": 20,
      "max_budget_usd": 0.50
    },
    {
      "id": "synthesizer",
      "type": "write",
      "task": "Read researcher output and write summary to output/summary.md",
      "model": "claude-sonnet-4-6",
      "max_turns": 10,
      "max_budget_usd": 0.50,
      "depends_on": ["researcher"]
    }
  ]
}
```

Each worker needs a matching `workers/{id}/prompt.md` that ends with:
```
Save ALL output files to /abs/fleet-root/workers/{id}/output/ — use absolute paths.
```

## Common Gotchas

1. **Never use `--bare`** — causes auth failures. STRICT RULE #2, no exceptions.

2. **Long thinking looks like a hang** — before killing a worker, run `view.sh` or `status.sh -v` to confirm it's actually stuck. Only the operator kills workers.

3. **`relaunch-worker.sh` needs a live tmux session** — if the fleet session was killed (`kill.sh all`), you must `launch.sh --force-relaunch` the whole fleet. You cannot relaunch a single worker into a dead session.

4. **Output paths must be absolute in prompt.md** — workers that write to relative paths will scatter files unpredictably. Always instruct workers with the full `$FLEET_ROOT/workers/{id}/output/` path.
