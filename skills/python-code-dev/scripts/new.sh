#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 || -z "$1" ]]; then
  printf 'usage: %s <project-name>\n' "$0" >&2
  exit 2
fi
if ! command -v uv >/dev/null 2>&1; then
  printf 'uv is required; install uv before scaffolding a project\n' >&2
  exit 127
fi

name="$1"
dir_name="$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')"
import_name="$(printf '%s' "$dir_name" | tr '-' '_')"
if [[ -z "$dir_name" || -z "$import_name" ]]; then
  printf 'project name must contain letters or numbers\n' >&2
  exit 2
fi
if ! [[ "$import_name" =~ ^[a-z_][a-z0-9_]*$ ]]; then
  printf 'project name must produce a valid Python import name\n' >&2
  exit 2
fi
case "$import_name" in
  and|as|assert|async|await|break|case|class|continue|def|del|elif|else|except|false|finally|for|from|global|if|import|in|is|lambda|match|none|nonlocal|not|or|pass|raise|return|true|try|while|with|yield)
    printf 'project name produces reserved Python import name: %s\n' "$import_name" >&2
    exit 2
    ;;
esac

looks_like_project_root=0
for marker in .git pyproject.toml README.md docs .fleet; do
  if [[ -e "$PWD/$marker" ]]; then
    looks_like_project_root=1
    break
  fi
done

if [[ "$looks_like_project_root" -eq 1 ]]; then
  root="$PWD"
  if [[ -e "$root/src" || -e "$root/tests" ]]; then
    printf 'refusing to scaffold in-place because src/ or tests/ already exists; use adapt/flatten workflow\n' >&2
    exit 1
  fi
else
  root="$PWD/$dir_name"
  if [[ -e "$root" ]]; then
    printf 'refusing to overwrite existing path: %s\n' "$root" >&2
    exit 1
  fi
fi

package="$root/src/$import_name"
mkdir -p \
  "$package/config" \
  "$package/core" \
  "$package/schemas" \
  "$package/utils" \
  "$root/tests/config" \
  "$root/tests/core" \
  "$root/tests/schemas" \
  "$root/tests/utils"
cat > "$root/pyproject.toml" <<EOF
[project]
name = "$dir_name"
version = "0.1.0"
description = "Class-first Python project"
requires-python = ">=3.12"
dependencies = []

[dependency-groups]
dev = ["pytest>=8"]

[build-system]
requires = ["setuptools>=68"]
build-backend = "setuptools.build_meta"

[tool.setuptools.packages.find]
where = ["src"]

[tool.pyright]
typeCheckingMode = "strict"
pythonVersion = "3.12"
include = ["src", "tests"]
EOF
cat > "$root/README.md" <<EOF
# $dir_name

## Setup

    uv sync

## Verify

    uv run pytest
EOF
cat > "$package/__init__.py" <<EOF
"""Public package for $dir_name."""

from .core import ExampleService

__all__ = ["ExampleService"]
EOF
cat > "$package/config/__init__.py" <<'EOF'
"""Configuration package."""

from .settings import Config

__all__ = ["Config"]
EOF
cat > "$package/config/settings.py" <<'EOF'
"""Immutable runtime configuration."""

from dataclasses import dataclass


@dataclass(frozen=True)
class Config:
    """Runtime configuration for project components.

    Attributes:
        name: Optional. Human-readable runtime name. Defaults to "default".
    """

    name: str = "default"
EOF
cat > "$package/core/__init__.py" <<'EOF'
"""Core domain package."""

from .service import ExampleService

__all__ = ["ExampleService"]
EOF
cat > "$package/core/service.py" <<'EOF'
"""Core domain services."""


class ExampleService:
    """Provide a small class that is safe to extend.

    Methods:
        greet: Return a greeting for a required name.
    """

    def greet(self, name: str) -> str:
        """Return a greeting for a required name.

        Args:
            name: Required. Non-empty name to greet.

        Returns:
            Greeting string formatted as ``Hello, <name>!``.

        Raises:
            ValueError: If ``name`` is empty or whitespace only.
        """
        if not name.strip():
            raise ValueError("name must not be empty")
        return f"Hello, {name}!"
EOF
cat > "$package/schemas/__init__.py" <<'EOF'
"""Boundary schemas package."""

from .contracts import Greeting

__all__ = ["Greeting"]
EOF
cat > "$package/schemas/contracts.py" <<'EOF'
"""Data contracts for package boundaries."""

from dataclasses import dataclass


@dataclass(frozen=True)
class Greeting:
    """Represent a generated greeting.

    Attributes:
        text: Required. Greeting text.
    """

    text: str
EOF
cat > "$package/utils/__init__.py" <<'EOF'
"""Cross-cutting utilities package."""

from .logging import get_logger

__all__ = ["get_logger"]
EOF
cat > "$package/utils/logging.py" <<'EOF'
"""Logging helpers without domain logic."""

import logging


def get_logger(name: str) -> logging.Logger:
    """Return module logger; configuration belongs to entrypoints.

    Args:
        name: Required. Logger name, usually ``__name__``.

    Returns:
        Logger instance with the requested name.
    """
    return logging.getLogger(name)
EOF
cat > "$root/tests/config/test_settings.py" <<EOF
from $import_name.config import Config


def test_config_defaults() -> None:
    assert Config().name == "default"
EOF
cat > "$root/tests/core/test_service.py" <<EOF
import pytest

from $import_name.core import ExampleService


def test_greet() -> None:
    assert ExampleService().greet("Kimi") == "Hello, Kimi!"


def test_greet_rejects_blank_name() -> None:
    with pytest.raises(ValueError, match="name must not be empty"):
        ExampleService().greet(" ")
EOF
cat > "$root/tests/schemas/test_contracts.py" <<EOF
from $import_name.schemas import Greeting


def test_greeting_contract() -> None:
    assert Greeting(text="Hello").text == "Hello"
EOF
cat > "$root/tests/utils/test_logging.py" <<EOF
import logging

from $import_name.utils import get_logger


def test_get_logger_returns_named_logger() -> None:
    logger = get_logger("test.logger")
    assert isinstance(logger, logging.Logger)
    assert logger.name == "test.logger"
EOF
cat > "$root/tests/test_smoke.py" <<EOF

def test_package_imports() -> None:
    import $import_name

    assert $import_name.ExampleService
EOF
(cd "$root" && uv lock --quiet)
printf '%s\n' "$root"
