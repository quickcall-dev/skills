#!/usr/bin/env bash
set -euo pipefail

skill_dir="${1:-skills/product-ui-kit}"
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
  if grep -RInE "$pattern" "$path" >/tmp/product-ui-kit-grep.txt 2>/dev/null; then
    echo "FAIL forbidden pattern '$pattern' in $path"
    cat /tmp/product-ui-kit-grep.txt
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

check_file "$skill_dir/SKILL.md"
check_file "$skill_dir/scripts/scaffold.mjs"
check_file "$skill_dir/scripts/audit-project.mjs"
check_file "$skill_dir/scripts/plan-surface.mjs"
check_file "$skill_dir/scripts/init-house-registry.mjs"
check_file "$skill_dir/references/agent-workflow.md"
check_file "$skill_dir/references/stack-policy.md"
check_file "$skill_dir/references/block-sourcing.md"
check_file "$skill_dir/references/map-apps.md"
check_file "$skill_dir/references/product-component-map.md"
check_file "$skill_dir/references/oss-provider-catalog.json"

if [[ -f "$skill_dir/SKILL.md" ]]; then
  check_grep '^name: product-ui-kit$' "$skill_dir/SKILL.md"
  check_grep '^description: Use when' "$skill_dir/SKILL.md"
  check_grep 'AGENTS_SKILLS_DIR' "$skill_dir/SKILL.md"
fi

check_no_grep '\.agents/skills/product-ui-kit' "$skill_dir"
check_no_grep 'Codex|codex|OpenAI|openai' "$skill_dir"
check_no_grep 'shadcn MCP/skill' "$skill_dir"
check_no_grep '\bground(ing|ed)?\b|\blightweight\b|\blite\b' "$skill_dir/SKILL.md"

if [[ -f "$skill_dir/references/oss-provider-catalog.json" ]]; then
  node -e "JSON.parse(require('fs').readFileSync(process.argv[1], 'utf8'))" "$skill_dir/references/oss-provider-catalog.json"
  echo "OK json: oss-provider-catalog.json"
fi

if [[ -f "$skill_dir/scripts/scaffold.mjs" ]]; then
  tmp="$(mktemp -d)"
  (cd "$tmp" && node "$OLDPWD/$skill_dir/scripts/scaffold.mjs" --framework vite --maps yes)
  check_file "$tmp/.agents/frontend/STACK.md"
  check_file "$tmp/.agents/frontend/MAP_GUIDE.md"
  rm -rf "$tmp"
fi

if [[ -f README.md ]]; then
  check_no_grep 'ground(ing|ed)? React frontend|ground React frontend|lightweight mockup' README.md
fi

if [[ "$failures" -gt 0 ]]; then
  echo "FAILURES: $failures"
  exit 1
fi

echo "product-ui-kit tests passed"
