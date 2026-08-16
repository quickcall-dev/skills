"""Data contracts for package boundaries."""

from dataclasses import dataclass
from pathlib import Path
from typing import Any


@dataclass(frozen=True)
class Greeting:
    """Represent a generated greeting.

    Attributes:
        text: Required. Greeting text.
    """

    text: str


@dataclass(frozen=True)
class RunResult:
    """Represent output from one end-to-end runner execution.

    Attributes:
        run_dir: Required. Directory containing run artifacts.
        status: Required. Completion status.
        metrics: Optional. JSON-serializable run metrics.
    """

    run_dir: Path
    status: str
    metrics: dict[str, Any]
