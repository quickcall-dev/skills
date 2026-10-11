#!/usr/bin/env bash
set -euo pipefail

skill_dir="${1:-skills/technical-manual}"
failures=0

check_file() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    echo "FAIL missing file: $path"
    failures=$((failures + 1))
  else
    echo "OK file: $path"
  fi
}

check_no_grep() {
  local pattern="$1"
  local path="$2"
  if grep -RInE "$pattern" "$path" >/tmp/technical-manual-grep.txt 2>/dev/null; then
    echo "FAIL forbidden pattern '$pattern' in $path"
    cat /tmp/technical-manual-grep.txt
    failures=$((failures + 1))
  else
    echo "OK absent: $pattern"
  fi
}

check_grep() {
  local pattern="$1"
  local path="$2"
  if grep -RInE "$pattern" "$path" >/dev/null 2>/dev/null; then
    echo "OK found: $pattern"
  else
    echo "FAIL missing pattern '$pattern' in $path"
    failures=$((failures + 1))
  fi
}

for f in SKILL.md \
  scripts/build.py scripts/components.py scripts/diagrams.py \
  scripts/analyze.py scripts/check.py scripts/setup.sh \
  references/editorial.md references/design.md references/components.md \
  assets/theme.css assets/signature.css \
  assets/vendor/mermaid.min.js assets/vendor/paged.polyfill.min.js \
  examples/gallery.md examples/git-internals.md examples/usd-web-viewer.md \
  examples/git-internals.raw.md; do
  check_file "$skill_dir/$f"
done

# no example build outputs shipped (rebuild with build.py)
check_no_grep '\.pdf$' <(find "$skill_dir/examples" -type f 2>/dev/null || true)

if [[ -f "$skill_dir/SKILL.md" ]]; then
  check_grep '^name: technical-manual$' "$skill_dir/SKILL.md"
  check_grep '^description: Use when' "$skill_dir/SKILL.md"
  check_grep 'AGENTS_SKILLS_DIR' "$skill_dir/SKILL.md"

  desc_len=$(sed -n 's/^description: //p' "$skill_dir/SKILL.md" | head -1 | wc -c | tr -d ' ')
  if [[ "$desc_len" -gt 500 ]]; then
    echo "FAIL description too long: ${desc_len} chars (max 500)"
    failures=$((failures + 1))
  else
    echo "OK description length: $desc_len"
  fi
fi

check_no_grep 'Codex|codex|OpenAI|openai' "$skill_dir"
check_no_grep 'python3 scripts/(build|analyze|check)\.py' "$skill_dir/SKILL.md"
check_no_grep 'bash scripts/setup\.sh' "$skill_dir/SKILL.md"

# python syntax
for py in "$skill_dir"/scripts/*.py; do
  python3 -m py_compile "$py"
  echo "OK py_compile: $(basename "$py")"
done

# bundled offline assets intact
font_count=$(ls "$skill_dir/assets/vendor/fonts" 2>/dev/null | wc -l | tr -d ' ')
if [[ "$font_count" -lt 8 ]]; then
  echo "FAIL too few bundled fonts: $font_count"
  failures=$((failures + 1))
else
  echo "OK bundled fonts: $font_count"
fi

# end-to-end smoke build if deps available
if python3 -c "import markdown_it, yaml, pygments, PIL, pypdf, playwright" 2>/dev/null \
   && command -v pdftoppm >/dev/null \
   && python3 - <<'E' 2>/dev/null
from playwright.sync_api import sync_playwright
with sync_playwright() as p:
    p.chromium.launch().close()
E
then
  tmp="$(mktemp -d)"
  cp "$skill_dir/examples/git-internals.raw.md" "$tmp/source.md"
  (cd "$tmp" && python3 "$OLDPWD/$skill_dir/scripts/build.py" source.md -o manual.pdf)
  check_file "$tmp/manual.pdf"
  rm -rf "$tmp"
else
  echo "SKIP smoke build: python deps / chromium / pdftoppm missing"
fi

if [[ "$failures" -gt 0 ]]; then
  echo "FAILURES: $failures"
  exit 1
fi

echo "technical-manual tests passed"
