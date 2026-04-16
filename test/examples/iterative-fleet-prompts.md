# Iterative Fleet — Worker Prompts

Workers run in cycles. After each cycle, the reviewer checks output.
If reviewer says "lgtm" — fleet stops. Otherwise, workers iterate with feedback.

## Setup

```bash
mkdir -p /tmp/example-iter/workers/{writer,tester,reviewer}
cp test/examples/iterative-fleet.json /tmp/example-iter/fleet.json
```

## workers/writer/prompt.md

```
Create fizzbuzz.py with a function fizzbuzz(n) that returns a list of strings:
- "Fizz" for multiples of 3
- "Buzz" for multiples of 5
- "FizzBuzz" for multiples of both
- The number as string otherwise
Keep it clean and simple.
```

## workers/tester/prompt.md

```
Write pytest tests at test_fizzbuzz.py for the fizzbuzz function.
Test: normal numbers, multiples of 3, 5, 15, edge cases (0, 1, negative).
Run the tests and report results.
```

## workers/reviewer/prompt.md

```
Review the code and test output from this iteration.
Check: correctness, edge cases covered, code style.
Write your verdict as exactly one of: lgtm | iterate | escalate
If iterating, explain what needs to change.
```

## Launch

```bash
bash skills/iterative-fleet/scripts/launch.sh /tmp/example-iter
bash skills/iterative-fleet/scripts/status.sh /tmp/example-iter
```
