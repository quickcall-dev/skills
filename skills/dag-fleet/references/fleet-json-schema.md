# fleet.json Schema

## Top-level fields

```json
{
  "fleet_name": "my-fleet",
  "fleet_id": "my-fleet-2026-03-31",
  "status": "pending",
  "config": { ... },
  "workers": [ ... ]
}
```

## Config fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `max_concurrent` | int | 5 | Max simultaneously running workers |
| `model` | string | "sonnet" | Default model for workers |
| `fallback_model` | string | "haiku" | Fallback when primary is overloaded. MUST differ from `model` |
| `launch_delay_seconds` | int | 3 | Delay between worker launches |
| `max_budget_fleet` | float | 0 (disabled) | Total fleet budget cap in USD. Stops launching when exceeded |

## Worker fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | string | Yes | Unique worker ID (e.g. "worker-01") |
| `type` | string | Yes | Worker type: `read-only`, `write`, `code-run`, `research`, `reviewer` |
| `model` | string | No | Override model (falls back to config.model) |
| `task` | string | Yes | Task description |
| `max_turns` | int | No | Max agentic turns (default: 30) |
| `max_budget_usd` | float | No | Per-worker budget cap (default: 0.25) |
| `depends_on` | string[] | No | Worker IDs that must complete before this worker launches |

## Example

```json
{
  "fleet_name": "research-fleet",
  "fleet_id": "research-fleet-001",
  "status": "pending",
  "config": {
    "max_concurrent": 3,
    "model": "sonnet",
    "fallback_model": "haiku",
    "launch_delay_seconds": 3,
    "max_budget_fleet": 1.00
  },
  "workers": [
    {
      "id": "researcher-01",
      "type": "research",
      "model": "haiku",
      "task": "Research topic A",
      "max_turns": 20,
      "max_budget_usd": 0.15
    },
    {
      "id": "synthesizer",
      "type": "write",
      "model": "sonnet",
      "task": "Synthesize all research into a report",
      "max_turns": 30,
      "max_budget_usd": 0.25,
      "depends_on": ["researcher-01"]
    }
  ]
}
```
