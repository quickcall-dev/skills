---
name: python-code-dev
description: Use when starting Python projects, creating importable packages, migrating notebooks into modules, or refactoring Python code into tested class-first components
argument-hint: "[new|adapt|migrate|verify] <project-or-path>"
allowed-tools: Read, Write, Edit, Bash
---

# Python Code Development

## Purpose

Build maintainable, importable Python packages with classes as the default boundary for state, lifecycle, I/O, and domain behavior. Use pure functions for small stateless transforms when a class would add ceremony. Keep business logic testable and separate from entrypoints.

## Workflows

| Command | Action |
|---|---|
| `/python-code-dev new <project-name>` | Create a deterministic starter project |
| `/python-code-dev adapt <path>` | Restructure existing Python code without changing behavior |
| `/python-code-dev migrate <notebook.py>` | Move notebook logic into the package and update notebook imports |
| `/python-code-dev verify <path>` | Run package, import, test, and quality checks |

`new` is a script-only workflow. Do not hand-scaffold it.

For `new`, run the skill script:

```bash
bash /path/to/python-code-dev/scripts/new.sh "<project-name>"
```

Resolve `/path/to/python-code-dev` from the loaded skill location. If the harness exposes `AGENTS_SKILLS_DIR`, use `${AGENTS_SKILLS_DIR}/scripts/new.sh`; otherwise use the path shown in the skill header/location. If the script cannot be found, STOP and report the missing script. Do not manually create files as a fallback.

If the current directory already looks like a project root (`.git`, `README.md`, `pyproject.toml`, `docs/`, or `.fleet/`), the script scaffolds in place as `./src/<package>/` and `./tests/`. Otherwise it creates `<project-name>/src/<package>/`. It refuses overwrites. `adapt`, `migrate`, and `verify` are agent-run workflows: inspect the target, make reviewed edits, then run declared checks.

## Starter Layout

`new` creates this class-first baseline. Do not invent domain classes, product concepts, CLIs, configs, or schemas beyond this starter; customization happens after the user asks.

```text
project-name/
├── pyproject.toml
├── uv.lock
├── README.md
├── src/project_name/
│   ├── __init__.py
│   ├── config/
│   │   ├── __init__.py
│   │   └── settings.py    # frozen runtime/config objects
│   ├── core/
│   │   ├── __init__.py
│   │   └── service.py     # primary domain service/class
│   ├── schemas/
│   │   ├── __init__.py
│   │   └── contracts.py   # input/output dataclasses and contracts
│   └── utils/
│       ├── __init__.py
│       └── logging.py      # small cross-cutting helpers only
└── tests/
    ├── test_core.py
    └── test_smoke.py
```

Keep domain modules under `src/project_name/`, never under a package literally named `src`. Add `data`, `features`, `models`, or `evaluate` only when the project needs them. Re-export only intentional public APIs; avoid eager imports that cause cycles or optional-dependency failures.

## New Project Contract

The generated project must:

- use `src/<import_name>/` layout, valid `pyproject.toml`, and committed `uv.lock`;
- import successfully from outside the repository root with `uv run`;
- include one small class with a typed method and one passing test;
- include `Config` as `@dataclass(frozen=True)` when configuration is needed;
- use explicit paths/config passed into constructors and methods;
- include no network calls, secrets, fake production data, or destructive actions;
- document setup and verification commands in `README.md`.

Project names become directories and import names: lowercase, non-alphanumeric characters converted to hyphens for the wrapper directory and underscores for the import package. If the user wants package `agentgames`, they must pass `agentgames`; `agent games` becomes `agent_games`. Reject empty or ambiguous names.

## Architecture

- Classes are preferred for domain services, adapters, repositories, pipelines, trainers, and objects with state or lifecycle.
- Functions are preferred for short pure transformations, predicates, and formatters.
- Dataclasses model configuration and data contracts; protocols/interfaces belong near the consuming domain.
- Keep I/O at boundaries. Pass paths, clients, seeds, and config explicitly.
- Keep orchestration thin; do not put domain logic in CLI scripts or `utils`.
- Use dependency injection for external services and filesystem access where tests need isolation.

## Packaging and Imports

Use a supported Python version in `pyproject.toml`, declare runtime/dev dependencies, and use `uv` for every environment and command:

```bash
uv sync
uv run pytest
```

Import the installed project package, not `src`:

```python
from project_name.core import ExampleService
```

Run commands from any working directory when possible. Resolve project-root-relative paths explicitly; do not depend on the caller's current directory.

## Config, Errors, and Logging

- Use immutable config (`@dataclass(frozen=True)`) and `dataclasses.replace` for overrides.
- Distinguish required-but-nullable (`value: T | None`) from optional-at-call-site (`value: T | None = None`).
- Validate external input with explicit exceptions (`ValueError`, `TypeError`, or domain errors), never runtime `assert`.
- Use `logging.getLogger(__name__)` in modules. Configure handlers, levels, and formats only in entrypoints/tests.
- Never log secrets, tokens, raw PII, or full sensitive records. Log safe identifiers, counts, shapes, and paths.
- Create output directories deliberately and define overwrite/atomic-write behavior.

## Code Quality

- Type-hint parameters, return values, and dataclass fields.
- Document public classes, methods, and functions; private trivial helpers need only clear names/types.
- Keep imports at module scope unless a documented optional-dependency, cycle, or startup-cost reason requires local import.
- Nested functions are allowed for closures/callbacks when they improve locality and testability.
- Prefer small cohesive classes over one class per line of code.
- Choose formatter, linter, and type-checker versions in project config; do not rely on “format after every save.”

## Notebook Migration

`/python-code-dev migrate <notebook.py>`:

1. Execute notebook from a clean kernel and record outputs, inputs, seeds, and side effects.
2. Identify responsibilities, hidden state, magics, display code, and execution-order dependencies.
3. Design package boundaries; do not equate cells automatically with classes/modules.
4. Move reusable logic into `src/<import_name>/`; keep classes where state/lifecycle warrants them.
5. Add unit and integration tests for contracts and representative outputs.
6. Replace notebook implementation cells with imports and explicit calls.
7. Verify package imports from outside repo root and execute notebook top-to-bottom again.
8. Preserve notebook as a reference unless explicit archival/deletion is requested.

Never delete the source notebook merely because duplicated implementation moved.

## Adapt Workflow

`adapt` first records current behavior, then changes structure in small steps. Preserve public APIs unless requested otherwise. Add tests before risky refactors, review the diff, and avoid broad unrelated rewrites.

## Flatten Nested Generated Projects

If the repo root is already the intended project root, do not keep a generated `<project-name>/` wrapper containing its own `src/`, `tests/`, `pyproject.toml`, `uv.lock`, `.venv`, egg-info, or caches. Flatten it into the repo root.

Required safety order:

1. Inspect both root and nested project files before moving anything.
2. Move nested package dirs to root: `mv <nested>/src ./src`, `mv <nested>/tests ./tests`, `mv <nested>/uv.lock ./uv.lock`.
3. Use nested `pyproject.toml` as canonical root `./pyproject.toml` only after reading both files.
4. Rewrite README setup/verify with `uv` while preserving the project title.
5. Confirm `src/`, `tests/`, `uv.lock`, and root `pyproject.toml` contain the moved content.
6. Only then remove nested project dir with `rm -rf <nested>`.
7. Do not touch `docs/` or `.fleet/` unless explicitly requested.
8. Verify with project-root and outside-root imports, then show `git diff`.

Template commands:

```bash
mv <nested>/src src
mv <nested>/tests tests
mv <nested>/uv.lock uv.lock
cp <nested>/pyproject.toml pyproject.toml
# after confirming moved content exists:
rm -rf <nested>
uv sync
uv run python -m compileall src tests
uv run pytest
cd /tmp && uv run --project /absolute/path/to/project python -c 'import package_name; print(package_name.__name__)'
git diff
```

Do not run `rm -rf <nested>` before proving root `src/`, `tests/`, `uv.lock`, and `pyproject.toml` are correct.

## Verify Workflow

`verify` runs the applicable checks from a clean environment. Replace `project_name` with actual import name:

```bash
uv sync
uv run python -m compileall src tests
uv run pytest
uv run python -c 'import project_name'
```

Also check formatting/lint/type commands declared in `pyproject.toml`, test imports from outside repo root, and report skipped checks with reasons. Never claim success without command output.

## Anti-Patterns

Never use `assert` for input validation, import from `src`, hide domain logic in `utils`, hardcode credentials, silently create fake production data, depend on notebook globals, or delete source artifacts without explicit approval. Do not hand-scaffold `new`; run the script or stop. Do not invent domain classes during scaffolding. `scripts/` is allowed for thin operational wrappers; it must not contain business logic.
