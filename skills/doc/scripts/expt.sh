#!/usr/bin/env bash
# /doc expt <name> — create a new experiment
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

NAME="${1:?Usage: /doc expt <name>}"

DIR_NAME="$(create_experiment "$NAME")"
NUM="$(echo "$DIR_NAME" | grep -oE '^[0-9]+' | sed 's/^0*//')"

echo "Created experiments/$DIR_NAME/"
echo "  plans/ findings/ checkpoints/ research/ .meta.json"
echo "  Index: $NUM (use this number with other /doc commands)"
