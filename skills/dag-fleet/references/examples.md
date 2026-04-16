# Fleet Examples

## Example 1: Echo test fleet (for testing)

```json
{
  "fleet_name": "echo-test",
  "fleet_id": "echo-test-001",
  "status": "pending",
  "config": {
    "max_concurrent": 3,
    "model": "sonnet",
    "fallback_model": "haiku",
    "launch_delay_seconds": 3
  },
  "workers": [
    {
      "id": "echo-01",
      "type": "code-run",
      "task": "Run a bash loop writing lines to output",
      "max_turns": 5,
      "max_budget_usd": 0.05
    }
  ]
}
```

Worker prompt (`workers/echo-01/prompt.md`):
```markdown
Run this bash command:
for i in $(seq 1 100); do echo "echo-01 line $i" >> /path/to/workers/echo-01/output/lines.txt; sleep 2; done

Save ALL output to /path/to/workers/echo-01/output/ using absolute paths.
```

## Example 2: Research fleet with DAG

3 researchers feed into 1 synthesizer:

```json
{
  "fleet_name": "research",
  "config": {
    "model": "haiku",
    "fallback_model": "sonnet",
    "max_budget_fleet": 0.50
  },
  "workers": [
    {"id": "r-01", "type": "research", "task": "Research topic A"},
    {"id": "r-02", "type": "research", "task": "Research topic B"},
    {"id": "r-03", "type": "research", "task": "Research topic C"},
    {
      "id": "synth",
      "type": "write",
      "model": "sonnet",
      "task": "Read all researcher outputs and write a synthesis report",
      "depends_on": ["r-01", "r-02", "r-03"]
    }
  ]
}
```

## Example 3: Code fleet with reviewer

```json
{
  "fleet_name": "code-impl",
  "config": {
    "model": "sonnet",
    "fallback_model": "haiku"
  },
  "workers": [
    {"id": "impl-01", "type": "code-run", "task": "Implement auth module"},
    {"id": "impl-02", "type": "code-run", "task": "Implement API routes"},
    {
      "id": "reviewer",
      "type": "reviewer",
      "task": "Review all implementation output for bugs and style",
      "depends_on": ["impl-01", "impl-02"]
    }
  ]
}
```
