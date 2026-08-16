"""Reusable class-first runner foundation."""

from abc import ABC, abstractmethod
from pathlib import Path
from typing import Any

from __PACKAGE__.core.context import RunContext
from __PACKAGE__.schemas import RunResult
from __PACKAGE__.utils.atomic import atomic_write_json
from __PACKAGE__.utils.ids import new_run_dir, today_str
from __PACKAGE__.utils.logging import setup_run_logger


class BaseRunner(ABC):
    """Base class for simple end-to-end runners.

    Attributes:
        name: Required. Stable runner name used for output directories and logs.
    """

    name: str = "runner"

    def __init__(self, output_root: str | Path) -> None:
        """Initialize the runner.

        Args:
            output_root: Required. Parent directory for dated run outputs.

        Returns:
            None.
        """
        self.output_root = Path(output_root)

    def run(self, params: dict[str, Any] | None = None) -> RunResult:
        """Create run context, execute implementation, and write artifacts.

        Args:
            params: Optional. JSON-serializable run parameters.

        Returns:
            Run result containing run directory, status, and metrics.
        """
        safe_params = dict(params) if params is not None else {}
        run_dir = new_run_dir(self.output_root / self.name / today_str())
        logger = setup_run_logger(self.name, run_dir / "run.log")
        atomic_write_json(run_dir / "config.json", safe_params)
        logger.info("Starting run name=%s run_dir=%s", self.name, run_dir)
        metrics = self.execute(RunContext(run_dir=run_dir, logger=logger, params=safe_params))
        result = RunResult(run_dir=run_dir, status="finished", metrics=metrics)
        atomic_write_json(
            run_dir / "result.json",
            {"status": result.status, "metrics": result.metrics},
        )
        logger.info("Finished run name=%s run_dir=%s", self.name, run_dir)
        return result

    @abstractmethod
    def execute(self, ctx: RunContext) -> dict[str, Any]:
        """Execute runner-specific work.

        Args:
            ctx: Required. Runtime context with run directory, logger, and params.

        Returns:
            JSON-serializable metrics for the run.
        """
        raise NotImplementedError


class ExampleRunner(BaseRunner):
    """Minimal end-to-end runner users can extend.

    Methods:
        execute: Write one message artifact and return metrics.
    """

    name = "example"

    def execute(self, ctx: RunContext) -> dict[str, Any]:
        """Write a message artifact and return metrics.

        Args:
            ctx: Required. Runtime context for this run.

        Returns:
            Metrics containing the emitted message length.
        """
        message = str(ctx.params.get("message", "hello"))
        artifact = ctx.run_dir / "message.txt"
        artifact.write_text(message + "\n", encoding="utf-8")
        ctx.logger.info("Wrote %s", artifact)
        return {"message": message, "message_length": len(message)}
