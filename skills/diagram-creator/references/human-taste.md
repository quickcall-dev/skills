# Human taste for architecture diagrams

## Purpose before polish

The diagram must explain architecture. It must make a system boundary, transformation, decision, or state change easier to understand than prose.

Do not create a diagram because a section looks empty. Do not diagram project-management mechanics unless the document is about project management.

## Preferred visual language

- Use a white canvas and a neutral ink color.
- Use thin borders and flat fills.
- Use rounded corners only to make nodes easy to scan. Do not use pill-shaped system nodes.
- Use one accent for each semantic stage. Reuse the accent across documents.
- Use muted text for descriptions. Use dark text for node titles.
- Use small arrowheads and orthogonal routes.
- Use generous space between nodes. Dense diagrams feel shallow because the reader cannot see the groups.

## Preferred structure

Use this order when the system supports it:

```text
Pinned input → prepare evidence → reason or solve → validate → verified output
                                                     └──────→ typed stop output
```

Put feedback loops below the main path. Use a dashed edge for the loop. State its bound when the loop is finite.

## Labels

- Node title: 2–6 words.
- Node description: 1–2 short lines.
- Edge label: 1–4 words.
- Diagram title: state the system and the view.
- Diagram subtitle: state the invariant or decision that the diagram explains.

Use the same term for the same object throughout the document. Do not rotate synonyms.

## What failed in earlier attempts

- Diagrams were generated for merges and review gates instead of product architecture.
- Diagrams existed on disk but were not embedded in the HTML.
- The surrounding page used large dark cards with weak text contrast.
- Some layouts used excessive empty space and read like presentation slides.
- Edge labels and arrows competed with node content.

The scaffold prevents these failures by using explicit positions, shared tokens, generated links, responsive containers, and a document validator.

