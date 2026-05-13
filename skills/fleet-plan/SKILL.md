---
name: fleet-plan
description: Analyze a task, pick the right fleet type, and generate a ready-to-launch fleet (fleet.json + prompt.md files). Discovers available fleet skills dynamically. Use when the user wants to run work in parallel, asks to "plan a fleet", or says "fleet-plan".
argument-hint: "<description of work to parallelize>"
allowed-tools: Read, Write, Edit, Glob, Grep, Bash(ls *), Bash(mkdir *)
license: Apache-2.0
metadata:
  author: Sagar Sarkale
  version: "1.0"
---

# Fleet Plan

Analyze work, pick the right fleet type, generate fleet.json + worker prompts. You plan — the fleet skills execute.

## Step 0: Discover available fleet types

Before planning, **read the fleet index** to know what's available:

1. Find the index: `Glob` for `**/fleet/FLEET-INDEX.md` (or look in the same parent dir as this skill)
2. Read `FLEET-INDEX.md` — it has a table of all fleet types with one-liner hints on when to use each
3. Based on the hints, **pick the best fleet type** for the user's task
4. **Then** read ONLY the chosen fleet's `SKILL.md` for the full schema: `Glob` for `**/<chosen-fleet>/SKILL.md`

This is a two-step lookup: cheap index first (one small file), full schema second (one SKILL.md). Never read all fleet SKILL.md files — that wastes context.

## Step 0.5: Verify prerequisites

Before generating the fleet, warn the user if any prerequisite is missing:

- **bash >= 4.0** — required for associative arrays in launch.sh. On macOS: `brew install bash` and invoke with `/opt/homebrew/bin/bash`
- **flock** — Linux has it built-in. On macOS: `brew install flock` or use `launch.sh --no-lock`
- **tmux** — `brew install tmux` or `apt install tmux`
- **jq** — `brew install jq` or `apt install jq`

If the user is on macOS, mention these upfront so they don't hit launch failures.

## Step 1: Ask where to place the fleet

Before analyzing anything, ask the user:

> Where should I place the fleet root? (Press enter for default)

- If the user provides a path → use it
- If the user ignores, says "default", or doesn't respond → use: `fleet-{YYYYMMDD-HHMMSS}-{fleet-name}/` in the current working directory

**Always use absolute paths for the fleet root.**

## Step 2: Pick a fleet type

Use the hints from FLEET-INDEX.md to match the user's task. Quick heuristic:

```
Q1: Can one agent handle this in a single session?
    YES → "No fleet needed — this fits in one session." STOP.

Q2: Does FLEET-INDEX.md have a matching fleet type?
    YES → Pick it. Read its SKILL.md for the full schema.

Q3: No match?
    → "Open multiple Claude Code sessions — you're the orchestrator." STOP.
```

After picking, read the chosen fleet's SKILL.md to get the exact fleet.json schema, worker type rules, and output path conventions. **Do not guess schemas from memory — read the SKILL.md.**
      STOP HERE.
```

**Show the user your reasoning.** Don't just pick a type — explain why.

## Step 3: Generate fleet.json

### Guardrail: unsupported provider or model

If the user requests a provider or model not in the valid lists below, you MUST either:
1. **Map to closest valid equivalent** and explicitly disclose: *"Fleet mode only supports [valid providers]. Mapped your request to [X] with [Y]."*
2. **Error and refuse to generate** if no reasonable mapping exists.

**Never silently emit invalid config.** The agent's own thinking recognizing a value is unsupported is not sufficient — the output must be valid.

### Valid models — ONLY use these

**Claude models (provider: "claude", default):**

| Alias | Full ID | When to use |
|-------|---------|-------------|
| `sonnet` | `claude-sonnet-4-6` | Default for most workers |
| `opus` | `claude-opus-4-6` | Complex reasoning, architectural review, large-context synthesis |
| `haiku` | `claude-haiku-4-5` | Cheap/fast — validators, linters, simple checks |

**Codex models (provider: "codex"):**

| Model | When to use |
|-------|-------------|
| `gpt-5.4` | Flagship — strongest reasoning, recommended default |
| `gpt-5.4-mini` | Fast/cheap — validators, simple tasks |
| `gpt-5.3-codex` | Coding-focused (migrating to gpt-5.4) |

**Default:** `sonnet` for Claude workers, `haiku` for fallback_model.
**Only use `opus`** when the task clearly needs it. Cost difference is significant.
**Use codex** when the user requests it or the task benefits from OpenAI models (e.g. research with web search via codex).

### Model family guidance

When the user says "use the [family]" without per-worker specifics, assign models by worker role:

**Claude family (provider: "claude"):**
| Worker role | Model | Why |
|-------------|-------|-----|
| Synthesis, architecture, complex reasoning | `opus` | Highest intelligence, largest context |
| General workers, researchers, builders | `sonnet` | Default — best cost/performance |
| Validators, linters, simple checks | `haiku` | Cheap/fast |

**Pi / Kimi family (provider: "pi"):**
| Worker role | Model | reasoning_effort |
|-------------|-------|------------------|
| Synthesis, deep reasoning, complex analysis | `kimi-k2-thinking` | `high` (or `medium` if not deeply analytical) |
| General coding, research, builders | `kimi-for-coding` | `medium` |
| Simple checks, validators | `kimi-for-coding` | `low` |

**Codex / GPT family (provider: "codex"):**
| Worker role | Model | reasoning_effort |
|-------------|-------|------------------|
| Complex reasoning, flagship tasks | `gpt-5.4` | `high` |
| General workers, research | `gpt-5.4` | `medium` |
| Validators, simple tasks | `gpt-5.4-mini` | `medium` or `low` |

**Rule:** Match model capability to task complexity. Don't put `opus` on a linter or `haiku` on an architecture review.

### Budget guidelines

| Task complexity | max_budget_usd |
|----------------|---------------|
| One-line change, simple edit | 0.25 - 0.50 |
| Moderate task (new function, refactor one file) | 1.00 - 2.00 |
| Complex task (new feature, multi-file changes) | 3.00 - 5.00 |
| Large task (architectural change, full module) | 5.00 - 10.00 |

**Do NOT set max_turns.** It defaults to unlimited. Budget is the only limiter.

### Validation checklist (MUST complete before output)

Before writing fleet.json to disk, verify EVERY item:
- [ ] `type` field present at top level (`"worktree"`, `"dag"`, or `"iterative"`)
- [ ] `max_turns` is NOT set on any worker (omit entirely for unlimited)
- [ ] `reasoning_effort` only paired with `codex` or `pi` provider
- [ ] All provider/model values are from the valid lists above
- [ ] Status command template uses `<fleet-root>` path, not fleet name

### Worker type selection — CRITICAL

Pick the worker type based on what the worker **needs to output**, not what it reads:

| Worker role | Correct type | WRONG type | Why wrong |
|-------------|-------------|------------|-----------|
| Researcher (web + findings file) | `research` | `read-only` | read-only has no WebFetch/WebSearch and cannot Write |
| Synthesizer (reads inputs, writes synthesis) | `write` | `read-only` | read-only cannot Write — burns entire budget trying |
| Code builder (shell + files) | `code-run` | `write` | write has no Bash |
| Reviewer (reads code, runs tests, writes verdict) | `reviewer` | `write` | reviewer has full access (Bash, Edit, etc.) for verification |

**`read-only` CANNOT write files.** Only use it for workers whose output is captured from assistant messages in session.jsonl, not from output files. If a worker needs to save ANY file, use `write`, `research`, `code-run`, or `reviewer`.

### fleet.json rules by type

**All types:**
```json
{
  "fleet_name": "<descriptive-kebab-case-name>",
  "type": "<worktree|dag|iterative>",
  "config": {
    "max_concurrent": 3,
    "model": "sonnet",
    "fallback_model": "haiku",
    "provider": "claude",
    "reasoning_effort": ""
  },
  "workers": [...]
}
```

`"type"` is a required top-level field.

**Provider fields (optional):**
- `config.provider` — `"claude"` (default) or `"codex"`. Per-worker override: `worker.provider`.
- `config.reasoning_effort` — `"low"`, `"medium"`, or `"high"` (codex only). Per-worker override: `worker.reasoning_effort`.
- When `provider: "codex"`, the `fallback_model` field is ignored (codex has no fallback).
- When `provider: "codex"`, `max_budget_usd` is NOT enforced per-worker (codex has no budget flag). Fleet-level cost tracking still works via token estimation.

**worktree-fleet additions:**
- Every worker MUST have `target_files` (array of file globs) and `branch` (unique branch name)
- No two workers can have overlapping target_files
- Default worker type: `code-run` (worktree workers need Bash for git commit)

**iterative-fleet additions:**
- Exactly one worker with `type: "reviewer"` (use `depends_on` to ensure it runs after builders)
- Must include `stop_when` block with at least `max_iterations` and `reviewer_lgtm_count`
- Workers have `max_budget_per_iter` instead of `max_budget_usd`

**dag-fleet additions:**
- Use `depends_on: ["worker-id"]` for dependency ordering
- Workers without dependencies run in parallel

### Config → prompt sync rule

After ANY change to `fleet.json` (models, budgets, methodology, provider), you MUST regenerate ALL `prompt.md` files to match. Prompts are not automatically synced — stale prompts cause partial update propagation bugs.

Specifically verify in each prompt.md:
- Model name matches fleet.json
- Budget value matches fleet.json
- Methodology (MECE, citations, web search) matches user requirements
- Output path rules match fleet type

## Step 4: Generate prompt.md for each worker

Create `$FLEET_ROOT/workers/{id}/prompt.md` for each worker. Every prompt MUST include:

1. **Clear task description** — what to do, in specific terms
2. **Scope boundaries** — what files to touch, what NOT to touch

### Output path rules (CRITICAL — different per fleet type)

**worktree-fleet:**
- Do NOT include a "Save ALL output to output/" line. The worker edits files in its worktree at the real repo paths.
- MUST include at the end:
  ```
  When you are done, commit your changes on the current branch with a descriptive message.
  ```

**dag-fleet:**
- Workers that produce artifacts (research, summaries, matrices) → include:
  ```
  Save ALL output files to $FLEET_ROOT/workers/{id}/output/ — use absolute paths.
  ```
- Workers that edit repo files (code changes, creating docs at specific paths) → tell them the exact target path. Do NOT also mention output/. One destination only.

**iterative-fleet:**
- Same as dag-fleet: if the deliverable is a specific file, give the exact path. Do not also mention output/.
- **Reviewer prompt MUST include verdict-writing instructions.** Without these, the reviewer won't write a verdict file and the orchestrator defaults to `iterate`, wasting an iteration. Every reviewer prompt.md must end with:

  ```
  ## Writing your verdict

  1. Determine the current iteration number: list the `iterations/` directory and find the
     highest-numbered subdirectory that does NOT yet contain a `review.md`.
  2. Write your verdict to `iterations/<N>/review.md` (relative to your working directory).
     **Never use absolute paths.**
  3. The file MUST contain a line exactly like one of:
     - `verdict: lgtm`
     - `verdict: iterate`
     - `verdict: escalate`
  4. Below the verdict line, list **actionable fix instructions** per worker — not just
     what's wrong, but exactly where and how to fix it (file path, function name, what
     to change). 2-3 precise points per worker. The builder sees this on next iteration,
     so vague feedback wastes a cycle.
  ```

  This is non-negotiable. Fleet 02 burned an iteration because the reviewer prompt didn't specify where/how to write the verdict.

**The rule:** Never give a worker two destinations. One task = one output location. Conflicting instructions cause workers to write to the wrong place.

## Step 5: Output to user

After generating everything, tell the user:

1. **Plan summary** — what each worker does (a table)
2. **Fleet type chosen** and why
3. **Launch command:**
   ```
   bash <path-to-fleet-skill>/scripts/launch.sh <fleet-root>
   ```
   For worktree-fleet, suggest `--dry-run` first.
4. **Status command:**
   ```
   bash <path-to-fleet-skill>/scripts/status.sh <fleet-root>
   ```
   `<fleet-root>` is the absolute path to the fleet directory. While status.sh can resolve fleet names, always give the user the absolute path to avoid confusion.

**ALWAYS give the user the status command.** This is mandatory.

## Preferred defaults

- **Implementation workers:** codex `gpt-5.3-codex`, `reasoning_effort: "medium"`
- **Reviewer workers:** claude `opus` (`claude-opus-4-6`), `reasoning_effort: "medium"`
- **max_turns:** unset (unlimited)
- **max_iterations** (iterative-fleet `stop_when`): `10`

Override only when user specifies different models/caps in the request.

## Rationalizations to reject

| Agent says | Rebuttal |
|--|--|
| "I can handle this without a fleet" | If the user asked for fleet-plan, they want parallel execution. Walk the decision tree and pick a type. Only say "no fleet" if Q1 is genuinely YES. |
| "I'll use opus for all workers since it's better" | Sonnet is the default. Opus costs ~5x more. Only use opus when the task demonstrably needs complex reasoning. |
| "I'll skip the decision tree and just use dag-fleet" | Walk the tree. Worktree-fleet is better for independent work (git isolation). Iterative-fleet is better for reviewer-gated work. dag-fleet is the fallback, not the default. |
| "The tasks overlap a little but worktree-fleet will work" | Overlapping files = not worktree-fleet. Use dag-fleet with depends_on, or restructure the split so files don't overlap. |
| "I'll set max_budget_usd high to be safe" | Budget should match task complexity. $0.50 for simple edits, $2 for medium, $5 for complex. Don't waste money. |
| "I don't know which fleet type to pick" | You have a decision tree. Walk it. If genuinely ambiguous after the tree, default to dag-fleet. |
| "The synthesizer just reads outputs, so read-only is fine" | **NO.** read-only cannot Write. The synthesizer reads inputs but WRITES a synthesis file. Use `write`. This mistake burned $1.23 in experiment 007 when Opus spent 26 turns trying to find a Write tool. |
| "Researchers should be read-only since they're reading" | **NO.** read-only has no WebFetch/WebSearch and no Write. Researchers need `research` type. |

$ARGUMENTS
