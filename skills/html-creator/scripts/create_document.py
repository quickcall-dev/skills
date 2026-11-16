#!/usr/bin/env python3
"""Build one standalone technical HTML file from metadata and an HTML fragment."""

from __future__ import annotations

import argparse
import json
import os
import re
from html import escape
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def uniquify_svg_ids(svg: str, suffix: str) -> str:
    """Make inlined SVG ids unique so several diagrams can coexist in one document."""
    for identifier in set(re.findall(r'id="([^"]+)"', svg)):
        svg = svg.replace(f'id="{identifier}"', f'id="{identifier}-{suffix}"')
        svg = svg.replace(f"url(#{identifier})", f"url(#{identifier}-{suffix})")
    def retarget(match: re.Match[str]) -> str:
        return 'aria-labelledby="' + " ".join(f"{name}-{suffix}" for name in match.group(1).split()) + '"'
    return re.sub(r'aria-labelledby="([^"]*)"', retarget, svg, count=1)


def inline_svgs(content: str, base: Path) -> str:
    pattern = re.compile(r'<img\s+([^>]*?)src="([^"]+\.svg)"([^>]*)>', re.IGNORECASE)

    def replace(match: re.Match[str]) -> str:
        source = (base / match.group(2)).resolve()
        if not source.is_file():
            raise SystemExit(f"SVG does not exist: {source}")
        svg = source.read_text(encoding="utf-8")
        svg = re.sub(r"<\?xml[^>]*>\s*", "", svg, count=1)
        svg = re.sub(r"<!DOCTYPE[^>]*>\s*", "", svg, count=1)
        svg = uniquify_svg_ids(svg, re.sub(r"[^a-z0-9]+", "-", source.stem.lower()))
        alt_match = re.search(r'alt="([^"]*)"', match.group(1) + match.group(3))
        alt = escape(alt_match.group(1) if alt_match else "Architecture diagram")
        svg = re.sub(r"<svg\b", f'<svg role="img" aria-label="{alt}"', svg, count=1)
        return svg

    return pattern.sub(replace, content)


def rewrite_local_links(content: str, source_base: Path, output_base: Path) -> str:
    pattern = re.compile(r'href="([^"#:]+\.(?:drawio|svg|png|pdf))"', re.IGNORECASE)

    def replace(match: re.Match[str]) -> str:
        source = (source_base / match.group(1)).resolve()
        relative = os.path.relpath(source, output_base).replace(os.sep, "/")
        return f'href="{relative}"'

    return pattern.sub(replace, content)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--meta", type=Path, required=True)
    parser.add_argument("--content", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--inline-svg", action="store_true")
    args = parser.parse_args()
    meta = json.loads(args.meta.read_text(encoding="utf-8"))
    content = args.content.read_text(encoding="utf-8")
    if args.inline_svg:
        content = inline_svgs(content, args.content.parent)
    content = rewrite_local_links(content, args.content.parent, args.out.parent.resolve())
    nav = "".join(f'<a href="{escape(item["href"])}">{escape(item["label"])}</a>' for item in meta["nav"])
    values = {
        "LANG": meta.get("lang", "en"),
        "DESCRIPTION": escape(meta["description"]),
        "TITLE": escape(meta["title"]),
        "MARK": escape(meta.get("mark", "DOC")),
        "BRAND": escape(meta.get("brand", "Technical document")),
        "DOCUMENT_KIND": escape(meta.get("documentKind", "Standalone architecture")),
        "NAV": nav,
        "CONTENT": content,
        "CSS": (ROOT / "assets/document.css").read_text(encoding="utf-8"),
        "JS": (ROOT / "assets/document.js").read_text(encoding="utf-8"),
    }
    output = (ROOT / "templates/standalone-document.html").read_text(encoding="utf-8")
    for key, value in values.items():
        output = output.replace(f"{{{{{key}}}}}", value)
    leftovers = re.findall(r"\{\{[A-Z_]+\}\}", output)
    if leftovers:
        raise SystemExit(f"unresolved template values: {leftovers}")
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(output, encoding="utf-8")
    print(args.out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

