"""
Component renderers for technical-manual.

Each component is a fenced code block whose language is the component name:

    ```bars
    title: Gap survey
    Arrow <= 17 | 98 | 228 of 233 files {hl}
    ```

Leading `key: value` lines (title, tag, sub, note, unit, scale, max ...) are
options; everything after is the body. Rows use `|` to separate fields.
Trailing `{hl}` highlights a row in the section's accent, `{dim}` mutes it,
`{gap}` marks a hatched gap (strip only).

Every renderer returns *inner* HTML only. The caller (build.py) wraps it in
a numbered figure panel. Renderers never emit colors: only classes that the
theme resolves. That is the consistency contract.
"""
import html
import math
import re
import sys

OPTION_KEYS = {
    "title", "tag", "sub", "note", "caption", "unit", "scale", "max", "cols",
    "layout", "left", "right", "cover", "nofig", "end", "start", "mono", "brace",
}

FLAG_WORDS = "hl|dim|gap|ghost|mono|strong|dashed|both|tall|note|c[1-9]"
FLAG_RE = re.compile(r"\s*\{((?:%s)(?:[ ,]+(?:%s))*)\}" % (FLAG_WORDS, FLAG_WORDS))


# ---------------------------------------------------------------- helpers
def esc(s):
    return html.escape(str(s), quote=True)


def inline(s):
    """Tiny inline markdown: `code`, **bold**, *em*. Escapes everything else."""
    s = esc(s)
    s = re.sub(r"`([^`]+)`", r"<code>\1</code>", s)
    s = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", s)
    s = re.sub(r"(?<![\w*])\*([^*]+)\*(?![\w*])", r"<em>\1</em>", s)
    return s


def flags(line):
    """Split trailing {hl}/{dim}/{gap} flags off a line."""
    found = set()
    for m in FLAG_RE.finditer(line):
        found |= {f.strip() for f in m.group(1).replace(",", " ").split()}
    return FLAG_RE.sub("", line).rstrip(), found


def cls(fl, *extra):
    names = [f for f in ("hl", "dim", "gap", "ghost", "mono", "strong") if f in fl] + [e for e in extra if e]
    return (' class="%s"' % " ".join(names)) if names else ""


def fields(line, n=None):
    parts = [p.strip() for p in line.split("|")]
    if n:
        parts += [""] * (n - len(parts))
    return parts


def number(s):
    """Parse '12,697,252 B', '10.0 MB', '98%', '1.2k' into a float (bytes for sizes)."""
    if s is None:
        return None
    t = str(s).strip().replace(",", "").replace("_", "")
    m = re.match(r"^~?(-?[\d.]+)\s*([kKMGT]i?B?|B|%|x|×)?", t)
    if not m:
        return None
    v = float(m.group(1))
    unit = (m.group(2) or "").upper().replace("I", "")
    mult = {"K": 1e3, "KB": 1e3, "M": 1e6, "MB": 1e6, "G": 1e9, "GB": 1e9, "T": 1e12, "TB": 1e12}
    if "I" in (m.group(2) or "").upper():  # KiB etc.
        mult = {"K": 1024, "KB": 1024, "M": 1024**2, "MB": 1024**2, "G": 1024**3, "GB": 1024**3}
    return v * mult.get(unit, 1)


def split_options(lines):
    opts, i = {}, 0
    while i < len(lines):
        m = re.match(r"^([a-z]+):\s?(.*)$", lines[i])
        if m and m.group(1) in OPTION_KEYS:
            opts[m.group(1)] = m.group(2).strip()
            i += 1
        else:
            break
    body = lines[i:]
    # trailing option lines are allowed too (e.g. `end: 12,697,284` after a strip)
    while body and re.match(r"^(start|end|brace|note|caption|scale|unit|max):\s", body[-1]):
        k, v = body.pop().split(":", 1)
        opts.setdefault(k, v.strip())
    # drop leading/trailing blank lines
    while body and not body[0].strip():
        body.pop(0)
    while body and not body[-1].strip():
        body.pop()
    return opts, body


def sections(body):
    """Group lines under '## heading' markers. Returns [(heading, flags, [lines])]."""
    out, cur = [], None
    for line in body:
        if line.startswith("## "):
            h, fl = flags(line[3:])
            cur = (h.strip(), fl, [])
            out.append(cur)
        elif line.strip():
            if cur is None:
                cur = ("", set(), [])
                out.append(cur)
            cur[2].append(line)
    return out


def arrow_svg():
    return '<div class="aline"></div>'


# ---------------------------------------------------------------- flow
ARROW_RE = re.compile(r"\s+-(?:\[([^\]]*)\])?->\s+|\s+->\s+")


def render_flow(opts, body):
    """Rows of boxes joined by arrows.

    GGML / unversioned -[version]-> GGMF v1 / adds a version -> GGJT {hl}
    >> KV header replaces 7 x u32          (elbow link from row end to next row start)
    ~~                                     (plain vertical gap)
    Node text: 'Title / subline / subline'. Flags: {hl} {dim} {ghost} {mono}.
    """
    out = ['<div class="flow">']
    pending_link = None
    for raw in body:
        line = raw.strip()
        if not line:
            continue
        if line.startswith(">>"):
            pending_link = line[2:].strip()
            continue
        if line == "~~":
            out.append('<div class="flow-gap"></div>')
            continue
        if pending_link is not None:
            out.append('<div class="flow-link" data-label="%s"><div class="lk"></div><div class="lk2"></div>'
                       '<div class="ll">%s</div></div>' % (esc(pending_link), inline(pending_link)))
            pending_link = None
        # split into nodes + arrow labels
        pieces, labels, pos = [], [], 0
        for m in ARROW_RE.finditer(line):
            pieces.append(line[pos:m.start()])
            labels.append(m.group(1) or "")
            pos = m.end()
        pieces.append(line[pos:])
        row = ['<div class="flow-row">']
        for i, p in enumerate(pieces):
            text, fl = flags(p)
            parts = [x.strip() for x in text.split(" / ")]
            inner = '<div class="nt">%s</div>' % inline(parts[0])
            inner += "".join('<div class="ns">%s</div>' % inline(s) for s in parts[1:])
            c = " ".join(["flow-node"] + [f for f in ("hl", "dim", "ghost", "mono") if f in fl])
            row.append('<div class="%s">%s</div>' % (c, inner))
            if i < len(labels):
                lab = labels[i]
                wide = " wide" if len(lab) > 9 else (" mid" if len(lab) > 4 else "")
                row.append('<div class="flow-arrow%s"><div class="al">%s</div>%s</div>' %
                           (wide, inline(lab) if lab else "&nbsp;", arrow_svg()))
        row.append("</div>")
        out.append("".join(row))
    out.append("</div>")
    return "\n".join(out)


# ---------------------------------------------------------------- bars
def render_bars(opts, body):
    """Horizontal bars.  Label | value | note {hl}"""
    rows = []
    for line in body:
        text, fl = flags(line)
        label, val, note = fields(text, 3)
        rows.append((label, val, note, fl))
    vals = [number(v) or 0 for _, v, _, _ in rows]
    vmax = number(opts.get("max")) or (max(vals) if vals else 1) or 1
    unit = opts.get("unit", "")
    log = opts.get("scale") == "log"
    longest = max((len(n) + len(v) for _, v, n, _ in rows), default=0)
    scale_room = 0.72 if longest < 22 else (0.6 if longest < 40 else 0.5)
    out = ['<div class="bars">']
    for (label, val, note, fl), v in zip(rows, vals):
        if log and v > 0:
            w = 100 * math.log10(1 + v) / math.log10(1 + vmax)
        else:
            w = 100 * v / vmax
        w = max(0.4, min(w, 100)) * scale_room  # leave room for the value text
        shown = esc(val) + ((" " + esc(unit)) if unit[:1].isalpha() else esc(unit))
        valtxt = "<b>%s</b>" % shown + (" · %s" % inline(note) if note else "")
        out.append('<div class="bar-label%s">%s</div>' % (" hl" if "hl" in fl else "", inline(label)))
        out.append('<div class="bar-track"><div%s style="width:%.2f%%"></div><div class="bar-val">%s</div></div>'
                   % (cls(fl, "bar"), w, valtxt))
    out.append("</div>")
    return "\n".join(out)


# ---------------------------------------------------------------- strip
def render_strip(opts, body):
    """Proportional horizontal segments (byte layouts, budgets, timelines of size).

    name | size | sublabel {hl}
    ~ 141 B   -> a hatched gap segment (or use {gap})
    scale: linear | sqrt | log | equal     (default sqrt: honest order, readable small parts)
    brace: one read if the reader bridges gaps / sub   (brace under the strip)
    """
    segs = []
    for line in body:
        text, fl = flags(line)
        if text.startswith("~"):
            fl = fl | {"gap"}
            text = text[1:].strip()
            f = fields(text, 3)
            name, size, sub = (f[0], f[0], f[1]) if len(f) < 2 or not f[1] else (f[0], f[1], f[2])
        else:
            name, size, sub = fields(text, 3)
        segs.append((name, size, sub, fl))
    scale = opts.get("scale", "sqrt")
    weights = []
    for name, size, sub, fl in segs:
        v = number(size) or 1
        if scale == "linear":
            w = v
        elif scale == "log":
            w = math.log10(v + 10)
        elif scale == "equal":
            w = 1
        else:
            w = math.sqrt(v)
        weights.append(w)
    total = sum(weights) or 1
    out = ['<div class="strip">']
    for (name, size, sub, fl), w in zip(segs, weights):
        pct = 100 * w / total
        minw = 22 if "gap" in fl else 40
        inner = '<div class="sn">%s</div>' % inline(name)
        if "gap" not in fl and size:
            inner += '<div class="ss">%s</div>' % esc(size)
        if sub:
            inner += '<div class="ss">%s</div>' % inline(sub)
        out.append('<div class="seg%s" style="flex:%.3f 1 0; min-width:%dpt">%s</div>' %
                   ("".join(" " + f for f in ("hl", "dim", "gap") if f in fl), pct, minw, inner))
    out.append("</div>")
    if opts.get("start") or opts.get("end"):
        out.append('<div class="strip-scale"><span>%s</span><span>%s</span></div>' %
                   (inline(opts.get("start", "")), inline(opts.get("end", ""))))
    if opts.get("brace"):
        t = opts["brace"].split(" / ")
        out.append('<div class="strip-note"><div class="b"></div><div class="t">%s</div>%s</div>' %
                   (inline(t[0]), "".join('<div class="t2">%s</div>' % inline(x) for x in t[1:])))
    return "\n".join(out)


# ---------------------------------------------------------------- bytes
def render_bytes(opts, body):
    """Hex byte groups with labels.  50 41 43 4b | magic "PACK" | 4 bytes {hl}"""
    out = ['<div class="bytes">']
    for line in body:
        text, fl = flags(line)
        hexes, label, desc = fields(text, 3)
        cells = "".join('<span class="bcell">%s</span>' % esc(b) for b in hexes.split())
        c = " ".join(["bgroup"] + [f for f in ("hl", "dim") if f in fl])
        out.append('<div class="%s"><div class="bcells">%s</div><div class="bbrace"></div>'
                   '<div class="blabel">%s</div>%s</div>' %
                   (c, cells, inline(label), ('<div class="bdesc">%s</div>' % inline(desc)) if desc else ""))
    out.append("</div>")
    return "\n".join(out)


# ---------------------------------------------------------------- stack
def render_stack(opts, body):
    """Vertical layers, top to bottom (file anatomy, architecture layers).

    name | detail | size | offset {hl}
    scale: equal (default) | sqrt | linear   -> layer heights
    end: 12,697,284                            -> offset label under the last layer
    """
    rows = []
    for line in body:
        text, fl = flags(line)
        rows.append(tuple(fields(text, 4)) + (fl,))
    scale = opts.get("scale", "equal")
    hs = []
    for name, detail, size, off, fl in rows:
        v = number(size) or 1
        hs.append({"linear": v, "sqrt": math.sqrt(v), "log": math.log10(v + 10)}.get(scale, 1))
    hmax = max(hs) if hs else 1
    out = ['<div class="stack">']
    for i, ((name, detail, size, off, fl), h) in enumerate(zip(rows, hs)):
        px = 16 + (40 * h / hmax if scale != "equal" else 0)
        mono = " mono" if name.isupper() or "mono" in fl else ""
        c = "stack-layer" + (" first" if i == 0 else "") + "".join(" " + f for f in ("hl", "dim") if f in fl)
        out.append('<div class="stack-off">%s</div>' % esc(off))
        out.append('<div class="%s" style="min-height:%.0fpt"><div class="ln%s">%s</div>%s</div>' %
                   (c, px, mono, inline(name), ('<div class="ld">%s</div>' % inline(detail)) if detail else ""))
        out.append('<div class="stack-size">%s</div>' % esc(size))
    if opts.get("end"):
        out.append('<div class="stack-end">%s</div><div></div><div></div>' % esc(opts["end"]))
    out.append("</div>")
    return "\n".join(out)


# ---------------------------------------------------------------- cols
def render_cols(opts, body):
    """Side-by-side columns ('who owns what').

    ## Page · main thread
    Public API
    three.js meshes {hl}
    > index.js · element.js        (footer)
    """
    secs = sections(body)
    out = ['<div class="cols" style="--n:%d">' % max(1, len(secs))]
    for i, (head, hfl, lines) in enumerate(secs):
        items, foot = [], []
        for l in lines:
            t, fl = flags(l.strip())
            if t.startswith(">"):
                foot.append(t[1:].strip())
            else:
                t = re.sub(r"^[-*]\s+", "", t)
                items.append('<div class="col-item%s">%s</div>' % (" hl" if "hl" in fl else "", inline(t)))
        color = "c%d" % (i % 9 + 1) if opts.get("layout") == "rainbow" else ""
        out.append('<div class="col %s"><div class="col-head">%s</div><div class="col-items">%s</div>%s</div>' %
                   (color, inline(head), "".join(items),
                    ('<div class="col-foot">%s</div>' % inline(" ".join(foot))) if foot else ""))
    out.append("</div>")
    return "\n".join(out)


# ---------------------------------------------------------------- steps
def render_steps(opts, body):
    """Numbered stages left to right.

    ## Bytes {hl}
    laptop.usd
    10.0 MB crate
    > fetched once by the worker    (italic footer)
    Item flags: {mono} {strong}.
    """
    secs = sections(body)
    out = ['<div class="steps" style="--n:%d">' % max(1, len(secs))]
    for i, (head, hfl, lines) in enumerate(secs):
        items, foot = [], []
        for l in lines:
            t, fl = flags(l.strip())
            if t.startswith(">"):
                foot.append(t[1:].strip())
            else:
                t = re.sub(r"^[-*]\s+", "", t)
                items.append('<div%s>%s</div>' % (cls(fl, "step-item"), inline(t)))
        out.append('<div class="step%s"><div class="step-head"><span class="step-num">%d</span>%s</div>'
                   '<div class="step-body">%s</div>%s</div>' %
                   (" hl" if "hl" in hfl else "", i + 1, inline(head), "".join(items),
                    ('<div class="step-foot">%s</div>' % inline(" ".join(foot))) if foot else ""))
    out.append("</div>")
    return "\n".join(out)


# ---------------------------------------------------------------- stats
def render_stats(opts, body):
    """A row of facts.  26,390 | objects | in one pack file {hl}"""
    rows = []
    for l in body:
        if l.strip():
            t, fl = flags(l)
            rows.append(tuple(fields(t, 3)) + (fl,))
    out = ['<div class="stats" style="--n:%d">' % max(1, len(rows))]
    for v, label, sub, fl in rows:
        out.append('<div class="stat%s"><div class="stat-value">%s</div><div class="stat-label">%s</div>%s</div>' %
                   (" hl" if "hl" in fl else "", esc(v), inline(label),
                    ('<div class="stat-sub">%s</div>' % inline(sub)) if sub else ""))
    out.append("</div>")
    return "\n".join(out)


# ---------------------------------------------------------------- kv
def render_kv(opts, body):
    """Key/value spec card.  key = value  # comment {hl}   ·  '## Section' headers allowed."""
    out = ['<div class="kv">']
    for line in body:
        if line.startswith("## "):
            out.append('<div class="sec">%s</div>' % inline(line[3:]))
            continue
        if not line.strip():
            continue
        text, fl = flags(line)
        comment = ""
        if "  #" in text:
            text, comment = text.split("  #", 1)
        if "=" in text:
            k, v = text.split("=", 1)
        elif ":" in text:
            k, v = text.split(":", 1)
        else:
            k, v = text, ""
        out.append('<div class="k">%s</div><div class="v%s">%s%s</div>' %
                   (esc(k.strip()), " hl" if "hl" in fl else "", inline(v.strip()),
                    ('<span class="cm">%s</span>' % inline(comment.strip())) if comment else ""))
    out.append("</div>")
    return "\n".join(out)


# ---------------------------------------------------------------- tree
def render_tree(opts, body):
    """Indented tree -> box-drawing tree.  Two spaces per level.
    'name · meta' renders meta muted; '# comment' renders as an aside; {hl} emphasises."""
    items = []
    for line in body:
        if not line.strip():
            continue
        # accept pre-drawn trees too: strip box-drawing prefixes into indentation
        m = re.match(r"^([\s│├└─|`\-]*)(.*)$", line)
        prefix, rest = m.group(1), m.group(2)
        if any(ch in prefix for ch in "│├└"):
            depth = len(prefix) // 4
        else:
            depth = (len(line) - len(line.lstrip(" "))) // 2
        items.append((depth, rest.strip()))
    lines = []
    n = len(items)
    for i, (d, text) in enumerate(items):
        # is this the last sibling at its depth?
        def last_at(idx, depth):
            for j in range(idx + 1, n):
                if items[j][0] < depth:
                    return True
                if items[j][0] == depth:
                    return False
            return True
        guide = ""
        for level in range(1, d):
            # ancestor at `level` still has siblings below?
            anc = max(j for j in range(i + 1) if items[j][0] == level) if any(items[j][0] == level for j in range(i + 1)) else i
            guide += "   " if last_at(anc, level) else "│  "
        if d > 0:
            guide += "└─ " if last_at(i, d) else "├─ "
        t, fl = flags(text)
        cmt = ""
        if "  #" in t:
            t, cmt = t.split("  #", 1)
        meta = ""
        if " · " in t:
            t, meta = t.split(" · ", 1)
        node = '<span%s>%s</span>' % (' class="hl"' if "hl" in fl else "", inline(t.strip()))
        if meta:
            node += ' <span class="tm">%s</span>' % inline(meta)
        if cmt:
            node += '  <span class="cmt">%s</span>' % inline(cmt.strip())
        lines.append('<div class="tn"><span class="tg">%s</span>%s</div>' % (esc(guide), node))
    return '<div class="tree">%s</div>' % "".join(lines)


# ---------------------------------------------------------------- timeline
def render_timeline(opts, body):
    """when | what | description {hl}   · horizontal up to 6 items, vertical beyond (or layout: vertical)."""
    rows = []
    for line in body:
        text, fl = flags(line)
        rows.append(tuple(fields(text, 3)) + (fl,))
    vertical = opts.get("layout") == "vertical" or len(rows) > 6
    if vertical:
        out = ['<div class="timeline vertical">']
        for when, what, desc, fl in rows:
            out.append('<div class="tl-when">%s</div><div class="tl%s"><div class="tl-dot"></div>'
                       '<div class="tl-what">%s</div>%s</div>' %
                       (esc(when), " hl" if "hl" in fl else "", inline(what),
                        ('<div class="tl-desc">%s</div>' % inline(desc)) if desc else ""))
    else:
        out = ['<div class="timeline" style="--n:%d">' % len(rows)]
        for when, what, desc, fl in rows:
            out.append('<div class="tl%s"><div class="tl-when">%s</div><div class="tl-dot"></div>'
                       '<div class="tl-what">%s</div>%s</div>' %
                       (" hl" if "hl" in fl else "", esc(when), inline(what),
                        ('<div class="tl-desc">%s</div>' % inline(desc)) if desc else ""))
    out.append("</div>")
    return "\n".join(out)


# ---------------------------------------------------------------- compare
def render_compare(opts, body):
    """Two (or more) sides.  '## Loose objects' / '## Packfile {hl}' then one item per line."""
    secs = sections(body)
    out = ['<div class="compare" style="grid-template-columns:repeat(%d,1fr)">' % max(2, len(secs))]
    for head, hfl, lines in secs:
        items = "".join('<div class="cmp-item">%s</div>' % inline(re.sub(r"^[-*]\s+", "", l.strip())) for l in lines)
        out.append('<div class="cmp%s"><div class="cmp-head">%s</div>%s</div>' %
                   (" hl" if "hl" in hfl else "", inline(head), items))
    out.append("</div>")
    return "\n".join(out)


RENDERERS = {
    "flow": render_flow,
    "bars": render_bars,
    "strip": render_strip,
    "bytes": render_bytes,
    "stack": render_stack,
    "cols": render_cols,
    "steps": render_steps,
    "stats": render_stats,
    "kv": render_kv,
    "tree": render_tree,
    "timeline": render_timeline,
    "compare": render_compare,
}

# Default figure tag (top-right label) per component, if the author gives none.
# Figure tags (the small label at the right of a figure header) are author-only;
# generic defaults like "MEASURED" or "FLOW" were noise.
DEFAULT_TAGS = {}


def render(name, info_attrs, text):
    lines = text.rstrip("\n").split("\n")
    opts, body = split_options(lines)
    for k, v in info_attrs.items():  # attributes on the fence line win
        opts.setdefault(k, v)
    return opts, RENDERERS[name](opts, body)


# ---------------------------------------------------------------- advanced primitives
def register(mod):
    RENDERERS.update(mod.RENDERERS)
    DEFAULT_TAGS.update(mod.DEFAULT_TAGS)
    OPTION_KEYS.update(mod.OPTION_KEYS)


if "diagrams" not in sys.modules:  # importing diagrams registers it (see the end of diagrams.py)
    import diagrams  # noqa: E402,F401
