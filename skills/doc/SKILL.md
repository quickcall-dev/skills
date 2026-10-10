---
name: doc
description: Create and manage structured documentation — experiments, plans, findings, checkpoints, research, learnings. Config-driven, parallel-safe.
argument-hint: "[start|expt|plan|finding|ckpt|research|review|learn|list|status|resume] [args]"
allowed-tools: Bash(bash ${AGENTS_SKILLS_DIR}/scripts/*), Read, Write, Glob, Grep
license: Apache-2.0
metadata:
  author: Sagar Sarkale
  version: "1.0"
---

# Documentation Skill

Config-driven documentation scaffolding. Config lives inside the skill at `config/defaults.yaml` — no repo-root files needed.

## Commands

| Command | What to run |
|---------|-------------|
| start \<name\> | `bash ${AGENTS_SKILLS_DIR}/scripts/start.sh "<name>"` |
| expt \<name\> | `bash ${AGENTS_SKILLS_DIR}/scripts/expt.sh "<name>"` |
| plan \<index\> \<title\> | `bash ${AGENTS_SKILLS_DIR}/scripts/plan.sh <index> "<title>"` |
| finding \<index\> \<title\> | `bash ${AGENTS_SKILLS_DIR}/scripts/finding.sh <index> "<title>"` |
| ckpt \<index\> \<description\> | `bash ${AGENTS_SKILLS_DIR}/scripts/ckpt.sh <index> "<description>"` |
| research \<index\> \<topic\> | `bash ${AGENTS_SKILLS_DIR}/scripts/research.sh <index> "<topic>"` |
| review \<index\> \<title\> | `bash ${AGENTS_SKILLS_DIR}/scripts/review.sh <index> "<title>"` |
| learn \<index\> \<domain\> \<title\> | `bash ${AGENTS_SKILLS_DIR}/scripts/learn.sh <index> "<domain>" "<title>"` |
| list | `bash ${AGENTS_SKILLS_DIR}/scripts/list.sh` |
| status \<index\> | `bash ${AGENTS_SKILLS_DIR}/scripts/status.sh <index>` |
| resume \<index\> | `bash ${AGENTS_SKILLS_DIR}/scripts/resume.sh <index>` |

**`start` = scaffold docs/ + create experiment.** Use this when beginning new work.
**`expt` = create experiment only.** Use when docs/ already exists.

## Agent Behavior — READ THIS

**You are responsible for tracking the active experiment per conversation.** When the user creates an experiment or references one, remember its index. Pass it to every script call — scripts are stateless and parallel-safe.

### When to use each command

| User says... | You do... |
|---|---|
| "Let's investigate X" / starts new work | `/doc start "<name>"` — remember the returned index |
| "Plan this" / "How should we approach" | If no recent plan covers this work: `/doc plan <idx> "<title>"` then write plan content. If updating/refining a recent plan: edit that same plan file. |
| User enters plan mode | **STOP.** Do NOT use `.claude/plan.md`. Use the existing relevant plan when this is an update; otherwise run `/doc plan <idx> "<title>"` and write there. Plans live in experiment folders, never in ephemeral storage. |
| You discover something significant | `/doc finding <idx> "<title>"` then write finding content |
| Conversation wrapping up / context switch | `/doc ckpt <idx> "<short-label>"` — short label only (2-5 words), then **write Complete Agent Handoff content with a Mermaid diagram into the file**. **Do this automatically without being asked.** |
| "Research X" / "Look into Y" | `/doc research <idx> "<topic>"` — write prompt, do research, write results |
| "Review X" / "Check this output" | `/doc review <idx> "<title>"` then write review content with verdict |
| "Remember this" / "Key learning" | `/doc learn <idx> <domain> "<title>"` — write distilled insight |
| "Continue experiment 19" / "Pick up" | `/doc resume <idx>` — reads meta + latest plan + Last 5 checkpoints. Set as active for this conversation. |
| "What experiments exist?" | `/doc list` |
| "What's the state of experiment 19?" | `/doc status <idx>` |

### Context resolution (when user doesn't give an index)

1. Experiment created or resumed in this conversation → use it
2. User referenced one by name/number → use it
3. User's request clearly relates to one experiment → use it
4. Ambiguous → ask: "Which experiment?" then run `/doc list` to show options

**You resolve context. Scripts just take a number.**

### Auto-behaviors

- **Checkpoint automatically** at natural stopping points — end of conversation, before context switch, after a milestone. Don't wait to be asked.
- **Plans go in experiments.** NEVER write plans to `.claude/plan.md` or any ephemeral storage.
- **Update the same recent file when the user is revising, refining, or extending that artifact.** Recent active doc = plan/finding/review/research file you created or resumed in this conversation, or the latest relevant file from `/doc resume`. Edit it directly.
- **Create a new numbered file when the topic, decision point, milestone, or artifact purpose changed.** In short: create a new numbered file for distinct work. Examples: new implementation approach after old plan is obsolete; separate finding; new review; new research question; checkpoint snapshots.
- **Agent takes the call.** If unclear whether this is update vs new: prefer editing the recent active doc when it still represents current work; create new only when history should preserve a distinct version.
- **Resume before continuing.** When picking up an existing experiment, run `/doc resume` first to load context, including Last 5 checkpoints for continuity.

### Checkpoint content — MANDATORY

The `ckpt` command arg is a **short label** (2-5 words), NOT the checkpoint content. After the script creates the file, you MUST write the body into it using this structure:

````markdown
```mermaid
graph TD
    A[Starting state] --> B[What was done]
    B --> C[Current state]
    C --> D[Next steps]
```

## What
What was accomplished. Bullet points, brief.

## Key Takeaways
Surprising findings, confirmed/rejected hypotheses, numbers that matter.

## Current State
Exact repo state: branch/commit if relevant, changed files, active experiment index, active plan/review/research files, commands already run, test results.

## Issues
Blockers hit, workarounds used, unresolved problems. Include exact error messages if relevant.

## Decisions
Key choices made and why. What was considered and rejected.

## Inferred Priority
Your inferred next priority based on conversation and repo state. Mark as "inferred" unless user stated it explicitly.

## Next
Concrete next steps with enough detail that a fresh agent can continue without reading chat history.
Include file paths, command examples, what to watch out for, and first command to run next.
````

The checkpoint is a **Complete Agent Handoff**. It must contain a Mermaid diagram plus enough detail that a fresh agent can continue without reading chat history or asking what happened. Be brief but complete — file paths, key numbers, decisions, current state, priority, what worked, what didn't, and exact next command.

**DO NOT** cram content into the description argument. Keep the arg short: `/doc ckpt 7 "v1 analysis complete"` then edit the file.

## Experiment Structure

```
experiments/NNN-{name}/
├── .meta.json          auto-updated by scripts
├── plans/              multiple plans, numbered
├── findings/           multiple findings, numbered  
├── checkpoints/        progress snapshots, numbered
├── review/             structured reviews, numbered
└── research/           prompt + response pairs, numbered
```

## Setup

`/doc start my-investigation` — that's it. Scaffolds docs/ and creates the first experiment.

To customize folder structure or naming: edit `config/defaults.yaml` inside the skill.

## Rules

1. **Scripts only create empty templates (frontmatter + headings). YOU must write the actual content into the file after the script runs.** Never treat the script call as the finished step.
2. **Always use the scripts** for file creation. Never manually create experiment dirs or edit `.meta.json`.
2. **Index is just the number.** `23` not `023` not `023-docs-and-structs`.
3. **No auto-commit.** Scripts scaffold files — you or the user decide when to commit.
4. **Plans go in experiments.** Never in `.claude/plan.md`. This is non-negotiable.
5. **Recent active docs are editable; historical docs are append-only.** Update the same recent file for revisions to current work. Create a new numbered file for distinct topics, milestones, decisions, or snapshots.
6. **Valid learnings domains** are listed in `config/defaults.yaml`. `learn` will error on invalid domains.
7. **Keep titles short.** Titles become filenames. Use 2-5 words max — concise and descriptive. `"auth-flow"` not `"investigation-into-authentication-flow-reliability-issues"`. The numbering prefix handles ordering; the title just needs to identify the topic at a glance.

$ARGUMENTS
