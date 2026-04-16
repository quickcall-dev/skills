# Documentation Framework Reference

## Philosophy

Documentation lives in two tiers:
- **Permanent** — architecture decisions, guides, learnings. Updated over time, never deleted.
- **Ephemeral** — experiments. Append-only archive. Insights graduate to permanent docs.

Experiments produce findings. Findings that are validated, actionable, and broadly applicable graduate to learnings. Everything else stays in the experiment archive.

---

## Quick Start

```bash
/doc init my-investigation       # scaffold docs/ + create first experiment
/doc plan 1 "approach"           # create a plan
/doc finding 1 "key discovery"   # log a finding
/doc ckpt 1 "end of day"         # save progress
/doc research 1 "literature"     # create research files
/doc learn 1 data "key insight"  # graduate to permanent learning
```

No config files in repo root. Defaults live inside the skill at `config/defaults.yaml`.

---

## Command Reference

### `/doc init [name]`

Scaffolds the `docs/` directory skeleton. If `name` is given, also creates the first experiment.

```bash
/doc init                        # just scaffold docs/
/doc init cursor-investigation   # scaffold + create experiment 001
```

Creates:
```
docs/
├── architecture/
├── guides/
├── learnings/
├── research/
└── experiments/
```

### `/doc expt <name>`

Creates a new experiment directory with auto-incremented number.

```bash
/doc expt "cursor null timestamps"
# → Created experiments/025-cursor-null-timestamps/
#   Index: 25
```

Creates:
```
experiments/025-cursor-null-timestamps/
├── .meta.json
├── plans/
├── findings/
├── checkpoints/
└── research/
```

### `/doc plan <index> <title>`

Creates a numbered plan file inside an experiment's `plans/` directory.

```bash
/doc plan 25 "root cause analysis"
# → Created 025-cursor-null-timestamps/plans/01-root-cause-analysis.md

/doc plan 25 "revised approach"
# → Created 025-cursor-null-timestamps/plans/02-revised-approach.md
```

Plans are **immutable**. Don't edit old plans — create a new numbered one. Plans evolve: 01, 02, 03.

**Agents: write plans directly here. Never use `.claude/plan.md` or ephemeral plan mode storage.**

Created file format:
```yaml
---
title: "root cause analysis"
experiment: 025-cursor-null-timestamps
created: "2026-04-05 07:13 UTC"
---

(agent writes plan content here)
```

### `/doc finding <index> <title>`

Creates a numbered finding file inside an experiment's `findings/` directory.

```bash
/doc finding 25 "timestamps missing in v2 format"
# → Created 025-cursor-null-timestamps/findings/01-timestamps-missing-in-v2-format.md

/doc finding 25 "codex double encodes json"
# → Created 025-cursor-null-timestamps/findings/02-codex-double-encodes-json.md
```

Each finding is its own file. Multiple findings per experiment is normal and expected.

Created file format:
```yaml
---
title: "timestamps missing in v2 format"
experiment: 025-cursor-null-timestamps
created: "2026-04-05 07:13 UTC"
---

(agent writes finding content here — include evidence, data, code links)
```

### `/doc ckpt <index> <description>`

Creates a numbered checkpoint file. Write these at natural stopping points — end of session, before context switch, after a milestone.

```bash
/doc ckpt 25 "initial investigation done"
# → Created 025-cursor-null-timestamps/checkpoints/01-initial-investigation-done.md
```

Created file format:
```yaml
---
title: "initial investigation done"
experiment: 025-cursor-null-timestamps
created: "2026-04-05 07:13 UTC"
---

(what's done, what's pending, blockers, next steps)
```

### `/doc research <index> <topic>`

Creates a pair of research files: a prompt file and a response file.

```bash
/doc research 25 "process mining literature"
# → Created 025-cursor-null-timestamps/research/01-prompt-process-mining-literature.md
# → Created 025-cursor-null-timestamps/research/01-res-process-mining-literature.md
```

Both files are blank with frontmatter. Agent writes the research prompt into the prompt file, does the research, writes results into the response file.

### `/doc learn <index> <domain> <title>`

Graduates a finding from an experiment into a permanent learning.

```bash
/doc learn 25 data "cursor null timestamps"
# → Created learnings/data/001-cursor-null-timestamps.md
#   (graduated from experiments/025-cursor-null-timestamps)
```

Created file format:
```yaml
---
title: "cursor null timestamps"
graduated_from: experiments/025-cursor-null-timestamps
domain: data
created: "2026-04-05 07:13 UTC"
created_date: "2026-04-05"
---

(distilled insight — problem, root cause, solution, evidence)
```

Updates the experiment's `.meta.json` status to `graduated`.

---

## Experiment Resolution

All commands target experiments by **index number only**. Just the number — no padding, no name.

```bash
/doc finding 25 "title"    # matches experiments/025-*
/doc ckpt 3 "desc"         # matches experiments/003-*
```

Resolution logic:
1. Pad input to 3 digits: `25` → `025`
2. Glob: `experiments/025-*` → match
3. If no match, substring search across all experiment names
4. If multiple matches, error with the list of matches
5. If no index given and cwd is inside an experiment dir, use that
6. If no index and not in experiment dir, error (no guessing)

Parallel-safe. No state files. Deterministic.

---

## Docs Skeleton

Created by `/doc init`. Core folders are the same everywhere. Add repo-specific folders by editing `config/defaults.yaml`.

```
docs/
├── architecture/          # System design, ADRs, data contracts
│                          # Immutable once accepted — supersede, never edit
│
├── guides/                # How-to guides, runbooks, setup procedures
│                          # Living docs — update as processes change
│
├── learnings/             # Graduated insights from experiments
│   └── {domain}/          # e.g. backend/, data/, pipeline/
│       └── NNN-title.md   # Frontmatter links back to source experiment
│
├── research/              # Global, permanent, ideation-level research
│   └── {topic}/           # Cross-cutting topics NOT tied to one experiment
│
├── experiments/           # Ephemeral experiment runs — the lab notebook
│   └── NNN-{name}/        # One dir per experiment, sequentially numbered
│       ├── .meta.json     # Machine-readable state (auto-updated by scripts)
│       ├── plans/         # Multiple plans, numbered (plans evolve)
│       ├── findings/      # Multiple findings, numbered
│       ├── checkpoints/   # Progress snapshots, numbered
│       └── research/      # Prompt + response pairs, numbered
│
└── {repo-specific}/       # e.g. schemas/, product/, contracts/, design/
```

**All experiment subdirs are plural. All files inside are numbered and auto-incremented.**

---

## Experiment Lifecycle

```
/doc init "name"               status: planning
  or /doc expt "name"
       │
       ▼
/doc plan <idx> "approach"     write plan content into the created file
       │
       ▼
   Run experiment              /doc finding, /doc ckpt, /doc research as needed
       │
       ▼
   Conclude                    manually set status to complete | abandoned
       │
       ▼
/doc learn <idx> <domain>      graduates key insights to learnings/
                               status auto-set to: graduated
```

### Status values

| Status | Meaning |
|--------|---------|
| `planning` | Created, plan being written |
| `active` | Experiment in progress |
| `complete` | Done, findings documented |
| `abandoned` | Stopped — findings may be incomplete |
| `graduated` | Key insights promoted to learnings/ |

---

## .meta.json

Machine-readable experiment state. Auto-created by `/doc expt`, auto-updated by all other commands.

```json
{
  "name": "cursor-null-timestamps",
  "created": "2026-04-05T07:13:29Z",
  "created_by": "Sagar Sarkale",
  "created_date": "2026-04-05",
  "status": "planning",
  "question": "",
  "tags": [],
  "plan_count": 2,
  "finding_count": 1,
  "checkpoint_count": 1,
  "research_count": 0,
  "last_activity": "2026-04-05T07:15:00Z"
}
```

**What's tracked:**
- `created` / `created_date` — when the experiment was created (ISO + date-only)
- `created_by` — from `git config user.name`
- `status` — auto-updated by `learn.sh`; other status changes are manual
- `plan_count`, `finding_count`, `checkpoint_count`, `research_count` — auto-incremented by each command
- `last_activity` — updated on every command

Agents can `cat .meta.json` to quickly check experiment state without parsing markdown.

---

## Two Levels of Research

| Level | Location | Scope | Lifespan |
|-------|----------|-------|----------|
| **Global** | `docs/research/` | Cross-cutting topics, ideation | Permanent |
| **Experiment** | `docs/experiments/NNN/research/` | Scoped to one experiment | Archived with experiment |

Global research = topics not tied to one experiment (e.g., "state graph analysis", "process mining techniques").
Experiment research = prompts, lit reviews, agent outputs for that experiment's specific question.

---

## Graduation: Experiment → Learning

When a finding is **validated, actionable, and broadly applicable**:

1. `/doc learn <index> <domain> "title"` creates `learnings/{domain}/NNN-title.md`
2. Write the distilled insight (problem → root cause → solution → evidence)
3. Experiment `.meta.json` status auto-updates to `graduated`
4. Experiment stays as-is — immutable archive

**Not every finding graduates.** Most stay in the experiment. Only promote insights that change how you build or operate.

---

## Config: `config/defaults.yaml`

Lives inside the skill — no files in repo root. Edit to customize.

```yaml
docs_root: docs

# Folder skeleton created by /doc init
structure:
  architecture: {}
  guides: {}
  learnings: {}
  research: {}
  experiments: {}

# Subdirs created inside each experiment
experiment_dirs:
  - plans
  - findings
  - checkpoints
  - research

# File naming templates
naming:
  experiment: "{NNN}-{name}"
  plan: "{NN}-{title}.md"
  finding: "{NN}-{title}.md"
  checkpoint: "{NN}-{description}.md"
  research_prompt: "{NN}-prompt-{topic}.md"
  research_response: "{NN}-res-{topic}.md"
  learning: "{NNN}-{title}.md"
  timestamp: "%Y-%m-%d %H:%M UTC"
```

### Config fields

| Field | Description |
|-------|-------------|
| `docs_root` | Path to docs dir relative to repo root. Default: `docs` |
| `structure` | YAML tree defining the folder skeleton. `/doc init` walks this to create dirs. |
| `experiment_dirs` | Subdirectories created inside each experiment. |
| `naming.*` | Templates for file naming. See tokens below. |

### Naming tokens

| Token | Replaced with | Example |
|-------|--------------|---------|
| `{NNN}` | Zero-padded 3-digit auto-increment | `025` |
| `{NN}` | Zero-padded 2-digit auto-increment | `03` |
| `{name}` | Slugified (lowercase, hyphens) | `cursor-null-timestamps` |
| `{title}` | Slugified | `root-cause-analysis` |
| `{description}` | Slugified | `initial-investigation-done` |
| `{topic}` | Slugified | `process-mining-literature` |
| `{timestamp}` | UTC time per `naming.timestamp` | `2026-04-05 07:13 UTC` |

### Customizing for a repo

To add repo-specific folders (e.g., `schemas/`, `contracts/`), edit the `structure:` tree:

```yaml
structure:
  architecture: {}
  guides: {}
  learnings: {}
  research: {}
  experiments: {}
  # repo-specific additions:
  schemas: {}
  contracts: {}
  design: {}
```

To add learnings subdomains:

```yaml
structure:
  learnings:
    backend: {}
    frontend: {}
    data: {}
```
