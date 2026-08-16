#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

for skill in python-code-dev python-notebook-dev; do
  test -f "$repo_root/skills/$skill/SKILL.md"
  grep -q "^name: $skill$" "$repo_root/skills/$skill/SKILL.md"
  grep -q '/python-' "$repo_root/skills/$skill/SKILL.md"
done
! test -e "$repo_root/skills/code-development"
! test -e "$repo_root/skills/notebook-development"

mkdir "$work/code" && cd "$work/code"
"$repo_root/skills/python-code-dev/scripts/new.sh" 'Tiny Demo'
test -f tiny-demo/pyproject.toml
test -f tiny-demo/uv.lock
test -f tiny-demo/src/tiny_demo/core/__init__.py
test -f tiny-demo/src/tiny_demo/config/__init__.py
test -f tiny-demo/src/tiny_demo/schemas/__init__.py
test -f tiny-demo/src/tiny_demo/utils/__init__.py
test -f tiny-demo/tests/test_core.py
grep -q 'uv sync' tiny-demo/README.md
(cd tiny-demo && uv sync --quiet && uv run pytest -q && uv run python -c 'from tiny_demo.core import ExampleService; assert ExampleService().greet("Kimi") == "Hello, Kimi!"')
! "$repo_root/skills/python-code-dev/scripts/new.sh" 'Tiny Demo' >/dev/null 2>&1
! "$repo_root/skills/python-code-dev/scripts/new.sh" '42' >/dev/null 2>&1

mkdir "$work/notebook" && cd "$work/notebook"
"$repo_root/skills/python-notebook-dev/scripts/new.sh" 'Tiny Notebook'
"$repo_root/skills/python-notebook-dev/scripts/new.sh" 'Second Notebook'
test -f notebooks/001-tiny-notebook/tiny_notebook.py
test -f notebooks/002-second-notebook/second_notebook.py
(cd /tmp && python3 "$work/notebook/notebooks/001-tiny-notebook/tiny_notebook.py" >/dev/null)
(cd /tmp && python3 "$work/notebook/notebooks/002-second-notebook/second_notebook.py" >/dev/null)
test -n "$(find "$work/notebook/outputs" -name result.txt -print -quit)"
printf 'python skill smoke tests: PASS\n'
