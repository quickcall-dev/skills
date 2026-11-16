# Standalone document contract

## Content authority

The document must state:

- what it specifies;
- what it does not specify;
- which older documents it replaces;
- which external contracts remain authoritative;
- what the input and output boundaries are.

## Required sections

Use the sections that apply:

- authority and scope;
- document index;
- glossary;
- system overview;
- architecture stages;
- schemas or object definitions;
- failure and result states;
- test cases;
- worked example;
- implementation or completion gate.

## File behavior

The generated file must:

- contain inline CSS;
- contain inline JavaScript;
- work when opened from disk;
- work through a local HTTP server;
- remain useful when JavaScript is disabled;
- contain no external font, image, CSS, or script dependency;
- provide text alternatives for diagrams;
- support printing without the sticky navigation bar.

## Responsive behavior

Desktop uses four-column summaries when the content fits. Tablet uses two columns. Mobile uses one column.

Tables keep their natural width inside a horizontal scroll container. The full page must never scroll horizontally.

Architecture diagrams can keep a minimum internal width. Their own frame can scroll horizontally on mobile.

