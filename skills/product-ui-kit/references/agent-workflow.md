# Agent Workflow

Use this reference when building the initial frontend mockup or production scaffold.

## Product-Grade Mockup Standard

A mockup may use fake data and mocked API calls, but it should still have:

- real component hierarchy
- typed data shapes close to the production contract
- loading, empty, error, disabled, and success states
- mobile and desktop layouts
- keyboard/focus behavior for interactive controls
- realistic labels and state transitions
- clear separation between app UI, domain state, and integration boundaries

## shadcn Practice

- Add shadcn components via CLI.
- Compose product components outside `components/ui`.
- Avoid editing shared shadcn primitives unless the user asks for a design-system change.
- Use semantic tokens/classes where possible instead of one-off color inventions.
- Keep custom app components small enough that future agents can reason about them.

## Verification

For first scaffolds:

- run typecheck/build if dependencies are present
- visually inspect the main route if a dev server is running
- verify the UI handles the main empty/loading/error paths

For later production work:

- add Playwright when visual or flow regressions matter
- add focused tests around typed map actions and stale response handling
