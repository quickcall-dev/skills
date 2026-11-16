# Diagram specification contract

The generator reads one JSON object.

## Required top-level fields

| Field | Type | Meaning |
|---|---|---|
| `name` | string | Output base name. Use lowercase letters, numbers, and hyphens. |
| `title` | string | Diagram title. |
| `width` | number | Canvas width in pixels. |
| `height` | number | Canvas height in pixels. |
| `nodes` | array | Explicitly positioned nodes. |
| `edges` | array | Directed connections. |

## Optional top-level fields

| Field | Type | Meaning |
|---|---|---|
| `subtitle` | string | One sentence that states the view invariant. |
| `palette` | object | Overrides for semantic color roles. |

## Node fields

Each node requires `id`, `x`, `y`, `width`, `height`, and `title`.

Optional fields:

- `body`: short supporting text.
- `role`: `input`, `stage0`, `stage1`, `stage2`, `stage3`, `gate`, `success`, `failure`, `human`, or `neutral`.
- `tag`: small stage or type label.
- `align`: `left` or `center`.

## Edge fields

Each edge requires `id`, `from`, and `to`.

Optional fields:

- `label`: short verb or state.
- `dashed`: use `true` for feedback or optional paths.
- `colorRole`: semantic color role.
- `points`: an array of explicit `[x, y]` waypoints between the source and target.
- `fromPort`: `left`, `right`, `top`, or `bottom`.
- `toPort`: `left`, `right`, `top`, or `bottom`.

The generator creates a direct orthogonal route when `points` is absent. Add points when that route crosses a node.

## Geometry rules

- Keep at least 60 px between neighbouring nodes. Use 100 px or more where an edge carries a label. A 30–50 px gap leaves almost no visible line, so the reader cannot see where the arrow points.
- Keep at least 16 px between an edge and an unrelated node. An edge that runs along a node border reads as part of the node.
- Keep at least 24 px between parallel segments of two edges. Closer lines merge, and their labels collide.
- Keep node text at least 12 px from each edge.
- Use one node width per lane where possible.
- Keep the main path on one horizontal or vertical axis.
- Do not put more than 5 nodes on one row. For a longer chain, use a snake layout: row 1 left to right, row 2 right to left, and so on, with a vertical edge between rows. Say "read as a snake" in the caption.

## Edge routing rules

These rules prevent arrowheads that lie flat along a node border ("sleeping arrows").

- The last segment must enter the target through its `toPort` side, moving toward the node: `top` moves down, `bottom` moves up, `left` moves right, `right` moves left. If the last waypoint is level with the port, the arrowhead lies along the border.
- The last segment must be at least 16 px long. A zero-length last segment gives `orient="auto"` no direction, so the arrowhead points right whatever the edge does.
- Every segment must be horizontal or vertical. Add a waypoint at each corner.
- A straight edge between aligned ports needs no waypoints. The generator adds an elbow only when the ports differ in both x and y.

## Edge label rules

- The generator puts the label at the middle of the longest segment, above the line. You do not need a midpoint waypoint.
- The label box is as wide as its text. The longest segment must be at least the label width plus 24 px, or the label hides the line.
- Edge labels are drawn last, so nodes never cover them.

## Embedding several diagrams in one page

The generator prefixes marker, title, and description ids with the spec `name`. Inline several SVGs in one HTML page without renaming ids. Give each spec a unique `name`.

## What the validator checks

`validate_diagram.py` fails on: node overlap or gaps under 60 px, diagonal segments, a last segment under 16 px or entering the wrong side, labels longer than their segment, edges within 16 px of an unrelated node, and parallel edges closer than 24 px. A PASS does not replace looking at the render.

