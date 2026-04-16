# Worker Types & Permission Matrix

## Disallowed tools per type

| Worker Type | Disallowed Tools |
|-------------|-----------------|
| `read-only` | Bash, Edit, Write, Agent, WebFetch, WebSearch |
| `write` | Bash, Agent, WebFetch, WebSearch |
| `code-run` | Agent, WebFetch, WebSearch |
| `research` | Bash, Edit, Agent |
| `reviewer` | Bash, Edit, Agent, WebFetch, WebSearch |

## When to use each type

| Type | Use for | Can do | CANNOT do |
|------|---------|--------|-----------|
| `read-only` | Pure analysis where output is inline text only (no files) | Read, Grep, Glob | Write, Edit, Bash — **cannot save output files** |
| `write` | Synthesizers, doc writers, any worker that reads inputs and writes output files | Read, Grep, Glob, Edit, Write | Bash |
| `code-run` | Writing and testing code, shell commands | Read, Grep, Glob, Edit, Write, Bash | (most capable) |
| `research` | Web research + writing findings to files | Read, Grep, Glob, Write, WebFetch, WebSearch | Bash, Edit |
| `reviewer` | Read-only review of other workers' output (verdict via inline text) | Read, Grep, Glob | Write, Edit, Bash — **cannot save output files** |

## Common mistakes

| Mistake | What happens | Fix |
|---------|-------------|-----|
| Synthesizer set to `read-only` | Burns all turns trying to find Write tool, never outputs | Use `write` — synthesizers read inputs and **write** output |
| Researcher set to `read-only` | Cannot use WebFetch/WebSearch, cannot save findings | Use `research` — has web access and Write |
| Any output-producing worker set to `read-only` or `reviewer` | Cannot save files, wastes budget | Only use `read-only`/`reviewer` for workers whose output is captured from assistant messages in session.jsonl, not from files |
