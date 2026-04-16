#!/usr/bin/env bash
# /doc learn <index> <domain> <title> — graduate finding to learnings/
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

INDEX="${1:?Usage: /doc learn <index> <domain> <title>}"
DOMAIN="${2:?Usage: /doc learn <index> <domain> <title>}"
TITLE="${3:?Usage: /doc learn <index> <domain> <title>}"
SLUG="$(slugify "$TITLE")"

# Validate domain against config
VALID_DOMAINS="$(cfg learnings_domains 2>/dev/null || echo '')"
if [[ -n "$VALID_DOMAINS" ]]; then
  if ! echo "$VALID_DOMAINS" | grep -qx "$DOMAIN"; then
    echo "ERROR: '$DOMAIN' is not a valid domain." >&2
    echo "Valid domains:" >&2
    echo "$VALID_DOMAINS" | sed 's/^/  /' >&2
    exit 1
  fi
fi

# Resolve experiment
EXPT_PATH="$(resolve_experiment "$INDEX")"
EXPT_NAME="$(basename "$EXPT_PATH")"

LEARN_DIR="$DOCS_ROOT/learnings/$DOMAIN"
mkdir -p "$LEARN_DIR"

# Next learning number
NUM="$(next_number "$LEARN_DIR" 3)"

# Render filename
FILENAME="$(cfg naming.learning 2>/dev/null || echo '{NNN}-{title}.md')"
FILENAME="${FILENAME//\{NNN\}/$NUM}"
FILENAME="${FILENAME//\{title\}/$SLUG}"

LEARN_PATH="$LEARN_DIR/$FILENAME"

cat > "$LEARN_PATH" << EOF
---
title: "$TITLE"
graduated_from: experiments/$EXPT_NAME
domain: $DOMAIN
created: "$(timestamp)"
created_date: "$(datestamp)"
---

EOF

# Update experiment meta
update_meta "$EXPT_PATH" "status" "graduated"

echo "Created learnings/$DOMAIN/$FILENAME (from experiment $EXPT_NAME)"
echo "  Path: $LEARN_PATH"
