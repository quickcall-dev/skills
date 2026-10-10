---
name: product-ui-kit
description: Use when starting, scaffolding, or setting up React frontend repos with Tailwind, shadcn/ui, OSS blocks, reusable app surfaces, optional MapLibre maps, or product-grade mockup foundations.
argument-hint: "[audit|scaffold|plan-surface|init-house-registry] [options]"
allowed-tools: Bash(node ${AGENTS_SKILLS_DIR}/scripts/*), Read, Write, Glob, Grep
license: Apache-2.0
metadata:
  author: Sagar Sarkale
  version: "1.0"
---

# Product UI Kit

Use this skill when the user asks to start, scaffold, or set up a frontend repo, build a high-confidence mockup foundation, configure shadcn/Tailwind agent practices, or prepare a product UI that can move from prototype to production without a rewrite. It is intentionally generic and reusable across SaaS apps, chat apps, dashboards, internal tools, admin panels, map apps, workflow tools, and AI products.

The default philosophy is **open-source, source-owned, reusable, and production-shaped**: install the smallest durable base, use shadcn/Tailwind-compatible OSS blocks before hand-building common surfaces, create explicit frontend rules for agents, and add specialized libraries only when the product requires them. The first iteration should feel 90% usable without the user needing frontend expertise.

## Default Stack

- App: Next.js for product apps, Vite for small mockups/SPAs.
- Language: TypeScript.
- Styling: Tailwind CSS.
- UI: shadcn/ui plus lucide-react.
- Agent support: shadcn docs/skills when available in the user's environment; repo-local guidance in `.agents/frontend/` for Pi Agent and other Agent Skills runtimes.
- Block sourcing: open-source shadcn-compatible registries first; no premium/pro providers unless the user explicitly opts in.
- Maps: MapLibre GL JS only for map/geospatial apps.
- State: React state first; Zustand only when envelope/map/undo/filter state becomes awkward.
- Forms/tables/tests: add React Hook Form + Zod, TanStack Table, and Playwright only when the feature needs them.

## Workflow

1. Inspect the repo shape first: package manager, framework, existing Tailwind/shadcn setup, `components.json`, `package.json`, and any product spec.
2. Read [references/stack-policy.md](references/stack-policy.md) before recommending dependencies or setup commands.
3. Read [references/block-sourcing.md](references/block-sourcing.md) when the product needs common app structures: navbars, sidebars, app shells, chat layouts, cards, dashboards, settings, auth, pricing, or marketing sections.
4. If the product has maps, geospatial layers, choropleths, viewport loading, region selection, or undoable map actions, read [references/map-apps.md](references/map-apps.md).
5. Use `node ${AGENTS_SKILLS_DIR}/scripts/plan-surface.mjs --surface <surface>` to produce an OSS-first block/dependency plan for common surfaces such as chat, sidebar, dashboard, settings, auth, onboarding, and map.
6. If the user provides a component inventory, product spec, or rough app idea, read [references/product-component-map.md](references/product-component-map.md) and map the product to reusable surfaces before installing anything.
7. Use `node ${AGENTS_SKILLS_DIR}/scripts/scaffold.mjs` to create repo-local frontend guidance files under `.agents/frontend/`. The script does not install npm packages or overwrite application code.
8. Use `node ${AGENTS_SKILLS_DIR}/scripts/audit-project.mjs` to inspect whether a repo already has the expected frontend foundations.
9. If the team wants reusable house blocks, use `node ${AGENTS_SKILLS_DIR}/scripts/init-house-registry.mjs` to create a starter shadcn registry skeleton.
10. After scaffolding, give the user exact install commands for the chosen stack. Do not run package installs without normal permission/approval.

## Scaffold Command

Run from the target repo root:

```bash
node ${AGENTS_SKILLS_DIR}/scripts/scaffold.mjs --framework next --maps yes
```

Use `--framework vite` for small mockup repos. Use `--maps no` when the app has no geospatial surface.

The script writes:

- `.agents/frontend/STACK.md`
- `.agents/frontend/AGENT_RULES.md`
- `.agents/frontend/COMPONENT_MAPPING.md`
- `.agents/frontend/BLOCK_SOURCING.md`
- `.agents/frontend/MAP_GUIDE.md` when `--maps yes`

Other helpers:

```bash
node ${AGENTS_SKILLS_DIR}/scripts/plan-surface.mjs --surface chat,sidebar,dashboard
node ${AGENTS_SKILLS_DIR}/scripts/audit-project.mjs
node ${AGENTS_SKILLS_DIR}/scripts/init-house-registry.mjs
```

`init-house-registry.mjs` creates usable starter blocks for app shell/sidebar, Clerk-ready auth, chat shell, dashboard overview, settings, billing, onboarding, data table toolbar, and map analysis shell.

## Guardrails

- Do not bloat the base setup. Avoid adding chart, form, table, animation, map, data-fetching, or testing libraries until a concrete component or workflow needs them.
- Do not waste time hand-building common app chrome. Search for an **open-source** shadcn-compatible block first for navbars, sidebars, app shells, chat surfaces, settings layouts, auth pages, dashboard shells, and card grids.
- Do not recommend premium/pro providers by default. Mention them only as optional alternatives after the OSS path is exhausted or the user asks.
- Prefer shadcn components before custom UI. Prefer composition in app components over editing shared `components/ui/*`.
- Prefer complete reusable surfaces over loose primitives when the user is not a frontend specialist.
- For production-facing work, include loading, empty, error, disabled, mobile, keyboard, and accessible states in the scaffolded UI patterns.
- For mockups, use realistic fake data and real component structure. Keep backend calls mocked, but keep types close to the expected production envelope.
- For maps, keep the UI framework separate from the map renderer. shadcn handles controls and panels; MapLibre handles the canvas/layers.
