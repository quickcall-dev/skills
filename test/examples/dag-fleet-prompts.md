# DAG Fleet — Worker Prompts

Create these files before launching:

## Setup

```bash
mkdir -p /tmp/example-dag/workers/{hello,utils,test-all}
cp test/examples/dag-fleet.json /tmp/example-dag/fleet.json
```

## workers/hello/prompt.md

```
Create a Python script at hello.py that:
1. Defines a greet(name) function that returns "Hello, {name}!"
2. Has a main block that greets "World"
Keep it simple — under 10 lines.
```

## workers/utils/prompt.md

```
Create a Python module at utils.py with these functions:
1. reverse(s) — returns the reversed string
2. capitalize_words(s) — capitalizes each word
Keep it simple — under 15 lines. No dependencies.
```

## workers/test-all/prompt.md

```
Write pytest tests at test_all.py that:
1. Test greet() from hello.py
2. Test reverse() and capitalize_words() from utils.py
At least 2 tests per function.
```

## Launch

```bash
bash skills/dag-fleet/scripts/launch.sh /tmp/example-dag
bash skills/dag-fleet/scripts/status.sh /tmp/example-dag
```
