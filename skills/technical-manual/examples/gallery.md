---
title: Primitives Gallery
name: Gallery
subtitle: Every component, source and result
edition: technical-manual skill · 2026.10
description: Each primitive the skill provides, shown as the Markdown you write and the figure it becomes. Data comes from a real Git repository (a two-commit demo and a bare clone of pallets/flask).
---

## Structure

*Boxes, zones, layers and hierarchies: how a system is put together.*

### Diagram

````text title="source" path="what you write"
```diagram
title: Writing one commit
sub: demo repository · three stores, one ref
cols: 4
zone Working tree {c2} @1
  hello.txt / 12 bytes @1 #1 =wt
zone .git {c5} @2-4
  index / 245 B, 2 entries @2 #2 =idx
  zone objects/ {c6} @3-4
    blob 3b18e5 @3 #3 =blob {mono}
    tree 011831 @4 #4 =tree {mono}
    commit 5bd513 @3-4 #5 =commit {mono,hl}
  refs/heads/main / → 5bd513 @2 #6 =ref
- wt -> idx : add
- idx -> blob
- blob -> tree
- tree.b -> commit.t
- commit -> ref : moves {hl}
#1 | Working tree | the file you edited
#2 | Index | path, id and stat data
#3 | Blob | content only, no name
#4 | Tree | names the blob
#5 | Commit | names the tree
#6 | Ref | the only mutable piece
```
````

```diagram
title: Writing one commit
sub: demo repository · three stores, one ref
cols: 4
zone Working tree {c2} @1
  hello.txt / 12 bytes @1 #1 =wt
zone .git {c5} @2-4
  index / 245 B, 2 entries @2 #2 =idx
  zone objects/ {c6} @3-4
    blob 3b18e5 @3 #3 =blob {mono}
    tree 011831 @4 #4 =tree {mono}
    commit 5bd513 @3-4 #5 =commit {mono,hl}
  refs/heads/main / → 5bd513 @2 #6 =ref
- wt -> idx : add
- idx -> blob
- blob -> tree
- tree.b -> commit.t
- commit -> ref : moves {hl}
#1 | Working tree | the file you edited
#2 | Index | path, id and stat data
#3 | Blob | content only, no name
#4 | Tree | names the blob
#5 | Commit | names the tree
#6 | Ref | the only mutable piece
```

Caption: **Zones share one column grid**, so boxes in different zones line up. Markers link to the key; `{hl}` picks the one edge that matters.

### Panels

`````text title="source" path="what you write"
````panels
title: One index entry, two views
widths: 1.2 1
```kv
title: decoded
ctime = 0x6aca7aa3
mode = 0x81a4  # 100644 {hl}
size = 12
id = 3b18e512…
path = hello.txt
```
```tree
title: what it describes
repo/
  hello.txt · 12 B {hl}
  src/
    main.py
```
````
`````

````panels
title: One index entry, two views
widths: 1.2 1
```kv
title: decoded
ctime = 0x6aca7aa3
mode = 0x81a4  # 100644 {hl}
size = 12
id = 3b18e512…
path = hello.txt
```
```tree
title: what it describes
repo/
  hello.txt · 12 B {hl}
  src/
    main.py
```
````

Caption: **Sub-figures share one number.** Each inner title becomes a 'Fig. n —' sub-caption.

### Cols

````text title="source" path="what you write"
```cols
title: Who owns what
## Porcelain
git add, commit, log
> user-facing
## Plumbing
hash-object, cat-file {hl}
update-ref, write-tree
> scriptable, stable
## Storage
objects/, refs/, index
> files on disk
```
````

```cols
title: Who owns what
## Porcelain
git add, commit, log
> user-facing
## Plumbing
hash-object, cat-file {hl}
update-ref, write-tree
> scriptable, stable
## Storage
objects/, refs/, index
> files on disk
```

Caption: **Responsibilities side by side.** Footers (`>`) carry file names or notes.

### Tree

````text title="source" path="what you write"
```tree
title: .git, abridged
.git/
  HEAD  # ref: refs/heads/main
  objects/
    ce/
      013625…  · blob, 21 B {hl}
    pack/
  refs/
    heads/
      main
```
````

```tree
title: .git, abridged
.git/
  HEAD  # ref: refs/heads/main
  objects/
    ce/
      013625…  · blob, 21 B {hl}
    pack/
  refs/
    heads/
      main
```

Caption: **Two spaces per level.** `· meta` is muted, `# note` is an aside.

### Stack

````text title="source" path="what you write"
```stack
title: .git/index, version 2
scale: sqrt
HEADER | DIRC, version, count | 12 B | 0
Entries | stat data, id, flags, path | 2 entries {hl} | 12
CHECKSUM | SHA-1 of the above | 20 B | 225
end: 245
```
````

```stack
title: .git/index, version 2
scale: sqrt
HEADER | DIRC, version, count | 12 B | 0
Entries | stat data, id, flags, path | 2 entries {hl} | 12
CHECKSUM | SHA-1 of the above | 20 B | 225
end: 245
```

Caption: **Layers top to bottom** with offsets on the left and sizes on the right.

## Flow and time

*What happens in what order, and who is busy when.*

### Flow

````text title="source" path="what you write"
```flow
title: Content addressing
blob 6\0hello\n {mono} -[SHA-1]-> ce013625… {mono,hl} -[zlib]-> objects/ce/0136… {mono}
```
````

```flow
title: Content addressing
blob 6\0hello\n {mono} -[SHA-1]-> ce013625… {mono,hl} -[zlib]-> objects/ce/0136… {mono}
```

Caption: **Rows of boxes and labelled arrows.** Use `>>` between rows for an elbow connector.

### Steps

````text title="source" path="what you write"
```steps
title: Writing one object
## Header
`blob 6\0`
## Hash {hl}
SHA-1 → `ce0136…`
## Deflate
zlib level 1
## Rename
atomic write
```
````

```steps
title: Writing one object
## Header
`blob 6\0`
## Hash {hl}
SHA-1 → `ce0136…`
## Deflate
zlib level 1
## Rename
atomic write
```

Caption: **Numbered stages.** `{hl}` on a heading highlights the step.

### Sequence

````text title="source" path="what you write"
```sequence
title: git push, simplified
actors: Client | Server {hl} | Hooks
Client -> Server : ref advertisement request
Server --> Client : refs + capabilities
Client => Server : packfile + ref updates {hl}
Server -> Hooks : pre-receive
Hooks --> Server : ok
note Server : updates refs atomically
Server --> Client : report-status
```
````

```sequence
title: git push, simplified
actors: Client | Server {hl} | Hooks
Client -> Server : ref advertisement request
Server --> Client : refs + capabilities
Client => Server : packfile + ref updates {hl}
Server -> Hooks : pre-receive
Hooks --> Server : ok
note Server : updates refs atomically
Server --> Client : report-status
```

Caption: **Native sequence diagrams.** `-->` is a reply, `=>` the important call, `note A : …` annotates a lifeline.

### Lanes

````text title="source" path="what you write"
```lanes
title: A clone, who is busy
sub: schematic
range: 0 | 100 | %
Network | 0-70 receive pack {hl}
CPU | 10-72 index-pack | 72-95 checkout
Disk | 5-72 write .pack | 72-98 write files
mark: 72 | pack complete
```
````

```lanes
title: A clone, who is busy
sub: schematic
range: 0 | 100 | %
Network | 0-70 receive pack {hl}
CPU | 10-72 index-pack | 72-95 checkout
Disk | 5-72 write .pack | 72-98 write files
mark: 72 | pack complete
```

Caption: **Swimlanes over time.** Marks draw a dashed line through every lane.

### Timeline

````text title="source" path="what you write"
```timeline
2005-04 | First commit | self-hosting in days
2005-12 | Git 1.0
2020-10 | Git 2.29 | SHA-256, experimental {hl}
2024-04 | Git 2.45 | reftable
```
````

```timeline
2005-04 | First commit | self-hosting in days
2005-12 | Git 1.0
2020-10 | Git 2.29 | SHA-256, experimental {hl}
2024-04 | Git 2.45 | reftable
```

Caption: **Dated events.** Vertical automatically beyond six.

## Data

*Numbers as shapes: trends, comparisons and proportions.*

### Chart

````text title="source" path="what you write"
```chart
title: Commits per year, pallets/flask
sub: all refs · 5,603 commits
type: line
series: Commits
y: commits
2010 | 573
2011 | 475
2012 | 332
2013 | 321
2014 | 465
2015 | 266
2016 | 299
2017 | 434
2018 | 321
2019 | 345
2020 | 263
2021 | 458
2022 | 376
2023 | 327
2024 | 172
2025 | 91
2026 | 85
mark: 2010 | first commit
```
````

```chart
title: Commits per year, pallets/flask
sub: all refs · 5,603 commits
type: line
series: Commits
y: commits
2010 | 573
2011 | 475
2012 | 332
2013 | 321
2014 | 465
2015 | 266
2016 | 299
2017 | 434
2018 | 321
2019 | 345
2020 | 263
2021 | 458
2022 | 376
2023 | 327
2024 | 172
2025 | 91
2026 | 85
mark: 2010 | first commit
```

Caption: **Direct labels, no legend.** The highlighted series is drawn last in the accent; `mark:` and `band:` annotate. 2026 is a partial year (to October).

### Chart column

````text title="source" path="what you write"
```chart
title: Tags per year, pallets/flask
type: column
series: Tags
2010 | 8
2011 | 4
2012 | 2
2013 | 2
2014 |
2015 |
2016 | 3
2017 | 2
2018 | 5
2019 | 4
2020 | 2
2021 | 7
2022 | 8
2023 | 8
2024 | 11
2025 | 2
2026 | 1
```
````

```chart
title: Tags per year, pallets/flask
type: column
series: Tags
2010 | 8
2011 | 4
2012 | 2
2013 | 2
2014 |
2015 |
2016 | 3
2017 | 2
2018 | 5
2019 | 4
2020 | 2
2021 | 7
2022 | 8
2023 | 8
2024 | 11
2025 | 2
2026 | 1
```

Caption: **Columns for counts.** Blank values are gaps, not zeros.

### Bars

````text title="source" path="what you write"
```bars
title: In-pack bytes by type
unit: MB
blob | 9.05 | 71% of the pack {hl}
commit | 2.19
tree | 1.44
tag | 0.015
```
````

```bars
title: In-pack bytes by type
unit: MB
blob | 9.05 | 71% of the pack {hl}
commit | 2.19
tree | 1.44
tag | 0.015
```

Caption: **A handful of labelled numbers.** `unit:`, `max:`, `scale: log`.

### Stats

````text title="source" path="what you write"
```stats
26,390 | objects | one pack
14.3× | smaller | than raw
22 | max chain | deltas deep
```
````

```stats
26,390 | objects | one pack
14.3× | smaller | than raw
22 | max chain | deltas deep
```

Caption: **Two to four headline numbers.**

### Strip

````text title="source" path="what you write"
```strip
title: pack-52b6bc9c….pack
scale: log
HEADER | 12 B
objects | 12,697,252 B {hl}
TRAILER | 20 B
start: 0
end: 12,697,284
```
````

```strip
title: pack-52b6bc9c….pack
scale: log
HEADER | 12 B
objects | 12,697,252 B {hl}
TRAILER | 20 B
start: 0
end: 12,697,284
```

Caption: **Parts of one whole**, proportional (`linear`), readable (`sqrt`, default) or `log`.

## Bytes

*Formats on disk, down to the byte.*

### Bytes

````text title="source" path="what you write"
```bytes
title: Pack header
50 41 43 4b | "PACK"
00 00 00 02 | version 2
00 00 67 16 | 26,390 objects {hl}
```
````

```bytes
title: Pack header
50 41 43 4b | "PACK"
00 00 00 02 | version 2
00 00 67 16 | 26,390 objects {hl}
```

Caption: **Labelled byte groups** for headers and magic numbers.

### Hexdump

````text title="source" path="what you write"
```hexdump
title: .git/index, first 80 bytes
sub: demo repository
44 49 52 43 00 00 00 02 00 00 00 02 6a ca 7a a3
08 e7 31 34 6a ca 7a a3 08 e7 31 34 00 00 fe 00
00 2a c0 35 00 00 81 a4 00 00 00 00 00 00 00 00
00 00 00 0c 3b 18 e5 12 db a7 9e 4c 83 00 dd 08
ae b3 7f 8e 72 8b 8d ad 00 09 68 65 6c 6c 6f 2e
span 0-11 | header: DIRC, v2, 2 entries
span 12-35 | ctime, mtime, dev, ino
span 36-39 | mode 100644
span 48-51 | size 12
span 52-71 | object id 3b18e5… {hl}
span 72-79 | flags, path "hello."
```
````

```hexdump
title: .git/index, first 80 bytes
sub: demo repository
44 49 52 43 00 00 00 02 00 00 00 02 6a ca 7a a3
08 e7 31 34 6a ca 7a a3 08 e7 31 34 00 00 fe 00
00 2a c0 35 00 00 81 a4 00 00 00 00 00 00 00 00
00 00 00 0c 3b 18 e5 12 db a7 9e 4c 83 00 dd 08
ae b3 7f 8e 72 8b 8d ad 00 09 68 65 6c 6c 6f 2e
span 0-11 | header: DIRC, v2, 2 entries
span 12-35 | ctime, mtime, dev, ino
span 36-39 | mode 100644
span 48-51 | size 12
span 52-71 | object id 3b18e5… {hl}
span 72-79 | flags, path "hello."
```

Caption: **Offset, hex, ASCII**, with coloured spans and a legend. Spans cycle six colours.

### Kv

````text title="source" path="what you write"
```kv
title: commit 5bd513
tree = 0118312260c2…  # the snapshot {hl}
parent = 63f6041c8173…
author = Ada <ada@example.com>
```
````

```kv
title: commit 5bd513
tree = 0118312260c2…  # the snapshot {hl}
parent = 63f6041c8173…
author = Ada <ada@example.com>
```

Caption: **One record, field by field.** `  # comment` adds an aside.

## Text

*Prose-shaped content that still deserves structure.*

### Compare

````text title="source" path="what you write"
```compare
## Loose
one file per object
cheap to write
## Packed {hl}
one file for all
deltas between versions
```
````

```compare
## Loose
one file per object
cheap to write
## Packed {hl}
one file for all
deltas between versions
```

Caption: **Two approaches side by side.** `{hl}` marks the recommended side.


### Callouts

````text title="source" path="what you write"
> [!CAUTION] Footgun title
> Body text.
````

> [!NOTE]
> Clarifications. Blue.

> [!TIP]
> Shortcuts. Green.

> [!IMPORTANT] Invariant
> Rules that always hold. Violet.

> [!WARNING]
> Sharp edges. Amber.

> [!CAUTION] Footgun
> Things that break. Crimson.

> [!RULES]
> - No mixed hash formats
> - No unreachable writes

> [!VERIFY]
> How the reader can check a claim themselves.

### Tables and code

| Setting | Default | Controls |
|---|---:|---|
| `pack.window` | 10 | delta candidates tried |
| `pack.depth` | 50 | longest delta chain |

Caption: **Tables get a ruled header, hairline rows and tabular figures.** Right-align numbers with `---:`.

```console title="Check a hash" path="any shell"
$ echo hello | git hash-object --stdin
ce013625030ba8dba906f756967f9e9ca394464a
```

Caption: **Code panels** show `title`, `path` and the language.
