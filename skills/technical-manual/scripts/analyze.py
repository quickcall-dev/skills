#!/usr/bin/env python3
"""
analyze.py: map a (large) Markdown file before turning it into a manual.

    python3 analyze.py notes.md

Prints:
  1. the heading outline with word counts and line numbers, and how build.py
     will interpret it (parts / chapters / title)
  2. structural advice (split, merge, group into parts, missing deks)
  3. component opportunities: places where a figure would beat prose,
     each with a line number and the component to try

It never edits the file. It is a map for the editorial pass.
"""
import re
import sys
from pathlib import Path

HEX_RUN = re.compile(r"\b[0-9a-fA-F]{2}(?:\s[0-9a-fA-F]{2}){3,}\b")
NUMERIC_ITEM = re.compile(r"^\s*[-*]\s+(?:\*\*)?([^:|\d][^:|]{0,60}?)(?:\*\*)?\s*[:|\-–—]\s*~?([\d][\d,._]*\s*(?:%|[kKMGT]i?B|B|ms|s|x|×)?)\b")
STEP_ITEM = re.compile(r"^\s*\d+[.)]\s+")
ARROW_CHAIN = re.compile(r"\S+\s*(?:->|→|=>)\s*\S+\s*(?:->|→|=>)\s*\S+")
DATE_ITEM = re.compile(r"^\s*[-*]\s+(?:\*\*)?((?:19|20)\d\d(?:-\d\d)?(?:-\d\d)?)")
CALLOUT_PARA = re.compile(r"^(?:\*\*)?(note|warning|caution|important|tip|gotcha|footgun|pitfall|danger)\b[:*]", re.I)
SIZE_ITEM = re.compile(r"\(?\b[\d,]+\s*(?:bytes|B|KiB|MiB|KB|MB|GB)\b")
COMPARE_HINT = re.compile(r"\b(vs\.?|versus|pros and cons|trade-?offs?|compared (?:to|with))\b", re.I)
GENERIC = re.compile(r"^(overview|introduction|intro|summary|conclusion|notes?|misc|details|background|other)$", re.I)


def scan(lines):
    """Yield (lineno, kind, payload). Kinds: heading, fence, line."""
    fence, fence_lang, fence_start, buf = None, "", 0, []
    for i, line in enumerate(lines, 1):
        m = re.match(r"^(\s*)(`{3,}|~{3,})(.*)$", line)
        if m:
            if fence is None:
                fence, fence_lang, fence_start, buf = m.group(2), m.group(3).strip().split(" ")[0], i, []
            elif m.group(2).startswith(fence):
                yield fence_start, "fence", (fence_lang, buf)
                fence = None
            continue
        if fence:
            buf.append(line)
            continue
        h = re.match(r"^(#{1,6})\s+(.+?)\s*#*\s*$", line)
        if h:
            yield i, "heading", (len(h.group(1)), h.group(2))
        else:
            yield i, "line", line


def main(path):
    text = Path(path).read_text(encoding="utf-8")
    fm = text.startswith("---\n")
    lines = text.split("\n")
    events = list(scan(lines))

    heads = [(n, lvl, t) for n, k, (lvl, t) in [(n, k, p) for n, k, p in events if k == "heading"]]
    h1 = [h for h in heads if h[1] == 1]
    h2 = [h for h in heads if h[1] == 2]

    # word counts per heading section
    counts, cur = {}, None
    for n, k, p in events:
        if k == "heading":
            cur = n
            counts[cur] = 0
        elif k == "line" and cur is not None:
            counts[cur] += len(re.findall(r"\w+", p))
        elif k == "fence" and cur is not None:
            counts[cur] += 0
    total = sum(len(re.findall(r"\w+", l)) for l in lines)

    print("# Analysis of %s" % path)
    print("\n%d lines · ~%d words · %d H1 · %d H2 · frontmatter: %s\n" % (len(lines), total, len(h1), len(h2), "yes" if fm else "no"))

    # interpretation
    title_h1 = None
    if not fm and h1:
        title_h1 = h1[0]
    parts = [h for h in h1 if h is not title_h1]
    print("## How build.py will read it\n")
    if title_h1:
        print("- Title: line %d `%s` (first H1, no frontmatter title)" % (title_h1[0], title_h1[2]))
    if parts:
        print("- %d parts (H1), %d chapters (H2)" % (len(parts), len(h2)))
    else:
        print("- No parts: %d chapters (H2), each opens a new page, colours cycle per chapter" % len(h2))
    print()

    print("## Outline\n")
    for n, lvl, t in heads:
        if lvl > 3:
            continue
        w = counts.get(n, 0)
        # include descendant words for H1/H2
        flag = ""
        if lvl == 2:
            sub = 0
            idx = [h[0] for h in heads].index(n)
            for m, l2, _ in heads[idx + 1:]:
                if l2 <= 2:
                    break
                sub += counts.get(m, 0)
            w += sub
            if w > 1400:
                flag = "  ← long: consider splitting"
            elif w < 90:
                flag = "  ← short: consider merging into a neighbour"
        print("%s- L%-5d %s  (%d words)%s" % ("  " * (lvl - 1), n, t, w, flag))
    print()

    # advice
    print("## Structural advice\n")
    advice = []
    if not fm:
        advice.append("Add frontmatter: title, name (short brand, ≤ 2 words), subtitle, edition, description (one sentence on what the reader will understand).")
    if not parts and len(h2) > 6:
        advice.append("%d chapters and no parts: group them into 2–5 parts with `#` headings, each with a one-line italic dek." % len(h2))
    if parts and len(parts) > 6:
        advice.append("%d parts is a lot for a manual: aim for 2–6." % len(parts))
    gen = [h for h in h2 if GENERIC.match(re.sub(r"^[\d.\s]+", "", h[2]))]
    if gen:
        advice.append("Generic chapter titles (%s): rename to say what the reader learns." % ", ".join("L%d %s" % (h[0], h[2]) for h in gen))
    numbered = [h for h in h2 if re.match(r"^\d+[.)]", h[2])]
    if numbered:
        advice.append("Numbered headings (%d) are fine: the number prefix is stripped, numbering is automatic." % len(numbered))
    # deks
    nodek = 0
    for n, lvl, t in h2:
        nxt = next((l for l in lines[n:n + 4] if l.strip()), "")
        if not re.match(r"^\s*[*_][^*_].*[*_]\s*$", nxt):
            nodek += 1
    if nodek:
        advice.append("%d of %d chapters have no dek: add an italic one- or two-sentence takeaway right under each `##`." % (nodek, len(h2)))
    for a in advice or ["Structure looks ready."]:
        print("- " + a)
    print()

    # opportunities
    print("## Component opportunities\n")
    ops = []
    run, run_start = [], 0
    steps, steps_start = 0, 0
    dates, dates_start = 0, 0
    sizes, sizes_start = 0, 0
    for n, k, p in events:
        if k == "fence":
            lang, buf = p
            body = "\n".join(buf)
            if lang == "mermaid":
                ops.append((n, "mermaid", "kept as a themed figure; consider `flow` if it is a simple left-to-right chain (crisper, matches the theme)"))
            elif re.search(r"[├└]──", body):
                ops.append((n, "tree", "box-drawing tree: auto-rendered as `tree`; add `title:` and `{hl}` on the key node"))
            elif not lang and re.search(r"\+-{3,}\+|\|.*\|.*\|", body) and len(buf) > 2:
                ops.append((n, "flow/stack", "ASCII diagram: redraw as `flow` (boxes and arrows) or `stack` (layers)"))
            elif HEX_RUN.search(body):
                ops.append((n, "bytes", "hex dump: pick the meaningful bytes and show them as `bytes` groups with labels"))
            continue
        if k != "line":
            continue
        line = p
        m = NUMERIC_ITEM.match(line)
        if m:
            if not run:
                run_start = n
            run.append(m.group(1))
        else:
            if len(run) >= 3:
                ops.append((run_start, "bars", "%d labelled numbers in a list (%s, …): a `bars` chart" % (len(run), ", ".join(run[:2]))))
            run = []
        if STEP_ITEM.match(line):
            if not steps:
                steps_start = n
            steps += 1
        elif line.strip():
            if 3 <= steps <= 6:
                ops.append((steps_start, "steps", "%d-item numbered procedure: `steps` (or `flow` if each step hands data to the next)" % steps))
            steps = 0
        if DATE_ITEM.match(line):
            if not dates:
                dates_start = n
            dates += 1
        elif line.strip():
            if dates >= 3:
                ops.append((dates_start, "timeline", "%d dated items: `timeline`" % dates))
            dates = 0
        if line.strip().startswith(("-", "*")) and SIZE_ITEM.search(line):
            if not sizes:
                sizes_start = n
            sizes += 1
        elif line.strip():
            if sizes >= 3:
                ops.append((sizes_start, "stack/strip", "%d items with byte sizes: a file or memory layout → `stack` (vertical) or `strip` (horizontal)" % sizes))
            sizes = 0
        if HEX_RUN.search(line):
            ops.append((n, "bytes", "inline hex bytes: `bytes`"))
        if ARROW_CHAIN.search(line) and not line.lstrip().startswith("|"):
            ops.append((n, "flow", "arrow chain in prose: `flow`"))
        if CALLOUT_PARA.match(line.strip()):
            kind = CALLOUT_PARA.match(line.strip()).group(1).lower()
            mapped = {"gotcha": "CAUTION", "footgun": "CAUTION", "pitfall": "CAUTION", "danger": "CAUTION"}.get(kind, kind.upper())
            ops.append((n, "callout", "'%s:' paragraph → `> [!%s] short title`" % (kind.title(), mapped)))
        if COMPARE_HINT.search(line) and line.strip().startswith("#"):
            ops.append((n, "compare", "comparison heading: `compare` side by side"))
    # a hand-written table of contents duplicates the generated one
    toc_run, toc_start = 0, 0
    for i, line in enumerate(lines, 1):
        if re.match(r"^\s*[-*+]\s+\[[^\]]+\]\(#[^)]+\)\s*$", line):
            toc_start = toc_start or i
            toc_run += 1
        elif line.strip():
            if toc_run >= 5:
                ops.append((toc_start, "remove", "%d-line list of in-page links: a hand-written contents list; delete it (the manual generates contents, bookmarks and links)" % toc_run))
            toc_run, toc_start = 0, 0
    badges = [i for i, l in enumerate(lines, 1) if re.search(r"!\[[^\]]*\]\(https?://(img\.shields\.io|badge|github\.com/.+/badge)", l)]
    if badges:
        ops.append((badges[0], "remove", "%d status badge image(s): web-only chrome; drop them in the manual" % len(badges)))
    # tables
    for i, line in enumerate(lines, 1):
        if re.match(r"^\s*\|?\s*:?-{3,}", line) and i >= 2 and "|" in lines[i - 2]:
            header = lines[i - 2]
            rows = 0
            for l in lines[i:]:
                if "|" not in l:
                    break
                rows += 1
            numeric_cols = 0
            sample = [l for l in lines[i:i + rows]]
            cols = len([c for c in header.split("|") if c.strip()])
            for c in range(cols):
                vals = []
                for l in sample:
                    cells = [x.strip() for x in l.strip().strip("|").split("|")]
                    if c < len(cells):
                        vals.append(cells[c])
                if vals and sum(bool(re.match(r"^~?[\d,._]+\s*(%|[kKMGT]?i?B|ms|s|x|×)?$", v)) for v in vals) >= max(2, len(vals) * 0.7):
                    numeric_cols += 1
            note = "%d rows, %d cols" % (rows, cols)
            if numeric_cols and rows >= 3:
                ops.append((i - 1, "table+bars", "table (%s) with a numeric column: keep the table, and consider a `bars` figure for the headline number" % note))
            if rows > 22:
                ops.append((i - 1, "table", "long table (%d rows): it will be allowed to break across pages; consider trimming" % rows))
            ops.append((i - 1, "caption", "table (%s): add `Caption: **Bold takeaway.** detail` under it" % note))
    seen = set()
    for n, comp, msg in sorted(ops):
        key = (n, comp)
        if key in seen:
            continue
        seen.add(key)
        print("- L%-5d **%s**: %s" % (n, comp, msg))
    if not ops:
        print("- None detected automatically. Look for numbers, sequences and layouts by reading.")
    print("\nNext: follow references/editorial.md, then run build.py and fix every issue in the report.")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(__doc__)
        sys.exit(1)
    main(sys.argv[1])
