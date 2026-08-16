"""Runtime context objects."""

import logging
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any


@dataclass(frozen=True)
class RunContext:
    """Runtime context passed through runner execution.

    Attributes:
        run_dir: Required. Directory for run artifacts.
        logger: Required. Logger for run messages.
        params: Optional. Run parameters copied from caller input.
    """

    run_dir: Path
    logger: logging.Logger
    params: dict[str, Any] = field(default_factory=dict)
