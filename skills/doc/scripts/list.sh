#!/usr/bin/env bash
# /doc list — show all experiments with status
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

if [[ ! -d "$EXPT_DIR" ]]; then
  echo "No experiments directory found at $EXPT_DIR"
  exit 0
fi

# Header
printf "%-6s %-40s %-12s %-12s %s\n" "INDEX" "NAME" "STATUS" "CREATED" "P/F/C/R"
printf "%-6s %-40s %-12s %-12s %s\n" "-----" "----" "------" "-------" "-----"

for expt in "$EXPT_DIR"/[0-9]*/; do
  [[ -d "$expt" ]] || continue
  local_name="$(basename "$expt")"
  num="$(echo "$local_name" | grep -oE '^[0-9]+' | sed 's/^0*//')"
  meta="$expt/.meta.json"

  if [[ -f "$meta" ]]; then
    read -r status created_date plan_count finding_count checkpoint_count research_count < <(
      python3 -c "
import json
with open('$meta') as f:
    m = json.load(f)
print(m.get('status','?'), m.get('created_date','?'), m.get('plan_count',0), m.get('finding_count',0), m.get('checkpoint_count',0), m.get('research_count',0))
" 2>/dev/null || echo "? ? 0 0 0 0"
    )
    printf "%-6s %-40s %-12s %-12s %s/%s/%s/%s\n" "$num" "$local_name" "$status" "$created_date" "$plan_count" "$finding_count" "$checkpoint_count" "$research_count"
  else
    printf "%-6s %-40s %-12s %-12s %s\n" "$num" "$local_name" "no-meta" "?" "-"
  fi
done
