#!/usr/bin/env bash
# Shared helpers for doc skill scripts
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG_FILE="$SKILL_DIR/config/defaults.yaml"

# Find repo root (walk up to find .git)
find_repo_root() {
  local dir="$PWD"
  while [[ "$dir" != "/" ]]; do
    [[ -d "$dir/.git" ]] && echo "$dir" && return
    dir="$(dirname "$dir")"
  done
  echo "ERROR: not inside a git repo" >&2
  exit 1
}

REPO_ROOT="$(find_repo_root)"

# Read a config value using python
cfg() {
  python3 -c "
import yaml, sys
with open('$CONFIG_FILE') as f:
    c = yaml.safe_load(f)
keys = '$1'.split('.')
v = c
for k in keys:
    if isinstance(v, dict):
        v = v.get(k)
    else:
        v = None
        break
if v is None:
    sys.exit(1)
if isinstance(v, list):
    print('\n'.join(str(i) for i in v))
elif isinstance(v, dict):
    print('\n'.join(v.keys()))
else:
    print(v)
" 2>/dev/null
}

# Walk a YAML dict tree and return all leaf paths
cfg_tree() {
  python3 -c "
import yaml
with open('$CONFIG_FILE') as f:
    c = yaml.safe_load(f)
keys = '$1'.split('.')
v = c
for k in keys:
    if isinstance(v, dict):
        v = v.get(k, {})
    else:
        v = {}
        break

def walk(d, prefix=''):
    if not isinstance(d, dict) or not d:
        if prefix:
            print(prefix)
        return
    for k, sub in d.items():
        path = f'{prefix}/{k}' if prefix else k
        if isinstance(sub, dict) and sub:
            walk(sub, path)
        else:
            print(path)

walk(v)
"
}

DOCS_ROOT="$REPO_ROOT/$(cfg docs_root 2>/dev/null || echo docs)"
EXPT_DIR="$DOCS_ROOT/experiments"

# Slugify: lowercase, spaces/underscores to hyphens, strip non-alphanumeric
slugify() {
  local slug
  slug="$(echo "$1" | tr '[:upper:]' '[:lower:]' | tr ' _' '-' | sed 's/[^a-z0-9-]//g' | sed 's/--*/-/g' | sed 's/^-//;s/-$//')"
  # Truncate to 60 chars max, trim trailing hyphen
  slug="${slug:0:60}"
  slug="${slug%-}"
  echo "$slug"
}

# UTC timestamp using config format
timestamp() {
  local fmt
  fmt="$(cfg naming.timestamp 2>/dev/null || echo '%Y-%m-%d %H:%M UTC')"
  date -u +"$fmt"
}

# ISO timestamp for .meta.json
iso_timestamp() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# Date stamp (YYYY-MM-DD)
datestamp() {
  date -u +"%Y-%m-%d"
}

# Next number: find highest NNN, return NNN+1 zero-padded
next_number() {
  local dir="$1"
  local digits="${2:-3}"
  local max=0

  if [[ -d "$dir" ]]; then
    for entry in "$dir"/[0-9]*; do
      [[ -e "$entry" ]] || continue
      local base
      base="$(basename "$entry")"
      local num
      num="$(echo "$base" | grep -oE '^[0-9]+' || echo 0)"
      num=$((10#$num))
      (( num > max )) && max=$num
    done
  fi

  printf "%0${digits}d" $(( max + 1 ))
}

# Resolve experiment from index number
resolve_experiment() {
  local index="${1:-}"

  if [[ -n "$index" ]]; then
    local padded
    padded=$(printf "%03d" "$((10#$index))")
    local matches=()
    for d in "$EXPT_DIR"/${padded}-*/; do
      [[ -d "$d" ]] && matches+=("$d")
    done

    if [[ ${#matches[@]} -eq 0 ]]; then
      for d in "$EXPT_DIR"/*/; do
        [[ -d "$d" ]] || continue
        local base
        base="$(basename "$d")"
        if [[ "$base" == *"$index"* ]]; then
          matches+=("$d")
        fi
      done
    fi

    if [[ ${#matches[@]} -eq 0 ]]; then
      echo "ERROR: no experiment matching '$index'" >&2
      exit 1
    elif [[ ${#matches[@]} -gt 1 ]]; then
      echo "ERROR: ambiguous index '$index'. Matches:" >&2
      for m in "${matches[@]}"; do
        echo "  $(basename "$m")" >&2
      done
      exit 1
    fi

    echo "${matches[0]%/}"
    return
  fi

  # No index — try cwd detection
  if [[ "$PWD" == "$EXPT_DIR"/* ]]; then
    local rel="${PWD#$EXPT_DIR/}"
    local expt_name="${rel%%/*}"
    if [[ -d "$EXPT_DIR/$expt_name" ]]; then
      echo "$EXPT_DIR/$expt_name"
      return
    fi
  fi

  echo "ERROR: no experiment index given and not inside an experiment dir" >&2
  exit 1
}

# Create experiment directory with subdirs and .meta.json
create_experiment() {
  local name="$1"
  local slug="$(slugify "$name")"
  local num="$(next_number "$EXPT_DIR" 3)"

  local dir_template="$(cfg naming.experiment 2>/dev/null || echo '{NNN}-{name}')"
  local dir_name="${dir_template//\{NNN\}/$num}"
  dir_name="${dir_name//\{name\}/$slug}"

  local expt_path="$EXPT_DIR/$dir_name"
  mkdir -p "$expt_path"

  # Create subdirs from config
  while IFS= read -r subdir; do
    [[ -z "$subdir" ]] && continue
    mkdir -p "$expt_path/$subdir"
    touch "$expt_path/$subdir/.gitkeep"
  done < <(cfg experiment_dirs 2>/dev/null || printf 'plans\nfindings\ncheckpoints\nresearch\n')

  # Create .meta.json
  local created_by="$(git config user.name 2>/dev/null || echo 'unknown')"
  local now="$(iso_timestamp)"
  cat > "$expt_path/.meta.json" << EOF
{
  "name": "$name",
  "created": "$now",
  "created_by": "$created_by",
  "created_date": "$(datestamp)",
  "status": "planning",
  "question": "",
  "tags": [],
  "plan_count": 0,
  "finding_count": 0,
  "checkpoint_count": 0,
  "research_count": 0,
  "last_activity": "$now"
}
EOF

  echo "$dir_name"
}

# Update .meta.json field
update_meta() {
  local expt_dir="$1"
  local field="$2"
  local value="$3"
  local meta="$expt_dir/.meta.json"

  [[ ! -f "$meta" ]] && return

  python3 -c "
import json
with open('$meta') as f:
    m = json.load(f)
field = '$field'
value = '$value'
if field in ('finding_count', 'checkpoint_count', 'plan_count', 'research_count'):
    m[field] = m.get(field, 0) + 1
else:
    m[field] = value
m['last_activity'] = '$(iso_timestamp)'
with open('$meta', 'w') as f:
    json.dump(m, f, indent=2)
    f.write('\n')
"
}
