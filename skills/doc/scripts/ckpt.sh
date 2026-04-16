#!/usr/bin/env bash
# /doc ckpt <index> <description> — create checkpoint in experiment
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

INDEX="${1:?Usage: /doc ckpt <index> <description>}"
DESC="${2:?Usage: /doc ckpt <index> <description>}"
SLUG="$(slugify "$DESC")"

EXPT_PATH="$(resolve_experiment "$INDEX")"
EXPT_NAME="$(basename "$EXPT_PATH")"
CKPT_DIR="$EXPT_PATH/checkpoints"
mkdir -p "$CKPT_DIR"

# Next checkpoint number
NUM="$(next_number "$CKPT_DIR" 2)"

# Render filename
FILENAME="$(cfg naming.checkpoint 2>/dev/null || echo '{NN}-{description}.md')"
FILENAME="${FILENAME//\{NN\}/$NUM}"
FILENAME="${FILENAME//\{description\}/$SLUG}"

CKPT_PATH="$CKPT_DIR/$FILENAME"

cat > "$CKPT_PATH" << EOF
---
title: "$DESC"
experiment: $EXPT_NAME
created: "$(timestamp)"
---

EOF

# Update meta
update_meta "$EXPT_PATH" "checkpoint_count" "increment"

echo "Created $EXPT_NAME/checkpoints/$FILENAME"
echo "  Path: $CKPT_PATH"
echo ""
echo ""
echo "⚠️  ACTION REQUIRED: Write checkpoint body into this file NOW."
echo "   Sections: mermaid diagram / What / Key Takeaways / Issues / Decisions / Next"
echo "   A new agent must be able to continue from this checkpoint alone."
echo "   The file is EMPTY — a title-only checkpoint is useless."
