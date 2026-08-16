#!/usr/bin/env bash
# lib/dag.sh — shared DAG primitives for fleet worker ordering
#
# All fleet types that support depends_on source this file.
# Functions use fleet.json as the single source of truth for worker ordering.
#
# Usage:
#   source "${SCRIPT_DIR}/../lib/dag.sh"
#   dag_topo_sort "fleet.json"          # prints worker IDs in topo order
#   dag_count_layers "fleet.json"       # prints number of layers
#   dag_get_layer_workers 0 "fleet.json"  # prints worker IDs in layer 0
#   dag_check_deps_done "reviewer" "/path/to/fleet-root" "fleet.json"
#   dag_wait_for_deps "reviewer" "/path/to/fleet-root" "fleet.json" [poll_interval]

# Kahn's BFS-layered topological sort. Prints worker IDs in topo order.
# Exits 2 on cycle. Writes "CYCLE:a,b,..." to stderr on cycle.
# Workers without depends_on are layer 0.
dag_topo_sort() {
  local fleet_json="$1"
  python3 -c '
import json, sys, collections
with open(sys.argv[1]) as f:
    data = json.load(f)
workers = data.get("workers", [])
ids = [w["id"] for w in workers]
idset = set(ids)
deps = {w["id"]: [d for d in (w.get("depends_on") or []) if d in idset] for w in workers}
indeg = {wid: 0 for wid in ids}
rev = collections.defaultdict(list)
for wid, ds in deps.items():
    for d in ds:
        indeg[wid] += 1
        rev[d].append(wid)
out = []
current = sorted([wid for wid in ids if indeg[wid] == 0], key=lambda w: ids.index(w))
while current:
    out.extend(current)
    next_layer = []
    for n in current:
        for m in rev[n]:
            indeg[m] -= 1
            if indeg[m] == 0:
                next_layer.append(m)
    current = sorted(next_layer, key=lambda w: ids.index(w))
if len(out) != len(ids):
    remaining = [wid for wid in ids if wid not in out]
    sys.stderr.write("CYCLE:" + ",".join(remaining) + "\n")
    sys.exit(2)
print("\n".join(out))
' "$fleet_json"
}

# Returns the number of layers in the DAG.
dag_count_layers() {
  local fleet_json="$1"
  python3 -c '
import json, sys, collections
with open(sys.argv[1]) as f:
    data = json.load(f)
workers = data.get("workers", [])
ids = [w["id"] for w in workers]
idset = set(ids)
deps = {w["id"]: [d for d in (w.get("depends_on") or []) if d in idset] for w in workers}
indeg = {wid: 0 for wid in ids}
rev = collections.defaultdict(list)
for wid, ds in deps.items():
    for d in ds:
        indeg[wid] += 1
        rev[d].append(wid)
layers = 0
current = sorted([wid for wid in ids if indeg[wid] == 0], key=lambda w: ids.index(w))
while current:
    layers += 1
    next_layer = []
    for n in current:
        for m in rev[n]:
            indeg[m] -= 1
            if indeg[m] == 0:
                next_layer.append(m)
    current = sorted(next_layer, key=lambda w: ids.index(w))
print(layers)
' "$fleet_json"
}

# Returns worker IDs in the given layer (0-indexed), space-separated.
dag_get_layer_workers() {
  local layer_num="$1"
  local fleet_json="$2"
  python3 -c '
import json, sys, collections
layer_target = int(sys.argv[1])
with open(sys.argv[2]) as f:
    data = json.load(f)
workers = data.get("workers", [])
ids = [w["id"] for w in workers]
idset = set(ids)
deps = {w["id"]: [d for d in (w.get("depends_on") or []) if d in idset] for w in workers}
indeg = {wid: 0 for wid in ids}
rev = collections.defaultdict(list)
for wid, ds in deps.items():
    for d in ds:
        indeg[wid] += 1
        rev[d].append(wid)
layer_idx = 0
current = sorted([wid for wid in ids if indeg[wid] == 0], key=lambda w: ids.index(w))
while current:
    if layer_idx == layer_target:
        print(" ".join(current))
        sys.exit(0)
    next_layer = []
    for n in current:
        for m in rev[n]:
            indeg[m] -= 1
            if indeg[m] == 0:
                next_layer.append(m)
    current = sorted(next_layer, key=lambda w: ids.index(w))
    layer_idx += 1
' "$layer_num" "$fleet_json"
}

# Returns the layer number (0-indexed) for a given worker ID.
dag_get_layer() {
  local worker_id="$1"
  local fleet_json="$2"
  python3 -c '
import json, sys, collections
target = sys.argv[1]
with open(sys.argv[2]) as f:
    data = json.load(f)
workers = data.get("workers", [])
ids = [w["id"] for w in workers]
idset = set(ids)
deps = {w["id"]: [d for d in (w.get("depends_on") or []) if d in idset] for w in workers}
indeg = {wid: 0 for wid in ids}
rev = collections.defaultdict(list)
for wid, ds in deps.items():
    for d in ds:
        indeg[wid] += 1
        rev[d].append(wid)
layer_idx = 0
current = sorted([wid for wid in ids if indeg[wid] == 0], key=lambda w: ids.index(w))
while current:
    if target in current:
        print(layer_idx)
        sys.exit(0)
    next_layer = []
    for n in current:
        for m in rev[n]:
            indeg[m] -= 1
            if indeg[m] == 0:
                next_layer.append(m)
    current = sorted(next_layer, key=lambda w: ids.index(w))
    layer_idx += 1
print(-1)
sys.exit(1)
' "$worker_id" "$fleet_json"
}

# Check if all dependencies for a worker are complete.
# Returns 0 if all deps done, 1 if any pending.
# "Done" = session.jsonl has terminal event OR .done sentinel exists.
dag_check_deps_done() {
  local worker_id="$1"
  local fleet_root="$2"
  local fleet_json="$3"

  local deps
  deps=$(python3 -c '
import json, sys
wid = sys.argv[1]
with open(sys.argv[2]) as f:
    data = json.load(f)
for w in data.get("workers", []):
    if w["id"] == wid:
        print(" ".join(w.get("depends_on") or []))
        break
' "$worker_id" "$fleet_json")

  [[ -z "$deps" ]] && return 0

  for dep_id in $deps; do
    local dep_jsonl="${fleet_root}/workers/${dep_id}/session.jsonl"
    if [[ -f "${fleet_root}/workers/${dep_id}/.done" ]]; then
      continue
    elif [[ -f "${dep_jsonl}" ]] && (grep -q '"type":"result"' "${dep_jsonl}" 2>/dev/null || grep -q '"type":"turn.completed"' "${dep_jsonl}" 2>/dev/null || grep -q '"type":"turn.failed"' "${dep_jsonl}" 2>/dev/null); then
      continue
    else
      return 1
    fi
  done
  return 0
}

# Block until all dependencies for a worker are complete.
# Polls every $poll_interval seconds (default 15).
dag_wait_for_deps() {
  local worker_id="$1"
  local fleet_root="$2"
  local fleet_json="$3"
  local poll_interval="${4:-15}"

  while ! dag_check_deps_done "$worker_id" "$fleet_root" "$fleet_json"; do
    sleep "$poll_interval"
  done
}
