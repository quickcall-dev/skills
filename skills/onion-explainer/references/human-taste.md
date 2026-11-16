# Human taste for onion explainers

The reviewer is a practitioner who wants first-principles understanding, not a summary. They ask "what question does this number answer?" before they accept any formula. This file records the feedback that shaped the reference page; apply all of it to every new explainer.

## What the reviewer wants

- **Onion peeling, outside in.** Start from the simplest possible case and add one complication per layer. The deepest concept sits at the center of the onion, not at the top of the page.
- **One core idea stated early.** Everything on the page must hang off a single sentence the reviewer can repeat. For the reference page: each metric is a model of one simulated user; know where the user stops and what the user wants, and you know what the number means.
- **First-principles coverage of every quantity.** For each metric or number: the question it answers, the intuition behind the formula, its lowest and highest value, and what a good value is. A value has meaning only next to a floor (a baseline on the same data), a ceiling, and the difficulty of the dataset.
- **Visual communication over prose.** Prefer an interactive diagram, a worked table, or a card to a paragraph. The reviewer asks for visual explanations explicitly.

## Language

- Write in ASD-STE100 style: short sentences (descriptions 25 words or fewer, instructions 20 or fewer), one idea per sentence, active voice, imperative instructions, no contractions, no idioms, no metaphors.
- Use one word for one concept across the whole page. Keep technical names as they are (nDCG, qrels, BM25); STE permits technical names.

## Definitions: assume nothing

- Put a **terms table at the start**. Define every noun you will reuse and every symbol, including single letters like `R` and `k`, each with an example.
- If a word conflicts with a common meaning in this domain, say so **before** first use. The reviewer flagged "model" (a metric's model vs. an ML model) and "reader" (a simulated user, not a person). Prefer coined terms: "simulated user" over "reader", and raise the conflict explicitly.
- Do not make the reader travel back to the terms table. Defined words get a **dotted underline** and carry a small definition card with them: hover or tap shows the meaning where the word is used. Underline only the first use in each paragraph — underlining every use makes the text unreadable. Skip formulas (each formula defines its own symbols) and live tool output.

## Formulas

- Build every formula in **plain HTML/CSS** (serif font, fraction and summation markup sized like body text). Do not use MathJax, KaTeX, LaTeX rendering, or image formulas. The reviewer rejected MathJax twice: formulas rendered too large, and the standalone file broke offline.
- Center every formula. It must wrap, not clip, at 390 px — the reviewer reported cut-off formulas.
- Every formula gets a **collapsible piece-by-piece card set**: "Understand this formula, piece by piece", closed by default, one card per symbol or operation. Each card shows the piece, its name, what it means in plain English, and a worked number. End the set with a short box that shows how the pieces combine.
- Break formulas down to the reviewer's bar, not yours. When the reviewer said the DCG and nDCG cards were "not broken down enough", the fix was building DCG letter by letter (gain → cumulative → discount → why log₂ → discounted gain → sum → no fixed maximum) and splitting nDCG's loss into order loss vs. finding loss.
- **One running example** reused across all card sets, so every number connects to the previous one.
- When one block holds two formulas, split them into separate blocks (Recall@k and Precision@k were split on request).

## Interactivity

- One shared state — the central object (for the reference page: one ranked list of 40 results) — drives the sticky strip, every layer, and the final tool. Editing it recomputes everything.
- Provide named presets that make quantities disagree with each other, so the reader sees why more than one metric exists.
- Headline numbers must be honest about what they are: a per-query binary metric shows as 0/1 in the strip, not a smoothed mean.
- End with a small tool that reads a result aloud: type your numbers, get each one explained in plain words plus a diagnosis.

## Chrome the reviewer asked for

- A **thin progress bar** across the very top that grows with scroll.
- A **contents block under the hero**: one entry per layer plus sub-parts, two columns on desktop, one on phones, smooth-scroll and open collapsed cards on the way.
- A **section rail** on the left edge (wide screens only): one tick per contents entry, h2 ticks medium grey and h3 ticks light grey, all equal length when idle, the current section's tick in accent blue. On hover the ticks grow into a **peak** around the hovered tick (Gaussian falloff); the peak exists only while hovering. Hover or focus also shows a preview card with section number, title, and the question that part answers.
- Keep the wording generic. Do not anchor the page to one specific user scenario ("your result line"); say what a typical report contains instead.

## Standalone file

- Ship one `.html` file with all CSS and JavaScript inline. The only allowed external reference is the Google Fonts link, and the page must work without it (system font fallbacks).
- The reviewer exports the file repeatedly; keep it openable with no server, no build step, and no network.

## Reviewer rejects

- unexplained symbols or nouns ("what is R and k? not clear at all");
- a glossary that forces travel back to a table for every use;
- LaTeX/MathJax formulas, oversized math, or formulas that clip;
- two formulas crammed into one block;
- card sets that stop one level above real understanding;
- pages tied to one specific example instead of the general case;
- interactive widgets that do not recompute the rest of the page.
