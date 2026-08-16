---
name: python-notebook-dev
description: Use when creating or editing # %% Python notebooks, starting numbered experiments, or migrating notebook work into tested Python packages
argument-hint: "[new|adapt|migrate|verify] <notebook-name-or-path>"
allowed-tools: Read, Write, Edit, Bash
---

# Python Notebook Development

## Purpose

Create reproducible `# %%` Python notebooks for focused experiments. Class-first is mandatory for stateful steps, I/O, pipelines, experiment execution, and lifecycle; pure functions are only for tiny stateless transforms. Loose notebooks are forbidden. Keep notebooks executable from a clean kernel and ready to migrate into `python-code-dev`.

## Workflows

| Command | Action |
|---|---|
| `/python-notebook-dev new <notebook-name>` | Create the next numbered experiment notebook |
| `/python-notebook-dev adapt <notebook.py>` | Bring an existing notebook under these rules |
| `/python-notebook-dev migrate <notebook.py>` | Move reusable logic into `python-code-dev` |
| `/python-notebook-dev verify <notebook.py>` | Execute and inspect reproducibility/validation |

For `new`, this is a script-only workflow: run `${AGENTS_SKILLS_DIR}/scripts/new.sh "<notebook-name>"` when available. Do not hand-create notebook files for `new`. It creates a notebook under the current project and refuses unsafe overwrites.

## Deterministic Naming

Every notebook path MUST match `notebooks/NNN-name-of-notebook.py`. Do not create folders per notebook. Do not create or keep loose notebooks such as `notebooks/foo.py`, `foo.py`, or `analysis.ipynb` unless the human explicitly requests an archive/import operation. Adapt loose files by moving/renaming them into the required numbered file path before changing content.

New notebooks use `notebooks/NNN-slug.py`:

- `NNN` is one greater than the highest existing three-digit notebook prefix; start at `001`.
- If the candidate exists, increment until free. Never reuse or overwrite an experiment number.
- Slug: lowercase; spaces/underscores become `-`; remove other characters; collapse hyphens; trim; max 50 chars.
- File name keeps slug hyphenated. Do not convert it to snake_case.

Example: `Customer Churn EDA` → `notebooks/001-customer-churn-eda.py`.

## Environment

Use `uv` for every Python environment and command. Project notebooks should have a `pyproject.toml`:

```bash
uv sync
uv run python notebooks/001-example.py
```

Use the project’s uv-backed kernel when working interactively. Do not create ad-hoc virtualenvs or install dependencies with `pip`.

## Notebook Contract

- One notebook has one objective and one clear output.
- Use project-root-relative `data/` for inputs and dated `outputs/` for generated artifacts.
- Put imports, immutable config, seed setup, and logger creation in the first code cell.
- Use markdown section cells before major logical blocks; state purpose, inputs, and outputs.
- Avoid hidden state, magic commands, implicit working-directory assumptions, and out-of-order execution.
- Keep secrets and PII out of notebooks, logs, committed files, and rendered outputs.

## First Cell

```python
# %%
import logging
import random
from dataclasses import dataclass, replace
from pathlib import Path

import numpy as np

logging.basicConfig(level=logging.INFO, format="%(message)s")
logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class Config:
    output_dir: Path
    seed: int = 42


CONFIG = Config(output_dir=Path("outputs/2026-01-01/001-example"))
random.seed(CONFIG.seed)
np.random.seed(CONFIG.seed)
```

`logging.basicConfig` may be a no-op in an already configured kernel. Do not depend on its formatting for correctness; configure logging in the runner when reproducible capture matters.

## Cell Design

Each code cell has one responsibility, explicit inputs/outputs, safe logging, and a local check. Sequential notebooks may consume named outputs from earlier cells, but every dependency must be visible and the full notebook must run top-to-bottom in a fresh kernel.

Use this class-first shape. Any cell that owns config, I/O, state, model/client setup, pipeline steps, or execution MUST live behind a typed class:

```python
# %%
class SummaryBuilder:
    """Build a summary from input values.

    Attributes:
        values: Input numeric values summarized by this builder.
    """

    def __init__(self, values: list[float]) -> None:
        """Initialize builder.

        Args:
            values: Input numeric values.
        """
        self.values = values

    def build(self) -> dict[str, float]:
        """Return count and mean for configured values.

        Returns:
            Summary containing count and mean.

        Raises:
            ValueError: If values are empty.
        """
        if not self.values:
            raise ValueError("values must not be empty")
        summary = {"count": len(self.values), "mean": sum(self.values) / len(self.values)}
        logger.info("Output keys=%s count=%s", list(summary), summary["count"])
        return summary


summary = SummaryBuilder([1.0, 2.0, 3.0]).build()
assert summary["count"] == 3  # internal/test invariant only
```

Rules:

- Type-hint parameters and return values.
- Document public classes/methods with `Args:`, `Returns:`, `Raises:`, and `Attributes:` where applicable; keep trivial private helpers concise.
- Optional at call site requires a default (`value: int | None = None`).
- Use explicit exceptions for external/input validation; reserve `assert` for internal invariants and tests.
- Log counts, shapes, schemas, and safe paths—not secrets, tokens, raw PII, or full records.
- Close figures and define output-directory/overwrite behavior.

## Missing Inputs

Fail clearly by default. Do not write mock data into `data/` or overwrite a configured input path. If a demo must run without real data, require an explicit `USE_MOCK_DATA=1`/config flag and write deterministic fixtures under an isolated temp or fixture directory. Log that mock mode is active and keep it out of production results.

## Reproducibility and Safety

- Pin Python/dependencies in the project environment with `uv.lock` and record the notebook execution command.
- Set all relevant random seeds in `Config`.
- Record input paths, schema/version, parameters, seed, and output paths in a small run manifest when results matter.
- Use atomic writes where partial artifacts would mislead consumers.
- Make reruns deterministic and explicit about overwrite/cleanup behavior.
- Resolve paths from a known project root, not whichever directory opened the notebook.

## Validation

Use local checks after each meaningful transformation, then integration checks at end. A final section normally contains:

1. invariant/schema/row-count checks using explicit exceptions or test assertions;
2. a safe preview plus artifact existence check.

Create output directories before writing:

```python
CONFIG.output_dir.mkdir(parents=True, exist_ok=True)
preview_path = CONFIG.output_dir / "preview.txt"
preview_path.write_text("summary ready\n", encoding="utf-8")
if not preview_path.exists():
    raise RuntimeError(f"artifact was not written: {preview_path}")
logger.info("Wrote %s", preview_path)
```

Exact cell count is not mandatory; checks must match notebook outputs.

## Adapt Workflow

`adapt` audits first, preserves behavior, then changes structure in small steps. Do not create or keep loose notebook paths during adapt; final path must match `notebooks/NNN-slug.py`.

1. Inspect cell order, hidden state, magics, side effects, inputs, and outputs.
2. Move imports/config/seeds to the first cell; add section markdown.
3. Extract stateful steps into typed classes; keep simple transforms as functions.
4. Add explicit input/output logging and local validation.
5. Replace unsafe mock creation, secrets, and hardcoded paths.
6. Run formatter and clean-kernel verification; review the diff.

## Migrate Workflow

`migrate` uses `python-code-dev`:

1. Capture clean-kernel behavior, representative outputs, dependencies, and artifacts.
2. Map responsibilities to package modules; do not map cells mechanically.
3. Move reusable classes/functions into `src/<import_name>/`.
4. Add unit/integration tests and preserve contracts.
5. Replace duplicated notebook logic with package imports.
6. Verify imports from outside repo root and rerun notebook top-to-bottom.
7. Keep notebook as a runnable reference or explicitly archive it; do not silently delete it.

## Verify Workflow

`verify` must run the notebook from a fresh kernel/top-to-bottom, then check:

- no missing dependencies or hidden state;
- stable seeds and explicit paths;
- safe logs and no accidental secrets/PII;
- local and final validations pass;
- artifacts exist at expected paths;
- formatter/linter checks pass where configured.

Report exact commands, pass/fail results, and skipped checks. Never claim verification without output.

## Formatting

Use the project formatter/configuration (normally `black` for Python). Run it at checkpoints or through CI; do not require a save hook. Keep the project’s configured line length consistent across notebook and package code.
