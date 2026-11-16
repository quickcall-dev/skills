#!/usr/bin/env python3
"""Validate diagram JSON and the generated SVG and draw.io files."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from xml.etree import ElementTree as ET

from create_diagram import edge_points, label_anchor

MIN_NODE_GAP = 60      # px between neighbouring nodes in a row or column
MIN_LABEL_GAP = 24     # px of visible line on top of the label width
MIN_LAST_SEGMENT = 16  # px; room for the arrowhead to point into the node
MIN_CLEARANCE = 16     # px between an edge and an unrelated node
MIN_PARALLEL_GAP = 24  # px between parallel segments of different edges
LABEL_CHAR_PX = 7.5    # 12 px bold estimate, no Pillow needed

ENTRY = {"top": (0, 1), "bottom": (0, -1), "left": (1, 0), "right": (-1, 0)}


def close_parallel(p: list, q: list) -> bool:
    for (ax1, ay1), (ax2, ay2) in zip(p, p[1:]):
        for (bx1, by1), (bx2, by2) in zip(q, q[1:]):
            if ay1 == ay2 and by1 == by2 and abs(ay1 - by1) < MIN_PARALLEL_GAP:
                overlap = min(max(ax1, ax2), max(bx1, bx2)) - max(min(ax1, ax2), min(bx1, bx2))
            elif ax1 == ax2 and bx1 == bx2 and abs(ax1 - bx1) < MIN_PARALLEL_GAP:
                overlap = min(max(ay1, ay2), max(by1, by2)) - max(min(ay1, ay2), min(by1, by2))
            else:
                continue
            if overlap > MIN_PARALLEL_GAP:
                return True
    return False


def check_geometry(spec: dict, errors: list[str]) -> None:
    nodes = {node["id"]: node for node in spec["nodes"]}
    items = list(nodes.values())
    for i, a in enumerate(items):
        for b in items[i + 1:]:
            ax2, ay2, bx2, by2 = a["x"] + a["width"], a["y"] + a["height"], b["x"] + b["width"], b["y"] + b["height"]
            share_rows = a["y"] < by2 and b["y"] < ay2
            share_cols = a["x"] < bx2 and b["x"] < ax2
            if share_rows and share_cols:
                errors.append(f"nodes {a['id']} and {b['id']} overlap")
            elif share_rows and max(b["x"] - ax2, a["x"] - bx2) < MIN_NODE_GAP:
                errors.append(f"nodes {a['id']} and {b['id']} are closer than {MIN_NODE_GAP} px horizontally")
            elif share_cols and max(b["y"] - ay2, a["y"] - by2) < MIN_NODE_GAP:
                errors.append(f"nodes {a['id']} and {b['id']} are closer than {MIN_NODE_GAP} px vertically")
    routed = {edge["id"]: edge_points(edge, nodes) for edge in spec["edges"] if edge.get("from") in nodes and edge.get("to") in nodes}
    ids = list(routed)
    for i, a in enumerate(ids):
        for b in ids[i + 1:]:
            if close_parallel(routed[a], routed[b]):
                errors.append(f"edges {a} and {b} run parallel closer than {MIN_PARALLEL_GAP} px; their lines and labels merge")
    for edge in spec["edges"]:
        if edge.get("from") not in nodes or edge.get("to") not in nodes:
            continue
        eid = edge["id"]
        points = edge_points(edge, nodes)
        segments = list(zip(points, points[1:]))
        if not segments:
            errors.append(f"edge {eid} has no length")
            continue
        for (x1, y1), (x2, y2) in segments:
            if x1 != x2 and y1 != y2:
                errors.append(f"edge {eid} has a diagonal segment; add waypoints")
        (x1, y1), (x2, y2) = segments[-1]
        length = abs(x2 - x1) + abs(y2 - y1)
        if length < MIN_LAST_SEGMENT:
            errors.append(f"edge {eid} last segment is {length:.0f} px; the arrowhead lies flat")
        to_port = edge.get("toPort", "left")
        dx, dy = (x2 > x1) - (x2 < x1), (y2 > y1) - (y2 < y1)
        if (dx, dy) != ENTRY[to_port]:
            errors.append(f"edge {eid} does not enter {edge['to']} through its {to_port} side; the arrowhead lies along the node edge")
        if edge.get("label"):
            _, _, span = label_anchor(points)
            need = len(edge["label"]) * LABEL_CHAR_PX + MIN_LABEL_GAP
            if span < need:
                errors.append(f"edge {eid} label needs a {need:.0f} px segment, longest is {span:.0f} px")
        for node in items:
            if node["id"] in (edge["from"], edge["to"]):
                continue
            nx1, ny1 = node["x"] - MIN_CLEARANCE, node["y"] - MIN_CLEARANCE
            nx2, ny2 = node["x"] + node["width"] + MIN_CLEARANCE, node["y"] + node["height"] + MIN_CLEARANCE
            for (sx1, sy1), (sx2, sy2) in segments:
                if max(sx1, sx2) > nx1 and min(sx1, sx2) < nx2 and max(sy1, sy2) > ny1 and min(sy1, sy2) < ny2:
                    errors.append(f"edge {eid} passes through or within {MIN_CLEARANCE} px of node {node['id']}")
                    break


def fail(errors: list[str], value: str) -> None:
    errors.append(value)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("spec", type=Path)
    parser.add_argument("--out-dir", type=Path, required=True)
    args = parser.parse_args()
    spec = json.loads(args.spec.read_text(encoding="utf-8"))
    errors: list[str] = []
    node_ids = [node.get("id") for node in spec.get("nodes", [])]
    edge_ids = [edge.get("id") for edge in spec.get("edges", [])]
    if len(node_ids) != len(set(node_ids)):
        fail(errors, "node IDs are not unique")
    if len(edge_ids) != len(set(edge_ids)):
        fail(errors, "edge IDs are not unique")
    known = set(node_ids)
    width, height = spec.get("width", 0), spec.get("height", 0)
    for node in spec.get("nodes", []):
        for key in ("x", "y", "width", "height", "title"):
            if key not in node:
                fail(errors, f"node {node.get('id')} has no {key}")
        if node.get("x", 0) < 0 or node.get("y", 0) < 0:
            fail(errors, f"node {node.get('id')} starts outside the canvas")
        if node.get("x", 0) + node.get("width", 0) > width or node.get("y", 0) + node.get("height", 0) > height:
            fail(errors, f"node {node.get('id')} exceeds the canvas")
        if len(node.get("title", "").split()) > 8:
            fail(errors, f"node {node.get('id')} title has more than 8 words")
    for edge in spec.get("edges", []):
        if edge.get("from") not in known or edge.get("to") not in known:
            fail(errors, f"edge {edge.get('id')} has an unknown endpoint")
        if len(edge.get("label", "").split()) > 4:
            fail(errors, f"edge {edge.get('id')} label has more than 4 words")
    check_geometry(spec, errors)
    svg = args.out_dir / f"{spec['name']}.svg"
    drawio = args.out_dir / f"{spec['name']}.drawio"
    for path in (svg, drawio):
        if not path.is_file() or path.stat().st_size == 0:
            fail(errors, f"missing output: {path}")
            continue
        try:
            ET.parse(path)
        except ET.ParseError as exc:
            fail(errors, f"invalid XML in {path}: {exc}")
    if svg.is_file():
        text = svg.read_text(encoding="utf-8")
        if "<title" not in text or "<desc" not in text:
            fail(errors, "SVG has no accessible title or description")
        if "foreignObject" in text:
            fail(errors, "SVG uses foreignObject and can render inconsistently")
    if errors:
        print("FAIL")
        for error in errors:
            print(f"- {error}")
        return 1
    print(f"PASS: {len(node_ids)} nodes, {len(edge_ids)} edges, SVG and draw.io valid")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

