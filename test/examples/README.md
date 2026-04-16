# Example Fleet Configs

Minimal, working fleet.json examples for each fleet type. Designed for cheap testing with `haiku` — each example runs for under $0.10 total.

## Usage

```bash
# 1. Copy example to a fleet root
mkdir -p /tmp/my-fleet/workers
cp test/examples/dag-fleet.json /tmp/my-fleet/fleet.json

# 2. Write prompts for each worker
echo "Create a hello-world Python script" > /tmp/my-fleet/workers/hello/prompt.md
echo "Write unit tests for hello.py" > /tmp/my-fleet/workers/test-hello/prompt.md

# 3. Launch
bash skills/dag-fleet/scripts/launch.sh /tmp/my-fleet
```

Each example below includes the fleet.json and the worker prompts you need.

## Quick Reference

| Example | Fleet Type | Workers | Estimated Cost |
|---------|-----------|---------|---------------|
| [dag-fleet.json](#dag-fleet) | dag-fleet | 3 (2 parallel → 1 dependent) | ~$0.03 |
| [worktree-fleet.json](#worktree-fleet) | worktree-fleet | 2 (isolated branches) | ~$0.03 |
| [iterative-fleet.json](#iterative-fleet) | iterative-fleet | 2 builders + 1 reviewer | ~$0.05 |
| [autoresearch-fleet.json](#autoresearch-fleet) | autoresearch-fleet | 1 (iterative loop) | ~$0.05 |
