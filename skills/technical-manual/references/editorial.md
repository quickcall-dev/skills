# Editorial pass: from notes to manual

The build makes any Markdown look consistent. What makes it *read* like the reference manuals (GGUF, Parquet, Pi Durable, usd-web-viewer) is this pass: restructuring, claim-first deks, and figures that replace paragraphs. Do it in a new file (`<name>.manual.md`); never overwrite the source.

## The one rule: restructure, never invent

Move, regroup, retitle, condense and visualise freely. Do not add facts, numbers, versions or dates that are not in the source. When a figure needs a number the source doesn't have, leave the figure out or describe it qualitatively. When the source states numbers that should add up (sizes of sections, percentages, counts by category), check the arithmetic; if it doesn't add up, say so in a caption or a note rather than silently fixing it. Every claim that survives should be traceable to the source, and the source list belongs in a `Sources:` paragraph.

## Structure

**Frontmatter.** `title` (what it is), `name` (≤ 2 words, used as the cover wordmark and in the running header), `subtitle` (default "Technical Manual"), `edition` (e.g. `Engineering edition · 2026.10`), `description` (one or two sentences: what the reader will understand after reading). Optional: `cover: dark` (the default is a white cover; choose dark for a reason), `openers: dark` (dark part-opener pages), `accent` (cover hex colour), `toc: false`, `legend: Page {c2} | Worker {c5} | …` (cover legend; use it when diagram colours mean layers, as in the usd-web-viewer example), `figures: true|false` (list of figures), `outline_figures: false`.

**Parts (`#`).** 2–6 parts, each a stage of understanding: orientation → mechanism → details → operation → reference. Each part gets a one-line italic dek right under it. A document under ~2,500 words usually needs no parts; just chapters.

**Chapters (`##`).** Each starts a new page, so each should earn one: aim for 250–900 words plus one to three figures (1–3 pages). Merge chapters under ~150 words into a neighbour; split chapters over ~1,400 words along a natural seam. Number prefixes in headings are stripped; numbering is automatic (`2.3`).

**Titles.** Short noun phrases that name the thing or the question: "The fixed header", "Why a worker at all", "Offsets, gaps and file_offset", "What readers check". Avoid "Overview", "Introduction", "Details", "Misc". Avoid colons and title case.

**Deks.** An italic paragraph directly under each `##` (and `#`). One or two sentences that state the chapter's *claim*, not its topic. The reader should be able to read only the deks and learn the document.
- Topic (weak): *This chapter describes the GGUF header.*
- Claim (strong): *Every number in this book was read from a file, a source line or a measured run, so each one can be checked.*
- Claim (strong): *Each predecessor fixed the last one's worst problem. GGUF fixed the one they all shared.*

**Sections (`###`)** inside chapters for 2–5 subtopics. `####` renders as a small mono label; use it sparingly.

## Figures

Aim for at least one figure per chapter, and prefer a figure wherever the source has: a list of numbers, a sequence of steps, a layout of bytes or sections, a hierarchy, a before/after, a set of components with responsibilities, or dated events. `scripts/analyze.py` lists these opportunities with line numbers. See `components.md` for syntax and the decision table.

- **One idea per figure.** If you need two highlights, you may need two figures.
- **Highlight one thing** with `{hl}`: the part the caption talks about.
- **`sub:` carries provenance and scale**: what was measured, where, and "not to scale" when it isn't.
- **Captions make the point.** `Caption: **The count is in the header; the offsets are not.** A pack can be streamed and verified front to back, but finding object n needs the separate .idx file.` The bold sentence is a conclusion; the rest is how to read the figure or where the data came from.
- **Keep the table too** when readers need exact values; add a figure for the headline comparison.
- **Draw the system once, big.** If the document describes an architecture, make a `diagram` plate of it (zones = boundaries, `#` markers + key = the walkthrough) and consider putting it on the cover with `cover`. Reuse its zone colours in later figures.
- **Ground it in a specimen.** The reference manuals pick one real file, run or repo and follow it through every chapter ("The example: laptop_17z90ur.usd … Every number on these two pages was read from it"). If the source has a running example, make it the spine.

## Prose

- Lead with the fact, then the reason: "The page never parses USD. A worker owns the network…"
- Put identifiers, paths, flags and values in `` `code` ``; they render in the part's accent colour.
- Use `**Term.** explanation` lead-in paragraphs for definitions instead of a heading per term.
- Callout titles are short sentences ("Gaps are not always metadata"); they become a bold run-in, while the kind ("Footgun") sits in the rail. Don't repeat the kind as the title.
- Callouts are for what the reader must not miss: `[!CAUTION]` for footguns (things that break), `[!WARNING]` for sharp edges, `[!NOTE]` for clarifications, `[!IMPORTANT]` for rules/invariants, `[!RULES]` for "what this rules out". At most one or two per chapter.
- A plain `>` quote is a pull quote: use it for one memorable line, not for notes.
- End claim-heavy chapters with `Sources:`, and make sources links where the source is public.
- **Index the terms a reader will hunt for.** Mark a term with `{{term}}` where it is *defined or explained* (not every mention), or start a definition paragraph with `**Term.**`. Aim for 15–60 entries in a long manual; the index appears automatically past 15.
- **Delete what the manual generates.** Hand-written contents lists, "back to top" links, status badges and web-only navigation; `analyze.py` flags them.
- **Cross-reference instead of repeating.** When a chapter depends on another, link it: `the header format ([[Pack anatomy]])` or `as [[Fig: Finding one object]] shows`. Page numbers are added automatically. Aim for a few per chapter, wherever a reader would otherwise flip pages; the reference manuals use them densely.

## Workflow for a large file

1. `python3 scripts/analyze.py source.md` to get the outline, sizes and opportunities.
2. Sketch the part plan (titles + deks) before writing anything else; check it covers every source section.
3. Write the manual file part by part. For each chapter: title, dek, prose condensed from the source, figures for the flagged opportunities, captions, sources.
4. Build, read the lint report, view the contact sheet, fix, repeat (see SKILL.md).
5. Final fidelity check: skim the source section by section and confirm nothing important was dropped and no number changed.
