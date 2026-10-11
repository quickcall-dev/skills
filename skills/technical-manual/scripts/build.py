#!/usr/bin/env python3
"""
build.py: turn a Markdown file into a technical-manual style PDF.

    python3 build.py input.md -o manual.pdf            # PDF (+ lint report)
    python3 build.py input.md -o manual.pdf --html out.html
    python3 build.py input.md --html-only out.html      # skip Chromium

Structure is read from headings:
    frontmatter     title, subtitle, name, edition, description, cover (dark|light)
    # Heading       a Part (dark opener page)   [the first H1 is the title if no frontmatter title]
    ## Heading      a Chapter (new page, numbered part.chapter)
    ### / ####      sections / mono labels
A paragraph that is entirely *italic* right after a heading becomes its dek.
See references/components.md for every block-level component.
"""
import argparse
import base64
import datetime
import hashlib
import html
import json
import re
import shlex
import sys
import urllib.parse
from pathlib import Path

import yaml
from markdown_it import MarkdownIt

sys.path.insert(0, str(Path(__file__).resolve().parent))
import components as C  # noqa: E402

SKILL = Path(__file__).resolve().parent.parent
ASSETS = SKILL / "assets"

# Figures that are drawings get the drafting grid (dots or lines) as their ground.
CANVAS = {"diagram", "flow", "sequence", "lanes", "stack", "strip", "bytes", "mermaid", "timeline", "steps"}

CALLOUT_LABELS = {
    "note": "Note", "tip": "Tip", "important": "Rule", "rule": "Rule", "warning": "Warning",
    "caution": "Footgun", "danger": "Footgun", "footgun": "Footgun", "rules": "What this rules out", "verify": "Verify",
}


# ============================================================== parsing
def split_frontmatter(text):
    if text.startswith("---\n"):
        end = text.find("\n---", 4)
        if end != -1:
            fm = yaml.safe_load(text[4:end]) or {}
            return fm, text[end + 4:].lstrip("\n")
    return {}, text


def scan_headings(lines):
    """Yield (index, level, text) for H1/H2 outside fenced code."""
    fence = None
    for i, line in enumerate(lines):
        m = re.match(r"^(\s*)(`{3,}|~{3,})", line)
        if m:
            mark = m.group(2)
            if fence is None:
                fence = mark[0] * len(mark)
            elif mark.startswith(fence):
                fence = None
            continue
        if fence:
            continue
        h = re.match(r"^(#{1,2})\s+(.+?)\s*#*\s*$", line)
        if h:
            yield i, len(h.group(1)), h.group(2)


NUM_PREFIX = re.compile(r"^(?:(?:part|chapter|section)\s+)?(?:[0-9]+(?:\.[0-9]+)*|[IVXLC]+)[.:)\s-]+\s*", re.I)


def clean_heading(t):
    t = NUM_PREFIX.sub("", t).strip()
    return t or "Untitled"


def take_dek(md_text):
    """If the body starts with a paragraph that is entirely italic, return (dek, rest)."""
    s = md_text.lstrip("\n")
    m = re.match(r"^(\*|_)(?!\*)([^\n]+(?:\n(?!\n)[^\n]+)*)\1[ \t]*(?:\n\n|\n?$)", s)
    if m and not m.group(2).startswith(("*", "_")):
        return m.group(2).strip(), s[m.end():]
    return None, md_text


def build_model(text, fm):
    lines = text.split("\n")
    heads = list(scan_headings(lines))
    title = fm.get("title")
    if not title:
        h1s = [h for h in heads if h[1] == 1]
        if h1s:
            title = h1s[0][2]
            idx = h1s[0][0]
            heads = [h for h in heads if h[0] != idx]
            lines[idx] = ""
        else:
            title = "Technical Manual"

    def chunk(a, b):
        return "\n".join(lines[a:b])

    model = {"title": title, "preamble": "", "front": [], "parts": []}
    first = heads[0][0] if heads else len(lines)
    model["preamble"] = chunk(0, first).strip()
    has_parts = any(h[1] == 1 for h in heads)
    cur_part = None
    for k, (i, level, htext) in enumerate(heads):
        end = heads[k + 1][0] if k + 1 < len(heads) else len(lines)
        body = chunk(i + 1, end)
        if level == 1:
            dek, rest = take_dek(body)
            if not dek:
                # first plain paragraph of the part intro becomes the dek
                paras = [p.strip() for p in body.strip().split("\n\n") if p.strip()]
                dek = re.sub(r"[*_]", "", paras[0]) if paras and not paras[0].startswith(("```", "|", "-", ">")) else None
            cur_part = {"title": clean_heading(htext), "dek": dek, "chapters": []}
            model["parts"].append(cur_part)
        else:
            dek, rest = take_dek(body)
            ch = {"title": clean_heading(htext), "dek": dek, "md": rest}
            if has_parts and cur_part is None:
                model["front"].append(ch)
            elif cur_part is None:
                cur_part = {"title": None, "dek": None, "chapters": [], "implicit": True}
                model["parts"].append(cur_part)
                cur_part["chapters"].append(ch)
            else:
                cur_part["chapters"].append(ch)
    model["has_parts"] = has_parts
    return model


# ============================================================== rendering
def parse_info(info):
    """'python title="x.py" path=src/ long' -> ('python', {title:..., path:..., long:True})"""
    info = info.strip()
    if not info:
        return "", {}
    try:
        toks = shlex.split(info)
    except ValueError:
        toks = info.split()
    lang, attrs = toks[0], {}
    for t in toks[1:]:
        if "=" in t:
            k, v = t.split("=", 1)
            attrs[k] = v
        else:
            attrs[t] = True
    return lang, attrs


def highlight(code, lang):
    try:
        from pygments import highlight as ph
        from pygments.formatters import HtmlFormatter
        from pygments.lexers import get_lexer_by_name
        from pygments.util import ClassNotFound
        try:
            lexer = get_lexer_by_name(lang or "text")
        except ClassNotFound:
            lexer = get_lexer_by_name("text")
        return ph(code, lexer, HtmlFormatter(nowrap=True))
    except Exception:
        return html.escape(code)


def gh_slug(text):
    """GitHub's heading anchor: lowercase, drop punctuation except - and _, spaces to hyphens."""
    t = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", text)          # [text](url) -> text
    t = re.sub(r"<[^>]+>", "", t).strip().lower()
    t = re.sub(r"[^\w\- ]", "", t)
    return t.replace(" ", "-")


def github_anchors(body, model, has_parts):
    """Map GitHub-style anchors (#android, #android-1, …) to this manual's element ids."""
    lines, fence, seen, ours, out = body.split("\n"), None, {}, {}, {}
    ch_seen, part_seen = {}, {}
    chapters = [c for p in model["parts"] for c in p["chapters"]]
    for line in lines:
        m = re.match(r"^\s*(`{3,}|~{3,})", line)
        if m:
            fence = None if fence and m.group(1).startswith(fence) else (fence or m.group(1))
            continue
        h = None if fence else re.match(r"^(#{1,6})\s+(.+?)\s*#*\s*$", line)
        if not h:
            continue
        level, text = len(h.group(1)), h.group(2)
        base = gh_slug(text)
        n = seen.get(base, 0)
        seen[base] = n + 1
        anchor = base if n == 0 else "%s-%d" % (base, n)
        if level >= 3:
            k = slug(text)
            c = ours.get(k, 0)
            ours[k] = c + 1
            out[anchor] = "s-" + k if c == 0 else "s-%s-%d" % (k, c + 1)
        elif level == 2:
            t = clean_heading(text)
            i = ch_seen.get(t, 0)
            ch_seen[t] = i + 1
            hits = [c for c in chapters if c["title"] == t]
            if i < len(hits):
                out[anchor] = hits[i]["id"]
        elif level == 1 and has_parts:
            t = clean_heading(text)
            idx = [j for j, p in enumerate(model["parts"]) if p["title"] == t]
            i = part_seen.get(t, 0)
            part_seen[t] = i + 1
            if i < len(idx):
                out[anchor] = "part-%d" % (idx[i] + 1)
    return out


def slug(s):
    return re.sub(r"[^a-z0-9]+", "-", s.lower()).strip("-")[:60]



def _outside_code(line, pattern, repl):
    """Apply a regex substitution only where the match does not start inside a `code span`."""
    spans = [(m.start(), m.end()) for m in re.finditer(r"`[^`]*`", line)]
    def guarded(m):
        if any(a < m.start() < b for a, b in spans):
            return m.group(0)
        return repl(m)
    return re.sub(pattern, guarded, line)

class Renderer:
    def __init__(self, base_dir, doc_name):
        self.md = MarkdownIt("commonmark", {"html": True, "typographer": True})
        self.md.enable(["table", "strikethrough", "replacements", "smartquotes"])
        try:  # bare URLs become links when linkify-it-py is installed
            import linkify_it  # noqa: F401
            self.md.options["linkify"] = True
            self.md.enable("linkify")
        except Exception:
            pass

        def link_open(r, tokens, idx, options, env):
            href = tokens[idx].attrGet("href") or ""
            if href.startswith("#"):
                return '<a class="xref" data-xref="%s">' % C.esc(urllib.parse.unquote(href[1:]))
            tokens[idx].attrSet("class", "ext")
            return r.renderToken(tokens, idx, options, env)
        self.md.add_render_rule("link_open", link_open)
        # cross-reference targets: key -> (element id, default link text)
        self.targets = {}
        self.section_ids = set()
        self.figures = []  # (id, number, title, part/chapter colour class)
        self.index = []    # (term, anchor id)
        self.doc_ids = set()
        self.cur_color = "c1"
        self.sep = "."   # set to "·" by the signature layer: 2·3, Figure 3·4
        self.base_dir = base_dir
        self.doc_name = doc_name
        self.fig_prefix = "1"
        self.fig_n = 0
        self.cover_hero = []
        self.warnings = []

    def disp(self, num):
        return str(num).replace(".", self.sep)

    # ---- helpers
    def inline(self, text):
        return self.md.renderInline(text)

    def blocks(self, tokens):
        out, i = [], 0
        while i < len(tokens):
            t = tokens[i]
            if t.nesting == 1:
                depth, j = 0, i
                while j < len(tokens):
                    depth += tokens[j].nesting
                    if depth == 0:
                        break
                    j += 1
                out.append(tokens[i:j + 1])
                i = j + 1
            else:
                out.append([t])
                i += 1
        return out

    @staticmethod
    def para_text(block):
        if block and block[0].type == "paragraph_open" and len(block) == 3:
            return block[1].content
        return None

    def next_caption(self, blocks, k):
        if k + 1 < len(blocks):
            txt = self.para_text(blocks[k + 1])
            if txt and re.match(r"^caption:\s*", txt, re.I):
                return re.sub(r"^caption:\s*", "", txt, flags=re.I), True
        return None, False

    def figure(self, body_html, opts, comp, caption, fig_id=None):
        self.fig_n += 1
        num = "%s.%d" % (self.fig_prefix, self.fig_n)
        title = opts.get("title", "")
        tag = opts.get("tag", "")
        sub = opts.get("sub", "")
        note = opts.get("note", "") if comp != "strip" else ""
        cap = caption or opts.get("caption", "")
        fid = fig_id or "fig-" + num.replace(".", "-")
        shown = "Fig. " + self.disp(num)
        self.targets.setdefault("fig:" + num, (fid, shown))
        self.targets.setdefault("id:" + fid, (fid, shown))
        if title:
            self.targets.setdefault("fig:" + slug(re.sub(r"[`*]", "", title)), (fid, shown))
        self.figures.append((fid, num, title, self.cur_color))
        h = ['<figure class="fig-wrap" id="%s">' % fid]
        h.append('<div class="tm-fig%s">' % ("" if cap else " no-cap"))
        h.append('<div class="fig-head"><span class="fig-num">Figure %s</span><div class="fig-titles">%s%s</div>'
                 '<span class="fig-tag">%s</span></div>' % (
                     self.disp(num), ('<span class="fig-title">%s</span>' % C.inline(title)) if title else "",
                     ('<span class="fig-sub">%s</span>' % C.inline(sub)) if sub else "", C.esc(tag)))
        h.append('<div class="fig-body%s">%s</div>' % (" canvas" if comp in CANVAS else "", body_html))
        if note:
            h.append('<div class="fig-note">%s</div>' % self.inline(note))
        h.append("</div>")
        if cap:
            h.append('<figcaption class="fig-cap">%s</figcaption>' % self.inline(cap))
        h.append("</figure>")
        return "\n".join(h)

    # ---- block renderers
    def render_fence(self, tok, caption):
        lang, attrs = parse_info(tok.info)
        lang_l = lang.lower()
        code = tok.content
        # automatic upgrade: an unlabelled box-drawing tree becomes the tree component
        if lang_l in ("", "text", "txt", "plain") and re.search(r"^[\s│]*[├└]──", code, re.M):
            lang_l = "tree"
        if lang_l in C.RENDERERS:
            try:
                opts, inner = C.render(lang_l, {k: v for k, v in attrs.items() if v is not True}, code)
            except Exception as e:  # never kill a build over one figure
                self.warnings.append({"kind": "component-error", "component": lang_l, "error": str(e)})
                return self.render_code(code, "text", {"title": "%s (failed to render)" % lang_l}, caption)
            if attrs.get("cover") or opts.get("cover"):
                label = ('<div class="cover-label">%s</div>' % C.inline(opts["title"])) if opts.get("title") else ""
                cap = ('<div class="cover-cap">%s</div>' % self.inline(opts["caption"])) if opts.get("caption") else ""
                if lang_l in CANVAS:
                    inner = '<div class="fig-body canvas">%s</div>' % inner
                self.cover_hero.append('<div class="cover-block cover-%s">%s%s%s</div>' % (lang_l, label, inner, cap))
                return ""
            if attrs.get("nofig") or opts.get("nofig"):
                return '<div class="tm-inline" style="margin:12pt 0">%s</div>' % inner
            return self.figure(inner, opts, lang_l, caption)
        if lang_l == "panels":
            return self.render_panels(code, attrs, caption)
        if lang_l == "mermaid":
            src = code
            opts = {}
            # allow '%% title: ...' style options at the top of mermaid source
            for m in re.finditer(r"^%%\s*(title|tag|sub|note):\s*(.+)$", code, re.M):
                opts[m.group(1)] = m.group(2).strip()
            for k, v in attrs.items():
                if v is not True:
                    opts[k] = v
            inner = '<div class="mermaid-wrap"><pre class="mermaid">%s</pre></div>' % html.escape(src)
            return self.figure(inner, opts, "mermaid", caption)
        return self.render_code(code, lang, attrs, caption)

    def render_panels(self, code, attrs, caption):
        """Several components side by side under one figure number.

        Outer options first (title, sub, tag, widths: 1.4 1 1), then nested blocks
        fenced with ``` inside a ```` (four-backtick) panels block. Each inner title
        becomes a sub-caption: 'Fig. 1 — elevation'."""
        m = re.search(r"^`{3,}", code, re.M)
        head = code[:m.start()] if m else code
        opts, _ = C.split_options(head.strip("\n").split("\n")) if head.strip() else ({}, [])
        for k, v in attrs.items():
            if v is not True:
                opts.setdefault(k, v)
        cells = []
        for i, mm in enumerate(re.finditer(r"^(`{3,})(\w+)([^\n]*)\n(.*?)^\1\s*$", code, re.M | re.S)):
            lang, info, inner_src = mm.group(2).lower(), mm.group(3), mm.group(4)
            _, iattrs = parse_info(lang + info)
            if lang in C.RENDERERS:
                try:
                    o, inner = C.render(lang, {k: v for k, v in iattrs.items() if v is not True}, inner_src)
                except Exception as e:
                    self.warnings.append({"kind": "component-error", "component": lang, "error": str(e)})
                    continue
            elif lang == "mermaid":
                o, inner = {}, '<div class="mermaid-wrap"><pre class="mermaid">%s</pre></div>' % html.escape(inner_src)
            else:
                o, inner = {}, '<pre class="hl panel-code"><code>%s</code></pre>' % highlight(inner_src, lang)
            cap = o.get("title", "")
            cells.append('<div class="pn-cell"><div class="pn-body">%s</div>%s</div>' % (
                inner, ('<div class="pn-cap">Fig. %d — %s</div>' % (i + 1, C.inline(cap))) if cap else ""))
        widths = opts.get("widths", "")
        tmpl = " ".join("%sfr" % w for w in widths.split()) if widths else "repeat(%d, minmax(0,1fr))" % max(1, len(cells))
        body = '<div class="pn" style="grid-template-columns:%s">%s</div>' % (tmpl, "".join(cells))
        return self.figure(body, opts, "panels", caption)

    def render_code(self, code, lang, attrs, caption):
        n_lines = code.count("\n")
        title = attrs.get("title") or attrs.get("file") or ""
        path = attrs.get("path") or attrs.get("note") or ""
        langname = {"sh": "shell", "bash": "shell", "console": "shell", "py": "python", "js": "javascript",
                    "ts": "typescript", "": "text"}.get(lang.lower(), lang.lower())
        head = ""
        if title or path or langname:
            head = ('<div class="code-head"><span class="file">%s</span><span class="path">%s</span>'
                    '<span class="lang">%s</span></div>' % (C.esc(title), C.inline(path), C.esc(langname)))
        long = " long" if n_lines > 38 or attrs.get("long") else ""
        cap_cls = "" if caption else " no-cap"
        h = '<figure class="tm-code%s%s">%s<pre class="hl"><code>%s</code></pre></figure>' % (
            long, cap_cls, head, highlight(code.rstrip("\n"), lang.lower()))
        if caption:
            h += '<figcaption class="fig-cap">%s</figcaption>' % self.inline(caption)
        return h

    def render_blockquote(self, block):
        inner = self.md.renderer.render(block[1:-1], self.md.options, {})
        m = re.match(r"^\s*<p>\[!([A-Za-z]+)\][ \t]*([^\n<]*)(\n|</p>)", inner)
        if m:
            kind = m.group(1).lower()
            # the rail holds only the short kind; a custom title becomes a bold run-in in the body
            label = CALLOUT_LABELS.get(kind, kind.title())
            title = m.group(2).strip()
            rest = inner[m.end():]
            if m.group(3) == "\n":
                rest = "<p>" + rest
            rest = re.sub(r"^\s*<p>\s*</p>", "", rest)
            if title and title.lower().rstrip(".") != label.lower():
                t = title.rstrip(".") + "."
                rest = re.sub(r"^\s*<p>", '<p><strong>%s</strong> ' % t, rest, count=1) if rest.lstrip().startswith("<p>") \
                    else '<p><strong>%s</strong></p>%s' % (t, rest)
            klass = kind if kind in CALLOUT_LABELS else "note"
            return '<aside class="callout %s"><div class="callout-label">%s</div><div class="callout-body">%s</div></aside>' % (klass, label, rest)
        return '<blockquote class="pull">%s</blockquote>' % inner

    @staticmethod
    def wiki_refs(md_text):
        """[[Target]] / [[Target|text]] -> [text](<#Target>), outside code."""
        out, fence = [], None
        for line in md_text.split("\n"):
            m = re.match(r"^\s*(`{3,}|~{3,})", line)
            if m:
                fence = None if fence and m.group(1).startswith(fence) else (fence or m.group(1))
                out.append(line)
                continue
            if fence or "[[" not in line:
                out.append(line)
                continue
            out.append(_outside_code(line, r"\[\[([^\]|]+)(?:\|([^\]]+))?\]\]",
                                     lambda m: "[%s](<#%s>)" % ((m.group(2) or "").strip(), m.group(1).strip())))
        return "\n".join(out)

    def resolve(self, key):
        k = key.strip()
        low = k.lower()
        cands = []
        if low.startswith(("fig", "figure")):
            rest = re.sub(r"^(figure|fig)\.?\s*:?\s*", "", k, flags=re.I)
            cands = ["fig:" + rest.strip(), "fig:" + slug(rest)]
        elif low.startswith("part"):
            rest = re.sub(r"^part\s*:?\s*", "", k, flags=re.I)
            cands = ["part:" + rest.strip(), "part:" + slug(rest)]
        else:
            rest = k.lstrip("§").strip()
            cands = ["ch:" + rest, "ch:" + slug(rest), slug(rest), "id:" + k, "fig:" + slug(rest)]
        for c in ["gh:" + k, "gh:" + low] + cands:
            if c in self.targets:
                return self.targets[c]
        if k in self.doc_ids:
            return (k, k)
        # unique prefix match on titles
        sk = slug(rest)
        hits = {v for kk, v in self.targets.items() if sk and kk.split(":")[-1].startswith(sk)}
        return hits.pop() if len(hits) == 1 else None

    def index_marks(self, md_text):
        """{{term}} -> the word in the text, plus an index entry at this spot (outside code)."""
        out, fence = [], None
        for line in md_text.split("\n"):
            m = re.match(r"^\s*(`{3,}|~{3,})", line)
            if m:
                fence = None if fence and m.group(1).startswith(fence) else (fence or m.group(1))
                out.append(line)
                continue
            if fence or "{{" not in line:
                out.append(line)
                continue
            def mark(mm):
                shown, _, entry = mm.group(1).partition("|")
                aid = "ix-%d" % (len(self.index) + 1)
                self.index.append(((entry or shown).strip(), aid))
                return '<span class="ix" id="%s">%s</span>' % (aid, shown.strip())
            out.append(_outside_code(line, r"\{\{([^}]+)\}\}", mark))
        return "\n".join(out)

    @staticmethod
    def highlights(md_text):
        """==text== -> text. The highlighter was removed; the markers are dropped so old documents stay clean."""
        out, fence = [], None
        for line in md_text.split("\n"):
            m = re.match(r"^\s*(`{3,}|~{3,})", line)
            if m:
                fence = None if fence and m.group(1).startswith(fence) else (fence or m.group(1))
            elif not fence and "==" in line:
                line = _outside_code(line, r"==(?=\S)(.+?)(?<=\S)==", lambda mm: mm.group(1))
            out.append(line)
        return "\n".join(out)

    def render_body(self, md_text, endmark=False):
        md_text = self.index_marks(self.wiki_refs(md_text))
        md_text = self.highlights(md_text)
        md_text = re.sub(r'<a\s+name="([^"]+)"\s*>', r'<a id="\1" class="anchor">', md_text)
        tokens = self.md.parse(md_text)
        blocks = self.blocks(tokens)
        out, skip = [], set()
        last_para = None
        for k, b in enumerate(blocks):
            if k in skip:
                continue
            t = b[0]
            if t.type == "fence" or t.type == "code_block":
                cap, used = self.next_caption(blocks, k)
                if used:
                    skip.add(k + 1)
                if t.type == "code_block":
                    out.append(self.render_code(t.content, "text", {}, cap))
                else:
                    out.append(self.render_fence(t, cap))
            elif t.type == "table_open":
                cap, used = self.next_caption(blocks, k)
                if used:
                    skip.add(k + 1)
                rows = sum(1 for x in b if x.type == "tr_open")
                tbl = self.md.renderer.render(b, self.md.options, {})
                cls_ = "tm-table" + (" long" if rows > 22 else "") + ("" if cap else " no-cap")
                h = '<figure class="%s">%s</figure>' % (cls_, tbl)
                if cap:
                    h += '<figcaption class="fig-cap">%s</figcaption>' % self.inline(cap)
                out.append(h)
            elif t.type == "heading_open":
                lvl = int(t.tag[1])
                text = b[1].content
                tag = "h3" if lvl <= 3 else "h4"
                sid = "s-" + slug(text)
                n = 2
                while sid in self.section_ids:
                    sid = "s-%s-%d" % (slug(text), n)
                    n += 1
                self.section_ids.add(sid)
                plain = re.sub(r"[`*]", "", text)
                self.targets.setdefault(slug(plain), (sid, plain))
                self.targets.setdefault("id:" + sid, (sid, plain))
                out.append('<%s id="%s">%s</%s>' % (tag, sid, self.inline(text), tag))
            elif t.type == "blockquote_open":
                out.append(self.render_blockquote(b))
            elif t.type == "paragraph_open":
                txt = self.para_text(b) or ""
                children = b[1].children or []
                real = [c for c in children if not (c.type == "text" and not c.content.strip()) and c.type != "softbreak"]
                if real and all(c.type == "image" for c in real):
                    cap, used = self.next_caption(blocks, k)
                    if used:
                        skip.add(k + 1)
                    out.append(self.render_image(real, cap))
                elif re.match(r"^caption:\s*", txt, re.I):
                    out.append('<figcaption class="fig-cap">%s</figcaption>' %
                               self.inline(re.sub(r"^caption:\s*", "", txt, flags=re.I)))
                elif re.match(r"^sources?:", txt, re.I):
                    body = re.sub(r"^sources?:\s*", "", txt, flags=re.I)
                    out.append('<div class="sources"><div class="src-label">Sources</div><div class="src-body">%s</div></div>' % self.inline(body))
                else:
                    rendered = self.md.renderer.render(b, self.md.options, {})
                    last_para = len(out)
                    if txt.startswith("**"):
                        lead = re.match(r"^\*\*([^*]{2,60}?)[.:]\*\*", txt)
                        if lead:  # a defined term: index it
                            aid = "ix-%d" % (len(self.index) + 1)
                            self.index.append((lead.group(1).strip(), aid))
                            rendered = rendered.replace("<p>", '<p class="lead" id="%s">' % aid, 1)
                        else:
                            rendered = rendered.replace("<p>", '<p class="lead">', 1)
                    out.append(rendered)
            else:
                out.append(self.md.renderer.render(b, self.md.options, {}))
        if endmark:
            k = len(out) - 1
            while k >= 0 and (not out[k].strip() or out[k].lstrip().startswith('<div class="sources"')):
                k -= 1
            if k >= 0:
                html_k = out[k]
                cut = max(html_k.rfind("</p>"), html_k.rfind("</figcaption>"), html_k.rfind("</li>"))
                if cut != -1:
                    out[k] = html_k[:cut] + '<span class="endmark"></span>' + html_k[cut:]
        return "\n".join(out)

    def render_image(self, imgs, caption):
        parts = []
        for im in imgs:
            src = im.attrs.get("src", "")
            if not re.match(r"^(https?|data|file):", src):
                p = (self.base_dir / src).resolve()
                if p.exists():
                    mime = {"svg": "image/svg+xml", "jpg": "image/jpeg", "jpeg": "image/jpeg"}.get(p.suffix[1:].lower(), "image/" + p.suffix[1:].lower())
                    src = "data:%s;base64,%s" % (mime, base64.b64encode(p.read_bytes()).decode())
                else:
                    self.warnings.append({"kind": "missing-image", "src": src})
            parts.append('<img src="%s" alt="%s">' % (C.esc(src), C.esc(im.content)))
            if not caption and im.attrs.get("title"):
                caption = im.attrs.get("title")
        opts = {"title": imgs[0].content} if imgs[0].content else {}
        return self.figure('<div class="tm-img">%s</div>' % "".join(parts), opts, "image", caption)


# ============================================================== assembly
def font_css(signature=True):
    css = (ASSETS / "theme.css").read_text()
    if signature and (ASSETS / "signature.css").exists():
        css += "\n" + (ASSETS / "signature.css").read_text()

    def inline_font(m):
        p = ASSETS / m.group(1)
        return 'url("data:font/woff2;base64,%s")' % base64.b64encode(p.read_bytes()).decode()
    return re.sub(r'url\("(vendor/fonts/[^"]+)"\)', inline_font, css)


def missing_glyphs(text):
    """Characters no bundled font can draw (they would fall back to a system font)."""
    try:
        cov = json.loads((ASSETS / "vendor" / "fonts" / "coverage.json").read_text())
    except Exception:
        return {}
    ok = set().union(*[set(v) for v in cov.values()])
    bad = {}
    for line in text.split("\n"):
        for ch in line:
            o = ord(ch)
            if o > 127 and o not in ok and not ch.isspace() and not (0xFE00 <= o <= 0xFE0F):
                bad.setdefault(ch, line.strip()[:60])
    return bad


def build_html(md_path, overrides=None):
    md_path = Path(md_path)
    text = md_path.read_text(encoding="utf-8")
    fm, body = split_frontmatter(text)
    fm.update(overrides or {})
    model = build_model(body, fm)
    glyph_issues = [{"page": 0, "kind": "missing-glyph", "char": ch, "U+": "%04X" % ord(ch), "context": ctx}
                    for ch, ctx in missing_glyphs(text).items()]
    title = model["title"]
    name = fm.get("name") or title
    short = re.sub(r"\s*[:—–-].*$", "", name) if len(name) > 28 else name
    footer = fm.get("footer") or ("%s / Technical Manual" % short).upper()
    today = datetime.date.today()
    edition = fm.get("edition") or "Edition %s" % today.strftime("%Y.%m")
    subtitle = fm.get("subtitle", "Technical Manual")
    cover_mode = fm.get("cover", "light")
    R = Renderer(md_path.parent, short)
    quirks = fm.get("quirks", True) is not False
    if quirks:
        R.sep = "·"

    parts = model["parts"]
    has_parts = model["has_parts"]
    # colour assignment
    for pi, part in enumerate(parts):
        part["c"] = (pi % 9) + 1
        for ci, ch in enumerate(part["chapters"]):
            ch["c"] = part["c"] if has_parts else (ci % 9) + 1
            ch["num"] = "%d.%d" % (pi + 1, ci + 1) if has_parts else "%d" % (ci + 1)
            ch["id"] = "ch-" + ch["num"].replace(".", "-")

    # ---- cross-reference targets known before rendering (forward refs work)
    for pi, part in enumerate(parts):
        if has_parts:
            R.targets["part:%d" % (pi + 1)] = ("part-%d" % (pi + 1), "Part %d" % (pi + 1))
            R.targets["part:" + slug(part["title"])] = ("part-%d" % (pi + 1), "Part %d" % (pi + 1))
        for ch in part["chapters"]:
            R.targets["ch:" + ch["num"]] = (ch["id"], ch["title"])
            R.targets["ch:" + slug(ch["title"])] = (ch["id"], ch["title"])
            R.targets.setdefault(slug(ch["title"]), (ch["id"], ch["title"]))
            R.targets["id:" + ch["id"]] = (ch["id"], ch["title"])

    # ---- body sections
    sections = []
    front_html = []
    preamble = model["preamble"]
    description = fm.get("description")
    if not description and preamble and len(preamble) < 420 and "\n\n" not in preamble.strip():
        description, preamble = re.sub(r"[*_`]", "", preamble), ""
    if preamble or model["front"]:
        R.fig_prefix, R.fig_n = "0", 0
        chunks = []
        if preamble:
            dek, rest = take_dek(preamble)
            chunks.append(("About this manual", dek, rest))
        for ch in model["front"]:
            chunks.append((ch["title"], ch["dek"], ch["md"]))
        for t, dek, mdtext in chunks:
            rendered = R.render_body(mdtext)
            if not rendered.strip() and not dek:
                continue  # e.g. a preamble that only held cover blocks
            front_html.append('<section class="front c2"><header class="ch-head"><div class="ch-num"></div><div><h2 class="chapter-title">%s</h2>%s</div></header>%s</section>' % (
                R.inline(t), ('<p class="dek">%s</p>' % R.inline(dek)) if dek else "", rendered))

    for pi, part in enumerate(parts):
        if has_parts:
            R.fig_prefix, R.fig_n = str(pi + 1), 0
            rows = "".join('<div class="part-row" data-href="#%s"><span class="n">%s</span><span class="t">%s</span>'
                           '<span class="p" data-ref="#%s"></span></div>' % (ch["id"], R.disp(ch["num"]), R.inline(ch["title"]), ch["id"])
                           for ch in part["chapters"])
            sections.append(
                '<section class="part-opener c%d" id="part-%d"><div class="po-num">%d</div><div class="po-body"><h1>%s</h1>%s'
                '<div class="part-list">%s</div></div></section>' % (
                    part["c"], pi + 1, pi + 1, R.inline(part["title"]),
                    ('<p class="part-dek">%s</p>' % R.inline(part["dek"])) if part["dek"] else "", rows))
        for ci, ch in enumerate(part["chapters"]):
            if not has_parts:
                R.fig_prefix, R.fig_n = ch["num"], 0
            R.cur_color = "c%d" % ch["c"]
            body_html = R.render_body(ch["md"], endmark=quirks)
            if quirks and body_html.lstrip().startswith("<p"):
                body_html = re.sub(r"^\s*<p( class=\"lead\")?", lambda m: '<p class="opening%s"' % (" lead" if m.group(1) else ""), body_html, count=1)
            sections.append(
                '<section class="chapter c%d" id="%s">%s<header class="ch-head"><div class="ch-num">%s</div><div>'
                '<h2 class="chapter-title">%s</h2>%s</div></header>%s</section>' % (
                    ch["c"], ch["id"],
                    ('<div class="thumb c%d" style="--k:%d;--step:%.2fin"><span><b>%d</b><i>%s</i></span></div>' % (
                        part["c"], pi, min(1.25, 8.4 / max(1, len(parts))), pi + 1, C.esc(part["title"])))
                    if has_parts and len(parts) <= 8 and fm.get("tabs", True) else "",
                    R.disp(ch["num"]), R.inline(ch["title"]),
                    ('<p class="dek">%s</p>' % R.inline(ch["dek"])) if ch["dek"] else "", body_html))

    # ---- contents
    toc = ['<section class="toc"><h1>Contents</h1>']
    for pi, part in enumerate(parts):
        if has_parts:
            toc.append('<div class="toc-part c%d"><div class="toc-part-head"><span class="tp-num">%d</span><span>%s</span></div>' % (
                part["c"], pi + 1, R.inline(part["title"])))
            for ch in part["chapters"]:
                toc.append('<div class="toc-row" data-href="#%s"><span class="n">%s</span><span class="t">%s</span><span class="lead"></span>'
                           '<span class="p" data-ref="#%s"></span></div>' % (ch["id"], R.disp(ch["num"]), R.inline(ch["title"]), ch["id"]))
            toc.append("</div>")
        else:
            for ch in part["chapters"]:
                toc.append('<div class="toc-row solo c%d" data-href="#%s"><span class="chip">%s</span><span class="t">%s</span><span class="lead"></span>'
                           '<span class="p" data-ref="#%s"></span></div>' % (ch["c"], ch["id"], R.disp(ch["num"]), R.inline(ch["title"]), ch["id"]))
    toc.append("</section>")

    # ---- cover
    if R.cover_hero:
        hero = "".join(R.cover_hero)
    else:
        items = []
        if has_parts:
            for pi, part in enumerate(parts):
                lst = " · ".join(C.esc(c["title"]) for c in part["chapters"])
                items.append('<div class="bm c%d"><div class="bm-num">%d</div><div class="bm-title">%s</div><div class="bm-list">%s</div></div>'
                             % (part["c"], pi + 1, C.esc(part["title"]), lst))
        else:
            for part in parts:
                for ch in part["chapters"]:
                    items.append('<div class="bm c%d"><div class="bm-num">%s</div><div class="bm-title">%s</div></div>'
                                 % (ch["c"], ch["num"], C.esc(ch["title"])))
        if len(items) > 10:
            items = items[:9] + ['<div class="bm"><div class="bm-num"></div><div class="bm-title">and %d more</div></div>' % (len(items) - 9)]
        hero = '<div class="bookmap">%s</div>' % "".join(items)
    legend_src = parts if has_parts else [ch for p in parts for ch in p["chapters"]]
    legend = ""
    if fm.get("legend"):
        items = fm["legend"] if isinstance(fm["legend"], list) else str(fm["legend"]).split("|")
        lg = []
        for k, it in enumerate(items):
            t, fl = C.flags(str(it).strip())
            c = next((f for f in fl if re.match(r"^c\d$", f)), "c%d" % (k % 9 + 1))
            lg.append('<span class="%s">%s</span>' % (c, C.esc(t)))
        legend = "".join(lg)
    mark = fm.get("mark") or short.strip()[:1].upper()
    cover = ('<section class="cover"><div class="cover-top"><div class="brand">%s</div>'
             '<div class="edition">%s</div></div><div class="cover-hero">%s</div>'
             '<div class="cover-bottom"><h1>%s</h1><div class="subtitle">%s</div>%s%s</div></section>') % (
        C.esc(short), C.esc(edition), hero, C.esc(title), C.esc(subtitle),
        ('<p class="description">%s</p>' % R.inline(description)) if description else "",
        ('<div class="legend">%s</div>' % legend) if legend else "")

    cover_accent = {"dark": "#e39a57", "light": "#2d6189"}[cover_mode if cover_mode in ("dark", "light") else "dark"]
    if fm.get("accent"):
        cover_accent = fm["accent"]
    page_css = ('@page { @top-right { content: "%s"; } }\n'
                ':root { --cover-accent: %s; }' % (short.replace('"', ""), cover_accent))

    # ---- list of figures (back matter): on by default once there are 12+ titled figures
    titled = [f for f in R.figures if f[2]]
    lof = ""
    if fm.get("figures", len(titled) >= 12) and titled:
        rows = "".join('<div class="toc-row %s" data-href="#%s"><span class="n">%s</span><span class="t">%s</span>'
                       '<span class="lead"></span><span class="p" data-ref="#%s"></span></div>' % (c, fid, R.disp(num), C.inline(t), fid)
                       for fid, num, t, c in titled)
        lof = ('<section class="lof" id="list-of-figures"><header class="ch-head"><div class="ch-num"></div><div>'
               '<h2 class="chapter-title">List of figures</h2></div></header>%s</section>' % rows)

    # ---- index (back matter): on with `index: true`, or automatically from 15 entries
    index_html = ""
    if R.index and fm.get("index", len(R.index) >= 15):
        groups = {}
        for term, aid in R.index:
            key = re.sub(r"[`*]", "", term)
            groups.setdefault(key.lower(), [key, []])[1].append(aid)
        letters, cur = [], None
        for k in sorted(groups, key=lambda x: re.sub(r"^[^a-z0-9]+", "", x)):
            term, aids = groups[k]
            first = (re.sub(r"^[^A-Za-z0-9]+", "", term)[:1] or "#").upper()
            if first != cur:
                cur = first
                letters.append('<div class="ix-letter">%s</div>' % C.esc(first))
            refs = ", ".join('<span class="ix-p" data-href="#%s" data-ref="#%s"></span>' % (a, a) for a in aids)
            letters.append('<div class="ix-entry"><span class="ix-t">%s</span> <span class="ix-refs">%s</span></div>' % (C.inline(term), refs))
        index_html = ('<section class="lof index-page" id="index"><header class="ch-head"><div class="ch-num"></div><div>'
                      '<h2 class="chapter-title">Index</h2></div></header><div class="ix-grid">%s</div></section>' % "".join(letters))

    # ---- colophon (signature layer): how the book was made, and whose it is
    colophon = ""
    if quirks and fm.get("colophon", True) is not False:
        words = len(re.findall(r"[A-Za-z0-9]+", re.sub(r"```.*?```", "", body, flags=re.S)))
        n_xref = len(re.findall(r'class="xref"', "".join(sections)))
        fp = hashlib.sha256(text.encode("utf-8")).hexdigest()[:12]
        owner = fm.get("owner") or fm.get("author")
        extra = fm.get("colophon") if isinstance(fm.get("colophon"), str) else ""
        colophon = (
            '<section class="colophon" id="colophon"><div class="col-body"><h2>Colophon</h2>'
            '<p>Typeset from <code>%s</code> on %s: %s words, %d figures, %d cross-references%s.</p>'
            '<p>Set in Manrope for display, Source Sans 3 for text, Source Serif 4 italic for the voice in the margins, '
            'and JetBrains Mono for code and data. Laid out on a 1.3-inch rail and a 75-character column, '
            'with drawings on a 9-point grid. Paginated by Paged.js in Chromium.</p>%s'
            '<p class="fp">source sha256 %s</p>%s</div></section>') % (
                C.esc(md_path.name), today.strftime("%-d %B %Y"), "{:,}".format(words), len(R.figures), n_xref,
                (", %d index entries" % len(R.index)) if R.index else "",
                ('<p>%s</p>' % R.inline(extra)) if extra else "", fp,
                ('<p class="sig-label">Typeset for</p><p class="sig">%s</p>' % C.esc(owner)) if owner else "")

    # ---- resolve cross-references now that every target is known
    for anchor, tid in github_anchors(body, model, has_parts).items():
        R.targets.setdefault("gh:" + anchor, (tid, anchor))
    for chunk in sections + front_html:
        R.doc_ids.update(re.findall(r'\bid="([^"]+)"', chunk))
    xref_issues = []

    def xref(m):
        key, text = html.unescape(m.group(1)), m.group(2)
        hit = R.resolve(key)
        if not hit:
            xref_issues.append({"page": 0, "kind": "broken-ref", "ref": key})
            return '<span class="xref broken">%s</span>' % (text or C.esc(key))
        tid, default = hit
        return '<span class="xref" data-href="#%s">%s<span class="xp" data-ref="#%s"></span></span>' % (
            tid, text if text.strip() else C.inline(default), tid)
    sections = [re.sub(r'<a class="xref" data-xref="([^"]*)">(.*?)</a>', xref, x, flags=re.S) for x in sections]
    front_html = [re.sub(r'<a class="xref" data-xref="([^"]*)">(.*?)</a>', xref, x, flags=re.S) for x in front_html]
    R.warnings.extend(xref_issues)

    grid = str(fm.get("grid", "dots")).lower()
    body_class = " ".join(x for x in ("dark-cover" if cover_mode == "dark" else "",
                                      "dark-openers" if fm.get("openers") == "dark" else "",
                                      "grid-" + (grid if grid in ("dots", "lines", "none") else "dots")) if x)
    show_toc = fm.get("toc", True) and sum(len(p["chapters"]) for p in parts) > 1
    doc = HTML_TEMPLATE.format(
        title=C.esc(title), css=font_css(quirks), page_css=page_css, body_class=body_class,
        cover=cover, toc="\n".join(toc) if show_toc else "", front="\n".join(front_html), sections="\n".join(sections) + lof + index_html + colophon,
        paged=(ASSETS / "vendor" / "paged.polyfill.min.js").as_uri(),
        mermaid=(ASSETS / "vendor" / "mermaid.min.js").as_uri(),
    )
    meta = {"title": title, "subject": description or subtitle, "outline_figures": fm.get("outline_figures", True)}
    return doc, glyph_issues + R.warnings, meta


HTML_TEMPLATE = """<!doctype html>
<html lang="en"><head><meta charset="utf-8"><title>{title}</title>
<style>{css}</style>
<style>{page_css}</style>
<script>
window.PagedConfig = {{
  auto: true,
  before: async () => {{
    await document.fonts.ready;
    if (window.mermaid && document.querySelector('pre.mermaid')) {{
      try {{
        mermaid.initialize({{ startOnLoad: false, theme: 'base', securityLevel: 'loose',
          fontFamily: '"Source Sans 3", "TM Symbols", sans-serif',
          flowchart: {{ useMaxWidth: false, htmlLabels: true, curve: 'basis', padding: 10, nodeSpacing: 34, rankSpacing: 38 }},
          sequence: {{ actorFontFamily: '"JetBrains Mono", monospace', messageFontFamily: '"Source Sans 3", sans-serif', mirrorActors: false, useMaxWidth: false, actorMargin: 60, boxMargin: 8, messageMargin: 34, width: 130 }},
          themeVariables: {{ fontSize: '12px', primaryColor: '#fffefb', primaryBorderColor: '#44423e', primaryTextColor: '#1d1a17',
            lineColor: '#47453f', secondaryColor: '#f4f3ef', tertiaryColor: '#f4f3ef', clusterBkg: '#f7f6f2', clusterBorder: '#d6d2c9',
            noteBkgColor: '#ffffff', noteBorderColor: '#d6d2c9', actorBkg: '#fffefb', actorBorder: '#44423e',
            signalColor: '#47453f', labelBoxBkgColor: '#f4f3ef', edgeLabelBackground: '#ffffff' }} }});
        await mermaid.run({{ querySelector: 'pre.mermaid', suppressErrors: true }});
      }} catch (e) {{ window.__tmMermaidError = String(e); }}
    }}
    document.querySelectorAll('.mermaid-wrap svg').forEach(function (svg) {{
      var w = svg.viewBox && svg.viewBox.baseVal ? svg.viewBox.baseVal.width : 0;
      svg.removeAttribute('height');
      svg.style.maxWidth = '100%';
      svg.style.width = Math.min(Math.max(w * 1.05, 0), 660) + 'px';
    }});
  }},
  after: () => {{ if (window.tmLayoutFlows) window.tmLayoutFlows(); if (window.tmLayoutDiagrams) window.tmLayoutDiagrams(); window.__tmDone = true; }}
}};

window.tmLayoutDiagrams = function () {{
  var NS = 'http://www.w3.org/2000/svg';
  document.querySelectorAll('.dg').forEach(function (dg) {{
    var edges = []; try {{ edges = JSON.parse(dg.getAttribute('data-edges') || '[]'); }} catch (e) {{}}
    var svg = dg.querySelector('.dg-edges'); if (!svg) return;
    while (svg.firstChild) svg.removeChild(svg.firstChild);
    dg.querySelectorAll('.dg-elabel').forEach(function (l) {{ l.remove(); }});
    var B = dg.getBoundingClientRect();
    function R(el) {{ var r = el.getBoundingClientRect(); return {{l: r.left - B.left, r: r.right - B.left, t: r.top - B.top, b: r.bottom - B.top,
      cx: (r.left + r.right) / 2 - B.left, cy: (r.top + r.bottom) / 2 - B.top}}; }}
    function node(id) {{ return dg.querySelector('.dg-node[data-id="' + id + '"]'); }}
    function head(x, y, dx, dy, hl) {{
      var s = 6.2, w = 3.4, L = Math.hypot(dx, dy) || 1; dx /= L; dy /= L;
      var p = document.createElementNS(NS, 'polygon');
      var P = [[x, y], [x - dx * s - dy * w, y - dy * s + dx * w], [x - dx * s + dy * w, y - dy * s - dx * w]];
      p.setAttribute('points', P.map(function (q) {{ return q[0].toFixed(1) + ',' + q[1].toFixed(1); }}).join(' '));
      if (hl) p.setAttribute('class', 'hl'); svg.appendChild(p);
    }}
    edges.forEach(function (e) {{
      var na = node(e.a), nb = node(e.b); if (!na || !nb) return;
      var a = R(na), b = R(nb), pa = e.pa, pb = e.pb;
      if (!pa || !pb) {{
        if (b.l >= a.r - 2) {{ pa = pa || 'r'; pb = pb || 'l'; }}
        else if (b.r <= a.l + 2) {{ pa = pa || 'l'; pb = pb || 'r'; }}
        else if (b.t >= a.b - 2) {{ pa = pa || 'b'; pb = pb || 't'; }}
        else {{ pa = pa || 't'; pb = pb || 'b'; }}
      }}
      var hz = function (p) {{ return p === 'l' || p === 'r'; }};
      var oy = [Math.max(a.t, b.t), Math.min(a.b, b.b)], ox = [Math.max(a.l, b.l), Math.min(a.r, b.r)];
      var ys = (oy[1] - oy[0] > 8) ? (oy[0] + oy[1]) / 2 : null, xs = (ox[1] - ox[0] > 8) ? (ox[0] + ox[1]) / 2 : null;
      function pt(r, p, shared) {{
        if (p === 'r') return [r.r, hz(pa) && hz(pb) && ys !== null ? ys : r.cy];
        if (p === 'l') return [r.l, hz(pa) && hz(pb) && ys !== null ? ys : r.cy];
        if (p === 'b') return [!hz(pa) && !hz(pb) && xs !== null ? xs : r.cx, r.b];
        return [!hz(pa) && !hz(pb) && xs !== null ? xs : r.cx, r.t];
      }}
      var p1 = pt(a, pa), p2 = pt(b, pb), pts = [p1];
      if (hz(pa) && hz(pb)) {{ if (Math.abs(p1[1] - p2[1]) > 0.8) {{ var mx = (p1[0] + p2[0]) / 2; if (pa === pb) mx = (pa === 'r' ? Math.max(p1[0], p2[0]) + 14 : Math.min(p1[0], p2[0]) - 14); pts.push([mx, p1[1]], [mx, p2[1]]); }} }}
      else if (!hz(pa) && !hz(pb)) {{ if (Math.abs(p1[0] - p2[0]) > 0.8) {{ var my = (p1[1] + p2[1]) / 2; if (pa === pb) my = (pa === 'b' ? Math.max(p1[1], p2[1]) + 12 : Math.min(p1[1], p2[1]) - 12); pts.push([p1[0], my], [p2[0], my]); }} }}
      else if (hz(pa)) pts.push([p2[0], p1[1]]);
      else pts.push([p1[0], p2[1]]);
      pts.push(p2);
      var d = 'M' + pts.map(function (q) {{ return q[0].toFixed(1) + ' ' + q[1].toFixed(1); }}).join(' L');
      var path = document.createElementNS(NS, 'path'); path.setAttribute('d', d);
      path.setAttribute('class', (e.dashed ? 'dashed ' : '') + (e.hl ? 'hl' : '')); svg.appendChild(path);
      var n = pts.length;
      if (!e.noarrow) head(p2[0], p2[1], p2[0] - pts[n - 2][0], p2[1] - pts[n - 2][1], e.hl);
      if (e.both) head(p1[0], p1[1], p1[0] - pts[1][0], p1[1] - pts[1][1], e.hl);
      if (e.label) {{
        var best = 0, bi = 0;
        for (var i = 0; i + 1 < n; i++) {{ var len = Math.hypot(pts[i + 1][0] - pts[i][0], pts[i + 1][1] - pts[i][1]); if (len > best) {{ best = len; bi = i; }} }}
        var lab = document.createElement('div'); lab.className = 'dg-elabel'; lab.textContent = e.label;
        lab.style.left = ((pts[bi][0] + pts[bi + 1][0]) / 2) + 'px'; lab.style.top = ((pts[bi][1] + pts[bi + 1][1]) / 2) + 'px';
        dg.appendChild(lab);
      }}
    }});
  }});
}};
window.tmLayoutFlows = function () {{
  document.querySelectorAll('.flow-link').forEach(function (link) {{
    var prev = link.previousElementSibling, next = link.nextElementSibling;
    while (prev && !prev.classList.contains('flow-row')) prev = prev.previousElementSibling;
    while (next && !next.classList.contains('flow-row')) next = next.nextElementSibling;
    if (!prev || !next) return;
    var box = link.getBoundingClientRect();
    var a = prev.querySelectorAll('.flow-node'), b = next.querySelectorAll('.flow-node');
    var ra = a[a.length - 1].getBoundingClientRect(), rb = b[0].getBoundingClientRect();
    var xr = ra.left + ra.width / 2 - box.left, xl = rb.left + rb.width / 2 - box.left;
    var lo = Math.min(xl, xr), hi = Math.max(xl, xr);
    var lk = link.querySelector('.lk'), lk2 = link.querySelector('.lk2'), ll = link.querySelector('.ll');
    lk.style.left = lo + 'px'; lk.style.width = (hi - lo) + 'px';
    if (xr < xl) {{ lk.style.borderRight = '0'; lk.style.borderLeft = '1px solid var(--ink-2)'; }}
    lk2.style.left = xl + 'px'; lk2.style.width = '1px';
    ll.style.left = ((lo + hi) / 2) + 'px';
  }});
}};
</script>
<script src="{paged}"></script>
<script src="{mermaid}"></script>
<script>if (window.mermaid) mermaid.initialize({{ startOnLoad: false }});</script>
<style>
.mermaid-wrap .node.hl rect, .mermaid-wrap .node.hl polygon, .mermaid-wrap .node.hl circle {{ fill: var(--tint) !important; stroke: var(--accent) !important; }}
.mermaid-wrap .edgeLabel, .mermaid-wrap .edgeLabel p {{ font-family: "Source Sans 3", sans-serif !important; font-size: 11px !important; background: #ffffff !important; }}
.mermaid-wrap .cluster-label, .mermaid-wrap .cluster-label p {{ font-family: "Source Sans 3", sans-serif !important; font-size: 11px !important; font-weight: 700; color: #47453f !important; }}
.mermaid-wrap .messageText {{ font-family: "Source Sans 3", sans-serif !important; }}
</style>
</head>
<body class="{body_class}">
{cover}
{toc}
{front}
{sections}
</body></html>
"""

LINT_JS = r"""
() => {
  const issues = [];
  const pages = [...document.querySelectorAll('.pagedjs_page')];
  const desc = el => (el.className && typeof el.className === 'string' ? el.tagName.toLowerCase() + '.' + el.className.split(' ')[0] : el.tagName.toLowerCase());
  const BLOCKS = 'h2,h3,h4,p,figure,ul,ol,.callout,.sources,blockquote,.ch-head,.toc-row,.tm-code,.ix-entry';
  const pageInfo = [];
  pages.forEach((pg, idx) => {
    const n = idx + 1;
    const area = pg.querySelector('.pagedjs_page_content');
    if (!area) return;
    const A = area.getBoundingClientRect();
    const named = /pagedjs_(cover|part|toc)_page/.test(pg.className);
    area.querySelectorAll('figure, table, pre, img, svg, .tm-fig, .callout').forEach(el => {
      const r = el.getBoundingClientRect();
      if (!r.width || el.closest('.mermaid-wrap svg') && el.tagName !== 'svg') return;
      if (r.right > A.right + 2) issues.push({page: n, kind: 'overflow-x', el: desc(el), by_px: Math.round(r.right - A.right)});
      if (!named && r.bottom > A.bottom + 2) issues.push({page: n, kind: 'overflow-y', el: desc(el), by_px: Math.round(r.bottom - A.bottom)});
    });
    area.querySelectorAll('.seg .sn, .seg .ss, .flow-arrow .al, .bar-val, .flow-node .nt').forEach(el => {
      if (el.scrollWidth > el.clientWidth + 2) issues.push({page: n, kind: 'clipped-text', el: desc(el), text: el.textContent.slice(0, 50)});
    });
    area.querySelectorAll('.tm-fig').forEach(fig => {
      const F = fig.getBoundingClientRect();
      for (const el of fig.querySelectorAll('*')) {
        if (el.children.length || !el.textContent.trim()) continue;
        const r = el.getBoundingClientRect();
        if (r.width && r.right > F.right + 2) { issues.push({page: n, kind: 'escapes-figure', el: desc(el), text: el.textContent.slice(0, 40), by_px: Math.round(r.right - F.right)}); break; }
      }
    });
    const blocks = [...area.querySelectorAll(BLOCKS)].filter(e => e.getBoundingClientRect().height > 0 && !(e.parentElement && e.parentElement.closest('figure, .callout, li')));
    let first = null, last = null, bottom = A.top;
    blocks.forEach(b => { const r = b.getBoundingClientRect(); if (!first || r.top < first.getBoundingClientRect().top) first = b; if (r.bottom >= bottom) { bottom = r.bottom; last = b; } });
    const fill = (bottom - A.top) / A.height;
    pageInfo.push({n, named, fill, first, last});
    if (last && /^H[234]$/.test(last.tagName)) issues.push({page: n, kind: 'orphan-heading', text: last.textContent.slice(0, 60)});
    if (last && last.classList && last.classList.contains('ch-head')) issues.push({page: n, kind: 'orphan-heading', text: 'chapter heading stranded'});
  });
  // whitespace left behind by a figure that jumped to the next page
  for (let i = 0; i + 1 < pageInfo.length; i++) {
    const p = pageInfo[i], q = pageInfo[i + 1];
    if (p.named || q.named || !q.first) continue;
    const startsChapter = q.first.classList && q.first.classList.contains('ch-head');
    if (!startsChapter && q.first.tagName === 'FIGURE' && p.fill < 0.62)
      issues.push({page: p.n, kind: 'figure-gap', fill: +p.fill.toFixed(2), note: 'page ends early because the next figure did not fit'});
    if (!startsChapter && p.fill < 0.25 && !(q.first.classList && q.first.classList.contains('ch-head')))
      issues.push({page: p.n, kind: 'sparse-page', fill: +p.fill.toFixed(2)});
  }
  document.querySelectorAll('.dg-wrap.key-right').forEach(w => {
    const d = w.querySelector('.dg').getBoundingClientRect(), k = w.querySelector('.dg-key').getBoundingClientRect();
    const pg = w.closest('.pagedjs_page');
    if (d.right > k.left + 1) issues.push({page: pg ? pages.indexOf(pg) + 1 : 0, kind: 'key-overlap', by_px: Math.round(d.right - k.left), note: 'diagram is wider than its column: fewer columns, shorter labels, or key: below'});
  });
  document.querySelectorAll('.dg').forEach(dg => {
    const D = dg.getBoundingClientRect(); const pg0 = dg.closest('.pagedjs_page');
    const wide = [...dg.querySelectorAll('.dg-zone, .dg-node')].some(z => z.getBoundingClientRect().right > D.right + 2);
    if (wide) issues.push({page: pg0 ? pages.indexOf(pg0) + 1 : 0, kind: 'diagram-overflow', note: 'columns do not fit: fewer columns, shorter titles, or shorter edge labels'});
  });
  document.querySelectorAll('.dg').forEach(dg => {
    const pg = dg.closest('.pagedjs_page'); const n = pg ? pages.indexOf(pg) + 1 : 0;
    const nodes = [...dg.querySelectorAll('.dg-node')].map(x => x.getBoundingClientRect());
    dg.querySelectorAll('.dg-elabel').forEach(l => { const r = l.getBoundingClientRect();
      if (nodes.some(b => r.left < b.right - 1 && r.right > b.left + 1 && r.top < b.bottom - 1 && r.bottom > b.top + 1))
        issues.push({page: n, kind: 'label-collision', text: l.textContent}); });
    const nr = [...dg.querySelectorAll('.dg-node')];
    for (let i = 0; i < nr.length; i++) for (let j = i + 1; j < nr.length; j++) { const a = nodes[i], b = nodes[j];
      if (a.left < b.right - 1 && a.right > b.left + 1 && a.top < b.bottom - 1 && a.bottom > b.top + 1)
        issues.push({page: n, kind: 'node-overlap', text: nr[i].textContent.slice(0, 20) + ' / ' + nr[j].textContent.slice(0, 20)}); }
  });
  document.querySelectorAll('.ln-seg span, .sq-actor, .dg-node .nt').forEach(el => {
    if (el.scrollWidth > el.clientWidth + 2) { const pg = el.closest('.pagedjs_page'); issues.push({page: pg ? pages.indexOf(pg) + 1 : 0, kind: 'clipped-text', el: el.className, text: el.textContent.slice(0, 40)}); }
  });
  pageInfo.forEach(p => { if (!p.named && p.fill < 0.12) issues.push({page: p.n, kind: 'near-empty-page', fill: +p.fill.toFixed(2)}); });
  document.querySelectorAll('.mermaid-wrap').forEach(w => {
    const pg = w.closest('.pagedjs_page'); const n = pg ? pages.indexOf(pg) + 1 : 0;
    if (w.querySelector('svg[aria-roledescription="error"]') || /Syntax error/i.test(w.textContent)) issues.push({page: n, kind: 'mermaid-error'});
  });
  const fonts = ['10pt "Source Sans 3"', '10pt "Manrope"', '10pt "JetBrains Mono"'].filter(f => !document.fonts.check(f));
  if (fonts.length) issues.push({page: 0, kind: 'font-missing', fonts});
  const unresolved = [...document.querySelectorAll('.toc-row .p, .part-row .p')].filter(e => !getComputedStyle(e, '::after').content || getComputedStyle(e, '::after').content === 'none').length;
  if (unresolved) issues.push({page: 0, kind: 'toc-unresolved', count: unresolved});
  return {pages: pages.length, issues, mermaidError: window.__tmMermaidError || null};
}
"""


NAV_JS = r"""
() => {
  const pages = [...document.querySelectorAll('.pagedjs_page')];
  const where = el => {
    const pg = el.closest('.pagedjs_page'); if (!pg) return null;
    const P = pg.getBoundingClientRect(), r = el.getBoundingClientRect();
    return {page: pages.indexOf(pg), x: r.left - P.left, y: r.top - P.top};
  };
  const first = id => [...document.querySelectorAll('[id="' + CSS.escape(id) + '"], [data-id="' + CSS.escape(id) + '"]')]
      .filter(e => e.closest('.pagedjs_page') && !e.hasAttribute('data-split-from'))[0];
  const links = [];
  document.querySelectorAll('.pagedjs_page [data-href]').forEach(el => {
    const pg = el.closest('.pagedjs_page'); const P = pg.getBoundingClientRect();
    for (const r of el.getClientRects()) {
      if (r.width < 1 || r.height < 1) continue;
      links.push({href: el.getAttribute('data-href'), page: pages.indexOf(pg),
                  x0: r.left - P.left, y0: r.top - P.top, x1: r.right - P.left, y1: r.bottom - P.top});
    }
  });
  const ids = [...new Set(links.map(l => l.href.slice(1)))];
  const targets = {};
  ids.forEach(id => { const el = first(id); if (el) targets[id] = where(el); });
  const outline = [];
  const sel = '.part-opener, section.chapter, section.front, section.lof, section.colophon, h3[id], figure.fig-wrap[id]';
  document.querySelectorAll('.pagedjs_page ' + sel.split(', ').join(', .pagedjs_page ')).forEach(el => {
    if (el.hasAttribute('data-split-from')) return;
    let kind, title;
    if (el.classList.contains('part-opener')) { kind = 'part'; title = 'Part ' + (el.querySelector('.po-num')?.textContent || '') + ' · ' + (el.querySelector('h1')?.textContent || ''); }
    else if (el.matches('section.chapter')) { kind = 'chapter'; title = (el.querySelector('.ch-num')?.textContent || '') + '  ' + (el.querySelector('h2')?.textContent || ''); }
    else if (el.matches('section.front, section.lof, section.colophon')) { kind = 'front'; title = el.querySelector('h2')?.textContent || ''; }
    else if (el.tagName === 'H3') { kind = 'section'; title = el.textContent; }
    else { kind = 'figure'; title = (el.querySelector('.fig-num')?.textContent || '') + '  ' + (el.querySelector('.fig-title')?.textContent || ''); }
    const w = where(el); if (!w) return;
    outline.push(Object.assign({kind, title: title.replace(/\s+/g, ' ').trim(), id: el.id}, w));
  });
  const toc = document.querySelector('.pagedjs_page section.toc');
  const sz = pages[0].getBoundingClientRect();
  return {links, targets, outline, toc: toc ? where(toc) : null, page_w: sz.width, page_h: sz.height};
}
"""


def add_navigation(pdf_path, nav, meta):
    """Write internal links, the bookmark tree and document metadata into the PDF."""
    from pypdf import PdfReader, PdfWriter
    from pypdf.generic import ArrayObject, DictionaryObject, Fit, FloatObject, NameObject, NullObject, NumberObject
    w = PdfWriter(clone_from=str(pdf_path))
    if not w.pages:
        return {}
    H = float(w.pages[0].mediabox.height)
    k = H / nav["page_h"] if nav.get("page_h") else 0.75  # CSS px -> PDF pt

    def fit(t):
        return Fit.xyz(left=0, top=max(0.0, H - max(0.0, t["y"] - 14) * k), zoom=None)

    n_links = broken = 0
    for l in nav["links"]:
        t = nav["targets"].get(l["href"][1:])
        if not t:
            broken += 1
            continue
        rect = (l["x0"] * k, H - l["y1"] * k, l["x1"] * k, H - l["y0"] * k)
        # a local /Dest must reference the page object, not its index (PDF 32000-1, 12.3.2)
        top = max(0.0, H - max(0.0, t["y"] - 14) * k)
        ann = DictionaryObject({
            NameObject("/Type"): NameObject("/Annot"), NameObject("/Subtype"): NameObject("/Link"),
            NameObject("/Rect"): ArrayObject([FloatObject(round(v, 2)) for v in rect]),
            NameObject("/Border"): ArrayObject([NumberObject(0)] * 3),
            NameObject("/Dest"): ArrayObject([w.pages[t["page"]].indirect_reference, NameObject("/XYZ"),
                                              FloatObject(0), FloatObject(round(top, 2)), NullObject()]),
        })
        pg = w.pages[l["page"]]
        if "/Annots" not in pg:
            pg[NameObject("/Annots")] = ArrayObject()
        annots = pg["/Annots"].get_object()
        annots.append(w._add_object(ann))
        n_links += 1
    parent = {"part": None, "chapter": None}
    n_out = 0
    if nav.get("toc"):
        w.add_outline_item("Contents", nav["toc"]["page"], fit=fit(nav["toc"]))
        n_out += 1
    for o in nav["outline"]:
        if o["kind"] == "figure" and not meta.get("outline_figures", True):
            continue
        if o["kind"] == "part":
            node = w.add_outline_item(o["title"], o["page"], fit=fit(o), bold=True)
            parent = {"part": node, "chapter": None}
        elif o["kind"] == "front":
            node = w.add_outline_item(o["title"], o["page"], fit=fit(o))
            parent = {"part": None, "chapter": node}
        elif o["kind"] == "chapter":
            node = w.add_outline_item(o["title"], o["page"], parent=parent["part"], fit=fit(o))
            parent["chapter"] = node
        else:
            w.add_outline_item(o["title"], o["page"], parent=parent["chapter"] or parent["part"], fit=fit(o),
                               italic=o["kind"] == "figure")
        n_out += 1
    w.add_metadata({"/Title": meta.get("title", ""), "/Subject": meta.get("subject", "") or "",
                    "/Creator": "technical-manual skill", "/Producer": "Paged.js + Chromium + pypdf"})
    w.page_mode = "/UseOutlines"
    with open(pdf_path, "wb") as f:
        w.write(f)
    return {"links": n_links, "outline": n_out, "unlinked": broken}


def render_pdf(html_path, pdf_path, timeout=180, meta=None):
    from playwright.sync_api import sync_playwright
    with sync_playwright() as p:
        browser = p.chromium.launch(args=["--allow-file-access-from-files"])
        page = browser.new_page(viewport={"width": 1000, "height": 1300})
        logs = []
        page.on("console", lambda m: logs.append(m.text) if m.type in ("error",) else None)
        page.on("pageerror", lambda e: logs.append(str(e)))
        page.goto(Path(html_path).resolve().as_uri())
        page.wait_for_function("window.__tmDone === true", timeout=timeout * 1000)
        page.wait_for_timeout(300)
        report = page.evaluate(LINT_JS)
        nav = page.evaluate(NAV_JS)
        page.pdf(path=str(pdf_path), prefer_css_page_size=True, print_background=True)
        browser.close()
    report["console_errors"] = logs[:20]
    try:
        report["navigation"] = add_navigation(pdf_path, nav, meta or {})
        if report["navigation"].get("unlinked"):
            report["issues"].append({"page": 0, "kind": "unlinked", "count": report["navigation"]["unlinked"],
                                     "note": "links whose target is not on any page"})
    except Exception as e:  # navigation is an enhancement; never lose the PDF over it
        import traceback
        report["issues"].append({"page": 0, "kind": "navigation-error", "error": str(e),
                                 "where": traceback.format_exc().strip().split("\n")[-3:]})
    return report


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("input")
    ap.add_argument("-o", "--output", help="PDF path (default: <input>.pdf)")
    ap.add_argument("--html", help="also keep the HTML at this path")
    ap.add_argument("--html-only", help="write HTML here and skip PDF rendering")
    ap.add_argument("--cover", choices=["dark", "light"], help="override frontmatter cover style")
    ap.add_argument("--report", help="write the layout lint report (JSON) here")
    a = ap.parse_args()

    overrides = {"cover": a.cover} if a.cover else {}
    doc, warnings, meta = build_html(a.input, overrides)
    if a.html_only:
        Path(a.html_only).write_text(doc, encoding="utf-8")
        print("HTML written:", a.html_only)
        return
    out_pdf = Path(a.output or Path(a.input).with_suffix(".pdf"))
    html_path = Path(a.html) if a.html else out_pdf.with_suffix(".build.html")
    html_path.write_text(doc, encoding="utf-8")
    report = render_pdf(html_path, out_pdf, meta=meta)
    report["issues"] = warnings + report["issues"]
    if not a.html:
        html_path.unlink(missing_ok=True)
    rpath = Path(a.report) if a.report else out_pdf.with_suffix(".report.json")
    rpath.write_text(json.dumps(report, indent=2))
    nv = report.get("navigation") or {}
    print("PDF: %s  (%d pages, %s links, %s bookmarks)" % (out_pdf, report["pages"], nv.get("links", 0), nv.get("outline", 0)))
    if report["issues"]:
        print("Layout issues (%d)  ->  %s" % (len(report["issues"]), rpath))
        for it in report["issues"][:40]:
            print("  p%-4s %-15s %s" % (it.get("page", "-"), it["kind"],
                                       json.dumps({k: v for k, v in it.items() if k not in ("page", "kind")})))
    else:
        print("No layout issues found.")
    if report.get("console_errors"):
        print("Console errors:", *report["console_errors"][:5], sep="\n  ")


if __name__ == "__main__":
    main()
