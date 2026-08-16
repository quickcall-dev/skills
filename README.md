# quickcall-dev/skills

[![Install](https://img.shields.io/badge/npx_skills_add-quickcall--dev/skills-blue?style=flat-square)](https://skills.sh/quickcall-dev/skills)
[![Agent Skills](https://img.shields.io/badge/Agent_Skills-compatible-green?style=flat-square)](https://agentskills.io)
[![License: Apache-2.0](https://img.shields.io/badge/License-Apache_2.0-blue?style=flat-square)](LICENSE)

Agent Skills for documentation management, Markdown export, and Python development workflows.

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
npx skills add quickcall-dev/skills --skill doc
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

### Python Development

<details>
<summary><b>python-code-dev</b> — class-first Python packages</summary>

Create importable `src/<package>/` projects, adapt existing code, migrate notebooks, and verify tests/imports.

**Use when:** starting Python projects, structuring reusable modules, or graduating notebook logic.

**Commands:** `new`, `adapt`, `migrate`, `verify`

```bash
npx skills add quickcall-dev/skills --skill python-code-dev
```

</details>

<details>
<summary><b>python-notebook-dev</b> — reproducible numbered notebooks</summary>

Create deterministic `notebooks/NNN-slug/` experiments, adapt notebooks, migrate logic to packages, and verify clean-kernel execution.

**Use when:** creating or editing `# %%` Python notebooks or running focused experiments.

**Commands:** `new`, `adapt`, `migrate`, `verify`

```bash
npx skills add quickcall-dev/skills --skill python-notebook-dev
```

</details>

## How It Works

Each skill follows the [Agent Skills](https://agentskills.io) open standard — a `SKILL.md` file with YAML frontmatter and markdown instructions. Agents load the skill when it matches the task at hand.

```
skills/
├── doc/                    # Documentation management
│   ├── SKILL.md
│   ├── config/defaults.yaml
│   ├── scripts/
│   └── references/
├── markdown-to-pdf/        # Markdown PDF export
├── python-code-dev/        # Class-first Python packages
└── python-notebook-dev/    # Reproducible numbered notebooks

archive/skills/             # Archived fleet skills, not installed by default
```

## Testing

Tests live in `test/` and are not part of the skills themselves. They validate skill wiring without calling real APIs.

```bash
# Run active skill tests (from repo root)
bash test/doc/run-all.sh skills/doc
bash test/python-skills/run-all.sh
```

## License

Apache-2.0 — see [LICENSE](LICENSE)
