"""
Advanced primitives for technical-manual:

  diagram   nested zones + boxes on a column grid, routed arrows, numbered markers, key
  sequence  actors, lifelines, messages, notes, phase dividers
  lanes     swimlane timeline (who is busy when)
  hexdump   offset / hex / ascii rows with coloured spans and a legend
  chart     line, area or column chart (SVG) with direct labels and annotations

Same contract as components.py: structure + classes only, the theme owns all colour.
"""
import json
import math
import re
import sys

from components import esc, inline, flags, fields, number, sections  # noqa: F401


# ===================================================================== diagram
NODE_RE = re.compile(r"^(?P<text>.*?)(?:\s+@(?P<cols>\d+(?:-\d+)?))?(?:\s+\^(?P<row>\d+))?"
                     r"(?:\s+#(?P<mark>\d+))?(?:\s+=(?P<id>[\w-]+))?\s*$")
EDGE_RE = re.compile(r"^-\s+(?P<a>[\w-]+)(?:\.(?P<pa>[lrtb]))?\s+(?P<op><->|->|--)\s+(?P<b>[\w-]+)(?:\.(?P<pb>[lrtb]))?"
                     r"(?:\s*:\s*(?P<label>.*))?$")


def _slug(s):
    return re.sub(r"[^a-z0-9]+", "-", s.lower()).strip("-")[:24] or "n"


def render_diagram(opts, body):
    """Boxes inside zones on a shared column grid.

    cols: 4                         number of grid columns (default 4)
    key: right | below | none       where the marker key goes (default: right if any key lines)
    zone Page · main thread {c2}    a zone; indent its children by two spaces
      load(url) / or <usd-viewer> @1 #1 =load
      three.js scene / meshes, then textures @3-4 #8 =scene
    zone Worker {c5} @1-4
      request / policy @1 #2 =req
      zone WASM · Rust {c6} @2-4
        add_layer / parse · deps @2 #4 =add
    - load -> req                   edge (ids from =id, or slug of the title)
    - req.b -> layers.t : fetch {dashed}     ports l r t b; {dashed} {both} {hl}
    #1 | Entry | a root .usd URL    key entry for marker 1

    Node columns are absolute (1-based); @2-3 spans. A node starts a new row when it
    begins at or left of the previous sibling's end; ^n forces row n in its container.
    Node flags: {hl} {dim} {ghost} {mono} {tall} {note}.  Zone flags: {c1}..{c9} {dashed}.
    """
    ncols = int(opts.get("cols", 4))
    root = {"kind": "zone", "children": [], "start": 1, "end": ncols, "depth": -1}
    stack = [(-1, root)]
    edges, keys, ids = [], [], {}
    for raw in body:
        if not raw.strip():
            continue
        indent = len(raw) - len(raw.lstrip(" "))
        line = raw.strip()
        if line.startswith("- ") and ("->" in line or " -- " in line):
            text, fl = flags(line)
            m = EDGE_RE.match(text)
            if m:
                edges.append({"a": m.group("a"), "b": m.group("b"), "pa": m.group("pa") or "", "pb": m.group("pb") or "",
                              "label": m.group("label") or "", "dashed": "dashed" in fl or m.group("op") == "--",
                              "both": m.group("op") == "<->", "hl": "hl" in fl, "noarrow": m.group("op") == "--"})
            continue
        km = re.match(r"^#(\d+)\s*\|\s*(.*)$", line)
        if km:
            f = fields(km.group(2), 2)
            keys.append((int(km.group(1)), f[0], f[1]))
            continue
        while stack and stack[-1][0] >= indent:
            stack.pop()
        parent = stack[-1][1]
        if line.startswith("zone "):
            rest = line[5:]
            colm = re.search(r"\s+@(\d+)(?:-(\d+))?", rest)
            text, fl = flags(re.sub(r"\s+@\d+(?:-\d+)?", "", rest))
            s = int(colm.group(1)) if colm else parent["start"]
            e = int(colm.group(2) or colm.group(1)) if colm else parent["end"]
            color = next((f for f in fl if re.match(r"^c\d$", f)), "")
            z = {"kind": "zone", "label": text.strip(), "start": s, "end": e, "children": [], "color": color,
                 "dashed": "dashed" in fl}
            parent["children"].append(z)
            stack.append((indent, z))
        else:
            text, fl = flags(line)
            m = NODE_RE.match(text)
            t = m.group("text").strip()
            if m.group("cols"):
                a, _, b = m.group("cols").partition("-")
                s, e = int(a), int(b or a)
            else:
                s, e = parent["start"], parent["start"]
            if t in ("~", ""):
                fl = fl | {"spacer"}
                t = ""
            nid = m.group("id") or _slug(t.split(" / ")[0]) or "spacer%d" % len(ids)
            node = {"kind": "node", "text": t, "start": s, "end": e, "row": int(m.group("row")) if m.group("row") else None,
                    "mark": m.group("mark"), "id": nid, "flags": fl}
            ids[nid] = node
            parent["children"].append(node)

    uid = "dg%x" % (abs(hash(json.dumps(body))) % 0xFFFFFF)

    def place(container):
        row, last_end = 1, 0
        for ch in container["children"]:
            ch["_parent"] = id(container)
            if ch.get("row"):
                row = ch["row"]
            elif ch["start"] <= last_end:
                row += 1
            ch["_row"] = row
            last_end = ch["end"]

    def emit(container, offset):
        place(container)
        out = []
        for ch in container["children"]:
            cs, ce = ch["start"] - offset, ch["end"] - offset
            grid = "grid-column:%d / %d; grid-row:%d" % (cs, ce + 1, ch["_row"] + (1 if container.get("label") else 0))
            if ch["kind"] == "zone":
                cls = "dg-zone %s%s" % (ch["color"], " dashed" if ch["dashed"] else "")
                inner = emit(ch, ch["start"] - 1)
                out.append('<div class="%s" style="%s"><div class="dg-zlabel">%s</div>%s</div>' %
                           (cls, grid, inline(ch["label"]), inner))
            else:
                parts = [p.strip() for p in ch["text"].split(" / ")]
                fl = ch["flags"]
                cls = "dg-node" + "".join(" " + f for f in ("hl", "dim", "ghost", "mono", "tall", "note", "spacer") if f in fl)
                mark = '<span class="dg-mark">%s</span>' % ch["mark"] if ch["mark"] else ""
                body_ = '<div class="nt">%s</div>' % inline(parts[0]) + "".join('<div class="ns">%s</div>' % inline(p) for p in parts[1:])
                out.append('<div class="%s" data-id="%s" style="%s">%s%s</div>' % (cls, esc(ch["id"]), grid, mark, body_))
        return "".join(out)

    grid_html = emit(root, 0)
    missing = [e for e in edges if e["a"] not in ids or e["b"] not in ids]
    edges = [e for e in edges if e["a"] in ids and e["b"] in ids]
    loops = "".join(" loop-" + p for p in ("t", "b") if any(e["pa"] == e["pb"] == p for e in edges))
    # column gap grows with the longest label on a horizontal edge, so labels never sit on boxes
    def horizontal(e):
        a, b = ids[e["a"]], ids[e["b"]]
        if e["pa"] in ("t", "b") or (e["pa"] and e["pa"] == e["pb"]):
            return False
        return a.get("_parent") == b.get("_parent") and a.get("_row") == b.get("_row")
    longest = max([len(e["label"]) for e in edges if e["label"] and horizontal(e)] + [0])
    gx = max(14, min(76, longest * 4.7 + 16))
    diag = ('<div class="dg%s" id="%s" style="--cols:%d;--gx:%.0fpt" data-edges=\'%s\'>%s<svg class="dg-edges"></svg></div>' %
            (loops, uid, ncols, gx, esc(json.dumps(edges)), grid_html))
    where = opts.get("key", "right" if keys else "none")
    if missing:
        diag += '<div class="fig-note">unknown edge ids: %s</div>' % esc(", ".join("%s→%s" % (e["a"], e["b"]) for e in missing))
    if keys and where != "none":
        k = "".join('<div class="dg-key-row"><span class="dg-mark static">%d</span><div><div class="dk-t">%s</div>'
                    '<div class="dk-d">%s</div></div></div>' % (n, inline(t), inline(d)) for n, t, d in sorted(keys))
        key_html = '<div class="dg-key"><div class="dg-key-h">Key</div>%s</div>' % k
        return '<div class="dg-wrap key-%s">%s%s</div>' % (where, diag, key_html)
    return diag


# ===================================================================== sequence
def render_sequence(opts, body):
    """Native sequence diagram.

    actors: Host | Harness | Storage {hl} | Model
    Host -> Harness : submit()
    Harness --> Host : ack            (dashed: a reply)
    Harness -> Harness : retry        (self message)
    Harness => Storage : append {hl}  (=> thick: the important call)
    note Harness : waits for a lease  (note on one actor;  note A..C : spans actors)
    == recovery ==                    (phase divider)
    """
    actors_line = opts.get("actors") or ""
    actors = []
    for a in actors_line.split("|"):
        t, fl = flags(a.strip())
        if t:
            actors.append((t, fl))
    names = [a[0] for a in actors]
    n = max(1, len(actors))
    idx = {name: i for i, name in enumerate(names)}

    def col(name):
        return idx.get(name.strip(), 0)

    rows = []
    for line in body:
        if not line.strip():
            continue
        text, fl = flags(line.strip())
        if text.startswith("=="):
            rows.append('<div class="sq-div"><span>%s</span></div>' % inline(text.strip("= ").strip()))
            continue
        nm = re.match(r"^note\s+([^:]+?)(?:\.\.([^:]+?))?\s*:\s*(.*)$", text)
        if nm:
            a, b = col(nm.group(1)), col(nm.group(2) or nm.group(1))
            lo, hi = min(a, b), max(a, b)
            left = (lo + 0.08) / n * 100
            width = (hi - lo + 0.84) / n * 100
            rows.append('<div class="sq-row note"><div class="sq-note%s" style="left:%.2f%%;width:%.2f%%">%s</div></div>' %
                        (" hl" if "hl" in fl else "", left, width, inline(nm.group(3))))
            continue
        mm = re.match(r"^(.+?)\s*(-->|->|=>)\s*(.+?)\s*:\s*(.*)$", text) or re.match(r"^(.+?)\s*(-->|->|=>)\s*(.+?)\s*$", text)
        if not mm:
            continue
        a, op, b = col(mm.group(1)), mm.group(2), col(mm.group(3))
        label = mm.group(4) if mm.lastindex and mm.lastindex >= 4 else ""
        kind = {"-->": " reply", "=>": " thick", "->": ""}[op] + (" hl" if "hl" in fl else "")
        if a == b:
            left = (a + 0.5) / n * 100
            rows.append('<div class="sq-row self"><div class="sq-self%s" style="left:%.2f%%"></div>'
                        '<div class="sq-lab self" style="left:calc(%.2f%% + 26pt)">%s</div></div>' % (kind, left, left, inline(label)))
            continue
        lo, hi = min(a, b), max(a, b)
        left, width = (lo + 0.5) / n * 100, (hi - lo) / n * 100
        dirc = " rtl" if b < a else ""
        rows.append('<div class="sq-row"><div class="sq-lab" style="left:%.2f%%;width:%.2f%%">%s</div>'
                    '<div class="sq-arrow%s%s" style="left:%.2f%%;width:%.2f%%"></div></div>' %
                    (left, width, inline(label), kind, dirc, left, width))
    heads = "".join('<div class="sq-actor%s">%s</div>' % (" hl" if "hl" in fl else "", inline(t)) for t, fl in actors)
    lines = "".join('<div class="sq-life" style="left:%.3f%%"></div>' % ((i + 0.5) / n * 100) for i in range(n))
    return ('<div class="sq" style="--n:%d"><div class="sq-heads">%s</div><div class="sq-body">%s%s</div></div>' %
            (n, heads, lines, "".join(rows)))


# ===================================================================== lanes
def render_lanes(opts, body):
    """Swimlanes over time.

    range: 0 | 100 | ms            start | end | unit (ticks drawn at nice steps)
    Page | 0-8 load {dim} | 60-85 meshes as they arrive {hl} | 85-100 textures
    Worker | 8-20 init | 20-55 fetch ⇄ add_layer
    mark: 55 | on screen
    mark: 100 | done
    """
    rng = fields(opts.get("range", "0 | 100 | "), 3)
    t0, t1, unit = float(number(rng[0]) or 0), float(number(rng[1]) or 100), rng[2]
    span = (t1 - t0) or 1
    marks, lanes = [], []
    for line in body:
        if line.startswith("mark:"):
            f = fields(line[5:], 2)
            marks.append((float(number(f[0]) or 0), f[1]))
            continue
        if not line.strip():
            continue
        parts = [p.strip() for p in line.split("|")]
        name, segs = parts[0], []
        for p in parts[1:]:
            t, fl = flags(p)
            m = re.match(r"^([\d.]+)\s*-\s*([\d.]+)\s*(.*)$", t)
            if m:
                segs.append((float(m.group(1)), float(m.group(2)), m.group(3), fl))
        lanes.append((name, segs))
    step = 10 ** math.floor(math.log10(span))
    if span / step < 4:
        step /= 2
    if span / step > 10:
        step *= 2
    ticks = []
    v = math.ceil(t0 / step) * step
    while v <= t1 + 1e-9:
        ticks.append(v)
        v += step
    names = "".join('<div class="ln-name">%s</div>' % inline(nm) for nm, _ in lanes)
    tracks = []
    for name, segs in lanes:
        bars = ""
        segs_sorted = sorted(segs, key=lambda x: x[0])
        for i, (a, b, t, fl) in enumerate(segs_sorted):
            w = max(0.6, (b - a) / span * 100)
            plain = re.sub(r"[`*]", "", t)
            need = len(plain) * 0.95 + 2.5          # % of a ~400pt track
            out = ""
            if w < need:
                free_l = (a - (segs_sorted[i - 1][1] if i else t0)) / span * 100
                free_r = ((segs_sorted[i + 1][0] if i + 1 < len(segs_sorted) else t1) - b) / span * 100
                if free_r >= need:
                    out = " out-r"
                elif free_l >= need:
                    out = " out-l"
            bars += '<div class="ln-seg%s%s" style="left:%.2f%%;width:%.2f%%"><span>%s</span></div>' % (
                "".join(" " + f for f in ("hl", "dim") if f in fl), out, (a - t0) / span * 100, w, inline(t))
        tracks.append('<div class="ln-track">%s</div>' % bars)
    axis = "".join('<span style="left:%.2f%%">%s</span>' % ((t - t0) / span * 100, ("%g" % t) + (unit if t == ticks[-1] else ""))
                   for t in ticks)
    mk = "".join('<div class="ln-mark%s" style="left:%.2f%%"><span>%s</span></div>' %
                 (" end" if (t - t0) / span > 0.85 else "", (t - t0) / span * 100, inline(l)) for t, l in marks)
    grid = "".join('<div class="ln-tick" style="left:%.2f%%"></div>' % ((t - t0) / span * 100) for t in ticks[1:-1])
    return ('<div class="ln%s"><div class="ln-names">%s</div><div class="ln-right"><div class="ln-tracks">%s%s</div>'
            '<div class="ln-axis">%s</div></div></div>' % (" has-marks" if marks else "", names, grid + "".join(tracks),
                                                          mk, axis))


# ===================================================================== hexdump
def render_hexdump(opts, body):
    """Classic hex dump with coloured spans.

    offset: 0                       first offset shown
    text: GGUF                      (optional) bytes from a string instead of hex lines
    47 47 55 46 03 00 00 00 ...     hex bytes, any number per line
    span 0-3 | magic "GGUF"         byte range (inclusive) and legend label; spans cycle colours
    span 4-7 | version u32 = 3 {hl}
    width: 16                       bytes per row (8 or 16)
    """
    data, spans = [], []
    for line in body:
        s = line.strip()
        if not s:
            continue
        if s.startswith("span "):
            f = fields(s[5:], 2)
            t, fl = flags(f[1])
            m = re.match(r"^(\d+)(?:-(\d+))?$", f[0].strip())
            if m:
                spans.append((int(m.group(1)), int(m.group(2) or m.group(1)), t, fl))
            continue
        data += [int(h, 16) for h in re.findall(r"\b[0-9a-fA-F]{2}\b", s)]
    if opts.get("text"):
        data = list(opts["text"].encode("utf-8").decode("unicode_escape").encode("latin-1")) + data
    width = int(opts.get("width", 16))
    base = int(number(opts.get("offset", "0")) or 0)
    owner = {}
    for k, (a, b, t, fl) in enumerate(spans):
        for i in range(a, b + 1):
            owner[i] = k
    rows = []
    for r in range(0, len(data), width):
        chunk = data[r:r + width]
        hexs, asc = [], []
        for j, byte in enumerate(chunk):
            k = owner.get(r + j)
            names = (["s%d" % (k % 6 + 1)] if k is not None else []) + (["gap"] if width >= 16 and j == width // 2 else [])
            c = (' class="%s"' % " ".join(names)) if names else ""
            hexs.append("<span%s>%02x</span>" % (c, byte))
            ch = chr(byte) if 32 <= byte < 127 else "·"
            ac = (' class="s%d"' % (k % 6 + 1)) if k is not None else ""
            asc.append("<span%s>%s</span>" % (ac, esc(ch)))
        rows.append('<div class="hx-off">%08x</div><div class="hx-hex">%s</div><div class="hx-asc">%s</div>' %
                    (base + r, "".join(hexs), "".join(asc)))
    legend = "".join('<span class="hx-leg s%d%s"><i></i>%s</span>' % (k % 6 + 1, " hl" if "hl" in fl else "", inline(t))
                     for k, (a, b, t, fl) in enumerate(spans))
    return '<div class="hx">%s</div>%s' % ("".join(rows), ('<div class="hx-legend">%s</div>' % legend) if legend else "")


# ===================================================================== chart
def _nice(vmax, ticks=5):
    """Nice tick step for ~`ticks` intervals; top is the max rounded up to a step."""
    if vmax <= 0:
        return 1, 0.2
    raw = vmax / ticks
    e = 10 ** math.floor(math.log10(raw))
    step = next(m * e for m in (1, 2, 2.5, 5, 10) if m * e >= raw - 1e-12)
    top = math.ceil(vmax / step - 1e-9) * step
    return top, step


def _fmt(v):
    if abs(v) >= 1e6:
        return ("%.1fM" % (v / 1e6)).replace(".0M", "M")
    if abs(v) >= 1e4:
        return ("%.0fk" % (v / 1e3))
    if v == int(v):
        return "{:,}".format(int(v))
    return ("%.2f" % v).rstrip("0").rstrip(".")


def render_chart(opts, body):
    """Line / area / column chart, direct-labelled.

    type: line | area | column        (default line)
    series: Pack | Loose              series names, in column order
    hl: Pack                          the series to emphasise (default: first)
    y: MB                             y-axis unit label
    max: 200                          fix the y maximum
    2010 | 1.2 | 15                   x | value per series   (blank = missing)
    mark: 2020 | SHA-256 lands        vertical annotation at an x value
    band: 2014-2016 | rewrite         shaded range annotation
    """
    kind = opts.get("type", "line")
    names = [s.strip() for s in opts.get("series", "").split("|") if s.strip()]
    hl = opts.get("hl", names[0] if names else "")
    xs, cols, marks, bands = [], [], [], []
    for line in body:
        s = line.strip()
        if not s:
            continue
        if s.startswith("mark:"):
            marks.append(fields(s[5:], 2))
            continue
        if s.startswith("band:"):
            f = fields(s[5:], 2)
            bands.append((f[0].split("-")[0].strip(), f[0].split("-")[-1].strip(), f[1]))
            continue
        f = fields(s)
        xs.append(f[0])
        cols.append([number(v) if v != "" else None for v in f[1:]])
    ns = max((len(c) for c in cols), default=1)
    if not names:
        names = ["Series %d" % (i + 1) for i in range(ns)]
        hl = names[0]
    vals = [v for c in cols for v in c if v is not None]
    top, step = _nice(float(number(opts.get("max")) or (max(vals) if vals else 1)))
    W, H, L, R, T, B = 640, 250, 46, 118 if kind != "column" else 20, 16, 30
    pw, ph = W - L - R, H - T - B
    n = len(xs)

    def X(i):
        if kind == "column":
            return L + pw * (i + 0.5) / max(n, 1)
        return L + (pw * i / (n - 1) if n > 1 else pw / 2)

    def Y(v):
        return T + ph * (1 - v / top)

    svg = ['<svg class="ch" viewBox="0 0 %d %d" xmlns="http://www.w3.org/2000/svg">' % (W, H)]
    xi = {x: i for i, x in enumerate(xs)}
    for a, b, lab in bands:
        if a in xi and b in xi:
            x0, x1 = X(xi[a]), X(xi[b])
            svg.append('<rect class="ch-band" x="%.1f" y="%d" width="%.1f" height="%d"/>' % (x0, T, x1 - x0, ph))
            svg.append('<text class="ch-note" x="%.1f" y="%d">%s</text>' % (x0 + 4, T + 10, esc(lab)))
    v = 0.0
    while v <= top + 1e-9:
        y = Y(v)
        svg.append('<line class="ch-grid%s" x1="%d" x2="%d" y1="%.1f" y2="%.1f"/>' % (" base" if v == 0 else "", L, L + pw, y, y))
        svg.append('<text class="ch-tick" x="%d" y="%.1f" text-anchor="end">%s</text>' % (L - 6, y + 3, _fmt(v)))
        v += step
    if opts.get("y"):
        svg.append('<text class="ch-unit" x="%d" y="%d">%s</text>' % (L - 6 - 0, T - 5, esc(opts["y"])))
    every = max(1, math.ceil(n / 12))
    for i, x in enumerate(xs):
        if i % every == 0 or i == n - 1:
            svg.append('<text class="ch-tick" x="%.1f" y="%d" text-anchor="middle">%s</text>' % (X(i), T + ph + 16, esc(x)))
    if kind == "column":
        gw = pw / max(n, 1) * 0.72
        bw = gw / ns
        for i, c in enumerate(cols):
            for k, v in enumerate(c):
                if v is None:
                    continue
                cls = "hl" if names[k] == hl else "s%d" % k
                x = X(i) - gw / 2 + k * bw
                svg.append('<rect class="ch-col %s" x="%.1f" y="%.1f" width="%.1f" height="%.1f"/>' % (cls, x + 0.5, Y(v), bw - 1, T + ph - Y(v)))
        if ns > 1:
            lg = "".join('<tspan class="ch-lg %s">■ %s</tspan>   ' % ("hl" if nm == hl else "s%d" % k, esc(nm)) for k, nm in enumerate(names))
            svg.append('<text class="ch-tick" x="%d" y="%d">%s</text>' % (L + 4, T + 8, lg))
    else:
        order = sorted(range(ns), key=lambda k: names[k] == hl)  # highlighted drawn last
        label_ys = []
        for k in order:
            pts = [(X(i), Y(c[k])) for i, c in enumerate(cols) if k < len(c) and c[k] is not None]
            if not pts:
                continue
            cls = "hl" if names[k] == hl else "s%d" % k
            d = "M" + " L".join("%.1f %.1f" % p for p in pts)
            if kind == "area":
                svg.append('<path class="ch-area %s" d="%s L%.1f %.1f L%.1f %.1f Z"/>' % (cls, d, pts[-1][0], T + ph, pts[0][0], T + ph))
            svg.append('<path class="ch-line %s" d="%s"/>' % (cls, d))
            lx, ly = pts[-1]
            svg.append('<circle class="ch-dot %s" cx="%.1f" cy="%.1f" r="2.6"/>' % (cls, lx, ly))
            last = [c[k] for c in cols if k < len(c) and c[k] is not None][-1]
            yy = ly
            for prev in label_ys:
                if abs(prev - yy) < 11:
                    yy = prev + 11 if yy >= prev else prev - 11
            label_ys.append(yy)
            svg.append('<text class="ch-label %s" x="%.1f" y="%.1f">%s <tspan class="ch-val">%s</tspan></text>' %
                       (cls, lx + 7, yy + 3.5, esc(names[k]), _fmt(last)))
    for x, lab in marks:
        if x in xi:
            px = X(xi[x])
            svg.append('<line class="ch-mark" x1="%.1f" x2="%.1f" y1="%d" y2="%d"/>' % (px, px, T, T + ph))
            svg.append('<text class="ch-note" x="%.1f" y="%d">%s</text>' % (px + 4, T + 22, esc(lab)))
    svg.append("</svg>")
    return "".join(svg)


RENDERERS = {
    "diagram": render_diagram,
    "sequence": render_sequence,
    "lanes": render_lanes,
    "hexdump": render_hexdump,
    "chart": render_chart,
}
DEFAULT_TAGS = {}
OPTION_KEYS = {"actors", "range", "offset", "text", "width", "type", "series", "hl", "y", "key"}


import components as _C  # noqa: E402
_C.register(sys.modules[__name__])
