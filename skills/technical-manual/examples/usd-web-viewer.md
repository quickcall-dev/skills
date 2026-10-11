---
title: usd-web-viewer
name: usd-web-viewer

subtitle: Technical Manual
cover: light
legend: Page {c2} | Worker {c5} | WASM {c6} | Network {c4} | GPU {c3}
edition: Main b9d011f · Engineering edition · 2026.10
description: A browser viewer for OpenUSD, from a URL to pixels. What runs in WebAssembly, what runs in JavaScript, what crosses the line between them, and where every request is made.
---

```diagram cover
title: Plate I · anatomy of one load
caption: Fig. 1 — the page asks, the worker fetches, Rust parses and composes, buffers come back.
cols: 5
zone Page · main thread {c2}
  load(url) / or <usd-viewer> @1 #1 =load {mono}
  three.js scene / meshes, then textures @4-5 #8 =scene
zone Worker · JavaScript {c5}
  request / policy @1 #2 =req {mono}
  zone WASM · Rust over OpenUSD {c6} @2-4
    add_layer / parse · deps @2 #4 =add {mono}
    compose / one stage @3 #5 =compose {mono}
    read(i) / triangles @4 #6 =read {mono}
    no network · forbid(unsafe_code) @2-4 =nonet {note}
  postMessage / buffers moved @5 #7 =post {mono,tall}
zone Network {c4}
  USD layers / root, then references @1-2 #3 =layers
  texture images / decoded small @4-5 #9 =tex
- load -> req
- req -> add
- add -> compose
- compose -> read
- read -> post
- post -> scene
- req -> layers : fetch
- tex -> post {dashed}
#1 | Entry | a root .usd URL
#2 | request() | the one door out, policy first
#3 | Layers | fetched as Rust names them
#4 | add_layer | parse a file, list what it needs
#5 | Compose | merge every layer into one stage
#6 | read(i) | one mesh at a time, on demand
#7 | Transfer | buffers moved, not copied
#8 | Scene | three.js meshes, on screen
#9 | Textures | fetched and decoded small
```

## Three places code runs

*The page never parses USD. A worker owns the network and the WebAssembly, and hands the page buffers a GPU can draw.*

A USD scene is usually not one file but a stack of them: a small root that pulls in geometry, materials and physics by reference, with variants to choose between and instances to repeat. Showing it means fetching that stack, composing it the way Pixar's OpenUSD would, and turning the result into triangles. The library splits that work across three places, each chosen for one reason.

```cols
title: Who owns what
tag: structure
## Page · main thread
Public API, `<usd-viewer>`
three.js meshes + materials
compiles .wasm once
camera, lighting, toBlob
> index.js · materials.js · element.js
## Worker · JS
`request()` + policy {hl}
fetch ↔ add_layer loop
budgets: bytes, layers, tris
texture fetch + decode
> worker.js · load-core.js
## WASM · Rust
parse usda · usdc · usdz
compose the stage
extract triangles, normals
read shader graphs
> crates/usd-wasm over openusd
```

Caption: **Each column does one job.** The page draws, the worker decides what crosses the network, and Rust understands USD. Only the worker talks to both of the others.

### Why a worker at all

Parsing and composition take tens to hundreds of milliseconds on a real asset. In a worker that time never blocks scrolling or input on the page. The worker also gives memory a clean lifetime: WebAssembly memory can grow but never shrink, so each load gets its own worker, and terminating it returns every byte at once.

### Why Rust only parses

Rust holds no sockets and makes no requests. It receives bytes and returns two things ([[What crosses the line|the boundary API]]): the paths a file depends on, and, once everything is in memory, the scene. Keeping the network on the JavaScript side puts every request through one function that a reader can audit, and lets the browser's own fetch, cookies and caching do their normal work.

| Concern | Lives in | Why there |
|---|---|---|
| Fetching, credentials, retries | Worker (JS) | Browser fetch, cookies, CORS; one audited door |
| USD parsing and composition | WASM (Rust) | The openusd crate; memory-safe, no unsafe code |
| Triangulation, normals, UVs | WASM (Rust) | Tight loops over large arrays |
| Image decoding | Worker (JS) | `createImageBitmap` decodes off the main thread, resized |
| Rendering | Page (JS) | WebGL needs the page's canvas |

Caption: **The split, one line each.** About 3k lines of Rust and 1.9k lines of JavaScript sit on top of the ~128k-line openusd crate.

## What crosses the line

*Two small Rust classes, exposed through wasm-bindgen. Bytes go in, paths and buffers come out, and nothing else is shared.*

```kv
title: The API at the boundary
tag: interface
sub: worker calls · rust answers · wasm-bindgen
## UsdLoader
add_layer(path, bytes) = → Vec<String>  # paths it references, anchored to its URL {hl}
mark_unavailable(path) = compose without it  # a warning
take_scene() = → UsdScene  # compose + plan; or the layers still missing
## UsdScene
scene.meta() = JSON  # instances, matrices, materials, bounds
scene.read(i, maxTris) = builds mesh i now  # lazily
positions() normals() … = typed arrays  # copied out of WASM memory
packaged_file(p, limit) = an image inside a .usdz  # size-capped
```

Caption: **Two classes, nine calls.** UsdLoader gathers files and composes; UsdScene hands the result out one mesh at a time. `last_panic()` reports a Rust panic's message if one happens.

```diagram
title: Where bytes live
tag: memory
sub: each mesh is copied once
cols: 4
zone Worker {c5} @1-2
  WASM linear memory / layer bytes, the stage, one mesh while read @1 =wasm
  Worker JS heap / typed arrays, briefly · ImageBitmaps @2 =heap
zone Page {c2} @3-4
  Page heap / until upload @3 =page
  GPU / buffers, textures @4 =gpu {hl}
- wasm -> heap : copy
- heap -> page : move
- page -> gpu : upload {hl}
```

Caption: **Out of WASM memory into a JavaScript array, then moved to the page and uploaded.** One copy out of linear memory per array; `postMessage` transfers it with no copy; the page drops its CPU copy after upload, since bounds were computed in Rust.

> [!IMPORTANT] Invariants worth memorizing
> **Rust never fetches.** Every byte arrives through `add_layer` or `packaged_file`; the worker decides what to request ([[Every request, one door]]).
> **One mesh in WASM memory at a time.** `read(i)` builds a mesh, its arrays are taken out, and the next read reuses the space.
> **The meta JSON is the contract.** Instances, world matrices, material parameters and texture paths cross once, as text; arrays cross as typed arrays.
> **Each load gets a fresh worker.** Terminating it is how WebAssembly memory is returned.

## One file, taken apart

*A binary USD layer is a block of values followed by six small index sections, and like Parquet it is read starting from its end.*

The example: `laptop_17z90ur.usd` from LGElectronics/simready-assets, one 10.0 MB crate file. Every number in this chapter was read from it.

````panels
title: laptop_17z90ur.usd, exploded
tag: structure · not to scale
widths: 1.25 1
```stack
title: elevation, byte 0 at top
Header | PXR-USDC · 0.9.0 | 88 B | 0
values | points, indices, normals, primvars:st, subsets, shader inputs | 10.03 MB {hl} | 88
TOKENS · STRINGS | 238 tokens, 51 strings | | 10,034,840
FIELDS · FIELDSETS | 295 fields | |
PATHS · SPECS | 811 specs | |
TOC | 6 sections | 200 B | 10,043,958
end: 10,044,158
```
```tree
title: PATHS, the prim tree
/root
  Geometry/laptop_17z90ur
    laptop…_mesh · Mesh {hl}
      keyboard … · ×23 subsets
  _materials · Scope
    keyboard · Material
      Principled_BSDF
```
````

Caption: **Indexes at the end, values in front.** A reader jumps to the table of contents (the last 200 bytes), loads six sections totaling 9 KB, and only then knows where each attribute's array sits in the 10 MB of values.

```steps
title: Five stages of one file
tag: pipeline
## Bytes
laptop….usd {mono}
10.0 MB crate
238 tokens · 811 specs
> fetched once by the worker
## Layer
108 prims
1 Mesh · 23 GeomSubset
26 Material · 53 Shader
> parse 8 ms
## Stage
no references to follow
upAxis Z · metersPerUnit 1
subset → material bindings
> compose + extract 31 ms
## Extract {hl}
134,228 triangles {strong}
402,684 corners → 153,679 vertices
indices 32-bit · 23 groups
> weld, 2.6× fewer
## three.js
1 BufferGeometry
23 draw groups
3 base-color maps ≤ 1024 px
> root rotated Z-up → Y-up
```

Caption: **Most of the work is reshaping, not parsing.** USD stores a normal and a UV per triangle corner; GPUs want one per vertex. Welding identical corners shrinks 402,684 corners to 153,679 vertices.

```strip
title: What goes to the GPU
sub: 6.5 MB of a 10.0 MB file · meta JSON 7.4 KB
scale: linear
positions | 1.8 MB
normals | 1.8 MB
uvs | 1.2 MB
indices | 1.6 MB {hl}
start: 0
end: 6.4 MB
```

```js title="buildScene" path="index.js · simplified"
const geometry = new THREE.BufferGeometry();
geometry.setAttribute('position', new THREE.BufferAttribute(positions, 3)); // 153,679 × 3
geometry.setAttribute('normal', new THREE.BufferAttribute(normals, 3));
geometry.setAttribute('uv', new THREE.BufferAttribute(uvs, 2));
geometry.setIndex(new THREE.BufferAttribute(indices, 1));                   // Uint32, 402,684
for (const [start, count, subset] of groups) geometry.addGroup(start, count, slot(subset)); // 23
const mesh = new THREE.Mesh(geometry, materials);                          // 23 MeshStandardMaterial
root.rotation.x = -Math.PI / 2;                                             // upAxis Z → three.js Y
```

Caption: **Seven USD ideas, seven three.js objects.** Textures are applied later, one message each.

Sources: LGElectronics/simready-assets laptop_17z90ur.usd; crate TOC read with a 30-line script; prims via Pixar usd-core; extraction via usd-web-viewer b9d011f in Node, 2026-10-09.

## Fetch, compose, extract

*Rust learns what a file needs only by reading it, so loading is a loop: fetch what is known, parse it, and ask again until nothing new appears.*

```diagram
title: The fetch and compose loop
tag: flow
cols: 4
request(url) / policy, then fetch @1 #1 =req {mono}
add_layer / parse, list deps @2 #2 =add {mono}
new paths? / dedupe · caps @3 #3 =new
take_scene / compose + plan @4 #4 =take {mono,hl}
- req -> add
- add -> new
- new -> take : no
- new.t -> req.t : yes — fetch them, 16 at a time
- take.b -> req.b : missing a layer → fetch, compose again (≤ 16 rounds) {dashed}
```

Caption: **Discovery drives fetching.** On the Hub, one tree listing lets the worker start every layer in a package at once, so most packages finish in two rounds instead of one per level.

Each pass around [[Fig: The fetch and compose loop]] ends in the resolver. The resolver inside Rust is entirely in memory: a map from URL to bytes. When openusd asks to open a layer, the resolver serves it from that map; if the bytes are not there yet, composition reports the path as missing and the worker fetches it. Files inside a .usdz are read from the package already in memory, with each entry's size checked before it is inflated.

| Cap | Default | Hitting it |
|---|---|---|
| `maxLayerBytes` | 768 MiB | load fails with a fetch error |
| `maxLayers` | 1024 | load fails with a fetch error |
| `maxTriangles` | 20M, counted × instances | further meshes skipped, triangle-limit warning |
| `maxInstances` | 100,000 | further copies skipped, instance-limit warning |
| Zip entries | 512 MiB each · 1 GiB per package | package refused before inflating |

Caption: **Every load is bounded by caps the worker passes in,** including bytes prefetched from a Hub listing and files inflated from nested packages.

```diagram
title: From prims to buffers
tag: transform
cols: 3
zone USD prim {c2} @1
  Mesh / faceVertexCounts, points =mesh
  Cube · Sphere · … / implicit shapes =implicit
  Shader graph / PreviewSurface · OmniPBR · glTF =shader
zone extract.rs · material.rs {c6} @2
  n-gons → triangle fans / per subset =fan
  tessellate / implicit shapes =tess
  follow connections / → parameters, texture refs =follow
zone Out {c4} @3
  Arrays / Float32 positions, normals, UVs · Uint16/32 =arrays {hl}
  ~ =gap1 {ghost}
  Meta JSON / instances, materials, texture paths, bounds =meta
- mesh -> fan
- implicit -> tess
- shader -> follow
- fan -> arrays
- tess -> arrays
- follow -> meta
```

Caption: **Rust does the geometry, not the drawing.** Every rule from USD's schema (visibility, purpose, subset bindings, primitive sizes, shader defaults) is applied before anything reaches JavaScript.

## Every request, one door

*All network traffic for a load passes through a single function in the worker, which runs the request policy before the browser's fetch.*

```diagram
title: The policy
tag: decision
cols: 4
request(url) @1 =r {mono}
http(s) · no user@ / allowed origin @2 =chk
root's repo / cookies, headers @3-4 =repo {hl}
anything else / credentials omitted @3-4 =else
refused / → a missing layer or texture @2 =no {dim}
- r -> chk
- chk -> repo
- chk.r -> else.l
- chk -> no : ✕
```

Caption: **One function decides every request.** On the Hub, `resolve` URLs and the tree listing count as the root's repo.

```lanes
title: One load in time
sub: schematic, not to scale · parsing hides behind downloads
range: 0 | 100 | %
Page | 0-6 load {dim} | 55-82 meshes as they arrive | 82-100 apply textures
Worker | 0-8 init | 8-52 fetch ↔ add_layer {hl} | 55-80 read → transfer | 80-97 decode, 4 at a time
WASM | 8-50 compose as files arrive | 55-80 read(i), one mesh at a time | 97-100 freed {dim}
Network | 6-48 root, layers, 16 in flight {hl} | 78-95 images
mark: 55 | on screen
mark: 100 | done
```

Caption: **Each file is parsed as it arrives.** The WASM row is the loop from [[Fig: The fetch and compose loop]]. Measured on real SimReady packages, 80–94% of a load is network time and the WebAssembly work is 50–200 ms.

| Request | From | When |
|---|---|---|
| The .wasm module | Page | once per page, shared |
| Root USD file | Worker | start of each load |
| Hub tree listing | Worker | Hub roots, beside the root |
| Referenced layers | Worker | as add_layer names them |
| Texture images | Worker | after geometry, color first |
| Images in a .usdz | — | read from memory |

Caption: **Six kinds of request, five through `request()`.**

> [!VERIFY]
> Open the Space and watch the waterfall: each bar is one call through `request()`; only the page's .wasm fetch is absent.

Sources: packages/viewer/src/{index,worker,load-core,hub-prefetch,materials}.js; crates/usd-wasm/src/{wasm,lib,resolver,deps,extract,material,implicit}.rs @ b9d011f; measurements from the Space trace and the 22-load leak audit, 2026-10-09.
