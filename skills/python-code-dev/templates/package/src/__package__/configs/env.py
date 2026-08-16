"""Environment access helpers."""

import os


def get_env(key: str, default: str | None = None) -> str | None:
    """Return an environment variable value.

    Args:
        key: Required. Environment variable name.
        default: Optional. Value returned when ``key`` is unset.

    Returns:
        Environment value or ``default``.
    """
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
