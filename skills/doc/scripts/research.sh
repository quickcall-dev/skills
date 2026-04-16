#!/usr/bin/env bash
# /doc research <index> <topic> — create research files in experiment
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

INDEX="${1:?Usage: /doc research <index> <topic>}"
TOPIC="${2:?Usage: /doc research <index> <topic>}"
SLUG="$(slugify "$TOPIC")"

EXPT_PATH="$(resolve_experiment "$INDEX")"
EXPT_NAME="$(basename "$EXPT_PATH")"
RESEARCH_DIR="$EXPT_PATH/research"
mkdir -p "$RESEARCH_DIR"

# Next research number
NUM="$(next_number "$RESEARCH_DIR" 2)"

# Render filenames
PROMPT_NAME="$(cfg naming.research_prompt 2>/dev/null || echo '{NN}-prompt-{topic}.md')"
PROMPT_NAME="${PROMPT_NAME//\{NN\}/$NUM}"
PROMPT_NAME="${PROMPT_NAME//\{topic\}/$SLUG}"

RESPONSE_NAME="$(cfg naming.research_response 2>/dev/null || echo '{NN}-res-{topic}.md')"
RESPONSE_NAME="${RESPONSE_NAME//\{NN\}/$NUM}"
RESPONSE_NAME="${RESPONSE_NAME//\{topic\}/$SLUG}"

cat > "$RESEARCH_DIR/$PROMPT_NAME" << EOF
---
topic: "$TOPIC"
experiment: $EXPT_NAME
created: "$(timestamp)"
---

EOF

cat > "$RESEARCH_DIR/$RESPONSE_NAME" << EOF
---
topic: "$TOPIC"
experiment: $EXPT_NAME
created: "$(timestamp)"
---

EOF

# Update meta
update_meta "$EXPT_PATH" "research_count" "increment"

echo "Created $EXPT_NAME/research/$PROMPT_NAME"
echo "Created $EXPT_NAME/research/$RESPONSE_NAME"
