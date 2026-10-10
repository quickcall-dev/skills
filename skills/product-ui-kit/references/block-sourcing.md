# Block Sourcing

Use this reference when the product needs common structures that should not be rebuilt from scratch every time: sidebars, navbars, app shells, chat surfaces, cards, dashboards, settings pages, auth screens, pricing pages, and marketing sections.

## Rule

Search for an open-source compatible block first. Hand-build only when:

- the block does not exist,
- the block is lower quality than composing from primitives,
- the license/commercial terms are unacceptable,
- the block would introduce heavy dependencies,
- or the product needs a highly specific interaction.

Prefer sources that install through the shadcn CLI or a shadcn-compatible registry, because agents can inspect, install, and adapt them reliably.

Do not use premium/pro providers by default. The user's preference is open source, customizable, source-owned, Tailwind/shadcn-compatible, and easy to theme through ordinary CSS variables/Tailwind classes.

## Provider Tiers

| Tier | Provider | Best use | Notes |
|---|---|---|---|
| 1 | shadcn/ui official blocks | sidebars, dashboards, login/signup, base app shells | Free, open source, CLI install, safest first stop |
| 1 | Your private registry | repeated consulting patterns: app shell, chat shell, settings, billing, onboarding | Highest leverage; make this from blocks you keep reusing |
| 2 | blocks.so | free sidebars and practical app blocks | Good quick source for app chrome |
| 2 | Manifest UI | chat/agentic app components, message bubbles, conversation surfaces | Best fit for chat apps and chat and agent-style app UIs |
| 2 | Origin UI | polished copy-paste app components | Good for app UI details; review dependency needs |
| 2 | Kibo UI and other OSS registry.directory entries | advanced OSS app components | Verify license and freshness before use |
| Avoid by default | shadcn.io / Shadcnblocks / shadcn-ui-blocks / Shadcn Pro | large premium catalogs | Mention only when user explicitly asks for paid/pro speed |

## Search Order

For sidebars/app shells:

1. shadcn official `sidebar-*` and `dashboard-*` blocks.
2. blocks.so sidebar/application-shell blocks.
3. Your private registry `app-shell-sidebar`.
4. Hand-compose from shadcn primitives if the OSS block sources do not cover the need.

For chat apps:

1. Manifest UI chat blocks.
2. shadcn official primitives: sidebar, scroll area, textarea, command, avatar, badge.
3. Dedicated shadcn chat registries only after checking maintenance/license.
4. Build custom message rendering only for domain-specific interactions.

For dashboards/cards:

1. shadcn official `dashboard-01`, cards, charts, data table examples.
2. blocks.so or your private registry `dashboard-overview` if the dashboard shell is routine.
3. TanStack Table only when the table needs real sorting/filtering/pagination state.

## Agent Instructions

When asked to build a common UI surface:

- Identify the surface category first: app shell, sidebar, navbar, chat, dashboard, settings, auth, marketing, data table, map.
- Search installed/configured shadcn registries or ask the user before adding a new registry.
- Prefer OSS sources with clear license. If license is unclear, say so and avoid installing it.
- Install or copy one block, then adapt data, labels, routes, and domain-specific states.
- Keep block code source-owned in the app after installation.
- Do not preserve unused demo sections, fake nav items, or heavy dependencies.
- Do not mix multiple visual systems in one surface unless the user explicitly wants a hybrid.

## Private Registry Strategy

For consulting velocity, build a small internal registry from the patterns you reuse:

- `app-shell-sidebar`
- `chat-shell`
- `chat-conversation`
- `auth-clerk-shell`
- `settings-shell`
- `billing-page`
- `onboarding-flow`
- `dashboard-overview`
- `data-table-toolbar`
- `map-analysis-shell`

Make each registry item include only the files needed for that pattern: components, hooks, small utils, and docs. This lets agents install your house style instead of rediscovering it.

The `init-house-registry.mjs` helper creates a starter registry with usable source-owned blocks for these surfaces. Treat those generated blocks as the first internal version, then replace pieces with better OSS registry blocks as the house style matures.
