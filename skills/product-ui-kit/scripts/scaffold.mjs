#!/usr/bin/env node
import { mkdirSync, writeFileSync, existsSync } from "node:fs";
import { join } from "node:path";

const args = new Map();
for (let i = 2; i < process.argv.length; i += 1) {
  const item = process.argv[i];
  if (item.startsWith("--")) {
    const key = item.slice(2);
    const next = process.argv[i + 1];
    if (next && !next.startsWith("--")) {
      args.set(key, next);
      i += 1;
    } else {
      args.set(key, "true");
    }
  }
}

const framework = args.get("framework") || "next";
const maps = (args.get("maps") || "no").toLowerCase();
const root = process.cwd();
const outDir = join(root, ".agents", "frontend");

mkdirSync(outDir, { recursive: true });

function writeIfMissing(name, content) {
  const path = join(outDir, name);
  if (existsSync(path) && args.get("force") !== "true") {
    console.log(`skip ${path} (already exists; use --force to overwrite)`);
    return;
  }
  writeFileSync(path, content.trimStart());
  console.log(`wrote ${path}`);
}

const frameworkLabel = framework === "vite" ? "Vite + React" : "Next.js";
const useMaps = maps === "yes" || maps === "true" || maps === "map";

writeIfMissing(
  "STACK.md",
  `# Frontend Stack

Default framework: ${frameworkLabel}

## Base Dependencies

- TypeScript
- Tailwind CSS
- shadcn/ui
- lucide-react
${useMaps ? "- maplibre-gl\n" : ""}
## Open-Source Rule

Use open-source, source-owned, shadcn/Tailwind-compatible components by default. Prefer files that land in this repo and can be edited through normal Tailwind classes and shadcn CSS variables.

## Add Later Only When Needed

- Zustand: complex shared state, especially map/envelope/undo/filter state.
- React Hook Form + Zod: real validated forms.
- TanStack Table: advanced tables with sorting/filtering/pagination/column state.
- Playwright: production UI regression and flow checks.
- Recharts/shadcn charts: real chart requirements.

## Bloat Rule

Do not install a library until a concrete component or workflow needs it. The base app should stay small and production-shaped.
`,
);

writeIfMissing(
  "AGENT_RULES.md",
  `# Frontend Agent Rules

## Build Style

- Prefer shadcn/ui components before custom UI.
- Prefer complete reusable surfaces over loose primitives for non-frontend users.
- Do not hand-build common app chrome until an OSS block or house block has been considered.
- Compose product components outside shared shadcn primitives.
- Do not casually edit \`components/ui/*\`; treat those as design-system primitives.
- Use Tailwind for layout and local styling.
- Use lucide-react for icons.
- Include loading, empty, error, disabled, mobile, and keyboard/focus states for production-facing UI.

## Mockups

- Fake data is allowed.
- Keep typed data shapes close to the expected production API.
- Keep integration boundaries obvious: client module, state module, and UI components should be separate.
- Build clickable flows over static screenshots.

## Production Path

- Start lean.
- Add forms/tables/maps/tests only when required.
- Run build/typecheck when available.
- Avoid adding multiple UI libraries.
- Avoid premium/pro component catalogs unless the user explicitly opts in.
`,
);

writeIfMissing(
  "COMPONENT_MAPPING.md",
  `# Component Mapping

Use this file to map product-specific logical slots to actual components.

| Product slot | Implementation | Library | Notes |
|---|---|---|---|
| Auth/login shell | \`auth-clerk-shell\` | House registry + shadcn | Clerk-ready UI boundary; no auth vendor lock-in in UI |
| App shell/sidebar | \`app-shell-sidebar\` | House registry + shadcn | Layout, panels, responsive behavior |
| Chat shell | \`chat-shell\` | House registry or Manifest UI | Conversations, composer, thread rail |
| Dashboard overview | \`dashboard-overview\` | House registry + shadcn | KPI cards, activity, summary panels |
| Settings shell | \`settings-shell\` | House registry + shadcn | Tabs, profile/team/API/billing sections |
| Billing page | \`billing-page\` | House registry + shadcn | Plan cards, invoices, payment-state placeholders |
| Onboarding flow | \`onboarding-flow\` | House registry + shadcn | Stepper, checklist, next-action cards |
| Data table toolbar | \`data-table-toolbar\` | House registry + shadcn | Upgrade to TanStack only when table state demands it |
| Drawer/panel | | shadcn Sheet/Card/Resizable | |
| Primary input | | shadcn Input/Button | |
| Picker/dropdown | | shadcn Select/Popover/Command | |
| Filter panel | | shadcn Sheet/Popover + inputs | Generated from schema when possible |
| Details disclosure | | shadcn Accordion/Collapsible | |
| Status/alert | | shadcn Alert/Badge | |
| Data table | | shadcn Table | Start simple; use the toolbar block for filters/actions |
| Form | | shadcn Form/Input | Add RHF/Zod only for real validation |
${useMaps ? "| Map analysis shell | `map-analysis-shell` | House registry + MapLibre | shadcn controls around it, MapLibre renders geometry |\n| Legend | | Tailwind/shadcn | Derived from active layer/metric breaks |\n| Map status line | | Tailwind/shadcn Button | Undo/reset map-only actions |\n" : ""}
`,
);

writeIfMissing(
  "BLOCK_SOURCING.md",
  `# Block Sourcing

## Rule

Do not hand-build common app chrome by default. Search for a shadcn-compatible block first, then adapt it.

## Common Surfaces

| Surface | First source | Fallback |
|---|---|---|
| Sidebar / app shell | shadcn official sidebar/dashboard blocks | blocks.so, private registry |
| Navbar / header | shadcn Navigation Menu + official/OSS header blocks | Origin UI, custom composition |
| Chat UI | Manifest UI | shadcn primitives + custom message components |
| Dashboard cards | shadcn dashboard/cards blocks | blocks.so, custom composition |
| Settings page | shadcn form/card/tabs blocks | private registry pattern |
| Auth pages | shadcn login/signup blocks | private registry pattern |
| Map analysis shell | local pattern | MapLibre + shadcn panels |

## Provider Shortlist

- shadcn official blocks: safest first stop.
- Manifest UI: chat and agentic app surfaces.
- blocks.so: free practical sidebars/app blocks.
- Origin UI: polished app UI details.
- Kibo UI: advanced OSS app components after license/freshness check.
- Premium catalogs: not default. Mention only when explicitly requested.

## Private Registry Goal

Promote repeated patterns into your own registry:

- \`app-shell-sidebar\`
- \`auth-clerk-shell\`
- \`chat-shell\`
- \`dashboard-overview\`
- \`settings-shell\`
- \`billing-page\`
- \`onboarding-flow\`
- \`data-table-toolbar\`
- \`map-analysis-shell\`
`,
);

if (useMaps) {
  writeIfMissing(
    "MAP_GUIDE.md",
    `# Map Guide

## Default Renderer

Use MapLibre GL JS for production map surfaces that need vector layers, choropleths, feature click, highlights, and viewport-driven loading.

## Ownership

- shadcn/Tailwind: controls, filter panels, legends, drawers, scope stats, status line.
- MapLibre: canvas, sources, layers, feature click, viewport events.
- State: active level, metric, filters, selected feature IDs, highlights, viewport, undo stack.

## Rules

- Do not load the heaviest geometry at startup.
- Keep first-paint layers small.
- Load high-detail layers on viewport demand or explicit level switch.
- Push map action batches to a map-only undo stack.
- New question or layer change should abort or invalidate stale requests.
- The answer should stay rendered when map undo/reset changes the map.

## Suggested Modules

\`\`\`text
src/components/map/MapCanvas.tsx
src/components/map/Legend.tsx
src/components/map/MapStatusLine.tsx
src/lib/map-actions.ts
src/lib/map-state.ts
\`\`\`
`,
  );
}

console.log("");
console.log("Frontend grounding complete.");
console.log("Next: install only the dependencies this repo actually needs.");
