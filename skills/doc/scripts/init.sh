#!/usr/bin/env bash
# /doc init [name] — scaffold docs/ skeleton, optionally create first experiment
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

NAME="${1:-}"

echo "Initializing docs structure in $DOCS_ROOT..."

# Walk the structure tree from config and create all dirs
while IFS= read -r path; do
  [[ -z "$path" ]] && continue
  dir="$DOCS_ROOT/$path"
  if [[ ! -d "$dir" ]]; then
    mkdir -p "$dir"
    echo "  Created $path/"
  else
    echo "  Exists  $path/"
  fi
done < <(cfg_tree "structure")

# .gitkeep in empty dirs
find "$DOCS_ROOT" -type d -empty -exec touch {}/.gitkeep \;

echo "Docs skeleton ready."

# If name given, create first experiment
if [[ -n "$NAME" ]]; then
  echo ""
  DIR_NAME="$(create_experiment "$NAME")"
  echo "Created experiments/$DIR_NAME/"
  echo "  Index: $(echo "$DIR_NAME" | grep -oE '^[0-9]+' | sed 's/^0*//')"
fi
