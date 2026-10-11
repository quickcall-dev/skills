#!/usr/bin/env bash
# Check and install what technical-manual needs. Safe to run repeatedly.
set -u
PIP="pip install -q"
python3 -c "import sys; sys.exit(0 if sys.prefix == sys.base_prefix else 1)" 2>/dev/null && PIP="$PIP --break-system-packages"

for mod in markdown_it:markdown-it-py yaml:pyyaml pygments:pygments PIL:pillow pypdf:pypdf playwright:playwright linkify_it:linkify-it-py; do
  m=${mod%%:*}; pkg=${mod##*:}
  if python3 -c "import $m" 2>/dev/null; then echo "ok   $pkg"; else echo "add  $pkg"; $PIP "$pkg"; fi
done

if python3 - <<'E' 2>/dev/null
from playwright.sync_api import sync_playwright
with sync_playwright() as p:
    p.chromium.launch().close()
E
then echo "ok   chromium (playwright)"; else echo "add  chromium"; python3 -m playwright install chromium; fi

if command -v pdftoppm >/dev/null; then echo "ok   pdftoppm"; else
  echo "add  poppler-utils (pdftoppm)"
  (command -v apt-get >/dev/null && sudo apt-get install -y poppler-utils) || \
  (command -v brew >/dev/null && brew install poppler) || echo "     install poppler manually"
fi

DIR="$(cd "$(dirname "$0")/.." && pwd)"
for f in assets/theme.css assets/vendor/paged.polyfill.min.js assets/vendor/mermaid.min.js; do
  [ -f "$DIR/$f" ] && echo "ok   $f" || echo "MISSING $f"
done
echo "fonts: $(ls "$DIR/assets/vendor/fonts" | wc -l) files"
