---
name: diagram-creator
description: Create consistent architecture flowcharts as editable draw.io files and deterministic SVG exports from one explicit diagram specification. Use for system, pipeline, gate, state, sequence, and decision diagrams. Do not use for decorative illustrations.
metadata:
  author: make-skill-templates
  version: "1.0"
license: Apache-2.0
compatibility: Compatible with Claude Code, Pi, and Codex. Requires Python 3 and uv; uv fetches Pillow for text measurement. Generated files are plain SVG and .drawio.
allowed-tools: Read Bash(uv:*) Bash(python3:*)
---

# Diagrams Creator

Create architecture diagrams that explain one decision or flow. Keep the editable `.drawio` file and the web-ready `.svg` file in sync by generating both from one JSON specification.

## Workflow

1. Read [references/human-taste.md](references/human-taste.md) before you design a new visual system.
2. Read [references/diagram-contract.md](references/diagram-contract.md) before you write a specification.
3. Copy the example closest to your diagram: [examples/four-stage-architecture.json](examples/four-stage-architecture.json) (pipeline with a gate and a repair loop), [examples/plan-lifecycle-states.json](examples/plan-lifecycle-states.json) (state view with terminal stops), or [examples/two-stage-retrieval.json](examples/two-stage-retrieval.json) (two-stage flow with failure lanes).
4. Give every node an explicit position and size. Give every non-trivial edge explicit waypoints.
5. Generate both formats:

   ```bash
   uv run --no-project --with pillow python scripts/create_diagram.py \
     examples/four-stage-architecture.json \
     --out-dir /tmp/diagram-output
   ```

6. Validate the source specification and outputs:

   ```bash
   uv run --no-project python scripts/validate_diagram.py \
     examples/four-stage-architecture.json \
     --out-dir /tmp/diagram-output
   ```

7. Inspect the SVG at desktop and mobile widths. Fix overlaps, clipped labels, weak hierarchy, and ambiguous edge routes. Zoom in on every arrowhead: each one must point into its target node, not along the border.

## Required rules

- One diagram explains one architecture question.
- Use nouns for nodes and short verbs for edge labels.
- Put the main path on one axis.
- Put failures, repair loops, and optional paths on a separate lane.
- Use one color per semantic role. Do not use color as decoration.
- Keep labels inside nodes. Do not place paragraphs on edges.
- Use solid edges for the main path. Use dashed edges for repair, feedback, or optional paths.
- Use active voice and short sentences. Apply STE-flavored wording to titles and descriptions.
- Do not use automatic layout for a reviewed diagram with fewer than 15 nodes.
- Keep at least 60 px between nodes, and 100 px where an edge has a label. Put at most 5 nodes on a row; wrap longer chains as a snake.
- Make every arrow enter its target through the `toPort` side, moving toward the node, with a last segment of 16 px or more. Otherwise the arrowhead lies flat on the node border.
- Keep edges 16 px from unrelated nodes and 24 px from parallel edges.
- Do not add midpoint waypoints for labels. The generator places each label above the middle of the longest segment.
- Do not generate diagrams for merge mechanics, agent waves, or review bureaucracy unless the user asks for those diagrams.

## Install

The skill works from any location; agents discover it from their skills directory. Personal skills: clone or symlink this folder into `~/.agents/skills/` (Pi, Codex) and `~/.claude/skills/` (Claude Code). Project skills: `.agents/skills/` or `.claude/skills/` at the repo root. Keep the folder name `diagram-creator` — the `name` field must match the directory name.

## External skills used

This toolkit was informed by these skills:

- `drawio-skill` for editable sources, structural validation, export, and visual review.
- `asd-ste100` for short, unambiguous labels.
- `design-taste-frontend` for alignment, spacing, contrast, and responsive embedding.
- `doc` for experiment-document conventions.

See [references/skills-used.md](references/skills-used.md) for exact sources and the parts that influenced this toolkit.

Install these if not available:

```bash
git clone https://github.com/Agents365-ai/drawio-skill ~/.agents/skills/drawio-skill
git clone https://github.com/danyuchn/asd-ste100-skill ~/.agents/skills/asd-ste100
git clone https://github.com/leonxlnx/taste-skill ~/.agents/skills/design-taste-frontend
git clone https://github.com/quickcall-dev/skills ~/.agents/skills/doc
```

Adjust the target directory if your skills live elsewhere (for example `~/.pi/agent/skills/`). After cloning, verify each skill is discoverable by listing the skills directory.

