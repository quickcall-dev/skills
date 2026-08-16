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

grep -q 'Loose notebooks are forbidden' "$repo_root/skills/python-notebook-dev/SKILL.md"
grep -q 'Every notebook path MUST match' "$repo_root/skills/python-notebook-dev/SKILL.md"
grep -q 'Class-first is mandatory' "$repo_root/skills/python-notebook-dev/SKILL.md"
grep -q 'Do not create or keep loose' "$repo_root/skills/python-notebook-dev/SKILL.md"
grep -q 'new.*script-only workflow' "$repo_root/skills/python-notebook-dev/SKILL.md"

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
test -f tiny-demo/.env.example
grep -q '^.env$' tiny-demo/.gitignore
grep -q 'TINY_DEMO_OUTPUT_ROOT' tiny-demo/.env.example
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
grep -q 'load_env' tiny-demo/src/tiny_demo/configs/env.py
test -f tiny-demo/src/tiny_demo/configs/paths.py
test -f tiny-demo/src/tiny_demo/core/context.py
test -f tiny-demo/src/tiny_demo/core/runner.py
test -f tiny-demo/src/tiny_demo/runner/cli.py
test -f tiny-demo/tests/core/test_service.py
test -f tiny-demo/tests/schemas/test_contracts.py
test -f tiny-demo/tests/utils/test_logging.py
test -f tiny-demo/tests/utils/test_atomic.py
test -f tiny-demo/tests/utils/test_ids.py
test -f tiny-demo/tests/configs/test_env.py
test -f tiny-demo/tests/configs/test_paths.py
test -f tiny-demo/tests/runner/test_cli.py
grep -q 'uv sync' tiny-demo/README.md
grep -q 'Args:' tiny-demo/src/tiny_demo/core/service.py
grep -q 'Returns:' tiny-demo/src/tiny_demo/core/service.py
grep -q 'Raises:' tiny-demo/src/tiny_demo/core/service.py
grep -q 'Attributes:' tiny-demo/src/tiny_demo/schemas/contracts.py
! grep -R '__PACKAGE__\|__package__\|__PROJECT__' tiny-demo/src tiny-demo/tests tiny-demo/README.md tiny-demo/pyproject.toml
(cd tiny-demo && uv sync --quiet && uv run pytest -q && uv run python -c 'from tiny_demo.core import ExampleService; assert ExampleService().greet("Kimi") == "Hello, Kimi!"' && uv run python -m tiny_demo.runner.cli --message hello)
! "$repo_root/skills/python-code-dev/scripts/new.sh" 'Tiny Demo' >/dev/null 2>&1
! "$repo_root/skills/python-code-dev/scripts/new.sh" '42' >/dev/null 2>&1

mkdir "$work/existing-root" && cd "$work/existing-root"
git init -q
touch README.md
"$repo_root/skills/python-code-dev/scripts/new.sh" 'agentgames'
test -f pyproject.toml
test -f .env.example
grep -q '^.env$' .gitignore
grep -q 'AGENTGAMES_OUTPUT_ROOT' .env.example
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
test -f notebooks/001-tiny-notebook.py
test -f notebooks/002-second-notebook.py
test ! -d notebooks/001-tiny-notebook
test ! -f notebooks/tiny_notebook.py
grep -q 'class Experiment' notebooks/001-tiny-notebook.py
grep -q 'Attributes:' notebooks/001-tiny-notebook.py
grep -q 'Args:' notebooks/001-tiny-notebook.py
grep -q 'Returns:' notebooks/001-tiny-notebook.py
grep -q 'Raises:' notebooks/001-tiny-notebook.py
(cd /tmp && python3 "$work/notebook/notebooks/001-tiny-notebook.py" >/dev/null)
(cd /tmp && python3 "$work/notebook/notebooks/002-second-notebook.py" >/dev/null)
test -f "$work/notebook/outputs/001-tiny-notebook/result.txt"
test -f "$work/notebook/outputs/002-second-notebook/result.txt"
test ! -d "$work/notebook/outputs/$(date +%F)"
printf 'python skill smoke tests: PASS\n'
