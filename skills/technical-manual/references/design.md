# Design system

Read this before changing `assets/theme.css` or adding a component. It records why the manual looks the way it does, so edits don't drift back into generic, machine-made styling.

## The one structural idea: the rail

Every page has a left **rail** (1.3in) and a **reading column** beside it (about 75 characters of 10.5pt Source Sans 3).

- **In the rail:** chapter numbers, part numerals, figure labels ("Figure 3.4"), callout kinds ("Footgun", "Note"), the "Sources" label, contents numbers. Numbers and labels hang; they never sit above a heading as an eyebrow.
- **In the column:** prose, lists, section headings, deks, captions, callout text.
- **Full width:** figures, tables and code, which need the room.

This one system is the manual's signature. Use it wherever a label would otherwise need a box, a badge or a tinted band. Tokens: `--rail`, `--gutter`, `--col` (rail + gutter, the column's left edge).

## Type roles

| Role | Face | Size |
|---|---|---|
| Display: title, part, chapter, section | Manrope 700 | 46 / 40 / 25 / 13.5pt |
| Body | Source Sans 3 400 (variable, with old-style figures and small caps) | 10.5pt / 1.55 |
| Dek, sub-captions, key descriptions, pull quotes | Source Serif 4 italic | 12.5pt (dek) |
| Labels: figure labels, table headers, callout kinds, zone names | Source Sans 3 600–700, sentence case | 8–10pt |
| Code, identifiers, offsets, sizes, hex, chart ticks | JetBrains Mono | 7.6–8.4pt |

Every adjacent heading step is at least 1.25×. Prose sets `hyphens: auto` with `text-wrap: pretty`; hyphenation takes effect where Chromium has its dictionaries (some headless builds don't, in which case the rag is evened by `pretty` alone). Numbers in tables, contents, offsets and charts use tabular figures.

## Colour

- White ground (`--paper: #fff`). The manual is read on screen or printed on white paper; a tinted "paper" ground is a costume.
- Ink `#1b1a17`. Secondary text uses `--ink-2` (9:1) or `--muted` (5.9:1). **No text below 4.5:1.** `--faint` is for guides, dashes and gridlines only.
- Nine part accents (`.c1`–`.c9`), each with `--accent`, `--tint` and `--accent-ink`. An accent marks structure (numbers, labels, the one highlighted element) and never decorates.
- A dark cover (`cover: dark`) and dark part openers (`openers: dark`) are options, not defaults. Choose them for a reason, not by category.

## Rules this theme follows

Audited against the craft floor of [Impeccable](https://github.com/pbakaus/impeccable). The skill's `check.py --html` runs its detector (`npx impeccable detect`) on every build.

1. **No side-tab borders.** No coloured `border-left`/`border-right` over 1px on figures, callouts or list items. Callouts are a hairline in the callout's colour above a rail-label/column pair.
2. **No cards.** Figures are introduced by a 1px ink rule and a rail label, then drawn directly on the page. Nothing inside a figure gets a bordered white box, which would be a card inside a card. Components separate content with rules and space: cols, steps, compare, kv, stats and hexdump all use hairlines, not containers.
3. **Boxes are notation, not decoration.** The only bordered boxes are diagram nodes, byte cells, strip segments and stack layers, where the box *is* the meaning (a component, a byte, a region).
4. **No eyebrows or kickers.** No "PART 1" above a part title, no letterspaced label above a heading. The number goes in the rail.
5. **Monospace only for code, data and measurement.** Never for labels, table headers or footers, and never letterspaced uppercase.
6. **No hero-metric template.** `stats` is a row of facts in ink: number, label, note. Only `{hl}` turns one number to the accent.
7. **No glyphs standing in for icons.** No ↗ on links, no ▪ bullets, no › chevrons, no badge chips. List markers are en dashes; external links are underlined.
8. **No decorative patterns.** No repeating-gradient stripes. Gaps in a strip are dotted outlines; lane gridlines are real ticks at axis values.
9. **No repeated labels.** No running footer that restates the header, no generic figure tags ("MEASURED", "FLOW"). Tags appear only when the author writes `tag:`.
10. **A grid only under drawings.** The drafting grid (`grid: dots`, `lines` or `none`) sits under diagrams, flows, sequences, timelines and byte layouts, where it says "this is an engineering drawing" and frames the figure without a box. It never goes behind running text, captions or tables: a full-page dot grid is a generated-landing-page signature and fights the reading column. Dots are vector SVG tiles (9pt pitch, `#c9c4b9`), so they stay crisp in print.
11. **Wayfinding is functional.** Thumb-index tabs (one per part, stepped down the outer edge) and the index exist so a reader can find their place when flipping a printout or scrolling thumbnails. They are the only solid-colour blocks in the book, which is why they work.
12. **Space before structure.** More space above a heading than below it; tight groups, generous separation; a 4pt-based scale.

## Adding or changing a component

- Emit structure and classes only. Colours come from tokens via `.hl`, `.dim` and `.cN`.
- Ask what the element *is*. If it is a thing in a diagram, a 1px box is fine. If it is a group of text, use a rule and space.
- If it needs a label, put the label in the rail or make it a bold run-in, not a tracked-caps eyebrow.
- Build `examples/gallery.md` and run `check.py --html`. The design scan must come back clean (advisories explained), and the contact sheet must still read as one book.

## The signature layer (house quirks)

`assets/signature.css` sits on top of the theme. The theme is the grammar; the signature is the accent: a few small, repeated habits that make every manual recognisably from the same hand. The voice is *an engineer who reads like an editor*. Turn the layer off with `quirks: false`.

| Quirk | What it does | Why |
|---|---|---|
| Interpunct numbering | `2·3`, `Figure 3·4` in the rail, contents and references | A Swiss-typography habit; reads as a number system, not a decimal |
| Old-style figures in prose | numbers in sentences sit like lowercase; data stays lining and tabular | prose reads evenly; tables still align |
| Small-caps opening line | the first line of every chapter in small caps | the classic book opening, marking where reading starts |
| End mark | a small square in the part colour closes each chapter | tells the reader the argument is finished |
| Folios | `13 / 20` | page of total, an engineer's sense of position |
| Pointing references | `Pack anatomy →16` instead of `(p. 16)` | terser, and it points |
| Named thumb tabs | the part name runs up the outer-edge tab | wayfinding that reads without the contents |
| Colophon | last page: fonts, method, word/figure/reference counts, source fingerprint, and `owner:` signed on a line | says how the book was made, and whose it is |

When adding a quirk: it must repeat (a one-off is a gimmick), stay quiet enough to read past, use only real typography (no glyph icons, no decoration), and live entirely in `signature.css` plus at most a class from `build.py`.

## Paged.js constraints

- A rule containing a sibling selector (`a + b`) drops every other selector in its list. Use one sibling selector per rule.
- Whitespace-only text nodes between inline elements are removed, so `<span>a</span> <span>b</span>` renders as "ab". Space adjacent spans with a margin.
- Margin boxes (running header, thumb tabs) take running elements via `position: running(name)` and `element(name)`; position their contents absolutely inside the margin box.

## Known detector limitations

`flat-type-hierarchy` can appear as an *advisory* on documents with many section headings, because the detector can't resolve `font:` shorthands that use `var()` and point sizes, and reads every role as 16px. The real ratios are in the table above. Verify by computed style rather than suppressing the check.
