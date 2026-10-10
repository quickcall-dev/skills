# Map Apps

Use this reference when the product includes a map, geospatial layers, choropleths, feature selection, viewport loading, or map-driven answers.

## Architecture

Separate the application into three layers:

| Layer | Owns | Typical code |
|---|---|---|
| UI controls | drawers, filters, legend, status line, buttons, tables | shadcn/ui + Tailwind |
| Map renderer | canvas, sources, layers, feature click, viewport events | MapLibre GL JS |
| Map state | active level, metric, filters, selected features, highlights, undo stack | React state or Zustand |

Do not make shadcn responsible for rendering map geometry. Do not make MapLibre responsible for app panels and forms.

## MapLibre Default

Prefer MapLibre GL JS for production map apps that need vector layers, choropleths, viewport-driven loading, and precise layer styling. Leaflet is acceptable for simpler marker/tile maps, but MapLibre is a better default for choropleth/vector-heavy products.

## Performance Rules

- Keep startup payload small. Load first-paint layers only.
- Defer heavy layers until viewport demand or explicit level switch.
- Avoid loading highest-granularity geometry at startup.
- Prefer simplified geometry or vector tiles for dense regional layers.
- Treat map updates as batches so undo/reset is predictable.
- Keep answer rendering independent from secondary map fetches.

## Interaction Rules

- Map feature click should emit a typed feature object, not mutate global loose state.
- Question asks should include `map_context`: level, metric, viewport, selection IDs, and filters.
- Undo/reset should affect map state only unless the product explicitly says otherwise.
- Stale map/query responses must be ignored after a newer question/layer change.
- The status line should explain the last map mutation in user language.

## Suggested Dependencies

Install for map apps:

```bash
npm install maplibre-gl
```

Consider later:

```bash
npm install zustand
```

Use Zustand when map state spans many components: map canvas, filters, legend, answer actions, status line, undo stack, and scope stats.
