"""Atomic file writes: temporary file plus replace."""

import json
import os
from pathlib import Path
from typing import Any


def atomic_write_text(path: str | Path, text: str) -> Path:
    """Write text to path atomically.

    Args:
        path: Required. Destination file path.
        text: Required. Text content to write.

    Returns:
        Resolved destination path.
    """
    destination = Path(path)
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = destination.with_suffix(destination.suffix + ".tmp")
    temporary.write_text(text, encoding="utf-8")
    os.replace(temporary, destination)
    return destination.resolve()


def atomic_write_json(path: str | Path, data: Any, indent: int = 2) -> Path:
    """Serialize data to JSON and write it atomically.

    Args:
        path: Required. Destination file path.
        data: Required. JSON-serializable data.
        indent: Optional. JSON indentation. Defaults to 2.

    Returns:
        Resolved destination path.
    """
    return atomic_write_text(path, json.dumps(data, indent=indent, default=str))
