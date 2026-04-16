#!/usr/bin/env python3
"""Visualize a fleet's DAG structure from fleet.json.

Usage:
  dag-viz.py <fleet.json>              # terminal ASCII
  dag-viz.py <fleet.json> --mermaid    # mermaid diagram
  dag-viz.py <fleet-root-dir>          # auto-finds fleet.json in dir
"""

import json
import sys
import collections
from pathlib import Path


def load_fleet(path_arg: str) -> dict:
    p = Path(path_arg)
    if p.is_dir():
        p = p / "fleet.json"
    with open(p) as f:
        return json.load(f)


def topo_layers(workers: list) -> list[list[dict]]:
    """Return workers grouped by DAG layer."""
    ids = [w["id"] for w in workers]
    idset = set(ids)
    by_id = {w["id"]: w for w in workers}
    deps = {w["id"]: [d for d in (w.get("depends_on") or []) if d in idset] for w in workers}

    indeg = {wid: 0 for wid in ids}
    rev = collections.defaultdict(list)
    for wid, ds in deps.items():
        for d in ds:
            indeg[wid] += 1
            rev[d].append(wid)

    layers = []
    current = sorted([wid for wid in ids if indeg[wid] == 0], key=lambda w: ids.index(w))
    while current:
        layers.append([by_id[wid] for wid in current])
        next_layer = []
        for n in current:
            for m in rev[n]:
                indeg[m] -= 1
                if indeg[m] == 0:
                    next_layer.append(m)
        current = sorted(next_layer, key=lambda w: ids.index(w))

    if sum(len(l) for l in layers) != len(ids):
        remaining = [wid for wid in ids if not any(wid in [w["id"] for w in layer] for layer in layers)]
        print(f"CYCLE detected: {', '.join(remaining)}", file=sys.stderr)
        sys.exit(2)

    return layers


def worker_label(w: dict) -> str:
    parts = [w["id"]]
    if w.get("type"):
        parts.append(f"({w['type']})")
    if w.get("model"):
        parts.append(f"[{w['model']}]")
    if w.get("provider") and w["provider"] != "claude":
        parts.append(f"via {w['provider']}")
    return " ".join(parts)


def ascii_viz(data: dict, layers: list[list[dict]]):
    name = data.get("fleet_name", "unnamed")
    fleet_type = data.get("type", "?")
    stop = data.get("stop_when", {})

    print(f"\n  Fleet: {name}  ({fleet_type})")
    print(f"  Stop:  max_iter={stop.get('max_iterations', '?')}  "
          f"lgtm={stop.get('reviewer_lgtm_count', '?')}  "
          f"cap=${stop.get('cost_cap_usd', '?')}")
    print()

    max_label = max(len(worker_label(w)) for layer in layers for w in layer)
    box_w = max(max_label + 4, 20)

    for i, layer in enumerate(layers):
        # layer header
        tag = "LAUNCH" if i == 0 else "DEFERRED"
        print(f"  Layer {i} ({tag})")

        # boxes
        boxes = []
        for w in layer:
            label = worker_label(w)
            deps = w.get("depends_on") or []
            budget = w.get("max_budget_per_iter") or w.get("max_budget_usd")
            budget_str = f" ${budget}" if budget else ""

            top    = "  +" + "-" * (box_w - 2) + "+"
            mid    = "  | " + label.ljust(box_w - 4) + " |"
            detail = "  | " + f"deps: {', '.join(deps) if deps else 'none'}{budget_str}".ljust(box_w - 4) + " |"
            bot    = "  +" + "-" * (box_w - 2) + "+"
            boxes.append((top, mid, detail, bot))

        # print boxes side by side
        for row_idx in range(4):
            line = ""
            for b in boxes:
                line += b[row_idx] + "  "
            print(line)

        # arrow to next layer
        if i < len(layers) - 1:
            arrow_x = box_w // 2 + 2
            print(" " * arrow_x + "|")
            print(" " * arrow_x + "v")

    print()

    # iteration loop (for iterative fleets)
    fleet_type = data.get("type", "")
    stop = data.get("stop_when", {})
    max_iter = stop.get("max_iterations", data.get("config", {}).get("max_iterations"))
    lgtm_count = stop.get("reviewer_lgtm_count")
    cost_cap = stop.get("cost_cap_usd")

    if fleet_type == "iterative" and max_iter:
        # find reviewer
        reviewer = None
        for layer in layers:
            for w in layer:
                if w.get("type") == "reviewer":
                    reviewer = w["id"]
        arrow_x = box_w // 2 + 2
        print(" " * arrow_x + "|")
        print(" " * arrow_x + "v")
        print(f"  +{'=' * (box_w - 2)}+")
        verdict_label = f"verdict? (from {reviewer})" if reviewer else "iteration complete?"
        print(f"  | {verdict_label.ljust(box_w - 4)} |")
        print(f"  +{'=' * (box_w - 2)}+")
        print(f"  |{''.ljust(box_w - 2)}|")

        col1 = "lgtm"
        col2 = "iterate"
        col3 = "escalate"
        pad = (box_w - 2 - len(col1) - len(col2) - len(col3)) // 2
        print(f"  |{' ' * max(pad,1)}{col1}{' ' * max(pad,1)}{col2}{' ' * max(pad,1)}{col3}{' ' * max(pad - len(col3) + len(col3), 1)}|")
        print(f"  +{'=' * (box_w - 2)}+")
        print(f"     |{''.ljust(12)}|{''.ljust(14)}|")
        print(f"     v{''.ljust(12)}v{''.ljust(14)}v")

        stop_label = f"STOP (after {lgtm_count}x)" if lgtm_count else "STOP"
        loop_label = f"LOOP (max {max_iter})"
        pause_label = "PAUSE"
        print(f"   [{stop_label}]   [{loop_label}]   [{pause_label}]")

        # loop arrow back to top
        print(f"{''.ljust(18)}|")
        print(f"{''.ljust(18)}+--- back to Layer 0 (reset state, re-execute DAG)")
        print()

        # cost info
        if cost_cap:
            print(f"  Cost cap: ${cost_cap} across all iterations")
    print()

    # summary
    total_workers = sum(len(l) for l in layers)
    print(f"  {total_workers} workers across {len(layers)} layers")
    if fleet_type == "iterative":
        print(f"  Each iteration re-executes the full DAG (layers 0 -> {len(layers)-1})")
        if len(layers) > 1:
            print(f"  Layer 0 spawns at launch; layers 1-{len(layers)-1} spawned by orchestrator")
        print(f"  Between iterations: snapshot costs to ledger, clear session state, respawn all workers")
    elif len(layers) > 1:
        print(f"  Layer 0 spawns first; layers 1-{len(layers)-1} spawn after dependencies complete")
    else:
        print(f"  All workers in layer 0 — no dependencies, all spawn at launch")
    print()


def mermaid_viz(data: dict, layers: list[list[dict]]):
    name = data.get("fleet_name", "unnamed")
    fleet_type = data.get("type", "")
    workers = data.get("workers", [])
    stop = data.get("stop_when", {})
    max_iter = stop.get("max_iterations", data.get("config", {}).get("max_iterations"))
    lgtm_count = stop.get("reviewer_lgtm_count")
    cost_cap = stop.get("cost_cap_usd")

    print(f"```mermaid")
    print(f"graph TD")

    # DAG subgraph
    print(f'    subgraph dag ["{name} — per-iteration DAG"]')
    for layer in layers:
        for w in layer:
            wid = w["id"]
            model = w.get("model", "")
            wtype = w.get("type", "")
            label = f"{wid}<br/>{wtype} · {model}" if model else f"{wid}<br/>{wtype}"
            print(f'    {wid}["{label}"]')
    for w in workers:
        for dep in (w.get("depends_on") or []):
            print(f"    {dep} --> {w['id']}")
    print(f"    end")

    # iteration loop (for iterative fleets)
    if fleet_type == "iterative":
        # find reviewer
        reviewer_id = None
        for w in workers:
            if w.get("type") == "reviewer":
                reviewer_id = w["id"]

        if reviewer_id:
            verdict_label = f"verdict?"
            print(f'    {reviewer_id} --> verdict{{{verdict_label}}}')
            stop_label = f"STOP after {lgtm_count}x lgtm" if lgtm_count else "STOP"
            loop_label = f"next iteration"
            print(f'    verdict -->|lgtm| stop["{stop_label}"]')
            print(f'    verdict -->|iterate| loop["{loop_label}<br/>max {max_iter}"]')
            print(f'    verdict -->|escalate| pause["PAUSE for human"]')

            # loop back to first layer
            first_worker = layers[0][0]["id"] if layers else None
            if first_worker:
                print(f'    loop -->|"reset state<br/>re-execute DAG"| {first_worker}')

    # styling
    for i, layer in enumerate(layers):
        for w in layer:
            if w.get("type") == "reviewer":
                print(f"    style {w['id']} fill:#f96,stroke:#333")
            elif i == 0:
                print(f"    style {w['id']} fill:#6f9,stroke:#333")
            else:
                print(f"    style {w['id']} fill:#69f,stroke:#333")

    if fleet_type == "iterative":
        print(f"    style stop fill:#4a4,stroke:#333,color:#fff")
        print(f"    style pause fill:#fa0,stroke:#333")
        print(f"    style loop fill:#aaf,stroke:#333")
        print(f"    style verdict fill:#fff,stroke:#333")

    if cost_cap:
        print(f'    cap["cost cap: ${cost_cap}"]')
        print(f"    style cap fill:#eee,stroke:#999")

    print(f"```")


def main():
    if len(sys.argv) < 2 or sys.argv[1] in ("-h", "--help"):
        print(__doc__)
        sys.exit(0)

    data = load_fleet(sys.argv[1])
    workers = data.get("workers", [])

    if not workers:
        print("No workers found in fleet.json", file=sys.stderr)
        sys.exit(1)

    layers = topo_layers(workers)
    mermaid = "--mermaid" in sys.argv

    if mermaid:
        mermaid_viz(data, layers)
    else:
        ascii_viz(data, layers)


if __name__ == "__main__":
    main()
