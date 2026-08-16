"""Logging setup: plain stdout plus optional file logging."""

import logging
import sys
from pathlib import Path


def setup_run_logger(name: str, log_file: str | Path | None = None) -> logging.Logger:
    """Create a named logger with stdout and optional file handlers.

    Args:
        name: Required. Logger name.
        log_file: Optional. File path for a file handler. ``None`` skips file logging.

    Returns:
        Configured logger.
    """
    logger = logging.getLogger(name)
    logger.setLevel(logging.INFO)
    logger.propagate = False
    if logger.handlers:
        return logger

    stdout = logging.StreamHandler(sys.stdout)
    stdout.setFormatter(logging.Formatter("%(message)s"))
    logger.addHandler(stdout)

    if log_file is not None:
        path = Path(log_file)
        path.parent.mkdir(parents=True, exist_ok=True)
        file_handler = logging.FileHandler(path)
        file_handler.setFormatter(logging.Formatter("%(asctime)s %(levelname)s %(message)s"))
        logger.addHandler(file_handler)

    return logger


def get_logger(name: str) -> logging.Logger:
    """Return module logger; configuration belongs to entrypoints.

    Args:
        name: Required. Logger name, usually ``__name__``.

    Returns:
        Logger instance with the requested name.
    """
    return logging.getLogger(name)
