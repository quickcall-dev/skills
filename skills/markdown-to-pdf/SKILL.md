---
name: markdown-to-pdf
description: Use when exporting Markdown reports to PDF, especially when Mermaid diagrams render blank, oversized, lose color, tables overflow, a TOC or PDF outline is needed, or Chrome/Puppeteer adds unwanted page headers and footers.
argument-hint: "[source.md] [output.pdf]"
allowed-tools: Bash, Read, Write
model: claude-sonnet-4-6
license: Apache-2.0
metadata:
  author: Sagar Sarkale
  version: "1.0"
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
   - Add a designed Table of Contents near the top for long documents. Generate it from headings in the temporary build, not by editing source Markdown. Links are preferred when supported.
   - Add PDF outline/bookmarks for Preview/sidebar navigation. This is separate from visible TOC content. Use document headings, usually title + major sections.
   - Do not leave the TOC as raw Markdown bullets with awkward hyperlink styling. Render it as a polished `nav.toc`, ordered hierarchy, or table-style list with clean spacing, muted section numbers, and normal link text.
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
| Preview sidebar index missing | Add PDF outline/bookmarks from headings; visible TOC alone is not enough |
| TOC looks like bullet links | Replace raw `ul` bullets with styled `nav.toc`, ordered hierarchy, or table-style rows |
| Source got changed | Stop. Restore source. Use temp build artifacts only |

## Navigation Requirements

Long PDFs need two navigation layers:

1. **Visible TOC page/section** inside PDF content.
2. **PDF outline/bookmarks** visible in Preview, Acrobat, browser sidebars, and other PDF readers.

Do not treat these as interchangeable. A clickable TOC page does not create Preview sidebar entries.

### Visible TOC Style

For long PDFs, add a Table of Contents that looks intentional:

- Place TOC after the document title and any short prefatory note.
- Use heading text from source, but generate TOC in temp HTML/build artifacts only.
- Prefer a `nav.toc` block with title `Table of Contents`.
- Avoid default Markdown bullets. If using `ul`/`ol`, set `list-style: none` and create visual hierarchy with spacing/indentation.
- Avoid ugly blue underlined links. Use document text color, subtle hover/print styling, and no text decoration in print.
- Make each entry feel like one clean row: section number or level marker, title, optional page/anchor affordance.
- Include top-level sections by default. Include second-level sections only when document is short enough or nested indentation stays readable.
- Keep TOC compact: no more than two pages unless user asks for exhaustive navigation.

Example CSS pattern:

```css
.toc {
  margin: 1.5rem 0 2rem;
  padding: 1rem 1.25rem;
  border: 1px solid #d8e0ee;
  border-radius: 12px;
  background: #f8fbff;
}
.toc h2 {
  margin: 0 0 0.75rem;
  break-before: auto;
}
.toc ol {
  list-style: none;
  margin: 0;
  padding: 0;
}
.toc li {
  margin: 0.35rem 0;
  line-height: 1.35;
}
.toc a {
  color: #162033;
  text-decoration: none;
}
.toc .toc-level-2 {
  margin-left: 1rem;
  color: #526173;
  font-size: 0.95em;
}
```

### PDF Outline / Bookmark Requirements

Add document outline entries from headings:

- Include document title.
- Include major sections by default: usually `h1` title and `h2` sections, or `h1` sections when a doc uses multiple top-level headings.
- Include `h3` only when nesting stays readable.
- Keep labels clean: remove Markdown numbering artifacts if duplicated, trim whitespace, decode HTML entities.
- Bookmarks must jump to correct section pages, not just page 1.
- Prefer PDF generators that emit outlines natively. If using Puppeteer/Chrome and it does not emit outlines, postprocess the PDF with a PDF library that can add outlines/bookmarks.
- If outline creation is unsupported by the available toolchain, say so explicitly in the output report instead of implying the TOC covers it.

Validation options:

```bash
# If mutool is available
mutool show output.pdf outline

# If qpdf is available, inspect JSON for outline data
qpdf --json output.pdf | rg -i 'outline|bookmark|title'
```

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
- Leaving auto-generated TOC as raw bullet points with blue underlined links.
- Assuming a visible TOC creates PDF bookmarks. Preview sidebar index requires PDF outline entries.
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
- Whether PDF outline/bookmarks were generated and how verified
- Toolchain used
