# Autoresearch Fleet — Setup

One agent loops: edit → eval → keep/discard → repeat.
No separate workers — the agent iterates autonomously.

## Setup

```bash
mkdir -p /tmp/example-autoresearch
cp test/examples/autoresearch-fleet.json /tmp/example-autoresearch/fleet.json
```

## program.md (the problem description)

Create at `/tmp/example-autoresearch/program.md`:

```
# String Classifier

Build a function `classify(s)` in `solution.py` that classifies strings:
- "short" if len(s) < 5
- "medium" if 5 <= len(s) < 15
- "long" if len(s) >= 15

Optimize for accuracy on the eval harness. Edit only solution.py.
```

## solution.py (starting point)

Create at `/tmp/example-autoresearch/solution.py`:

```python
def classify(s):
    return "unknown"
```

## eval.py (evaluation harness)

Create at `/tmp/example-autoresearch/eval.py`:

```python
from solution import classify

tests = [
    ("hi", "short"), ("ok", "short"), ("a", "short"),
    ("hello", "medium"), ("good morning", "medium"), ("python code", "medium"),
    ("this is a long string", "long"), ("abcdefghijklmnop", "long"),
]

correct = sum(1 for s, expected in tests if classify(s) == expected)
total = len(tests)
print(f"accuracy: {correct/total:.2f}")
print(f"{correct}/{total} correct")
```

## Launch

```bash
bash skills/autoresearch-fleet/scripts/launch.sh /tmp/example-autoresearch
bash skills/autoresearch-fleet/scripts/status.sh /tmp/example-autoresearch
```

The agent will edit solution.py, run eval.py, check the accuracy metric,
keep improvements and discard regressions. Should reach 1.00 in 1-2 iterations.
