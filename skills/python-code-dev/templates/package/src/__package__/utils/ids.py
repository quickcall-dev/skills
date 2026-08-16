"""Run directory and ID helpers."""

import re
from datetime import date
from pathlib import Path

_RUN_DIR_RE = re.compile(r"^run_(\d{3})$")


def today_str() -> str:
    """Return today's date as YYYY-MM-DD.

    Returns:
        ISO-8601 date string.
    """
    return date.today().isoformat()


def new_run_dir(base: str | Path) -> Path:
    """Create base if needed and return the next run_NNN directory.

    Args:
        base: Required. Parent directory for run folders.

    Returns:
        Newly-created run directory path.
    """
    root = Path(base)
    root.mkdir(parents=True, exist_ok=True)
    max_num = 0
    for entry in root.iterdir():
        match = _RUN_DIR_RE.match(entry.name)
        if match and entry.is_dir():
            max_num = max(max_num, int(match.group(1)))
    run_dir = root / f"run_{max_num + 1:03d}"
    run_dir.mkdir(parents=True, exist_ok=True)
    return run_dir
