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

grep -q 'Flatten Nested Generated Projects' "$repo_root/skills/python-code-dev/SKILL.md"
grep -q 'Do not touch `docs/` or `.fleet/`' "$repo_root/skills/python-code-dev/SKILL.md"
grep -q 'rm -rf' "$repo_root/skills/python-code-dev/SKILL.md"
grep -q 'script-only workflow' "$repo_root/skills/python-code-dev/SKILL.md"
grep -q 'Do not hand-scaffold' "$repo_root/skills/python-code-dev/SKILL.md"
grep -q 'Do not invent domain classes' "$repo_root/skills/python-code-dev/SKILL.md"
! test -e "$repo_root/skills/code-development"
! test -e "$repo_root/skills/notebook-development"

mkdir "$work/code" && cd "$work/code"
"$repo_root/skills/python-code-dev/scripts/new.sh" 'Tiny Demo'
test -f tiny-demo/pyproject.toml
grep -q 'requires-python = ">=3.12"' tiny-demo/pyproject.toml
grep -q '\[tool.pyright\]' tiny-demo/pyproject.toml
grep -q 'typeCheckingMode = "strict"' tiny-demo/pyproject.toml
test -f tiny-demo/uv.lock
test -f tiny-demo/src/tiny_demo/core/__init__.py
test -f tiny-demo/src/tiny_demo/schemas/__init__.py
test -f tiny-demo/src/tiny_demo/utils/__init__.py
test -f tiny-demo/src/tiny_demo/utils/atomic.py
test -f tiny-demo/src/tiny_demo/utils/ids.py
test -f tiny-demo/src/tiny_demo/utils/logging.py
test -f tiny-demo/src/tiny_demo/configs/env.py
test -f tiny-demo/src/tiny_demo/configs/paths.py
test -f tiny-demo/src/tiny_demo/core/context.py
test -f tiny-demo/src/tiny_demo/core/runner.py
test -f tiny-demo/src/tiny_demo/runner/cli.py
test -f tiny-demo/tests/core/test_service.py
test -f tiny-demo/tests/schemas/test_contracts.py
test -f tiny-demo/tests/utils/test_logging.py
test -f tiny-demo/tests/utils/test_atomic.py
test -f tiny-demo/tests/utils/test_ids.py
test -f tiny-demo/tests/configs/test_paths.py
test -f tiny-demo/tests/runner/test_cli.py
grep -q 'uv sync' tiny-demo/README.md
grep -q 'Args:' tiny-demo/src/tiny_demo/core/service.py
grep -q 'Returns:' tiny-demo/src/tiny_demo/core/service.py
grep -q 'Raises:' tiny-demo/src/tiny_demo/core/service.py
grep -q 'Attributes:' tiny-demo/src/tiny_demo/schemas/contracts.py
(cd tiny-demo && uv sync --quiet && uv run pytest -q && uv run python -c 'from tiny_demo.core import ExampleService; assert ExampleService().greet("Kimi") == "Hello, Kimi!"' && uv run python -m tiny_demo.runner.cli --message hello)
! "$repo_root/skills/python-code-dev/scripts/new.sh" 'Tiny Demo' >/dev/null 2>&1
! "$repo_root/skills/python-code-dev/scripts/new.sh" '42' >/dev/null 2>&1

mkdir "$work/existing-root" && cd "$work/existing-root"
git init -q
touch README.md
"$repo_root/skills/python-code-dev/scripts/new.sh" 'agentgames'
test -f pyproject.toml
grep -q 'requires-python = ">=3.12"' pyproject.toml
test -f uv.lock
test -f src/agentgames/core/__init__.py
test -f tests/core/test_service.py
test -f tests/schemas/test_contracts.py
test -f tests/utils/test_logging.py
test ! -e agentgames/src/agentgames
(cd /tmp && uv run --project "$work/existing-root" python -c 'from agentgames.core import ExampleService; assert ExampleService().greet("Kimi") == "Hello, Kimi!"')

mkdir "$work/notebook" && cd "$work/notebook"
"$repo_root/skills/python-notebook-dev/scripts/new.sh" 'Tiny Notebook'
"$repo_root/skills/python-notebook-dev/scripts/new.sh" 'Second Notebook'
test -f notebooks/001-tiny-notebook/tiny_notebook.py
test -f notebooks/002-second-notebook/second_notebook.py
(cd /tmp && python3 "$work/notebook/notebooks/001-tiny-notebook/tiny_notebook.py" >/dev/null)
(cd /tmp && python3 "$work/notebook/notebooks/002-second-notebook/second_notebook.py" >/dev/null)
test -n "$(find "$work/notebook/outputs" -name result.txt -print -quit)"
printf 'python skill smoke tests: PASS\n'
