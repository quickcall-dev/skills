---
name: onion-explainer
description: Create standalone, single-file interactive explainer pages that peel a technical subject in onion layers, outside in, with one shared interactive model, piece-by-piece formula cards, an inline glossary, and a section rail. Use for teaching metrics, algorithms, protocols, or any concept the reader must understand from first principles. Do not use for marketing pages or static reports.
metadata:
  author: make-skill-templates
  version: "1.0"
license: Apache-2.0
compatibility: Compatible with Claude Code, Pi, and Codex. Requires Python 3 for the checker script; the built page has no runtime dependencies beyond an optional Google Fonts link.
allowed-tools: Read Bash(python3:*) Bash(node:*)
---

# Onion Explainer

Create one local HTML file that takes the reader from the simplest case to the deepest concept, one layer at a time. The reader must never need outside material: every term, symbol, formula piece, and value judgment is defined on the page.

## Workflow

1. Read [references/human-taste.md](references/human-taste.md). It records real reviewer feedback; treat every item as a requirement.
2. Read [references/onion-contract.md](references/onion-contract.md) for the document anatomy.
3. Copy [templates/onion-skeleton.html](templates/onion-skeleton.html) and replace every `{{PLACEHOLDER}}`. Keep the CHROME script sections unchanged; author only the CONFIG arrays, the layer sections, and the model + renderers.
4. Study [examples/retrieval-metrics.html](examples/retrieval-metrics.html) when a mechanism is unclear. It is a complete, reviewed instance.
5. Validate:

   ```bash
   python3 scripts/check_onion.py /tmp/your-explainer.html
   ```

6. Review the page in a browser at 1440, 1024, 768, and 390 px. Confirm the rail, glossary tooltips, formula cards, and strip all work.

## Required rules

- Peel outside in: simplest case first, deepest concept at the center.
- State one core idea the whole page hangs on, in the first layer.
- For every quantity: the question it answers, its lowest and highest value, and what a good value is, with named reference values.
- Put a terms table before any term is used. Dotted-underline defined words so the definition appears where the word is used.
- Build every formula in HTML/CSS at body-text size, centered, wrapping at 390 px. No MathJax, KaTeX, or LaTeX renderers.
- Give every formula a collapsible piece-by-piece card set with worked numbers from one running example.
- Drive every widget from one shared state and one `render()` function.
- Keep a thin progress bar, a sticky strip with the live model and headline numbers, a contents block, and a hover-peak section rail.
- Ship one standalone file: inline CSS and JavaScript, system-font fallbacks. The Google Fonts link is the only allowed external reference.
- Write STE-flavored prose. Do not use metaphors, idioms, or unexplained symbols.

## Subagent instructions

Use subagents to keep the main context clean; the full page is too large to iterate inline.

- **Always launch one subagent for visual QA** after the page passes `check_onion.py`:

  > Open `<absolute path>.html` in a browser at 1440, 1024, 768, and 390 px. Screenshot each width. Report: console errors, horizontal overflow, clipped or wrapped formulas, overlapping rail/tooltip, strip and KPIs updating on interaction, glossary cards appearing on hover and tap. Change nothing; report findings as a list.

  Fix confirmed issues in the main context, then re-run the QA subagent once.

- **Launch a subagent to author long layer content** (more than three layers or more than ~40 KB of HTML): give it the skeleton path, the contract, the running example, and the layer outline; have it return only the authored `<section>` blocks and CONFIG entries. Assemble and wire in the main context.

- Never let a subagent redesign the chrome. It configures and authors layers only.

## Install

The skill works from any location; agents discover it from their skills directory. Personal skills: clone or symlink this folder into `~/.agents/skills/` (Pi, Codex) and `~/.claude/skills/` (Claude Code). Project skills: `.agents/skills/` or `.claude/skills/` at the repo root. Keep the folder name `onion-explainer` — the `name` field must match the directory name.

## Skills used

- `asd-ste100` for short, unambiguous prose.
- `design-taste-frontend` for layout, responsive behavior, contrast, and visual QA.
- `doc` for findings and review conventions.

Install these if not available:

```bash
git clone https://github.com/danyuchn/asd-ste100-skill ~/.agents/skills/asd-ste100
git clone https://github.com/leonxlnx/taste-skill ~/.agents/skills/design-taste-frontend
git clone https://github.com/quickcall-dev/skills ~/.agents/skills/doc
```
