---
name: dag-fleet
description: Persistent, budgeted, DAG-ordered runner for parallel `claude -p`, `codex exec`, or `pi -p` workers in tmux. Use ONLY when you need persistence across sessions, per-worker budget caps, dependency ordering, or mixed models/providers per worker. For ad-hoc parallel sub-agents inside a live conversation, use Claude Code's built-in Agent tool instead.
argument-hint: "[launch|relaunch-worker|status|kill|report] [args]"
allowed-tools: Bash(bash ${AGENTS_SKILLS_DIR}/scripts/*), Read, Write, Glob
model: claude-sonnet-4-6
license: Apache-2.0
metadata:
  author: Sagar Sarkale
  version: "1.0"
---

# Fleet

A skill for running parallel `claude -p`, `codex exec`, or `pi -p` workers in tmux with budgets and DAG dependencies. Supports Claude, Codex, and Pi providers — set per-fleet or per-worker. Operator owns all kill / steer / re-direction — there is no auto-restart, no auto-verify, no babysitter loop.

## When to use this skill (and when NOT to)

**FIRST: prefer Claude Code's built-in Agent tool when any of these are true.** It's simpler, faster, and avoids the fleet machinery entirely.
- The work fits inside the current conversation
- All sub-agents will finish in under 10 minutes
- You'll synthesize the results in the same session
- You don't need budget caps or dependency ordering

**Reach for THIS skill only when ≥1 of these is true:**
- **Persistence:** the run will outlive the parent `claude` process (e.g. multi-hour fleet, user closes laptop)
- **Per-worker budgets:** you need `max_budget_usd: N` enforced per worker
- **DAG dependencies:** worker D must wait for A, B, C to finish first
- **Mixed models per worker:** Sonnet researchers + Haiku validators in the same fleet
- **Tmux pane visibility:** the user wants to attach to individual workers and watch them stream

If none of those apply, **stop reading this skill** and use the Agent tool.

## What this skill is NOT

- Not an auto-recovery system. If a worker fails or hangs, the operator decides what to do.
- Not a babysitter. There is no `orchestrate.sh`, no stuck-detection that kills, no mid-flight steering.
- Not for "spawn 3 quick lookups in parallel" — that's the Agent tool's job.

## Available scripts

| Script | When to call | Args |
|--------|-------------|------|
| `launch.sh` | Start a new fleet from a `fleet.json` you generated | `<fleet-root>` |
| `status.sh` | Show what's running, what's done, live cost, last message per worker | `<fleet-name-or-root> [-v] [--watch] [--json]` |
| `kill.sh` | Stop one worker or the entire fleet (operator's hard stop) | `<fleet-name-or-root> <worker-id>\|all [--force]` |
| `relaunch-worker.sh` | After editing one worker's `prompt.md`, re-run just that worker | `<fleet-name-or-root> <worker-id>` |
| `report.sh` | Generate a markdown summary when the fleet is done | `<fleet-root>` |
| `view.sh` | Capture a single worker's tmux pane content | `<fleet-name-or-root> <worker-id>` |
| `feed.sh` | Stream a unified event feed across all workers | `<fleet-name-or-root> [--agent <id>]` |

**Utilities (in `lib/`):**

| Utility | Purpose | Usage |
|---------|---------|-------|
| `dag-viz.py` | Visualize fleet DAG structure (ASCII or mermaid) | `python3 ${AGENTS_SKILLS_DIR}/lib/dag-viz.py <fleet.json> [--mermaid]` |

All scripts accept either an absolute fleet-root path **or** a fleet name (resolved via `~/.claude/fleet-registry.json`, populated automatically by `launch.sh`).

## Launch procedure (MUST follow exactly)

When the user asks you to launch a fleet:

1. **Set `FLEET_ROOT`** to the user's specified directory. Default to cwd if unspecified. Use absolute paths only.
2. **`mkdir -p $FLEET_ROOT/workers`**
3. **Generate `$FLEET_ROOT/fleet.json`** — see `references/fleet-json-schema.md` for the full schema. Required top-level fields: `fleet_name`, `config`, `workers[]`. Each worker needs `id`, `type`, `task`, `model`, `max_turns`, `max_budget_usd`. Use `depends_on: [...]` for DAG ordering.
4. **For each worker, create `$FLEET_ROOT/workers/{id}/prompt.md`.** The prompt MUST include this line verbatim:
   ```
   Save ALL output files to $FLEET_ROOT/workers/{id}/output/ — use absolute paths.
   ```
   (Substitute the real fleet root and worker id.)
5. **Run:** `bash ${AGENTS_SKILLS_DIR}/scripts/launch.sh $FLEET_ROOT`
6. **Do NOT** write your own tmux/claude commands. `launch.sh` handles topo sort, tmux session creation, per-worker spawning, budgets, and the registry.
7. **ALWAYS tell the user** the exact status command so they can monitor manually:
   ```
   bash ${AGENTS_SKILLS_DIR}/scripts/status.sh <fleet-name-or-root>
   ```
   This is mandatory after every launch. The user must be able to check status without asking you.

## Re-running ONE worker (the addendum workflow)

The user has a finished fleet and wants to add 1-2 sources / change one worker's instructions:

1. Edit `$FLEET_ROOT/workers/{id}/prompt.md` (add the new sources / instructions)
2. Run `bash ${AGENTS_SKILLS_DIR}/scripts/relaunch-worker.sh <fleet-name> {id}`
3. The worker's old `session.jsonl` is rotated to `.bak`, a fresh tmux window spawns, other workers are untouched
4. **The fleet's tmux session must still exist.** If it's been killed, the user must `launch.sh --force-relaunch` the whole fleet — `relaunch-worker.sh` only works against a live fleet session.

If the user wants to re-run multiple workers, do it one at a time. There is no batch re-run; that's intentional.

## Killing

There are two operator-initiated kill paths and **no automatic kills**:

- `kill.sh <fleet> <worker-id>` — kill one worker. Sweeps subprocess descendants. Use this when you've decided a single worker is going down the wrong path.
- `kill.sh <fleet> all --force` — tear down the entire fleet, kill all tmux windows, sweep every orphan subprocess, mark workers KILLED, unregister from the registry.

There is no `steer.sh`. There is no mid-flight redirection. The intentional workflow for "I want this worker to take a different direction" is: `kill.sh` it, edit `prompt.md`, `relaunch-worker.sh`. Three steps, fully under operator control.

## Resetting a partially-run fleet

Use when the fleet ran partially (bad prompts, wrong models, hit a bug) and you want to re-launch from scratch without state collision.

```
bash ${AGENTS_SKILLS_DIR}/scripts/reset.sh <FLEET_ROOT> [--soft|--hard] [--dry-run] [--force]
```

**Preserved (both levels):** `fleet.json` structure, `workers/{id}/prompt.md`.
**Gone on `--soft` (default):** prior run outputs archived to `archive/<ts>/`, tmux session killed, status fields in `fleet.json` cleared.
**Gone on `--hard`:** everything under the fleet root except `fleet.json` + prompts; registry entry removed.

Refuses with exit 2 if live workers detected — pass `--force` to kill them first. Preview with `--dry-run`.

## Worker types

The `type` field on each worker controls the `--disallowed-tools` set passed to claude (or the `--tools` allowlist for pi, or the sandbox mode for codex). Pick one:

- `read-only` — disallows: Bash, Edit, Write, Agent, WebFetch, WebSearch. **Cannot write files.** Only use for pure analysis where output is captured from assistant messages in session.jsonl.
- `write` — disallows: Bash, Agent, WebFetch, WebSearch. **Use for synthesizers and any worker that writes output files.**
- `code-run` — disallows: Agent, WebFetch, WebSearch (the typical default for build/test workers)
- `research` — disallows: Bash, Edit, Agent (web access enabled). **Use for researchers, not `read-only`.**
- `reviewer` — disallows: Bash, Edit, Agent, WebFetch, WebSearch. Has Read + Write only. Use for reviewers that write verdict files.
- `orchestrator` — disallows: Agent, WebFetch, WebSearch, Edit

**WARNING:** `read-only` cannot write files. If a worker needs to save output (findings.md, synthesis.md, etc.), use `write`, `research`, `reviewer`, or `code-run`. Setting a synthesizer to `read-only` will burn its entire budget trying to find a Write tool.

See `references/worker-types.md` for the full permission matrix.

## Provider support (Claude + Codex + Pi)

Workers can run on `claude` (default), `codex` (OpenAI Codex CLI), or `pi` (pi.dev CLI). Set at fleet level or per-worker:

```json
{
  "config": {
    "provider": "pi",
    "model": "k2p6",
    "reasoning_effort": "medium"
  },
  "workers": [
    { "id": "researcher", "type": "research", "provider": "pi", "model": "kimi-k2-thinking", "reasoning_effort": "high" },
    { "id": "writer", "type": "write", "provider": "claude", "model": "sonnet" }
  ]
}
```

```json
{
  "config": {
    "provider": "codex",
    "model": "gpt-5.4",
    "reasoning_effort": "medium"
  },
  "workers": [
    { "id": "researcher", "type": "research", "provider": "codex", "model": "gpt-5.4", "reasoning_effort": "medium" },
    { "id": "writer", "type": "write", "provider": "claude", "model": "sonnet" }
  ]
}
```

### Provider-specific fields

| Field | Values | Default | Scope |
|---|---|---|---|
| `provider` | `"claude"` \| `"codex"` \| `"pi"` | `"claude"` | config + per-worker |
| `reasoning_effort` | `"low"` \| `"medium"` \| `"high"` | (none) | config + per-worker, codex/pi only |

### Codex model aliases

| Model | Use case |
|---|---|
| `gpt-5.4` | Flagship — strongest reasoning, recommended default |
| `gpt-5.4-mini` | Fast/cheap — validators, simple tasks |
| `gpt-5.3-codex` | Coding-focused (migrating to gpt-5.4) |

### Pi models

Pi is a **provider harness**, not a model. The actual model is determined by whichever provider is configured in your `pi` setup. Run `pi --list-models` to see what's available.

**Example:** With the `kimi-coding` provider configured:

| Model | Use case |
|---|---|
| `k2p6` | Flagship — default, strongest reasoning |
| `kimi-for-coding` | Fast/cheap — validators, simple tasks |
| `kimi-k2-thinking` | Deep reasoning — research workers |

Whatever string you put in `model` is passed straight through to `pi -p --model`. No aliases, no validation.

### Provider limitations vs Claude

**Codex:**
- **No `--max-budget-usd`** — codex has no per-worker budget cap. Fleet-level cost tracking still works (estimated from token counts).
- **No `--fallback-model`** — codex has no automatic model fallback.
- **No per-tool disabling** — codex uses sandbox modes (`read-only`, `workspace-write`) instead of `--disallowed-tools`. Worker types are mapped automatically.
- **Web search** — research workers get `-c 'web_search="live"'` automatically.
- **All output workers need `workspace-write`** — codex `read-only` sandbox blocks ALL file writes including output.

**Pi:**
- **No `--max-budget-usd`** — pi has no per-worker budget cap. Fleet-level cost tracking works via token estimation.
- **No `--fallback-model`** — pi has no automatic model fallback.
- **`--tools` allowlist** — pi uses an allowlist (not blocklist). Worker types are mapped automatically to the correct tool set.
- **Session dir** — pi writes sessions to a per-worker `.pi-sessions/` directory and symlinks the JSONL log to the standard path.

## DAG dependencies

```json
{
  "id": "synthesizer",
  "depends_on": ["researcher-01", "researcher-02"]
}
```

`launch.sh` uses the shared `lib/dag.sh` primitives (Kahn's BFS-layered topo-sort) to order workers and waits for dependencies to emit a terminal `result` event before starting dependents. Cycles are detected before any tmux state is created — fleet exits 2 with `CYCLE:a,b,...` on stderr. Workers within a layer run in parallel up to `max_concurrent`. Use `dag-viz.py` to preview the DAG structure before launch.

## Budgets

- `worker.max_budget_usd: N` — per-worker hard cap, passed to `claude --max-budget-usd`
- `config.max_budget_fleet: N` — total fleet cap; `launch.sh` stops launching new workers once this is exceeded (already-running workers are not killed, the cap is "no new spending")

## STRICT RULES

1. **ALWAYS use the scripts above for EVERY operation.** Never write your own tmux / claude commands.
2. **NEVER use the `--bare` flag** with `claude` — causes auth failures.
3. **Fleet root = user's directory.** Default to cwd. ALL fleet files go inside `$FLEET_ROOT`.
4. **Worker output paths must be absolute:** `$FLEET_ROOT/workers/{id}/output/`. Tell the worker this in its prompt.md.
5. **`launch.sh` is the only way to start workers.** `relaunch-worker.sh` is the only way to selectively re-run one. There is no other path.
6. **Operator owns kill and direction changes.** Do not auto-kill, do not auto-restart, do not auto-redirect. If a worker is misbehaving, surface it to the user and let them decide.
7. **Do NOT invent missing scripts.** If you find yourself wanting `steer.sh`, `verify.sh`, `add-worker.sh`, or `orchestrate.sh` — they were intentionally removed. Use the operator-owned workflow above instead.

## Rationalizations to reject

| Agent says | Rebuttal |
|--|--|
| "The task is small enough that I can write the tmux commands myself" | The skill exists to prevent the 15 things you'll forget (unset CLAUDECODE, --disallowed-tools, session naming, registry, topo sort). Use launch.sh. |
| "I'll use `relaunch-worker.sh` to restart all stuck workers at once" | One at a time, intentional. Batch restart is how experiment 001 burned $20 — cache rebuilds on every worker compounded. |
| "The worker seems stuck — I should kill and restart it" | Long thinking blocks look like hangs. Check `status.sh` or `view.sh` first. Only the operator kills workers. |
| "I should add a verify step after each worker finishes" | There is no verify step. The operator reads output and decides. Auto-verify was removed after it caused more harm than the failures it caught. |
| "I'll just add `--bare` to speed things up" | `--bare` causes auth failures. Never use it. This is STRICT RULE #2. |

## When to give up on this skill

If the user asks for behavior that requires auto-recovery, mid-flight steering, or per-worker validation loops, **tell them this skill no longer does those things by design.** Suggest:
- For auto-recovery → they should run a watcher script themselves and call `kill.sh` + `relaunch-worker.sh` from it
- For mid-flight steering → kill + edit prompt.md + relaunch-worker
- For validation → they read the output files themselves and decide

The skill's surface area was deliberately reduced after experiments where automated behavior caused more harm than the failures it was trying to recover from.

$ARGUMENTS
