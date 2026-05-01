---
name: worktree-fleet
description: Independence-validated parallel fleet that runs each worker (claude -p, codex exec, or pi -p) in its own git worktree. Use when tasks touch non-overlapping files and you need merge-safe isolation (each worker on its own branch). For DAG-ordered one-shot workers with budgets, use dag-fleet. For headless iteration with a reviewer loop, use iterative-fleet.
argument-hint: "[launch|status|merge|cleanup] [args]"
allowed-tools: Bash(bash ${CLAUDE_SKILL_DIR}/scripts/*), Read, Write, Glob
model: claude-sonnet-4-6
license: Apache-2.0
metadata:
  author: Sagar Sarkale
  version: "1.0"
---

# Worktree Fleet

A skill for running N independent agents in parallel, each isolated in its own git worktree on its own branch. Independence is validated before anything spawns — if two workers declare overlapping `target_files`, the skill refuses with a clear conflict message.

## Decision tree — which fleet?

```
You want to run multiple agents in parallel. Which fleet?

1. Are the tasks independent (no shared files, no shared state)?
   YES → worktree-fleet  ← YOU ARE HERE
   NO  → continue

2. Does the work need iteration with a reviewer making accept/iterate decisions?
   YES → iterative-fleet
   NO  → continue

3. Is the work a one-shot DAG (each agent runs to completion, dependencies via depends_on)?
   YES → dag-fleet
   NO  → continue

4. None of the above?
   → You're the orchestrator. Open multiple Claude Code sessions.
```

## When to use THIS skill

- Tasks touch **non-overlapping files** (different modules, different docs, etc.)
- You want **merge-safe isolation** — each worker on its own branch, no mid-flight conflicts possible
- The merge decision is **yours** — after workers complete, you choose merge order / strategy
- You want **independent branches** in git that you can inspect, cherry-pick, or discard

## When NOT to use this skill

- Workers need to coordinate or read each other's output → `dag-fleet` with `depends_on`
- Tasks overlap files (even partially) → fix the task split first, then come back
- You want headless workers + reviewer-in-loop → `iterative-fleet`
- Work fits in the current conversation → use Claude Code's built-in Agent tool directly

## fleet.json schema

```json
{
  "fleet_name": "refactor-utils",
  "type": "worktree",
  "config": {
    "max_concurrent": 4,
    "model": "sonnet",
    "fallback_model": "haiku"
  },
  "workers": [
    {
      "id": "rename-foo",
      "task": "Rename foo() to baz() in src/utils/foo.ts and all callers",
      "target_files": ["src/utils/foo.ts", "src/**/*.test.ts"],
      "branch": "rename-foo-to-baz",
      "type": "code-run",
      "max_turns": 30,
      "max_budget_usd": 2.0
    }
  ]
}
```

New fields vs dag-fleet:
- `target_files` (required per worker) — list of file globs this worker will touch. Overlap across workers = launch refuses with exit 2.
- `branch` (required per worker) — git branch name for this worker's worktree. Must not already exist.

**Worker type override (Claude only):** Worktree workers always need Bash for `git commit`. If you set `type` to `read-only`, `write`, or `reviewer`, launch.sh will automatically override to `code-run` with a warning. The worktree itself provides isolation — Bash restrictions are unnecessary here. This override does not apply to codex workers (codex uses sandbox modes).

**Provider support:** Set `"provider": "codex"` or `"provider": "pi"` at config or per-worker level to use OpenAI Codex CLI or pi.dev CLI instead of Claude. Codex workers use `--sandbox workspace-write` (needed for git commit). Pi workers use `--tools` allowlists for tool restriction. See dag-fleet SKILL.md for full provider documentation (model aliases, reasoning_effort, limitations).

**Default max_turns is 100** (not 50 like dag-fleet). Worktree workers typically edit, test, and commit — they need headroom.

## Available scripts

| Script | When to call | Args |
|--------|-------------|------|
| `launch.sh` | Validate independence, create worktrees, spawn workers in tmux | `<fleet-root> [--dry-run]` |
| `status.sh` | Per-worktree progress, cost, completion state | `<fleet-name-or-root> [--json]` |
| `merge.sh` | Print merge plan (files changed, line counts) — no auto-merge | `<fleet-name-or-root>` |
| `cleanup.sh` | Remove git worktrees, requires --force | `<fleet-name-or-root> --force` |

## Launch procedure

1. Set `FLEET_ROOT` to an absolute path.
2. Create `$FLEET_ROOT/fleet.json` with the schema above.
3. For each worker, create `$FLEET_ROOT/workers/{id}/prompt.md`. Include:
   ```
   Save ALL output to $FLEET_ROOT/workers/{id}/output/ — use absolute paths.
   ```
4. Run: `bash ${CLAUDE_SKILL_DIR}/scripts/launch.sh $FLEET_ROOT`
5. `--dry-run` validates independence without creating worktrees or spawning workers.
6. **ALWAYS tell the user** the exact status command so they can monitor manually:
   ```
   bash ${CLAUDE_SKILL_DIR}/scripts/status.sh <fleet-name-or-root>
   ```
   This is mandatory after every launch. The user must be able to check status without asking you.

**IMPORTANT:** Worker prompts MUST instruct the worker to commit its changes before exiting:
```
When you are done, commit your changes on the current branch with a descriptive message.
```
Without this, changes stay as unstaged modifications and cannot be merged via `git merge`.

## After workers complete

1. Run `merge.sh` to see what each branch changed.
2. Decide your merge strategy (in-order, cherry-pick, etc.).
3. Merge manually — the skill does NOT auto-merge.
4. Run `cleanup.sh --force` to remove worktrees.

## Rationalizations to reject

| Agent says | Rebuttal |
|--|--|
| "The tasks overlap slightly but I can manage" | Overlapping target_files = reject. No exceptions. Fix the task split first. If you think you can manage it, you're wrong — merge conflicts in parallel worktrees are unrecoverable. |
| "I'll skip `--dry-run` since I wrote the fleet.json carefully" | Then dry-run will be fast. Run it. The independence validator catches things you didn't think of (glob overlap, bidirectional fnmatch). |
| "Two workers both need the config file, but in different sections" | Same file = overlap. The validator doesn't know about "sections." Split the config change into a separate sequential step, or have one worker own it. |
| "I'll auto-merge since the branches are clean" | Never auto-merge. Run `merge.sh`, read the output, decide strategy. The whole point of worktree-fleet is that the operator owns the merge decision. |
| "I can skip cleanup — the worktrees aren't hurting anything" | Worktrees hold branch locks. Stale worktrees block future branch creation and waste disk. Run `cleanup.sh --force` when done. |

## STRICT RULES

1. Never skip `--dry-run` validation for new fleet configurations.
2. Never merge without reviewing `merge.sh` output first.
3. `cleanup.sh` requires `--force` — no accidental removals.
4. Worktrees persist until you explicitly clean them up. They will not auto-remove.

$ARGUMENTS
