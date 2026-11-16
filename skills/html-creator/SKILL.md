---
name: html-creator
description: Create standalone, responsive technical HTML documents with embedded architecture diagrams, local navigation, tables, code, test cases, and print support. Use for findings, plans, architecture briefs, and technical manuals. Do not use for marketing sites.
metadata:
  author: make-skill-templates
  version: "1.0"
license: Apache-2.0
compatibility: Compatible with Claude Code, Pi, and Codex. Requires Python 3 and uv to run the build and check scripts. Output is a single HTML file that opens from disk.
allowed-tools: Read Bash(uv:*) Bash(python3:*)
---

# HTML Creator

Create a technical document that works as one local HTML file. The reader must not need an earlier document to understand its scope, terms, contracts, tests, or result states.

## Workflow

1. Read [references/human-taste.md](references/human-taste.md).
2. Read [references/standalone-contract.md](references/standalone-contract.md).
3. Copy the two files in `examples/source/` and edit their content. For a full-capability reference — two embedded diagrams, glossary, badges, callouts, contracts, states, tests, and a worked example — read [examples/showcase/content.html](examples/showcase/content.html) and [examples/showcase/architecture-plan.html](examples/showcase/architecture-plan.html).
4. Build a single-file document:

   ```bash
   uv run --no-project python scripts/create_document.py \
     --meta examples/source/document.json \
     --content examples/source/content.html \
     --out /tmp/standalone-architecture.html \
     --inline-svg
   ```

5. Validate the document:

   ```bash
   uv run --no-project python scripts/check_document.py \
     /tmp/standalone-architecture.html
   ```

6. Review the output at 1440, 1024, 768, and 390 px widths.

## Required rules

- Use one opaque navigation bar.
- Keep one content edge across all sections.
- Use no collapsible sections.
- Put the document index near the beginning.
- Define terms before the algorithm uses them.
- Embed each diagram next to the architecture it explains. Several diagrams may be inlined into one document; the builder makes their IDs unique.
- Give every diagram an editable-source link when one exists.
- Keep complete object definitions and complete YAML examples.
- Put test method, good output, bad output, minimum scope, and cases near each stage.
- Use a light document ground. Reserve dark color for code and one final completion section.
- Use short section titles and STE-flavored descriptions.
- Make tables scroll on narrow screens. Do not shrink text until it becomes unreadable.
- Use the teaching components in `document.css` where they fit: `.glossary` for term grids, `.badge` for result states, `.callout` for notes and warnings.
- Keep all CSS and JavaScript inside the output file. Inline SVG diagrams when `--inline-svg` is used.

## Install

The skill works from any location; agents discover it from their skills directory. Personal skills: clone or symlink this folder into `~/.agents/skills/` (Pi, Codex) and `~/.claude/skills/` (Claude Code). Project skills: `.agents/skills/` or `.claude/skills/` at the repo root. Keep the folder name `html-creator` — the `name` field must match the directory name.

## Skills used

- `design-taste-frontend` for layout, responsive behavior, contrast, and visual QA.
- `asd-ste100` for unambiguous technical prose.
- `drawio-skill` for editable architecture diagrams.
- `doc` for standalone findings, plans, and review conventions.

