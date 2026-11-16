#!/usr/bin/env python3
"""Check an onion-explainer HTML file: structure, links, standalone assets, and required chrome."""

from __future__ import annotations

import argparse
import re
from html.parser import HTMLParser
from pathlib import Path


class Inspector(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.ids: list[str] = []
        self.hrefs: list[str] = []
        self.srcs: list[str] = []
        self.images_without_alt = 0
        self.details = 0
        self.styles = 0
        self.scripts = 0
        self.sections = 0
        self.h2 = 0

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        data = dict(attrs)
        if data.get("id"):
            self.ids.append(data["id"] or "")
        if data.get("href"):
            self.hrefs.append(data["href"] or "")
        if data.get("src"):
            self.srcs.append(data["src"] or "")
        if tag == "img" and not data.get("alt"):
            self.images_without_alt += 1
        if tag == "details":
            self.details += 1
        if tag == "style":
            self.styles += 1
        if tag == "script":
            self.scripts += 1
        if "class" in data and "layer" in (data["class"] or "").split():
            self.sections += 1
        if tag == "h2":
            self.h2 += 1


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("html", type=Path)
    args = parser.parse_args()
    text = args.html.read_text(encoding="utf-8")
    inspector = Inspector()
    inspector.feed(text)
    errors: list[str] = []
    if len(inspector.ids) != len(set(inspector.ids)):
        errors.append("duplicate IDs exist")
    known = set(inspector.ids)
    for href in inspector.hrefs:
        if href.startswith("#") and href[1:] not in known:
            errors.append(f"missing local target: {href}")
        elif not href.startswith(("#", "http://", "https://", "mailto:", "data:")) and not (args.html.parent / href).exists():
            errors.append(f"missing linked file: {href}")
    allowed_external = ("https://fonts.googleapis.com", "https://fonts.gstatic.com")
    for source in inspector.srcs:
        if source.startswith(("http://", "https://", "//")) and not source.startswith(allowed_external):
            errors.append(f"external runtime asset: {source}")
        elif not source.startswith(("http://", "https://", "//")) and not (args.html.parent / source).exists():
            errors.append(f"missing local asset: {source}")
    for link in re.findall(r'<link[^>]+href="([^"]+)"', text):
        if not link.startswith(allowed_external):
            errors.append(f"unexpected external link: {link}")
    if inspector.images_without_alt:
        errors.append(f"{inspector.images_without_alt} images have no alt text")
    if inspector.sections < 3:
        errors.append(f"only {inspector.sections} layer sections exist; an explainer needs at least 3")
    if inspector.h2 < inspector.sections:
        errors.append("every layer section needs an h2 title")
    if inspector.styles != 1 or inspector.scripts != 1:
        errors.append("standalone output must contain one inline style and one inline script")
    if re.search(r"\{\{[A-Z_0-9]+\}\}", text):
        errors.append("unresolved skeleton placeholder exists")
    if re.search(r"MathJax|katex", text, re.I):
        errors.append("math library detected; build formulas in HTML/CSS so they work offline")
    for required in (
        'id="progress"',
        'id="mini"',
        'id="kpis"',
        'id="onion"',
        'class="toc',
        'class="layer"',
        'class="question"',
        'glossify',
        'drawOnion',
        'id="terms"',
        "data-theme",
        "@media (max-width:720px)",
        "@media (max-width:1060px)",
        "prefers-reduced-motion",
    ):
        if required not in text:
            errors.append(f"missing required pattern: {required}")
    if errors:
        print("FAIL")
        for error in errors:
            print(f"- {error}")
        return 1
    print(f"PASS: {inspector.sections} layers, {len(inspector.ids)} IDs, {len(inspector.hrefs)} links, standalone chrome, HTML/CSS formulas")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
