#!/usr/bin/env bash
# /doc review <index> <title> — create a review file in experiment
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

INDEX="${1:?Usage: /doc review <index> <title>}"
TITLE="${2:?Usage: /doc review <index> <title>}"
SLUG="$(slugify "$TITLE")"

EXPT_PATH="$(resolve_experiment "$INDEX")"
EXPT_NAME="$(basename "$EXPT_PATH")"
REVIEW_DIR="$EXPT_PATH/review"
mkdir -p "$REVIEW_DIR"

# Next review number
NUM="$(next_number "$REVIEW_DIR" 2)"

# Render filename
FILENAME="$(cfg naming.review 2>/dev/null || echo '{NN}-review-{title}.md')"
FILENAME="${FILENAME//\{NN\}/$NUM}"
FILENAME="${FILENAME//\{title\}/$SLUG}"

REVIEW_PATH="$REVIEW_DIR/$FILENAME"

cat > "$REVIEW_PATH" << EOF
---
title: "$TITLE"
experiment: $EXPT_NAME
reviewer: ""
created: "$(timestamp)"
verdict: ""
---

EOF

# Update meta
update_meta "$EXPT_PATH" "review_count" "increment"

echo "Created $EXPT_NAME/review/$FILENAME"
echo "  Path: $REVIEW_PATH"
