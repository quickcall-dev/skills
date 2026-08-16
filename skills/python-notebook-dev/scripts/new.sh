#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 || -z "$1" ]]; then
  printf 'usage: %s <notebook-name>\n' "$0" >&2
  exit 2
fi

name="$1"
slug="$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]' | sed -E 's/[_ ]+/-/g; s/[^a-z0-9-]+//g; s/-+/-/g; s/^-+//; s/-+$//' | cut -c1-50 | sed -E 's/-+$//')"
stem="$(printf '%s' "$slug" | tr '-' '_')"
if [[ -z "$slug" || -z "$stem" ]]; then
  printf 'notebook name must contain letters or numbers\n' >&2
  exit 2
fi

mkdir -p notebooks
shopt -s nullglob
next=1
for path in notebooks/[0-9][0-9][0-9]-*; do
  [[ -d "$path" ]] || continue
  prefix="${path##*/}"; prefix="${prefix%%-*}"
  [[ "$prefix" =~ ^[0-9]{3}$ ]] || continue
  value=$((10#$prefix + 1))
  (( value > next )) && next=$value
done
while :; do
  id="$(printf '%03d' "$next")"
  dir="$PWD/notebooks/$id-$slug"
  [[ ! -e "$dir" ]] && break
  next=$((next + 1))
done

mkdir -p "$dir"
file="$dir/$stem.py"
cat > "$file" <<EOF
# %% [markdown]
# # $name
#
# Focused experiment. Record objective, inputs, and expected output here.

# %%
import logging
from dataclasses import dataclass
from pathlib import Path

PROJECT_ROOT = (Path(__file__).resolve().parents[2]
                if "__file__" in globals() else Path.cwd())

logging.basicConfig(level=logging.INFO, format="%(message)s")
logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class Config:
    """Configuration for this experiment."""

    output_dir: Path = PROJECT_ROOT / "outputs/$(date +%F)/$id-$slug"


CONFIG = Config()

# %% [markdown]
# ## Run Experiment
# Build one small, inspectable result from explicit inputs.

# %%
class Experiment:
    """Run experiment logic with explicit configuration."""

    def __init__(self, config: Config) -> None:
        self.config = config

    def run(self) -> dict[str, str]:
        """Create and return a minimal result."""
        result = {"status": "ready"}
        logger.info("Output keys=%s", list(result))
        return result


result = Experiment(CONFIG).run()
if result["status"] != "ready":
    raise RuntimeError("experiment did not become ready")

# %% [markdown]
# ## Validation
# Confirm result contract and write one deterministic artifact.

# %%
CONFIG.output_dir.mkdir(parents=True, exist_ok=True)
artifact = CONFIG.output_dir / "result.txt"
artifact.write_text(result["status"] + "\n", encoding="utf-8")
if not artifact.exists():
    raise RuntimeError(f"artifact was not written: {artifact}")
logger.info("Wrote %s", artifact)
EOF
printf '%s\n' "$file"
