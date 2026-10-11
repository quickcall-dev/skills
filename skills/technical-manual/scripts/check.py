#!/usr/bin/env python3
"""
check.py: render a built manual into images you can look at.

    python3 check.py manual.pdf                 # contact sheet(s) + flagged pages
    python3 check.py manual.pdf --pages 4 9     # also render these pages large
    python3 check.py manual.pdf --out /tmp/qa

Writes to <out>/ (default: ./qa-<pdfname>/):
  sheet-1.png, sheet-2.png …   every page, 7 per row, 28 per sheet: rhythm, density, colour
  page-N.png                   100 dpi renders of pages flagged in <pdf>.report.json
                               and of any --pages given: detail, alignment, clipping
Then open the PNGs with the image viewer and compare against the checklist in SKILL.md.
"""
import argparse
import glob
import json
import subprocess
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw


def contact_sheets(pdf, out, per_sheet=28, cols=7, dpi=42):
    tmp = Path(tempfile.mkdtemp())
    subprocess.run(["pdftoppm", "-r", str(dpi), "-png", str(pdf), str(tmp / "p")], check=True)
    files = sorted(glob.glob(str(tmp / "p-*.png")))
    sheets = []
    for s in range(0, len(files), per_sheet):
        batch = [Image.open(f).convert("RGB") for f in files[s:s + per_sheet]]
        w, h = batch[0].size
        rows = (len(batch) + cols - 1) // cols
        pad = 6
        S = Image.new("RGB", (cols * w + (cols + 1) * pad, rows * (h + 14) + (rows + 1) * pad), "#7a7874")
        d = ImageDraw.Draw(S)
        for i, im in enumerate(batch):
            x, y = pad + (i % cols) * (w + pad), pad + (i // cols) * (h + 14 + pad)
            S.paste(im, (x, y))
            d.text((x + 2, y + h + 1), str(s + i + 1), fill="#ffffff")
        path = out / ("sheet-%d.png" % (s // per_sheet + 1))
        S.save(path)
        sheets.append(path)
    return len(files), sheets


def render_pages(pdf, out, pages, dpi=100):
    paths = []
    for n in sorted(set(pages)):
        prefix = out / ("page-%d" % n)
        subprocess.run(["pdftoppm", "-r", str(dpi), "-png", "-singlefile", "-f", str(n), "-l", str(n), str(pdf), str(prefix)], check=True)
        paths.append(prefix.with_suffix(".png"))
    return paths


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("pdf")
    ap.add_argument("--pages", nargs="*", type=int, default=[])
    ap.add_argument("--out")
    ap.add_argument("--html", help="the built HTML (build.py --html): also run the Impeccable design detector on it")
    a = ap.parse_args()
    pdf = Path(a.pdf)
    out = Path(a.out or ("qa-" + pdf.stem))
    out.mkdir(parents=True, exist_ok=True)

    n, sheets = contact_sheets(pdf, out)
    flagged = []
    report = pdf.with_suffix(".report.json")
    if report.exists():
        data = json.loads(report.read_text())
        issues = data.get("issues", [])
        flagged = [i["page"] for i in issues if isinstance(i.get("page"), int) and i["page"] > 0]
        print("Report: %d issue(s)" % len(issues))
        for it in issues:
            print("  p%-4s %-16s %s" % (it.get("page", "-"), it["kind"], {k: v for k, v in it.items() if k not in ("page", "kind")}))
    pages = render_pages(pdf, out, flagged + a.pages) if (flagged or a.pages) else []
    print("%d pages → %s" % (n, ", ".join(str(s) for s in sheets)))
    if pages:
        print("Close-ups: " + ", ".join(str(p) for p in pages))
    if a.html:
        design_scan(Path(a.html), out)
    print("Always also view page 1 (cover) and the contents page close up before calling it done.")


def design_scan(html_path, out):
    """Impeccable's anti-pattern detector (npx impeccable detect) over the HTML and the theme.
    Catches AI-slop tells (side-tab borders, nested cards, cream palettes, stripe gradients) and
    craft issues (contrast, cramped padding, flat hierarchy). Needs Node; skipped if unavailable."""
    import shutil
    assets = Path(__file__).resolve().parent.parent / "assets"
    theme = out / "theme+signature.css"   # scan the stylesheet the book actually uses
    theme.write_text((assets / "theme.css").read_text() + "\n" + ((assets / "signature.css").read_text() if (assets / "signature.css").exists() else ""))
    if not shutil.which("npx"):
        print("Design scan skipped: npx not found (install Node to enable `impeccable detect`).")
        return
    try:
        r = subprocess.run(["npx", "-y", "impeccable@latest", "detect", "--json", str(html_path), str(theme)],
                           capture_output=True, text=True, timeout=600)
        data = json.loads(r.stdout or "[]")
    except Exception as e:
        print("Design scan failed:", e)
        return
    items = data if isinstance(data, list) else data.get("findings", [])
    (out / "design-scan.json").write_text(json.dumps(items, indent=2))
    hard = [i for i in items if not i.get("advisory")]
    print("Design scan (Impeccable): %d finding(s), %d advisory" % (len(hard), len(items) - len(hard)))
    seen = {}
    for i in items:
        key = (i["antipattern"], i.get("snippet", "")[:100])
        seen[key] = seen.get(key, 0) + 1
    for (k, snip), n in sorted(seen.items(), key=lambda x: -x[1])[:15]:
        print("  %-22s x%-3d %s" % (k, n, snip))


if __name__ == "__main__":
    main()
