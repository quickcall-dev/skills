# quickcall-dev/skills

[![Install](https://img.shields.io/badge/npx_skills_add-quickcall--dev/skills-blue?style=flat-square)](https://skills.sh/quickcall-dev/skills)
[![Agent Skills](https://img.shields.io/badge/Agent_Skills-compatible-green?style=flat-square)](https://agentskills.io)
[![License: Apache-2.0](https://img.shields.io/badge/License-Apache_2.0-blue?style=flat-square)](LICENSE)

Agent Skills for documentation management, Markdown export, Python development workflows, frontend product UI foundations, and standalone technical documents, diagrams, and interactive explainers.

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

### Frontend Development

<details>
<summary><b>product-ui-kit</b> — React product UI foundation</summary>

Set up React frontend repos with Tailwind, shadcn/ui, OSS block sourcing, reusable app surfaces, optional MapLibre maps, and product-grade mockup patterns.

**Use when:** starting, scaffolding, or setting up React frontend repos; building durable product UI foundations; planning common app surfaces.

**Commands:** `audit`, `scaffold`, `plan-surface`, `init-house-registry`

```bash
npx skills add quickcall-dev/skills --skill product-ui-kit
```

</details>

### Technical Manuals

<details>
<summary><b>technical-manual</b> — Markdown → engineering-manual PDF</summary>

Turn Markdown notes, specs, design docs, READMEs, or agent-written reports into a beautifully typeset, print-ready technical manual PDF: styled parts/chapters, 17 figure primitives, tables, Mermaid, clickable contents, PDF bookmarks, page-numbered cross-references, and layout QA.

**Use when:** making a Markdown doc easier to read or consume, "make this doc beautiful", turning notes into a manual/handbook/explainer, or rendering .md as a polished PDF.

**Commands:** `setup`, `analyze`, `build`, `check`

```bash
npx skills add quickcall-dev/skills --skill technical-manual
```

</details>

### Documents & Diagrams

<details>
<summary><b>html-creator</b> — standalone technical HTML documents</summary>

Build findings, plans, architecture briefs, and manuals as one local HTML file: embedded diagrams, glossary, complete object contracts, failure states, test gates, and print support.

**Use when:** writing an architecture plan, findings doc, or technical manual that must open from disk, stand alone without earlier context, and stay readable from phone to print.

```bash
npx skills add quickcall-dev/skills --skill html-creator
```

</details>

<details>
<summary><b>diagram-creator</b> — diagrams from one JSON specification</summary>

Create consistent architecture flowcharts as editable draw.io files and deterministic SVG exports from one explicit JSON spec. System, pipeline, gate, state, sequence, and decision diagrams; failure and repair lanes by convention.

**Use when:** an architecture decision or flow needs a diagram that stays editable and in sync with the document that embeds it.

```bash
npx skills add quickcall-dev/skills --skill diagram-creator
```

</details>

<details>
<summary><b>onion-explainer</b> — first-principles interactive explainers</summary>

Create single-file explainer pages that peel a technical subject in layers, outside in: one shared interactive model, inline glossary, piece-by-piece formula cards, progress rail, and a benchmark-reading tool.

**Use when:** teaching metrics, algorithms, or protocols from first principles — the reader must know what each number answers, its range, and what a good value is.

```bash
npx skills add quickcall-dev/skills --skill onion-explainer
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
├── product-ui-kit/         # React product UI foundation
├── technical-manual/       # Markdown → engineering-manual PDF
├── html-creator/           # Standalone technical HTML documents
├── diagram-creator/        # Diagrams from one JSON spec
├── onion-explainer/        # First-principles interactive explainers
├── python-code-dev/        # Class-first Python packages
└── python-notebook-dev/    # Reproducible numbered notebooks

archive/skills/             # Archived fleet skills, not installed by default
```

## Testing

Tests live in `test/` and are not part of the skills themselves. They validate skill wiring without calling real APIs.

```bash
# Run active skill tests (from repo root)
bash test/doc/run-all.sh skills/doc
bash test/product-ui-kit/run-all.sh
bash test/technical-manual/run-all.sh
bash test/python-skills/run-all.sh
```

## License

Apache-2.0 — see [LICENSE](LICENSE)
