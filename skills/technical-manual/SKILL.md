---
name: technical-manual
description: Use when turning Markdown notes, specs, design docs, READMEs, or agent-written reports into a polished, print-ready technical manual PDF with styled parts/chapters, figure primitives, tables, Mermaid, clickable contents, PDF bookmarks, page-numbered cross-references, and layout QA.
argument-hint: "[setup|analyze|build|check] <source.md> [options]"
allowed-tools: Bash(bash ${AGENTS_SKILLS_DIR}/scripts/*), Bash(python3 ${AGENTS_SKILLS_DIR}/scripts/*), Read, Write, Glob, Grep
license: Apache-2.0
metadata:
  author: Sagar Sarkale
  version: "1.0"
---

# Technical manual

Markdown in, engineering-manual PDF out. Two layers do the work:

1. **The build (deterministic).** `scripts/build.py` reads the Markdown structure, renders 17 figure primitives plus tables, code, Mermaid and callouts through one theme, paginates with Paged.js in headless Chromium, lints the layout, prints the PDF, then writes in navigation: clickable contents and cross-references, a bookmark tree, and metadata. The same input always gives the same look.
2. **The editorial pass (you).** Restructure the notes into parts and chapters, write claim-first deks, replace prose with figures where a picture is clearer, add captions. This is what makes it read like the reference manuals. It is described in `references/editorial.md`.

A raw file builds fine on its own (try it first to get a baseline); the editorial pass is what turns "styled notes" into "a manual".

## Setup

Needs Python 3 with `markdown-it-py`, `pyyaml`, `pygments`, `pillow`, `pypdf`, `playwright` (with Chromium), and `pdftoppm` (poppler-utils); `linkify-it-py` is optional (turns bare URLs into links). Run `bash ${AGENTS_SKILLS_DIR}/scripts/setup.sh` once to check and install what's missing. Fonts (Manrope, Source Sans 3, Source Serif 4, JetBrains Mono), Paged.js and Mermaid are bundled in `assets/vendor/`, so no network is needed at build time.

## Workflow

Work in a scratch directory; write the final PDF to wherever the user can get it.

**1. Map the source.**
```bash
python3 ${AGENTS_SKILLS_DIR}/scripts/analyze.py source.md
```
Gives the heading outline with word counts, how the build will interpret it (title / parts / chapters), structural advice, and a line-numbered list of component opportunities (lists of numbers → `bars`, hex → `bytes`, numbered procedures → `steps`, sizes → `stack`/`strip`, trees, timelines, callouts, captions).

**2. Baseline build** (optional but cheap; shows what the build does with no editing):
```bash
python3 ${AGENTS_SKILLS_DIR}/scripts/build.py source.md -o baseline.pdf
```

**3. Editorial pass.** Read `references/editorial.md` (rules and conventions) and `references/components.md` (syntax for every component, with a decision table). Write `source.manual.md`: frontmatter, parts with deks, chapters with deks, figures with captions, sources. Restructure and visualise; never invent facts or numbers. For very large sources, write it part by part.

**4. Build.**
```bash
python3 ${AGENTS_SKILLS_DIR}/scripts/build.py source.manual.md -o manual.pdf
```
Prints the page count, link and bookmark counts, and every layout issue, and writes `manual.report.json`.

**5. Verify, then iterate until you're proud of it.** Fix every reported issue (table below), then look at the pages, because a clean report does not mean a good layout. Keep the HTML so the design scan can run:
```bash
python3 ${AGENTS_SKILLS_DIR}/scripts/build.py source.manual.md -o manual.pdf --html manual.html
python3 ${AGENTS_SKILLS_DIR}/scripts/check.py manual.pdf --html manual.html --pages 1 2
```
`check.py` writes contact sheets and close-ups, and runs Impeccable's anti-pattern detector (`npx impeccable detect`; needs Node, skipped otherwise) over the HTML and theme. A finding there means the output has drifted toward generic machine styling (side-tab borders, nested cards, low contrast, cramped padding); fix the cause in the theme or component, never by suppressing the rule. View `qa-manual/sheet-*.png` (the whole book at a glance) and each `page-N.png` close-up with the image viewer. Check:
- Cover: hero fills the space and nothing clips; title and description read well.
- Contents: every row has a page number.
- Rhythm: no page is mostly empty except at a chapter end; figures are spread out rather than stacked in a wall.
- Each figure: arrows and connectors stay inside the panel, labels aren't truncated with "…" unintentionally, exactly one thing is highlighted, and the caption's bold sentence states a conclusion.
- Diagrams: zones line up, the key sits beside the plate without overlap, arrows don't cross boxes needlessly.
- Text: deks are claims, titles are short noun phrases, code doesn't wrap mid-token awkwardly.
- Navigation: the build line reports a sensible number of links and bookmarks; no `broken-ref` or `unlinked` issues. Cross-references read naturally ("…described in Pack anatomy (p. 16)").

Rebuild after each round of fixes. Two or three rounds is normal. Stop when the report is clean and the sheets look like the reference manuals.

**6. Deliver** the PDF (and the `.manual.md` source, so the user can edit and rebuild).

## Layout issues and fixes

| Issue | Meaning | Usual fix |
|---|---|---|
| `figure-gap` | page ends early because the next figure didn't fit | move a short paragraph or small figure ahead of the big one; shorten the figure (fewer rows, `scale: equal`); split it in two |
| `sparse-page` / `near-empty-page` | a page mid-chapter is mostly blank | same as above; or merge a short chapter into its neighbour |
| `orphan-heading` | a heading is the last thing on a page | add a sentence under it, or reorder so the following figure comes later |
| `escapes-figure`, `overflow-x` | something sticks out of its panel or the page | shorten labels/values (hashes → `ce0136…`), fewer nodes per `flow` row, shorter `bars` notes |
| `clipped-text` | a label is truncated in a segment or node | shorter label, or a sublabel on a second line (`Title / sub`) |
| `overflow-y` | a figure is taller than a page | split it, or use `scale: equal` on stacks |
| `mermaid-error` | Mermaid syntax error | fix the diagram source; test smaller pieces |
| `component-error` | a component block failed to parse; rendered as code instead | check the syntax in components.md |
| `diagram-overflow` | a `diagram`'s columns are wider than its box | fewer `cols`, shorter box titles or edge labels, or `key: below` |
| `key-overlap` | the plate runs into its key | as above, or `key: below` |
| `label-collision` / `node-overlap` | an edge label sits on a box / two boxes share cells | move a box to another column or row (`@`, `^`), shorten the label, add a spacer `~` |
| `broken-ref` | a `[[…]]` reference matched nothing (or several things) | use the exact chapter/section/figure title, `Fig: n.n`, or `n.n` |
| `missing-glyph` | a character no bundled font can draw | replace it (e.g. `⇄` → `↔`, `①` → `(1)`); arrows, math, box drawing and shapes are covered |
| `unlinked`, `navigation-error` | a link target isn't on any page / the PDF post-process failed | the PDF is still written; check the target exists, rerun |
| `toc-unresolved`, `font-missing` | build environment problem | rerun; check `assets/vendor` is intact |

## How the input is interpreted

- Frontmatter: `title`, `name`, `subtitle`, `edition`, `description`, `cover: light|dark` (light by default), `openers: dark` (dark part-opener pages), `grid: dots|lines|none` (drafting grid under drawings; dots by default), `tabs: false` (thumb-index tabs, on when there are 2–8 parts), `index: true|false` (back-of-book index; automatic from 15 entries), `owner` (your name, signed in the colophon), `colophon` (an extra colophon line, or `false`), `quirks: false` (drop the signature layer), `accent` (cover colour), `legend`, `toc`, `figures`, `outline_figures`.
- No frontmatter title → the first `#` is the title. Remaining `#` headings are **parts** (dark opener page, own accent colour); `##` are **chapters** (new page, numbered `part.chapter`); `###`/`####` are sections.
- Chapters before the first part, and long intro text before the first heading, become unnumbered front pages (use this for "How to read this manual").
- An all-italic paragraph right after a heading is its **dek**. A short single-paragraph preamble becomes the cover description.
- Fenced blocks named after a component become figures; ```` ```mermaid ```` becomes a themed figure; other code becomes a code panel; `Caption:` paragraphs attach to the block above; `> [!CAUTION]`-style alerts become callouts; `Sources:` paragraphs become the sources block.
- `[[Title]]`, `[[Fig: Title]]`, `[[2.3]]`, `[[Part 2]]` become clickable cross-references with "(p. N)"; so do ordinary GitHub-style heading links (`[x](#some-heading)`, `#android-1` for a repeated heading) and raw `<a name="…">` anchors, so links in Markdown you didn't write keep working. External links are underlined. A list of figures is added once there are 12+ titled figures.
- `{{term}}` (or `{{shown text|index entry}}`) marks a term for the index, as does every `**Term.**` definition paragraph. The index is generated with clickable page numbers.
- Drawings (diagram, flow, sequence, lanes, stack, strip, bytes, steps, timeline, mermaid) sit on a fine drafting grid; prose never does. Parts get thumb-index tabs on the outer page edge.
- Unlabelled code blocks containing a `├──` tree are upgraded to the `tree` component automatically.

## Consistency contract

The look is a deliberate design system plus a signature layer of house quirks (`assets/signature.css`: interpunct numbering, old-style figures, small-caps openings, end marks, pointing references, a signed colophon), written down in `references/design.md`: a left rail that holds every number and label, a reading column of about 75 characters, figures introduced by a rule instead of boxed, monospace only for code and data, a white ground, and no text under 4.5:1 contrast. **Read design.md before touching the theme or adding a component.** It also lists the patterns this skill refuses (side-tab borders, cards and nested cards, eyebrow labels, hero-metric blocks, icon glyphs, decorative stripes), following the Impeccable craft floor.

All styling lives in `assets/theme.css`: colour tokens, nine part accents (`.c1`…`.c9`), type scale, page geometry, and every component's look. Components emit only structure and classes (`hl`, `dim`, `gap`…), never colours or fonts, so every manual looks like it came from the same press, and restyling means editing one file. When extending:
- Add a component as a function in `scripts/components.py` (register it in `RENDERERS` and `DEFAULT_TAGS`), style it in `theme.css` with tokens only, document it in `references/components.md`, and add an example to `examples/`.
- Paged.js rewrites CSS rules that use sibling selectors (`a + b`) and drops the rest of the selector list: keep one sibling selector per rule.
- The bundled fonts cover Latin, Latin-extended, Greek, arrows, math operators, box drawing, geometric shapes and dingbats (via the "TM Symbols" fallback). Anything else (CJK, emoji, `⇄`, `①`) is reported as `missing-glyph`.
- Navigation is written from `[data-href]` attributes: give any new clickable element `data-href="#target-id"` and it becomes a PDF link.

## Files

```
scripts/build.py       Markdown → HTML → paginated PDF + lint report + links/bookmarks
scripts/components.py  basic components (flow, bars, strip, bytes, stack, cols, steps, stats, kv, tree, timeline, compare)
scripts/diagrams.py    advanced primitives (diagram, sequence, lanes, chart, hexdump)
scripts/analyze.py     outline + component opportunities for a source file
scripts/check.py       contact sheets, close-ups, and the Impeccable design scan
scripts/setup.sh       dependency check / install
assets/theme.css       the design system (tokens, layout, components)
assets/vendor/         fonts (+ a symbol fallback and coverage.json), Paged.js, Mermaid (bundled, offline)
references/editorial.md   how to restructure notes into a manual (read before step 3)
references/design.md      the design system and the anti-patterns it avoids (read before changing the theme)
references/components.md  syntax for every component and block (read before step 3)
examples/gallery.md / usd-web-viewer.md / git-internals.md / git-internals.raw.md  sources (input) — build the .pdf outputs yourself with build.py; the rendered PDFs are build artifacts and are not shipped with the skill
```
