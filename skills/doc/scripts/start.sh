#!/usr/bin/env bash
# /doc start <name> — scaffold docs/ + create first experiment in one shot
# Alias for: init <name> (but "start" is the preferred verb)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

NAME="${1:?Usage: /doc start <name>}"

# Scaffold docs/ if needed
while IFS= read -r path; do
  [[ -z "$path" ]] && continue
  dir="$DOCS_ROOT/$path"
  [[ ! -d "$dir" ]] && mkdir -p "$dir"
done < <(cfg_tree "structure")
find "$DOCS_ROOT" -type d -empty -exec touch {}/.gitkeep \;

# Create experiment
DIR_NAME="$(create_experiment "$NAME")"
NUM="$(echo "$DIR_NAME" | grep -oE '^[0-9]+' | sed 's/^0*//')"

echo "Started experiment $NUM: $DIR_NAME"
echo "  Use /doc plan $NUM, /doc finding $NUM, /doc ckpt $NUM, etc."
