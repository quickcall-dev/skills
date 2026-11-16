#!/usr/bin/env python3
"""Check standalone HTML structure, links, assets, and unsafe template patterns."""

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
    for source in inspector.srcs:
        if source.startswith(("http://", "https://", "//")):
            errors.append(f"external runtime asset: {source}")
        elif not (args.html.parent / source).exists():
            errors.append(f"missing local asset: {source}")
    if inspector.images_without_alt:
        errors.append(f"{inspector.images_without_alt} images have no alt text")
    if inspector.details:
        errors.append(f"{inspector.details} collapsible details elements exist")
    if inspector.styles != 1 or inspector.scripts != 1:
        errors.append("standalone output must contain one inline style and one inline script")
    if re.search(r"\{\{[A-Z_]+\}\}", text):
        errors.append("unresolved template value exists")
    for required in ("document-index", "architecture-diagram", "@media(max-width:620px)", "@media print"):
        if required not in text:
            errors.append(f"missing required pattern: {required}")
    if errors:
        print("FAIL")
        for error in errors:
            print(f"- {error}")
        return 1
    print(f"PASS: {len(inspector.ids)} IDs, {len(inspector.hrefs)} links, standalone assets, no collapsibles")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

