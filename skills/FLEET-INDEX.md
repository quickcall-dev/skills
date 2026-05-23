# Fleet Skill Index

Quick-reference table for all available fleet types. Read this first, then read ONLY the chosen fleet's `SKILL.md`.

| Fleet type | When to use | When NOT to use |
|---|---|---|
| **dag-fleet** | One-shot DAG workers with dependencies, budgets, mixed models/providers. Persistent across sessions. | Workers need git isolation or edit overlapping files. |
| **worktree-fleet** | Independent tasks touching non-overlapping files. Each worker in its own git worktree/branch. Merge-safe isolation. | Tasks share files or need coordination/read each other's output. |
| **iterative-fleet** | Work needs reviewer-in-the-loop (builder → reviewer → verdict → repeat). Quality-gated iteration. | One-shot work without review cycles. |
| **autoresearch-fleet** | Optimizing a single metric with fast eval harness. Autonomous overnight runs. Plateau-triggered web search. | No eval harness exists, or task isn't optimization. |

## Decision tree

```
You want to run multiple agents in parallel. Which fleet?

1. Can one agent handle this in a single session?
   YES → "No fleet needed." STOP.

2. Are the tasks independent (no shared files, no shared state)?
   YES → worktree-fleet
   NO  → continue

3. Does the work need iteration with a reviewer making accept/iterate decisions?
   YES → iterative-fleet
   NO  → continue

4. Is the work a one-shot DAG (each agent runs to completion, dependencies via depends_on)?
   YES → dag-fleet
   NO  → continue

5. Is it an optimization loop with a fast eval harness?
   YES → autoresearch-fleet
   NO  → "Open multiple sessions — you're the orchestrator." STOP.
```

## Next step

Pick one fleet type above, then read its `SKILL.md` for the full schema, script reference, and rules.
