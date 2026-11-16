# Onion explainer contract

The document is a single `.html` file that peels one technical subject in layers, outside in. This file defines the anatomy. The skeleton at [../templates/onion-skeleton.html](../templates/onion-skeleton.html) implements the chrome; the reference page at [../examples/retrieval-metrics.html](../examples/retrieval-metrics.html) shows a complete instance.

## Chrome (do not redesign; configure instead)

These parts are fixed. Change only their configuration.

1. **Progress bar.** `#progress` — a thin bar across the top, `scaleX` driven by scroll position.
2. **Sticky strip.** `.strip` — always visible under the top edge. `#mini` holds one cell per slot of the shared state (grade fills, `.cut` gaps at the k boundaries the page uses). The cells are not passive: they are a second editor for the state, wired through the same delegated `[data-i]` handler as the main board, and focus is restored on the clicked cell after every re-render (innerHTML rewrites destroy focus otherwise). `#kpis` holds headline numbers (`<div class="kpi"><b>0.84</b><span>nDCG@10</span></div>`), computed live from state. Per-query binary metrics show as 0/1, not a smoothed mean — state what the number is.
3. **Hero onion.** `#onion` — concentric rings, one per layer, outside ring = layer 1. Rings and labels scroll to their layer. Configure with the `SECTIONS` array in the script.
4. **Contents.** `.toc` directly under the hero. One entry per layer plus sub-parts. Every link carries `data-go` and targets an element ID. The rail, the onion, and smooth scrolling all derive from these entries.
5. **Section rail.** Built at runtime from the contents entries: one tick each, h2 vs h3 levels by nesting, equal length when idle, accent blue on the current entry, Gaussian peak only while hovering, preview card. Preview text comes from `.question`, falling back to the `Question` entry of a `dl.reader` block (`dl.reader dd:nth-of-type(2)`), then the next `<p>`. Clicking opens a collapsed card (`details.open = true`) before scrolling.
6. **Inline glossary.** `glossify()` wraps defined words in `<button class="term">` with a hover/tap tooltip (`#tip`). Configure with `GLOSS` (regex, term, definition — regexes cover plurals and variants, e.g. `quer(?:y|ies)`) and `SYMS` (single-letter symbols found in `<i>`). First use per block only; the `SKIP` selector must exclude formulas, worked values, widget labels, and axis labels (`.tex, .piece .val, .where, .controls, .chips, #funnel, #readOut, .bars, .work, .sub, .legend, .depth, svg, button, label, input, .math, .tbl, .board, .term, #tip, .kpis`) or definitions get injected into numbers and formulas.
7. **Theme.** Light ground, dark mode via `prefers-color-scheme` and an optional `data-theme` override. Respect `prefers-reduced-motion` for every scroll animation.

## Chrome CSS inventory

The skeleton CSS is forked from the reference page. When trimming, keep at least: `.strip/.mini/.kpis/.cut`, `.onion`, `.toc`, `.rail/.railcard/.rk`, `.depth/.question/.panel/.insight/.note/.math/.frac/.op`, `dl.reader`, `details.anatbox/.anat/.piece/.tx/.no/.val/.together/.cnt`, `.work`, `.say`, `.board/.bg0-3/.top5/.top10/.rowlab`, `.chips/.chip`, `.form/.out`, `.gauge/.big`, `.meter`, `.pipe/.stg/.sn/.d/.c40/.c10/.t10/.first/.flow/.ar/.loss/.keep/.chipd.miss/.met-b/.mv/.mq/.fix`, `.where`, `.card/.two`, `.badge`-free result styles, `#tip`, `#progress`.

## State and rendering

- One shared state object; one delegated `document` click handler routes by attribute (`[data-i]`, `[data-preset]`, `[data-add]`, `[data-rm]`, `[data-gain]`).
- `render()` fans out to **board-driven** views only (board, mini-map, KPIs, per-metric charts, funnel). Self-contained widgets (slider worlds, reader tools) own their state, listeners, and renderers outside `render()`.
- Load order is prescribed: chrome first, static layers once, then `load(defaultPreset)` (which triggers the first full `render()`), then self-contained widgets, and `glossify()` **last**, after every `innerHTML` write, because it walks the finished DOM.

## Layers (author these)

Each layer is `<section class="layer" id="sN">` with, in order:

- `.depth` — "Layer N · {one-line scope}";
- an `h2` title that states what the layer establishes (not a topic name);
- `.question` — the italic question this layer answers. The rail preview uses this text;
- content: prose, panels (`.panel`), tables (`.tbl`), and interactive widgets bound to the shared state;
- at least one `.insight` box for the takeaway.

Required layer sequence for a subject with measurable quantities:

1. **Terms and failure modes.** Terms table first. Then the small set of ways the subject can fail (two, for retrieval). State the core idea.
2. **Simplest case.** One control, one visible effect. A slider world with a single moving quantity. Give the reader a translation rule (for example: nDCG@10 = 0.50 means one relevant document at rank 3).
3. **Full case.** The real state space. Then one `.metric` block per quantity, each with an `id` like `m-recall` so contents and rail can point at it, and each containing, in order: a `dl.reader` (Simulated user / Question / Range / Ignores), the `.math` formula, a collapsible `.anatbox` with piece-by-piece cards, and a **live chart bound to the shared state** re-rendered from `render()`. Close the layer with the pipeline funnel (`.pipe`) that maps each headline number to the stage that owns it.
4. **Ranges.** A table of lowest and highest value for every quantity, and when the highest is unreachable.
5. **Good values.** No universal good value: floor, ceiling, dataset difficulty. Reference values from public benchmarks, named. A step-by-step procedure to judge a number. Optionally a "gap closed" chart.
6. **Read a result.** A form tool that takes the reader's numbers and explains each in plain words, with a diagnosis.

## Rules

- Every formula: `.math` HTML/CSS only (`.frac` inline-flex columns, `.op` for stacked limits, real `<sub>/<sup>`), centered, wraps at 390 px, followed by a closed-by-default `details.anatbox` (summary carries the piece count in `.cnt`): inside `.inner > .anat`, one `.piece` per symbol or operation (mini-formula `.tx.tex`, `.no` piece label, `h5` name, plain-English meaning, `.val` worked number), ending with a `.together` box. Worked numbers reuse one fixed running example across every card set.
- All prose STE-flavored; defined terms dotted-underlined on first use per block.
- No external runtime dependencies. Fonts link allowed; everything else inline.
- Layer count: 3 minimum, 6–8 typical. More than 8 means the subject needs two pages.
- The final reader tool reads values aloud in plain sentences, normalizes 0–100 input to 0–1, flags impossible values, and ends with 3–5 hardcoded diagnosis rules plus a floor comparison.
