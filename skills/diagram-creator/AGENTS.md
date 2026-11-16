# Agent guide for diagram creation

Use this folder to create architecture diagrams for technical documents.

## Human taste to preserve

The reviewer wants diagrams that explain the product architecture. The reviewer does not want decorative flowcharts about merges, agent waves, or document-review mechanics.

Use these rules:

1. Start with the architecture question. If the diagram does not answer one question, split it.
2. Show the main system path first. Put repair loops and failure states below or beside it.
3. Use explicit geometry. Do not accept accidental layout from a graph engine.
4. Keep the reading direction consistent. Use left to right for processes and top to bottom for state transitions.
5. Use the same semantic colors in every diagram.
6. Use short, literal labels. Apply STE-flavored wording.
7. Show inputs, transformations, gates, outputs, and stop states when they exist.
8. Keep one visual hierarchy. Titles, nodes, secondary text, and edge labels must have fixed sizes.
9. Avoid crossing edges. Use orthogonal waypoints when a direct edge crosses a node.
10. Inspect the rendered output. A valid file can still be visually wrong.
11. Leave room for the arrows. Use 60 px or more between nodes, 100 px or more where an edge has a label. Each arrow must end with a 16 px or longer segment that enters its target through the declared port side. See "Edge routing rules" in `references/diagram-contract.md`.

## Skills and references

Use these installed skills when available:

- `drawio-skill`: editable `.drawio` authoring and validation.
- `asd-ste100`: controlled-language labels and instructions.
- `design-taste-frontend`: layout, contrast, rhythm, and responsive embedding.
- `doc`: experiment documentation conventions.

Read `SKILL.md` first. Then read only the relevant file in `references/`.

## Commands

Create a diagram from one JSON specification:

```bash
uv run --no-project --with pillow python scripts/create_diagram.py \
  diagram-creator/examples/four-stage-architecture.json \
  --out-dir /tmp/diagram-output
```

Validate it:

```bash
uv run --no-project python scripts/validate_diagram.py \
  diagram-creator/examples/four-stage-architecture.json \
  --out-dir /tmp/diagram-output
```

If the installed draw.io skill is present, also run its validator against the generated `.drawio` file:

```bash
python3 /Users/sagar/.codex/skills/drawio-skill/scripts/validate.py \
  /tmp/diagram-output/four-stage-architecture.drawio --score
```

## Output contract

Each completed diagram has:

- one JSON source specification;
- one editable `.drawio` file;
- one deterministic `.svg` file;
- descriptive alternative text in the HTML document;
- a successful validation result;
- a visual review at desktop and mobile widths.

Do not commit temporary PNG review exports.

