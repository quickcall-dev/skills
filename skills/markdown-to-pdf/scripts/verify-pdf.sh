#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <source.md> <output.pdf> [pages-dir]" >&2
  exit 2
fi

SRC="$1"
PDF="$2"
PAGES_DIR="${3:-/tmp/pdf-pages-$(date +%s)}"

if [[ ! -f "$SRC" ]]; then
  echo "source missing: $SRC" >&2
  exit 1
fi
if [[ ! -f "$PDF" ]]; then
  echo "pdf missing: $PDF" >&2
  exit 1
fi

MERMAID_COUNT=$(rg -c '^```mermaid' "$SRC" || true)
SIZE=$(wc -c < "$PDF" | tr -d ' ')
PAGES="unknown"
if command -v pdfinfo >/dev/null 2>&1; then
  PAGES=$(pdfinfo "$PDF" | awk '/^Pages:/ {print $2}')
fi

echo "source: $SRC"
echo "pdf: $PDF"
echo "bytes: $SIZE"
echo "pages: $PAGES"
echo "mermaid_blocks: $MERMAID_COUNT"

if command -v pdftoppm >/dev/null 2>&1; then
  mkdir -p "$PAGES_DIR"
  pdftoppm -png -r 120 "$PDF" "$PAGES_DIR/page" >/dev/null
  echo "rasterized_pages: $PAGES_DIR"
  echo "Inspect pages with diagrams for blank blocks or oversized figures."
else
  echo "pdftoppm not found, skipping rasterization"
fi
