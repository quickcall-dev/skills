#!/usr/bin/env bash
# /doc finding <index> <title> — create a finding file in experiment
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

INDEX="${1:?Usage: /doc finding <index> <title>}"
TITLE="${2:?Usage: /doc finding <index> <title>}"
SLUG="$(slugify "$TITLE")"

EXPT_PATH="$(resolve_experiment "$INDEX")"
EXPT_NAME="$(basename "$EXPT_PATH")"
FINDING_DIR="$EXPT_PATH/findings"
mkdir -p "$FINDING_DIR"

# Next finding number
NUM="$(next_number "$FINDING_DIR" 2)"

# Render filename
FILENAME="$(cfg naming.finding 2>/dev/null || echo '{NN}-{title}.md')"
FILENAME="${FILENAME//\{NN\}/$NUM}"
FILENAME="${FILENAME//\{title\}/$SLUG}"

FINDING_PATH="$FINDING_DIR/$FILENAME"

cat > "$FINDING_PATH" << EOF
---
title: "$TITLE"
experiment: $EXPT_NAME
created: "$(timestamp)"
---

EOF

# Update meta
update_meta "$EXPT_PATH" "finding_count" "increment"

echo "Created $EXPT_NAME/findings/$FILENAME"
echo "  Path: $FINDING_PATH"
