# quickcall-dev/skills

[![Install](https://img.shields.io/badge/npx_skills_add-quickcall--dev/skills-blue?style=flat-square)](https://skills.sh/quickcall-dev/skills)
[![Agent Skills](https://img.shields.io/badge/Agent_Skills-compatible-green?style=flat-square)](https://agentskills.io)
[![License: Apache-2.0](https://img.shields.io/badge/License-Apache_2.0-blue?style=flat-square)](LICENSE)

Agent Skills for documentation management and fleet orchestration. Run parallel AI workers with DAG ordering, git worktree isolation, reviewer gates, and autonomous research loops.

Works with **Claude Code**, **Cursor**, **GitHub Copilot**, **Gemini CLI**, **OpenAI Codex**, **Goose**, **Roo Code**, **JetBrains Junie**, and [25+ other agents](https://agentskills.io).

## Install

### Quick (Claude Code + Pi only, no prompts)

```bash
npx skills add quickcall-dev/skills --agent claude-code --agent pi -g -y
```

### Interactive (all agents, wizard-guided)

```bash
# All skills
npx skills add quickcall-dev/skills

# Just one
npx skills add quickcall-dev/skills --skill dag-fleet
```

### Update / refresh

`npx skills add` is idempotent for symlinks. Re-run the quick command above to pull latest changes. If you installed before `skillPath` tracking existed, `npx skills update` will not work — use `add` instead.

```bash
# Add shell alias for one-command refresh
alias skills-up='npx skills add quickcall-dev/skills --agent claude-code --agent pi -g -y'
```

## Skills

### Documentation

<details>
<summary><b>doc</b> — structured documentation management</summary>

Create and manage structured documentation — experiments, plans, findings, checkpoints, research, learnings. Config-driven, parallel-safe.

**Use when:** starting new investigations, tracking experiment progress, writing plans, recording findings, or creating checkpoints at natural stopping points.

**Commands:** `start`, `expt`, `plan`, `finding`, `ckpt`, `research`, `review`, `learn`, `list`, `status`, `resume`

```bash
npx skills add quickcall-dev/skills --skill doc
```

</details>

### Document Rendering

<details>
<summary><b>markdown-to-pdf</b> — Markdown to PDF export</summary>

Convert Markdown docs to PDF with robust Mermaid diagram rendering, consistent styling, page breaks, TOC support, and no browser print headers or footers.

**Use when:** exporting Markdown reports to PDF, especially when Mermaid diagrams render blank, oversized, colorless, or Chrome adds page headers/footers.

```bash
npx skills add quickcall-dev/skills --skill markdown-to-pdf
```

</details>

### Fleet Orchestration

<details>
<summary><b>fleet-plan</b> — analyze tasks and generate fleet configs</summary>

Analyze a task, pick the right fleet type, and generate a ready-to-launch fleet (`fleet.json` + `prompt.md` files). Discovers available fleet skills dynamically.

**Use when:** you want to run work in parallel and need help choosing between dag-fleet, worktree-fleet, iterative-fleet, or autoresearch-fleet.

```bash
npx skills add quickcall-dev/skills --skill fleet-plan
```

</details>

<details>
<summary><b>dag-fleet</b> — DAG-ordered parallel workers</summary>

Persistent, budgeted, DAG-ordered runner for parallel `claude -p` or `codex exec` workers in tmux. Supports dependency ordering, per-worker budget caps, mixed models/providers, and concurrency limits.

**Use when:** you need persistence across sessions, per-worker budget caps, dependency ordering, or mixed models/providers per worker.

**Commands:** `launch`, `status`, `kill`, `report`, `relaunch-worker`, `feed`, `view`

```bash
npx skills add quickcall-dev/skills --skill dag-fleet
```

</details>

<details>
<summary><b>worktree-fleet</b> — git-worktree-isolated parallel workers</summary>

Independence-validated parallel fleet that runs each worker in its own git worktree. Each worker gets its own branch for merge-safe isolation.

**Use when:** tasks touch non-overlapping files and you need merge-safe isolation with each worker on its own branch.

**Commands:** `launch`, `status`, `merge`, `cleanup`

```bash
npx skills add quickcall-dev/skills --skill worktree-fleet
```

</details>

<details>
<summary><b>iterative-fleet</b> — reviewer-gated iterative cycles</summary>

Reviewer-gated iterative fleet for headless workers that run in cycles until a designated reviewer approves the output. A reviewer worker reads all worker logs, writes a verdict (`lgtm` | `iterate` | `escalate`), and the orchestrator decides whether to continue, pause, or stop.

**Use when:** work needs multiple rounds of iteration with a quality gate. Never kills or restarts workers automatically — the operator owns all decisions.

**Commands:** `launch`, `status`, `pause`, `resume`, `kill`

```bash
npx skills add quickcall-dev/skills --skill iterative-fleet
```

</details>

<details>
<summary><b>autoresearch-fleet</b> — autonomous research loop</summary>

Karpathy-inspired autonomous research loop. Agent edits one file, evals, keeps or discards, repeats. Plateau-triggered web search breaks through ceilings. Git as state machine.

**Use when:** you need autonomous, iterative optimization with automatic evaluation. Runs until stopped or budget exhausted.

**Commands:** `launch`, `status`, `view`, `report`, `pause`, `resume`, `kill`

```bash
npx skills add quickcall-dev/skills --skill autoresearch-fleet
```

</details>

## How It Works

Each skill follows the [Agent Skills](https://agentskills.io) open standard — a `SKILL.md` file with YAML frontmatter and markdown instructions. Agents load the skill when it matches the task at hand. Fleet skills bundle bash scripts that orchestrate parallel workers in tmux sessions.

```
skills/
├── doc/                    # Documentation management
│   ├── SKILL.md
│   ├── config/defaults.yaml
│   ├── scripts/            # 13 command scripts
│   └── references/
├── dag-fleet/              # DAG-ordered parallel workers
│   ├── SKILL.md
│   ├── scripts/            # 7 orchestration scripts
│   ├── lib/                # Shared fleet libraries (copied from _canonical)
│   └── references/
├── worktree-fleet/         # Git-worktree isolated workers
├── iterative-fleet/        # Reviewer-gated cycles
├── autoresearch-fleet/     # Autonomous research loop
├── fleet-plan/             # Fleet config generator
└── markdown-to-pdf/ # Markdown PDF export
```

### Shared Libraries (`_canonical/`)

Fleet skills share common bash libraries via `_canonical/fleet-lib/`. This is the single source of truth for:

| File | Purpose |
|------|---------|
| `logging.sh` | Colorized log helpers (`info`, `warn`, `error`, `die`) |
| `tools.sh` | Tool validation, fleet ID sanitization |
| `worker-spawn.sh` | Per-worker tmux spawning, provider-specific CLI construction |
| `registry.sh` | Fleet name → root mapping for `kill.sh`/`status.sh` resolution |
| `dag.sh` | Kahn's algorithm topo sort + cycle detection |
| `dag-viz.py` | ASCII / mermaid DAG visualization |
| `reset.sh` | Fleet reset logic (`--soft` / `--hard`) |

**Sync:** `bash scripts/sync-lib.sh` copies canonical files into each skill's `lib/` directory. Run it after editing any file in `_canonical/fleet-lib/`. Skill-specific scripts (e.g. `launch.sh`, `kill.sh`) live directly in `skills/<name>/scripts/` — they are NOT in `_canonical`.

## Testing

Tests live in `test/` and are not part of the skills themselves. They validate skill wiring without calling real APIs.

```bash
# Run all test suites (from repo root)
bash test/fleet/dag-fleet/fixtures-claude/run-all.sh skills/dag-fleet
bash test/fleet/dag-fleet/fixtures-codex/run-all.sh skills/dag-fleet
bash test/fleet/worktree-fleet/fixtures-claude/run-all.sh skills/worktree-fleet
bash test/fleet/worktree-fleet/fixtures-codex/run-all.sh skills/worktree-fleet
bash test/fleet/iterative-fleet/fixtures-claude/run-all.sh skills/iterative-fleet
bash test/fleet/iterative-fleet/fixtures-codex/run-all.sh skills/iterative-fleet
bash test/fleet/autoresearch-fleet/run-all.sh skills/autoresearch-fleet
```

59/59 scenarios passing across all suites.

## License

Apache-2.0 — see [LICENSE](LICENSE)
