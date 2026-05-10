#!/usr/bin/env bash
# /doc resume <index> — brief the agent on an experiment's current state
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

INDEX="${1:?Usage: /doc resume <index>}"

EXPT_PATH="$(resolve_experiment "$INDEX")"
EXPT_NAME="$(basename "$EXPT_PATH")"
META="$EXPT_PATH/.meta.json"
NUM="$(echo "$EXPT_NAME" | grep -oE '^[0-9]+' | sed 's/^0*//')"

echo "=== Resuming experiment $NUM: $EXPT_NAME ==="
echo ""

# Meta summary
if [[ -f "$META" ]]; then
  python3 -c "
import json
with open('$META') as f:
    m = json.load(f)
print(f\"Status: {m.get('status', '?')} | Created: {m.get('created_date', '?')} | Last active: {m.get('last_activity', '?')}\")
print(f\"Plans: {m.get('plan_count', 0)} | Findings: {m.get('finding_count', 0)} | Checkpoints: {m.get('checkpoint_count', 0)} | Research: {m.get('research_count', 0)}\")
if m.get('question'):
    print(f\"Question: {m['question']}\")
"
fi

# Latest plan
latest_plan=$(find "$EXPT_PATH/plans" -name "*.md" -type f 2>/dev/null | sort | tail -1)
if [[ -n "$latest_plan" ]]; then
  echo ""
  echo "--- Latest plan: $(basename "$latest_plan") ---"
  echo "<file-content source=\"$(basename "$latest_plan")\">"
  cat "$latest_plan"
  echo "</file-content>"
fi

# Latest checkpoint
latest_ckpt=$(find "$EXPT_PATH/checkpoints" -name "*.md" -type f 2>/dev/null | sort | tail -1)
if [[ -n "$latest_ckpt" ]]; then
  echo ""
  echo "--- Latest checkpoint: $(basename "$latest_ckpt") ---"
  echo "<file-content source=\"$(basename "$latest_ckpt")\">"
  cat "$latest_ckpt"
  echo "</file-content>"
fi

# List findings
finding_count=$(find "$EXPT_PATH/findings" -name "*.md" -type f 2>/dev/null | wc -l)
if [[ $finding_count -gt 0 ]]; then
  echo ""
  echo "--- Findings ($finding_count) ---"
  find "$EXPT_PATH/findings" -name "*.md" -type f 2>/dev/null | sed 's|.*/|  |' | sort
fi

echo ""
echo "Active experiment set to $NUM. Use /doc plan $NUM, /doc finding $NUM, etc."
