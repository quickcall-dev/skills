#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 || -z "$1" ]]; then
  printf 'usage: %s <project-name>\n' "$0" >&2
  exit 2
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

root="$PWD/$dir_name"
if [[ -e "$root" ]]; then
  printf 'refusing to overwrite existing path: %s\n' "$root" >&2
  exit 1
fi

mkdir -p "$root/src/$import_name" "$root/tests"
cat > "$root/pyproject.toml" <<EOF
[build-system]
requires = ["setuptools>=68"]
build-backend = "setuptools.build_meta"

[project]
name = "$dir_name"
version = "0.1.0"
description = "Class-first Python project"
requires-python = ">=3.11"
dependencies = []

[project.optional-dependencies]
dev = ["pytest>=8"]

[tool.setuptools.packages.find]
where = ["src"]
EOF
cat > "$root/README.md" <<EOF
# $dir_name

## Setup

    python -m venv .venv
    . .venv/bin/activate
    python -m pip install -e '.[dev]'

## Verify

    python -m pytest
EOF
cat > "$root/src/$import_name/__init__.py" <<EOF
"""Public package for $dir_name."""

from .core import ExampleService

__all__ = ["ExampleService"]
EOF
cat > "$root/src/$import_name/config.py" <<'EOF'
"""Immutable project configuration."""

from dataclasses import dataclass


@dataclass(frozen=True)
class Config:
    """Runtime configuration for project components."""

    name: str = "default"
EOF
cat > "$root/src/$import_name/core.py" <<'EOF'
"""Primary domain components."""


class ExampleService:
    """Provide a small class that is safe to extend."""

    def greet(self, name: str) -> str:
        """Return a greeting for a required name."""
        if not name.strip():
            raise ValueError("name must not be empty")
        return f"Hello, {name}!"
EOF
cat > "$root/src/$import_name/schemas.py" <<'EOF'
"""Data contracts for project boundaries."""

from dataclasses import dataclass


@dataclass(frozen=True)
class Greeting:
    """Represent a generated greeting."""

    text: str
EOF
cat > "$root/src/$import_name/utils.py" <<'EOF'
"""Small cross-cutting helpers without domain logic."""

import logging


def get_logger(name: str) -> logging.Logger:
    """Return module logger; configuration belongs to entrypoints."""
    return logging.getLogger(name)
EOF
cat > "$root/tests/test_core.py" <<EOF
from $import_name import ExampleService


def test_greet() -> None:
    assert ExampleService().greet("Kimi") == "Hello, Kimi!"
EOF
cat > "$root/tests/test_smoke.py" <<EOF

def test_package_imports() -> None:
    import $import_name

    assert $import_name.ExampleService
EOF
printf '%s\n' "$root"
