"""Project path helpers."""

from pathlib import Path

from __PACKAGE__.configs.env import get_env


def repo_root() -> Path:
    """Return repository root inferred from this package location.

    Returns:
        Repository root path.
    """
    return Path(__file__).resolve().parents[3]


def _root_from_env(key: str, default: str) -> Path:
    """Resolve a path from env, defaulting relative to repo root.

    Args:
        key: Required. Environment variable name.
        default: Required. Default repo-root-relative path.

    Returns:
        Absolute resolved path.
    """
    value = get_env(key, default)
    path = Path(value) if value is not None else Path(default)
    if not path.is_absolute():
        path = repo_root() / path
    return path.resolve()


def output_root() -> Path:
    """Return output root path.

    Returns:
        Absolute output root path.
    """
    return _root_from_env("__PACKAGE_UPPER___OUTPUT_ROOT", "outputs")


def logs_root() -> Path:
    """Return logs root path.

    Returns:
        Absolute logs root path.
    """
    return _root_from_env("__PACKAGE_UPPER___LOGS_ROOT", "logs")
