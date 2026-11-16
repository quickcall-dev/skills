#!/usr/bin/env python3
"""Generate an editable draw.io file and a deterministic SVG from one JSON spec."""

from __future__ import annotations

import argparse
import json
import re
from html import escape
from pathlib import Path
from xml.etree import ElementTree as ET

LABEL_FONT_SIZE = 12
LABEL_PAD = 6  # px of white box on each side of an edge label


DEFAULT_PALETTE = {
    "ink": {"stroke": "#121a2a", "fill": "#ffffff"},
    "input": {"stroke": "#475569", "fill": "#f1f5f9"},
    "stage0": {"stroke": "#2563eb", "fill": "#e8f0ff"},
    "stage1": {"stroke": "#ea580c", "fill": "#fff0dd"},
    "stage2": {"stroke": "#6d28d9", "fill": "#f0edff"},
    "stage3": {"stroke": "#047857", "fill": "#dcfce7"},
    "gate": {"stroke": "#a16207", "fill": "#fef3c7"},
    "success": {"stroke": "#047857", "fill": "#dcfce7"},
    "failure": {"stroke": "#b91c1c", "fill": "#fee2e2"},
    "human": {"stroke": "#0e7490", "fill": "#e0f7fa"},
    "neutral": {"stroke": "#64748b", "fill": "#ffffff"},
}
FONT_PATHS = [
    Path("/System/Library/Fonts/Helvetica.ttc"),
    Path("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"),
]


def load_font(size: int, bold: bool = False):
    try:
        from PIL import ImageFont
    except ImportError as exc:  # pragma: no cover
        raise SystemExit("Pillow is required. Run with: uv run --no-project --with pillow python ...") from exc
    for path in FONT_PATHS:
        if path.exists():
            try:
                return ImageFont.truetype(str(path), size=size * 4, index=1 if bold and path.suffix == ".ttc" else 0)
            except OSError:
                continue
    return ImageFont.load_default()


def text_width(value: str, size: int, bold: bool = False) -> float:
    return load_font(size, bold).getlength(value) / 4


def wrap(value: str, width: float, size: int, bold: bool = False) -> list[str]:
    result: list[str] = []
    for paragraph in value.split("\n"):
        line = ""
        for word in paragraph.split():
            trial = word if not line else f"{line} {word}"
            if text_width(trial, size, bold) <= width:
                line = trial
            else:
                if line:
                    result.append(line)
                line = word
        if line:
            result.append(line)
    return result


def port(node: dict, name: str) -> tuple[float, float]:
    x, y, width, height = node["x"], node["y"], node["width"], node["height"]
    return {
        "left": (x, y + height / 2),
        "right": (x + width, y + height / 2),
        "top": (x + width / 2, y),
        "bottom": (x + width / 2, y + height),
    }[name]


def edge_points(edge: dict, nodes: dict[str, dict]) -> list[tuple[float, float]]:
    source = nodes[edge["from"]]
    target = nodes[edge["to"]]
    from_name = edge.get("fromPort", "right")
    to_name = edge.get("toPort", "left")
    points = [port(source, from_name)]
    points.extend(tuple(point) for point in edge.get("points", []))
    points.append(port(target, to_name))
    if len(points) == 2 and points[0][0] != points[1][0] and points[0][1] != points[1][1]:
        midpoint = (points[0][0] + points[1][0]) / 2
        points = [points[0], (midpoint, points[0][1]), (midpoint, points[1][1]), points[1]]
    # A repeated point makes a zero-length segment. If it is the last segment,
    # orient="auto" has no direction and the arrowhead lies flat on the node edge.
    deduped: list[tuple[float, float]] = []
    for point in points:
        point = (float(point[0]), float(point[1]))
        if not deduped or deduped[-1] != point:
            deduped.append(point)
    return deduped


def label_anchor(points: list[tuple[float, float]]) -> tuple[float, float, float]:
    """Midpoint and length of the longest segment. Labels go there, not at a fixed index."""
    best = max(range(len(points) - 1), key=lambda i: abs(points[i + 1][0] - points[i][0]) + abs(points[i + 1][1] - points[i][1]))
    (x1, y1), (x2, y2) = points[best], points[best + 1]
    return (x1 + x2) / 2, (y1 + y2) / 2, abs(x2 - x1) + abs(y2 - y1)


def render_node(node: dict, palette: dict) -> str:
    role = node.get("role", "neutral")
    colors = palette[role]
    x, y, width, height = (node[key] for key in ("x", "y", "width", "height"))
    align = node.get("align", "center")
    anchor = "middle" if align == "center" else "start"
    tx = x + width / 2 if align == "center" else x + 14
    title_lines = wrap(node["title"], width - 28, 16, True)
    body_lines = wrap(node.get("body", ""), width - 28, 13)
    tag = node.get("tag")
    total = (14 if tag else 0) + len(title_lines) * 21 + (6 if body_lines else 0) + len(body_lines) * 18
    cursor = y + (height - total) / 2
    parts = [f'<g id="{escape(node["id"])}">', f'<rect x="{x}" y="{y}" width="{width}" height="{height}" rx="8" fill="{colors["fill"]}" stroke="{colors["stroke"]}" stroke-width="1.8"/>']
    if tag:
        cursor += 11
        parts.append(f'<text x="{tx}" y="{cursor}" text-anchor="{anchor}" font-size="10.5" font-weight="700" letter-spacing=".7" fill="{colors["stroke"]}">{escape(tag)}</text>')
        cursor += 3
    for line in title_lines:
        cursor += 18
        parts.append(f'<text x="{tx}" y="{cursor}" text-anchor="{anchor}" font-size="16" font-weight="700" fill="#121a2a">{escape(line)}</text>')
    if body_lines:
        cursor += 5
    for line in body_lines:
        cursor += 17
        parts.append(f'<text x="{tx}" y="{cursor}" text-anchor="{anchor}" font-size="13" fill="#556176">{escape(line)}</text>')
    parts.append("</g>")
    return "\n".join(parts)


def render_svg(spec: dict, palette: dict) -> str:
    width, height = spec["width"], spec["height"]
    nodes = {node["id"]: node for node in spec["nodes"]}
    used_colors = {palette.get(edge.get("colorRole", "neutral"), palette["neutral"])["stroke"] for edge in spec["edges"]}
    markers = "".join(
        f'<marker id="{spec["name"]}-arrow-{color[1:]}" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto"><path d="M0 0 L10 5 L0 10z" fill="{color}"/></marker>'
        for color in sorted(used_colors)
    )
    parts = [
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {width} {height}" role="img" aria-labelledby="{spec["name"]}-title {spec["name"]}-desc" font-family="Helvetica,Arial,sans-serif">',
        f'<title id="{spec["name"]}-title">{escape(spec["title"])}</title>',
        f'<desc id="{spec["name"]}-desc">{escape(spec.get("subtitle", ""))}</desc>',
        f'<defs>{markers}</defs>',
        f'<rect width="{width}" height="{height}" fill="#ffffff"/>',
        f'<text x="40" y="46" font-size="28" font-weight="700" fill="#121a2a">{escape(spec["title"])}</text>',
    ]
    if spec.get("subtitle"):
        parts.append(f'<text x="40" y="74" font-size="14" fill="#556176">{escape(spec["subtitle"])}</text>')
    labels: list[str] = []
    for edge in spec["edges"]:
        points = edge_points(edge, nodes)
        color = palette.get(edge.get("colorRole", "neutral"), palette["neutral"])["stroke"]
        dash = ' stroke-dasharray="7 5"' if edge.get("dashed") else ""
        value = " ".join(f"{x},{y}" for x, y in points)
        parts.append(f'<polyline id="{escape(edge["id"])}" points="{value}" fill="none" stroke="{color}" stroke-width="1.8" marker-end="url(#{spec["name"]}-arrow-{color[1:]})"{dash}/>' )
        if edge.get("label"):
            mx, my, _ = label_anchor(points)
            box = text_width(edge["label"], LABEL_FONT_SIZE, True) + 2 * LABEL_PAD
            labels.append(f'<rect x="{mx - box / 2:.1f}" y="{my - 19}" width="{box:.1f}" height="16" rx="3" fill="#ffffff"/>')
            labels.append(f'<text x="{mx}" y="{my - 6}" text-anchor="middle" font-size="{LABEL_FONT_SIZE}" font-weight="700" fill="{color}">{escape(edge["label"])}</text>')
    parts.extend(render_node(node, palette) for node in spec["nodes"])
    parts.extend(labels)  # labels last: always on top of lines and nodes
    parts.append("</svg>")
    return "\n".join(parts) + "\n"


def drawio_style(node: dict, palette: dict) -> str:
    colors = palette[node.get("role", "neutral")]
    return f"rounded=1;whiteSpace=wrap;html=1;arcSize=8;strokeWidth=2;strokeColor={colors['stroke']};fillColor={colors['fill']};fontColor=#121a2a;fontSize=14;align={node.get('align','center')};verticalAlign=middle;spacing=12;"


def render_drawio(spec: dict, palette: dict) -> str:
    model = ET.Element("mxfile", host="app.diagrams.net", modified="2026-11-16T00:00:00.000Z", agent="diagram-creator", version="1.0")
    diagram = ET.SubElement(model, "diagram", id="page-1", name="Architecture")
    graph = ET.SubElement(diagram, "mxGraphModel", dx="0", dy="0", grid="1", gridSize="10", guides="1", tooltips="1", connect="1", arrows="1", fold="1", page="1", pageScale="1", pageWidth=str(spec["width"]), pageHeight=str(spec["height"]), math="0", shadow="0")
    root = ET.SubElement(graph, "root")
    ET.SubElement(root, "mxCell", id="0")
    ET.SubElement(root, "mxCell", id="1", parent="0")
    for node in spec["nodes"]:
        label = f"<b>{escape(node['title'])}</b>"
        if node.get("body"):
            label += f"<br><font color=\"#556176\">{escape(node['body'])}</font>"
        cell = ET.SubElement(root, "mxCell", id=node["id"], value=label, style=drawio_style(node, palette), vertex="1", parent="1")
        ET.SubElement(cell, "mxGeometry", x=str(node["x"]), y=str(node["y"]), width=str(node["width"]), height=str(node["height"]), **{"as": "geometry"})
    nodes = {node["id"]: node for node in spec["nodes"]}
    for edge in spec["edges"]:
        color = palette.get(edge.get("colorRole", "neutral"), palette["neutral"])["stroke"]
        dashed = "1" if edge.get("dashed") else "0"
        style = f"edgeStyle=orthogonalEdgeStyle;rounded=0;orthogonalLoop=1;jettySize=auto;html=1;strokeWidth=2;strokeColor={color};dashed={dashed};endArrow=block;endFill=1;"
        cell = ET.SubElement(root, "mxCell", id=edge["id"], value=edge.get("label", ""), style=style, edge="1", parent="1", source=edge["from"], target=edge["to"])
        geometry = ET.SubElement(cell, "mxGeometry", relative="1", **{"as": "geometry"})
        points = edge_points(edge, nodes)[1:-1]
        if points:
            array = ET.SubElement(geometry, "Array", **{"as": "points"})
            for x, y in points:
                ET.SubElement(array, "mxPoint", x=str(x), y=str(y))
    ET.indent(model, space="  ")
    return ET.tostring(model, encoding="unicode", xml_declaration=True) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("spec", type=Path)
    parser.add_argument("--out-dir", type=Path, required=True)
    args = parser.parse_args()
    spec = json.loads(args.spec.read_text(encoding="utf-8"))
    if not re.fullmatch(r"[a-z0-9-]+", spec["name"]):
        raise SystemExit("name must contain lowercase letters, numbers, and hyphens only")
    palette = {**DEFAULT_PALETTE, **spec.get("palette", {})}
    args.out_dir.mkdir(parents=True, exist_ok=True)
    svg = args.out_dir / f"{spec['name']}.svg"
    drawio = args.out_dir / f"{spec['name']}.drawio"
    svg.write_text(render_svg(spec, palette), encoding="utf-8")
    drawio.write_text(render_drawio(spec, palette), encoding="utf-8")
    print(svg)
    print(drawio)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

