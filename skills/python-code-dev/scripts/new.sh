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

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
skill_dir="$(cd "$script_dir/.." && pwd)"
template_dir="$skill_dir/templates/package"
if [[ ! -d "$template_dir" ]]; then
  printf 'missing template directory: %s\n' "$template_dir" >&2
  exit 1
fi

name="$1"
dir_name="$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')"
import_name="$(printf '%s' "$dir_name" | tr '-' '_')"
package_upper="$(printf '%s' "$import_name" | tr '[:lower:]' '[:upper:]')"
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

mkdir -p "$root"
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

## Run

    uv run python -m $import_name.runner.cli --message hello
EOF

mkdir -p "$root/src" "$root/tests"
cp -R "$template_dir/src/__package__" "$root/src/$import_name"
cp -R "$template_dir/tests/." "$root/tests/"

python3 - "$root" "$import_name" "$dir_name" "$package_upper" <<'PY'
from pathlib import Path
import sys

root = Path(sys.argv[1])
package = sys.argv[2]
project = sys.argv[3]
package_upper = sys.argv[4]
for path in list((root / "src" / package).rglob("*.py")) + list((root / "tests").rglob("*.py")):
    text = path.read_text(encoding="utf-8")
    text = text.replace("__PACKAGE_UPPER__", package_upper)
    text = text.replace("__PACKAGE__", package)
    text = text.replace("__package__", package)
    text = text.replace("__PROJECT__", project)
    path.write_text(text, encoding="utf-8")
PY

(cd "$root" && uv lock --quiet)
printf '%s\n' "$root"
