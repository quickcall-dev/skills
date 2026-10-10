# Stack Policy

## Bare Minimum Open-Source Stack

Use this base for most new production-shaped React frontends:

| Layer | Default | Why |
|---|---|---|
| Framework | Next.js for products, Vite for simple mockups/SPAs | Durable app structure or fast small-app setup |
| Language | TypeScript | Typed API envelopes, component contracts, map actions |
| Styling | Tailwind CSS | Fast iteration, shadcn compatibility, agent-readable styling |
| UI | shadcn/ui | Copy-in components, low bundle risk, easy customization |
| Icons | lucide-react | Small, consistent icon set commonly used with shadcn |
| Agent support | shadcn docs/skills plus repo-local `.agents/frontend/*` docs | Reduces hallucinated component APIs and keeps conventions explicit |

All defaults should be open-source and source-owned. Prefer libraries whose code lands in the repo or whose APIs are conventional Tailwind/React. Avoid proprietary override systems and vendor-specific theming paths.

## Add Only When Needed

| Need | Add | Trigger |
|---|---|---|
| Geospatial map, choropleth, vector layers | MapLibre GL JS | Product has a real map canvas |
| Complex shared state | Zustand | React state/contexts become hard to reason about |
| Real forms with validation | React Hook Form + Zod | Forms need validation, submit lifecycle, typed schema |
| Serious data grids | TanStack Table | Sorting/filtering/pagination/column state is required |
| Visual/e2e confidence | Playwright | UI is production-bound or agent changes need verification |
| Charts | Recharts or shadcn charts | Product has actual chart requirements |

## Avoid By Default

- Heavy animation libraries for ordinary dashboards.
- Multiple UI libraries in the same product.
- Installing every shadcn registry or block library upfront.
- Premium/pro component catalogs as the default path.
- Global state libraries before there is cross-component state pressure.
- Map libraries in non-map apps.
- Data-fetching libraries unless caching, dedupe, or server synchronization is genuinely needed.

## Recommended Install Commands

Choose one app foundation:

```bash
npx create-next-app@latest
```

or:

```bash
npm create vite@latest
```

Then initialize Tailwind and shadcn using the current official docs for the selected framework. Prefer the shadcn CLI over manually copying component files.

Common add-ons:

```bash
npm install lucide-react
npm install maplibre-gl
npm install zustand
npm install react-hook-form zod
npm install @tanstack/react-table
npm init playwright@latest
```

Only run the add-on commands when the need is present.
