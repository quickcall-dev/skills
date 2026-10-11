# Component reference

Every component is a fenced block whose language is the component name. It becomes a numbered figure: a hairline rule, "Figure 2.3" in the rail in the part's colour, the title beside it, then the graphic drawn directly on the page (no box).

## Contents
1. Shared rules (options, flags, captions, cover)
2. Choosing a component
3. Basic components: `flow` · `bars` · `strip` · `bytes` · `stack` · `cols` · `steps` · `stats` · `kv` · `tree` · `timeline` · `compare`
4. Advanced components: `diagram` · `sequence` · `lanes` · `chart` · `hexdump` · `panels`
5. Plain Markdown that is styled automatically: mermaid, code, tables, callouts, images, sources
6. Links and cross-references

`examples/gallery.md` shows every component as source next to its rendered result; build it when in doubt.

---

## 1. Shared rules

**Options** are `key: value` lines at the top of the block (some may also go at the end):

| Option | Effect |
|---|---|
| `title:` | figure title, set in the column beside the "Figure n.n" label in the rail |
| `tag:` | small muted label at the right of the figure header; only shown when you write one |
| `sub:` | italic line under the title: source, scope, "not to scale" |
| `note:` | small muted text inside the panel, under the figure |
| `caption:` | caption (prefer the `Caption:` paragraph below) |

Options can also go on the fence line: ```` ```bars title="Gap survey" tag=measured ````.

**Rows** split fields on `|`. **Flags** in braces, anywhere in the row, change emphasis using the section's accent:
`{hl}` highlight (the one thing to look at), `{dim}` de-emphasise / optional, `{gap}` hatched gap (strip), `{ghost}` borderless node (flow), `{mono}` monospace text, `{strong}` bold item. Combine: `{mono,hl}`.

Use `{hl}` on **one** element per figure, two at most. A figure where everything is highlighted says nothing.

**Captions**: a paragraph starting `Caption:` directly after a figure, table, code block or image attaches to it. Write it as `**Bold takeaway sentence.** Supporting detail, source, or how to read it.` The bold sentence is the point of the figure, not a description of it ("Most chains are short.", not "Chart of chain lengths.").

**Inline markup** inside components: `` `code` ``, `**bold**`, `*italic*`.

**Cover**: add `cover` to the fence line (```` ```bytes cover ````) to lift a component onto the cover instead of the body. Several may be stacked; `title:` becomes the plate label. `bytes`, `stats` and `flow` have dark-cover styles. Without any, the cover shows a map of the parts.

**`nofig`** on the fence line renders the component without a panel or number.

---

## 2. Choosing a component

| The content is… | Use |
|---|---|
| a system: components inside boundaries (processes, threads, services, crates) with arrows between them | `diagram` |
| messages between actors over time (protocols, RPC, handshakes) | `sequence` |
| who is busy when; overlap and idle time across components | `lanes` |
| a trend over time or a comparison of counts across categories | `chart` |
| the raw bytes of a file region, with fields marked | `hexdump` |
| two or three small views of one thing that belong together | `panels` |
| a simple left-to-right chain, a pipeline, a lineage | `flow` |
| a handful of labelled numbers to compare | `bars` |
| parts of one whole laid side by side (file regions, a budget, a timeline of size) | `strip` |
| specific bytes of a format, a header, a magic number | `bytes` |
| layers top to bottom (file anatomy, an architecture stack, memory) | `stack` |
| responsibilities split across components ("who owns what") | `cols` |
| numbered stages, each with a few facts | `steps` |
| 2–4 headline numbers | `stats` |
| one record, config, or object printed field by field | `kv` |
| a hierarchy: directories, a prim tree, an org | `tree` |
| dated events | `timeline` |
| two approaches side by side | `compare` |
| branching graphs, state machines, anything `diagram` can't lay out | `mermaid` |
| exact rows of data the reader will look up | a Markdown table |

---

## 3. Components

### flow
Rows of boxes joined by arrows. Node text: `Title / subline / subline`.

````
```flow
title: Format lineage
sub: predecessors · llama.cpp, 2023
GGML / unversioned -[version]-> GGMF v1 / adds a version -[alignment]-> GGJT / mmap aligned {hl}
>> KV header replaces 7 × u32
GGUF v1 / typed KV -[64-bit]-> GGUF v2 -[endianness]-> GGUF v3 {hl}
```
````
- `A -> B` plain arrow, `A -[label]-> B` labelled arrow. Spaces around arrows are required.
- `>> label` draws an elbow connector from the end of the previous row to the start of the next.
- `~~` adds vertical space between rows.
- Keep rows to ≤ 5 nodes and labels ≤ 12 characters; long hashes should be shortened (`ce013625030b…`).

### bars
````
```bars
title: Gap survey
sub: files with at least one gap · 715 files
unit: %
Arrow ≤ 17 | 98 | 228 of 233 files {hl}
Polars | 95 | 21 of 22
All writers | 35 | 249 of 715
```
````
`Label | value | note`. Options: `unit:` (a leading letter gets a space: `unit: MB`), `max:` (fix the scale, e.g. `max: 100` for percentages), `scale: log`. Values may contain commas.

### strip
Proportional horizontal segments.
````
```strip
title: Row group 0
sub: offsets 4 → 2,875,959 · not to scale
scale: sqrt
conversation_hash | 34,041 B
~ 141
model | 248 B
content | 2,790,676 B {hl}
brace: one read if the reader bridges gaps ≤ 8 KiB / six reads if it only merges ranges that touch
start: 4
end: 2,875,959
```
````
`name | size | sublabel`. A line starting `~` is a hatched gap (`~ 141`). `scale: sqrt` (default: honest order, small parts stay readable), `linear` (true proportions; tiny parts get a minimum width), `log`, `equal`. `brace:` puts a brace and a label under the strip (`/` separates a second, muted line). `start:` / `end:` label the ends.

### bytes
````
```bytes
title: The pack header
sub: first 12 bytes, big-endian
50 41 43 4b | "PACK" | signature
00 00 00 02 | version 2
00 00 67 16 | 26,390 objects {hl}
```
````
`hex bytes | label | description`. Abbreviate long runs: `3b 18 e5 12 db … 8d ad`. Only use glyphs that exist in JetBrains Mono (no `␀`/`␠`; write `\0`, `·`).

### stack
Vertical layers, top to bottom.
````
```stack
title: Layout of .git/index
scale: equal
HEADER | signature, version, entry count | 12 B | 0
Entries | one per path, sorted | 2 entries {hl} | 12
CHECKSUM | SHA-1 over everything above | 20 B | 225
end: 245
```
````
`name | detail | size | offset`. ALL-CAPS names render in mono (good for fixed sections). `scale: sqrt|linear|log` makes heights proportional to size (capped, so tall stacks stay on one page); default `equal`. `end:` labels the final offset. Offsets are shown at the top-left of each layer.

### cols
````
```cols
title: Who owns what
## Page · main thread
Public API, <usd-viewer>
three.js meshes + materials {hl}
> index.js · materials.js
## Worker · JS
request() + policy
fetch ⇄ add_layer loop
> worker.js · load-core.js
```
````
One `##` per column, one item per line, `>` lines become a mono footer. 2–4 columns.

### steps
````
```steps
title: Five stages of one file
## Bytes
laptop.usd {mono}
10.0 MB crate
> fetched once by the worker
## Layer {hl}
108 prims
parse 8 ms {strong}
```
````
Numbered left to right. `>` lines become an italic footnote under the step. 3–6 steps fit a page width.

### stats
````
```stats
26,390 | objects | in a single pack
12.7 MB | pack file | 14.3× smaller
```
````
`value | label | sub {hl}`. 2–4 per block, set as a row of facts in ink; `{hl}` turns one value to the accent. Values should be short (≤ 9 characters). Use it for a chapter's two or three defining numbers, not as decoration.

### kv
````
```kv
title: One spec
## Spec
path = …_mesh.points
type = Attribute
## Its fieldset
default = ValueRep  # offset into the values section {hl}
```
````
`key = value  # comment` (two spaces before `#`). `## Section` dividers optional.

### tree
````
```tree
title: The prim tree
/root
  Geometry/laptop_17z90ur
    laptop_mesh · Mesh {hl}
  _materials · Scope  # 26 materials
```
````
Two spaces per level. `name · meta` renders meta muted; `  # comment` renders an italic aside. Pre-drawn `├──` trees are accepted as-is, and an unlabelled code block containing one is upgraded to `tree` automatically.

### timeline
````
```timeline
2005-04 | First commit | self-hosting within days
2020-10 | Git 2.29 | experimental SHA-256 {hl}
```
````
`when | what | description`. Horizontal up to 6 items, vertical beyond (or `layout: vertical`).

### compare
````
```compare
## Loose objects
one zlib file per object
cheap to write
## Packfile {hl}
all objects in one file
deltas between similar objects
```
````
One `##` per side (2–3), one point per line. The `{hl}` side is usually the recommended or current one.

---

## 4. Advanced components

### diagram
The primitive behind the reference manuals' plates: zones (boundaries) containing boxes, on one shared column grid, with arrows routed after layout, numbered markers and a key.
````
```diagram
title: Anatomy of one load
caption: the page asks, the worker fetches, Rust parses
cols: 5
key: right
zone Page · main thread {c2}
  load(url) / or <usd-viewer> @1 #1 =load {mono}
  three.js scene / meshes, then textures @4-5 #8 =scene
zone Worker · JavaScript {c5}
  request / policy @1 #2 =req {mono}
  zone WASM · Rust over OpenUSD {c6} @2-4
    add_layer / parse · deps @2 #4 =add {mono}
    compose / one stage @3 #5 =compose
    no network · forbid(unsafe_code) @2-4 {note}
  postMessage @5 #7 =post {mono,tall}
- load -> req
- req -> add
- add -> compose
- compose -> post
- post -> scene
- req.b -> layers.t : fetch
- tex -> post {dashed}
#1 | Entry | a root .usd URL
#2 | request() | the one door out
```
````
- **Grid**: `cols: N` columns. `@2` puts a box in column 2, `@2-4` spans. Columns are absolute even inside zones, so boxes in different zones line up.
- **Zones**: `zone Label {c2} @1-3`; indent children two spaces. Nest zones for boundaries inside boundaries. Colour with `{c1}`…`{c9}` (pick colours that mean something and reuse them across figures and the cover `legend:`). `{dashed}` for optional or virtual boundaries.
- **Rows**: a box starts a new row when it begins at or left of the previous sibling's end; `^2` forces row 2 within its container. A line of `~` is an invisible spacer.
- **Boxes**: `Title / subtitle @cols #marker =id {flags}`. Flags: `{hl}`, `{dim}` (dashed, optional), `{mono}` (identifiers), `{tall}` (stretches across the rows of its container, e.g. a channel or bus), `{note}` (borderless italic annotation), `{ghost}`. Ids default to a slug of the title; set `=id` for anything you connect.
- **Edges**: `- a -> b`, `- a <-> b`, `- a -- b` (no arrowhead), `: label`, flags `{dashed}` `{hl}`. Ports are chosen automatically (side-by-side → left/right, stacked → top/bottom); force them with `a.b -> c.t` (`l r t b`). Same-side ports (`a.t -> b.t`) draw a loop around, and the diagram reserves room for it.
- **Key**: `#n | Label | description` lines; `key: right` (default when present), `below`, or `none`.
- Keep to ≤ 5 columns beside a key, ≤ 6 without. The build reports `diagram-overflow`, `key-overlap`, `label-collision` and `node-overlap`.

### sequence
````
```sequence
title: git push, simplified
actors: Client | Server {hl} | Hooks
Client -> Server : ref advertisement request
Server --> Client : refs + capabilities
Client => Server : packfile + ref updates {hl}
Server -> Server : verify pack
note Server : updates refs atomically
note Client..Hooks : everything above is one connection
== after the push ==
Server --> Client : report-status
```
````
`->` call, `-->` reply (dashed), `=>` the important call (thick), `A -> A` self message, `note A : …` or `note A..C : …` (spans actors), `== label ==` phase divider. 3–5 actors read best.

### lanes
````
```lanes
title: One load in time
sub: schematic, not to scale
range: 0 | 100 | %
Page | 0-6 load {dim} | 55-82 meshes as they arrive
Worker | 8-52 fetch ↔ add_layer {hl} | 55-80 read → transfer
Network | 6-48 layers, 16 in flight
mark: 55 | on screen
```
````
`Lane | start-end label {flags} | …`. `range: start | end | unit` sets the axis. `mark:` draws a dashed line through all lanes. Labels that don't fit a bar move outside it when there is free space; otherwise they truncate and the build reports `clipped-text`. If the timings are illustrative, say so in `sub:`.

### chart
````
```chart
title: Commits per year
type: line            # line | area | column
series: Commits | Merges
hl: Commits
y: commits
max: 600              # optional
2010 | 573 | 40
2011 | 475 | 35
mark: 2010 | first commit
band: 2014-2016 | rewrite
```
````
`x | value | value …`, one column per series; blank cells are gaps. Lines are direct-labelled at their last point (no legend); the `hl:` series is drawn in the accent, others in greys. The y-axis rounds up to a nice step. Columns support several series (grouped, with a legend). Use real data only.

### hexdump
````
```hexdump
title: .git/index, first 32 bytes
offset: 0
44 49 52 43 00 00 00 02 00 00 00 02 6a ca 7a a3
span 0-3 | signature "DIRC"
span 4-7 | version 2
span 8-11 | 2 entries {hl}
```
````
Hex bytes on any number of lines (or `text: GGUF\x03` to start from a string); `span a-b | label` colours an inclusive byte range and adds it to the legend; spans cycle six colours. `width: 8` for narrow dumps. Works on the dark cover with the `cover` flag.

### panels
Several sub-figures side by side under one figure number. Use a four-backtick outer fence and normal inner fences; each inner `title:` becomes "Fig. n — title".
`````
````panels
title: laptop.usd, exploded
widths: 1.25 1
```stack
title: elevation, byte 0 at top
...
```
```tree
title: the prim tree
...
```
````
`````

---

## 5. Plain Markdown, styled automatically

**Mermaid**: ```` ```mermaid ```` blocks render as themed figures (ink lines, sans labels, on the drafting grid). Give them a title with comment lines at the top: `%% title: …`, `%% sub: …`, `%% tag: …`. Add `:::hl` to a flowchart node to highlight it in the part accent. Prefer `flow` for simple left-to-right chains; use mermaid for branching graphs, cycles, sequence diagrams and state machines.

**Code**: ```` ```python title="worker.js" path="packages/viewer/src" ```` renders a panel with a file name, a muted path, and the language as a tag. Lines wrap (print cannot scroll). Blocks over ~38 lines may break across pages; add `long` to force that.

**Tables**: GFM tables get a ruled header in semibold sans, hairline rows, tabular figures and a bold first column. Add a `Caption:` paragraph. Right-align numeric columns with `---:`. Tables over 22 rows may break across pages.

**Callouts**: GitHub alert syntax, with an optional custom label on the first line.
```
> [!CAUTION] Gaps are not always metadata
> Bloom filters and page indexes may also sit between row groups.
```
The kind goes in the rail in its colour, with a hairline above: `NOTE` (blue, "Note"), `TIP` (green), `IMPORTANT`/`RULE` (violet, "Rule"), `WARNING` (amber), `CAUTION`/`DANGER`/`FOOTGUN` (crimson, "Footgun"), `RULES` ("What this rules out"), `VERIFY` (teal). A custom title on the first line becomes a bold run-in sentence at the start of the text. Any other blockquote becomes an italic pull quote.

**Images**: `![Title](relative/path.png "optional caption")` becomes a figure; local files are embedded.

**Sources**: a paragraph starting `Sources:` becomes the mono sources block. Put one at the end of each chapter that makes claims.

**Lead-ins**: a paragraph starting with `**Bold phrase.**` reads as a run-in heading; use it for definition-style paragraphs instead of a heading per term.

**Verify**: `> [!VERIFY]` (teal) tells the reader how to check a claim themselves.

---

## 6. Links and cross-references

The PDF gets a bookmark tree (parts → chapters → sections and figures), a clickable contents page and part openers, and clickable cross-references. All of it is generated; you only write references.

**Cross-references** are resolved by title, so they survive renumbering:

| You write | Renders as (clickable) |
|---|---|
| `[[Pack anatomy]]` | Pack anatomy (p. 16) |
| `[[Pack anatomy\|the pack format]]` | the pack format (p. 16) |
| `[[Fig: Finding one object]]` or `[[Fig: 3.6]]` | Fig. 3.6 (p. 16) |
| `[[2.3]]` / `[[§2.3]]` | the chapter's title (p. 12) |
| `[[Part 2]]` | Part 2 (p. 8) |
| `[[What a commit actually contains]]` | a `###` section, by title |
| `[text](#Pack anatomy)` | the same, in standard link syntax |

Matching ignores case and punctuation, and a unique prefix is enough (`[[Fig: Finding]]`). An unresolved reference renders struck through and is reported as `broken-ref`. References inside code are left alone.

**External links**: `[text](https://…)` and bare URLs are clickable and underlined. Put them in `Sources:` paragraphs or prose.

**Links written for GitHub keep working.** `[Android](#android-1)` resolves the way GitHub would: lowercase, punctuation dropped, a counter suffix for repeated headings. `<a name="x"></a>` anchors in the source are targets too. So a README or design doc full of in-page links builds with its links intact.

**Index**: `{{packfile}}` marks a term where it is explained; `{{fanout table|fanout table (idx)}}` shows the first text and files it under the second. Every paragraph that starts with a `**Term.**` definition is indexed automatically. The back-of-book index (alphabetical, letter headings, clickable page numbers) is added when there are 15+ entries or `index: true`. Mark the place a term is *explained*, not every mention: one to three entries per term.

**List of figures**: added as back matter automatically once a manual has 12 or more titled figures; force with `figures: true` or turn off with `figures: false` in the frontmatter. `outline_figures: false` keeps figures out of the bookmark tree.
