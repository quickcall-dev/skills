"""Environment access helpers with lightweight .env loading."""

import os
from pathlib import Path

_LOADED = False


def _repo_root() -> Path:
    """Return repository root inferred from this package location.

    Returns:
        Repository root path.
    """
    return Path(__file__).resolve().parents[3]


def load_env(path: str | Path | None = None) -> None:
    """Load key-value pairs from a .env file into ``os.environ``.

    Existing environment variables win. Lines starting with ``#`` and blank lines
    are ignored. Quotes around values are stripped.

    Args:
        path: Optional. .env path. ``None`` uses ``repo_root() / ".env"``.

    Returns:
        None.
    """
    global _LOADED
    if _LOADED and path is None:
        return

    env_path = Path(path) if path is not None else _repo_root() / ".env"
    if not env_path.exists():
        _LOADED = True
        return

    for raw_line in env_path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip().strip('"').strip("'")
        if key and key not in os.environ:
            os.environ[key] = value
    _LOADED = True


def get_env(key: str, default: str | None = None) -> str | None:
    """Return an environment variable value.

    Args:
        key: Required. Environment variable name.
        default: Optional. Value returned when ``key`` is unset.

    Returns:
        Environment value or ``default``.
    """
    load_env()
    return os.getenv(key, default)


def require_env(key: str) -> str:
    """Return an environment variable value or fail clearly.

    Args:
        key: Required. Environment variable name.

    Returns:
        Environment value.

    Raises:
        RuntimeError: If ``key`` is unset.
    """
    value = get_env(key)
    if value is None:
        raise RuntimeError(f"Missing required environment variable: {key}")
    return value
