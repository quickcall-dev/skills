# Product Component Map

Use this reference when the user provides a product spec, component inventory, or rough app idea. The goal is to map the product to reusable surfaces before building custom UI.

## Common Product Surfaces

| Product need | Start with | Add only when needed |
|---|---|---|
| Auth/login | `auth-clerk-shell`, shadcn login blocks, Clerk UI integration point | Real Clerk wiring, org switcher, invite flow |
| App chrome | `app-shell-sidebar`, shadcn sidebar/dashboard blocks | Role-based nav, command menu, notifications |
| Chat app | `chat-shell`, Manifest UI, shadcn sidebar/scroll/textarea/avatar | Streaming, attachments, threads, reactions |
| Dashboard | `dashboard-overview`, shadcn dashboard blocks | Recharts, TanStack Table, real metrics |
| Settings | `settings-shell` | React Hook Form + Zod for validation |
| Billing | `billing-page` | Stripe/Lemon Squeezy/backend integration |
| Onboarding | `onboarding-flow` | Persistent progress, invite/team steps |
| Data table | `data-table-toolbar`, shadcn Table | TanStack Table for real sorting/filtering/pagination |
| Map/geospatial | `map-analysis-shell` + MapLibre | Vector tiles, viewport loading, drawing tools |
| AI answer panel | Card, Accordion, Badge, Alert, Table, ScrollArea | Streaming, citations, retries, receipts |
| Admin CRUD | App shell + table toolbar + settings/form patterns | RHF/Zod, optimistic updates, permissions |

## Mapping Process

1. Identify the app archetype: SaaS dashboard, chat, internal tool, map app, marketplace, workflow tool, content app, admin panel, or hybrid.
2. List screens first, not components. Example: login, onboarding, dashboard, chat, settings, billing.
3. For each screen, pick an existing block before composing custom UI.
4. For each block, mark integration slots: auth provider, backend API, billing provider, map data source, chat backend, file storage.
5. Keep demo data realistic but removable.
6. Create reusable product components under `components/blocks` or `components/features`, not inside `components/ui`.

## State Boundaries

Keep state boring and explicit:

- Local component state for simple toggles and tabs.
- URL/search params for shareable filters and navigation state.
- React context or small store for cross-surface state such as current workspace, active conversation, selected map layer, or undo stack.
- Add Zustand only when prop-drilling or context churn becomes obvious.
- API client modules should own fetch, abort, idempotency, and typed response parsing.

## Production Defaults

Every first iteration should include:

- responsive desktop/mobile layout
- accessible labels and keyboard focus
- loading, empty, error, disabled, and success states
- realistic skeleton/demo data
- clear integration slots
- no unnecessary dependency sprawl

## Non-Frontend Operator Rule

When the user is not a frontend specialist, prefer a complete working surface over a bag of primitives. A good first pass should let the user continue product work without asking the agent to center buttons, fix mobile sidebars, invent spacing, or rebuild common forms.
