---
name: markdown-to-pdf
description: Use when converting Markdown docs to PDF, especially when Mermaid diagrams render blank, oversized, lose color, or browser print adds page headers/footers
---

# Rendering Markdown PDF

## Overview

Markdown to PDF with Mermaid is a visual export task, not a plain file conversion. Render diagrams, style them consistently, disable print headers, then verify the PDF pages visually.

## When to Use

Use for:
- Markdown docs containing Mermaid diagrams
- PDF export where diagrams are blank, oversized, clipped, or colorless
- Chrome/Puppeteer exports with unwanted page headers/footers
- report/document exports where tables and diagrams must stay readable

Do not use for plain text Markdown without diagrams.

## Core Workflow

1. **Preflight**
   - Count Mermaid blocks in source.
   - Create a temp build dir.
   - Never edit source Markdown.

2. **Render Mermaid explicitly**
   - Use `mmdc` or browser-side Mermaid.
   - Apply a theme config with colors, font, and white background.
   - Set Mermaid `flowchart.htmlLabels=false` for PDF exports. Chrome PDF can drop `foreignObject` labels, causing blank boxes.
   - Wrap each diagram in a controlled container.

3. **Build HTML with print CSS**
   - Set `@page { margin: 0.55in; }`.
   - Add a Table of Contents near the top for long documents. Generate it from headings in the temporary build, not by editing source Markdown. Links are preferred when supported.
   - Use readable body width and table styles.
   - Start major sections on new pages. For docs where `##` are major sections, use `h2 { break-before: page; }` and exempt the first major section if needed. For true H1 sectioned docs, use `h1 { break-before: page; }` except the document title.
   - Set diagram CSS:
     - `max-width: 100%`
     - `height: auto`
     - `max-height: 7in`
     - `page-break-inside: avoid`

4. **Print with headers disabled**
   - Prefer Puppeteer/CDP `Page.printToPDF` with `displayHeaderFooter: false`.
   - Do not rely on Chrome CLI defaults.

5. **Verify**
   - Confirm output PDF exists and has pages.
   - Rasterize PDF pages with `pdftoppm` or inspect screenshots.
   - Check diagram pages for blank placeholders.
   - Verify rendered diagram count equals Mermaid block count.
   - Check no page URL/date/title headers or footers exist.

## Quick Reference

| Symptom | Fix |
|---|---|
| Blank Mermaid block | Render with `mmdc`; verify SVG non-empty before PDF |
| Blank Mermaid node labels | Set `flowchart.htmlLabels=false`; avoid SVG `foreignObject` labels |
| Diagram too large | Strip fixed SVG dimensions; CSS max width/height |
| Mermaid colors gone | Use explicit Mermaid theme config and white background |
| Headers/footers on every page | Use Puppeteer `displayHeaderFooter:false` |
| Tables overflow | CSS `table-layout:auto`, smaller font, horizontal-safe widths |
| Major sections run together | Add print CSS page breaks on `h1`/`h2`, excluding title |
| Long doc hard to navigate | Generate TOC from headings in temp HTML/PDF build |
| Source got changed | Stop. Restore source. Use temp build artifacts only |

## Validation Commands

```bash
# Count diagrams in Markdown
rg -n '^```mermaid' input.md

# Check PDF page count
pdfinfo output.pdf | rg '^Pages:'

# Rasterize for visual inspection
mkdir -p /tmp/pdf-pages
pdftoppm -png -r 120 output.pdf /tmp/pdf-pages/page
open /tmp/pdf-pages
```

## Recommended Toolchain

Preferred:

```text
Markdown -> temp Markdown/HTML -> Mermaid SVG -> styled HTML -> Puppeteer PDF
```

Use:
- `mmdc` for Mermaid SVGs
- `pandoc` or Python Markdown for HTML
- Puppeteer/Chrome CDP for PDF
- `pdfinfo` and `pdftoppm` for verification

## Common Mistakes

- Assuming successful PDF creation means diagrams rendered.
- Trusting Chrome CLI `--print-to-pdf` without checking headers/footers.
- Letting SVG intrinsic dimensions control PDF layout.
- Leaving Mermaid source blocks after failed rendering.
- Allowing Mermaid `foreignObject` HTML labels in PDF exports. They may show in browser but print as blank boxes.
- Verifying only the first page.
- Forgetting that many Markdown docs use `##` as major sections after one document `#` title.
- Editing the source Markdown to make PDF conversion easier.

## Required Output Report

After conversion, report:

- Output path
- File size
- Page count
- Mermaid block count vs rendered SVG count
- Whether headers/footers are absent
- Whether any diagram pages were visually checked
- Whether major sections start on new pages
- Whether TOC was generated
- Toolchain used
