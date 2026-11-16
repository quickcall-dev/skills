# Agent guide for standalone technical HTML

Use this folder to create findings, plans, architecture briefs, and manuals that open as local HTML files.

## Human taste to preserve

The reviewer prefers a deep technical document, not a slide deck. Use a quiet editorial layout. Show architecture with real diagrams. Keep all important objects and tests visible.

The reviewer rejects these patterns:

- many collapsible sections;
- a weak or oversized navigation bar;
- dark cards with low-contrast text;
- empty space that makes the document look shallow;
- diagrams that exist on disk but are absent from the HTML;
- incomplete YAML objects;
- generic headings that do not state the section purpose;
- an HTML file that depends on an earlier plan to make sense.

## Skills

Use these installed skills when available:

- `doc` for experiment document creation and updates;
- `asd-ste100` for controlled technical English;
- `drawio-skill` for editable diagrams and validation;
- `design-taste-frontend` for responsive layout and browser QA.

Read `SKILL.md` before work. Read `references/human-taste.md` before visual changes.

## Build and check

```bash
uv run --no-project python scripts/create_document.py \
  --meta examples/source/document.json \
  --content examples/source/content.html \
  --out /tmp/standalone-architecture.html \
  --inline-svg

uv run --no-project python scripts/check_document.py \
  /tmp/standalone-architecture.html
```

Open the generated file through a local HTTP server for visual QA. Verify widths of 1440, 1024, 768, and 390 px.

## Standalone definition

The output is standalone in two ways:

1. Content standalone: the file states its authority, scope, vocabulary, inputs, outputs, failures, tests, and completion gate.
2. File standalone: the output contains its CSS, JavaScript, and SVG diagrams. It has no CDN dependency.

Editable `.drawio` links can remain external because they are authoring sources, not runtime dependencies.

## Completion gate

Do not call the document complete until:

- all local anchors resolve;
- all diagrams render;
- no browser console errors exist;
- no horizontal page overflow exists at 390 px;
- the body text remains at least 15 px;
- tables scroll inside their containers;
- every visible section has a useful heading;
- the result is readable with JavaScript disabled.

