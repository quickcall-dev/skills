# Agent guide for onion explainer pages

Use this folder to build single-file interactive explainers that peel a technical subject in layers.

## Human taste to preserve

The reviewer wants first-principles understanding. Every number must answer a stated question, have a stated range, and be judgeable against a named floor and ceiling. Assume the reader knows none of the vocabulary. Formulas are built in HTML/CSS, sized like text, centered, and each has collapsible piece-by-piece cards with worked numbers from one running example. Defined words carry their definitions inline (dotted underline, hover or tap).

The reviewer rejects these patterns:

- MathJax, KaTeX, LaTeX-rendered, oversized, or clipped formulas;
- symbols or nouns used before definition, including single letters;
- a glossary that forces travel back to a table;
- two formulas in one block;
- widgets that do not recompute the rest of the page;
- metaphors and idioms in prose;
- pages anchored to one specific user scenario instead of the general case;
- any runtime dependency besides the Google Fonts link.

## Build and check

```bash
cp templates/onion-skeleton.html /tmp/explainer.html
# replace {{PLACEHOLDER}} values, author layers, wire the shared state

python3 scripts/check_onion.py /tmp/explainer.html
```

Open the file in a browser (no server needed) and review at 1440, 1024, 768, and 390 px.

## Subagent use

- Visual QA at four widths is always delegated to a subagent (see SKILL.md for the prompt).
- Long layer content is drafted by a subagent; chrome changes are not.

## Completion gate

Do not call the explainer complete until:

- `check_onion.py` passes;
- no browser console errors exist at any of the four widths;
- no horizontal overflow exists at 390 px and every formula wraps;
- glossary tooltips open on hover and tap, and close on Escape and scroll;
- the rail shows equal-length ticks when idle, a peak only on hover, and a blue active tick that follows scroll;
- the strip mini-map and KPIs recompute on every interaction;
- every formula card set is collapsible and starts closed;
- the page works with JavaScript disabled for reading the prose, terms, and ranges;
- the page works offline except for fonts.
