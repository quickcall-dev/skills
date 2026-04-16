#!/usr/bin/env bash
# /doc status <index> — show experiment details
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

INDEX="${1:?Usage: /doc status <index>}"

EXPT_PATH="$(resolve_experiment "$INDEX")"
EXPT_NAME="$(basename "$EXPT_PATH")"
META="$EXPT_PATH/.meta.json"

echo "Experiment: $EXPT_NAME"
echo ""

# Show meta
if [[ -f "$META" ]]; then
  python3 -c "
import json
with open('$META') as f:
    m = json.load(f)
print(f\"  Status:      {m.get('status', '?')}\")
print(f\"  Created:     {m.get('created_date', '?')} by {m.get('created_by', '?')}\")
print(f\"  Last active: {m.get('last_activity', '?')}\")
print(f\"  Plans:       {m.get('plan_count', 0)}\")
print(f\"  Findings:    {m.get('finding_count', 0)}\")
print(f\"  Checkpoints: {m.get('checkpoint_count', 0)}\")
print(f\"  Research:    {m.get('research_count', 0)}\")
if m.get('question'):
    print(f\"  Question:    {m['question']}\")
if m.get('tags'):
    print(f\"  Tags:        {', '.join(m['tags'])}\")
"
else
  echo "  No .meta.json found"
fi

# List files
echo ""
echo "Files:"
for subdir in plans findings checkpoints research; do
  dir="$EXPT_PATH/$subdir"
  [[ -d "$dir" ]] || continue
  count=$(find "$dir" -name "*.md" -type f 2>/dev/null | wc -l)
  if [[ $count -gt 0 ]]; then
    echo "  $subdir/"
    find "$dir" -name "*.md" -type f -printf "    %f\n" 2>/dev/null | sort
  fi
done

# Show latest checkpoint content (first 10 lines)
latest_ckpt=$(find "$EXPT_PATH/checkpoints" -name "*.md" -type f 2>/dev/null | sort | tail -1)
if [[ -n "$latest_ckpt" ]]; then
  echo ""
  echo "Latest checkpoint: $(basename "$latest_ckpt")"
  echo "---"
  head -15 "$latest_ckpt" | sed 's/^/  /'
fi
