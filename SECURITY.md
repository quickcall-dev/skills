# Security

## Automated Audit Results

All skills are automatically audited by three services on [skills.sh](https://skills.sh/quickcall-dev/skills):

- **Gen Agent Trust Hub** — static analysis for injection, exfiltration, unsafe patterns
- **Socket** — malicious behavior, credential exposure, obfuscation
- **Snyk** — third-party content exposure, prompt injection risk

## Hardened (addressed)

| Finding | Fix |
|---------|-----|
| Fleet.json worker IDs/names interpolated into shell commands | `validate_fleet_id()` rejects anything not `[a-zA-Z0-9._-]` |
| Model names and session names in worker-spawn.sh | `validate_safe_id()` applied before command construction |
| `eval` in autoresearch orchestrator | Replaced with `bash -c` |
| Doc experiment index in arithmetic expansion | Digits-only validation before `$((10#$index))` |
| Doc `cfg()` Python string interpolation | Key validated as `[a-zA-Z0-9._]` before interpolation |
| Doc resume.sh/status.sh read files into agent context | `<file-content>` boundary markers added |

## By Design (won't fix)

These findings are flagged by auditors but are intentional design decisions:

### `--dangerously-skip-permissions` in fleet workers

Fleet skills spawn headless `claude -p` workers in tmux. These workers cannot prompt for permission interactively — the flag is required for headless operation. This is explicitly documented in Claude Code's headless mode.

**Affects:** dag-fleet, worktree-fleet, iterative-fleet, autoresearch-fleet

### Web content in research workers (Snyk W011)

Research-type workers intentionally access WebFetch/WebSearch to break through knowledge plateaus. The `tools.sh` mapping restricts web access to `research` worker type only — `code-run`, `write`, and `read-only` workers cannot access the web.

**Risk:** Web content could influence agent decisions (indirect prompt injection).
**Mitigation:** Worker type isolation. Only research workers get web access. Code-run workers that execute the actual changes have no web access.

**Affects:** dag-fleet, worktree-fleet, iterative-fleet, autoresearch-fleet

### Reviewer feedback loop in iterative-fleet

The iterative-fleet's core feature is that a reviewer worker's output (`review.md`) feeds into the next iteration's prompt. One LLM's output directly influences another's instructions. This IS the skill — sanitizing it would break the reviewer gate.

**Mitigation:** The reviewer worker has restricted tool access. The orchestrator checks for specific verdict strings (`lgtm`, `iterate`, `escalate`) rather than executing arbitrary reviewer output.

### Autonomous code modification in autoresearch-fleet

The autoresearch loop edits code, evaluates it, and keeps or discards changes. This is the Karpathy-inspired design — the agent MUST be able to modify and execute code.

**Mitigation:** Git as state machine. Every iteration is a commit. Discarded changes are reverted. The eval command is operator-defined in fleet.json (not agent-chosen).

## Reporting

If you find a security issue, open a GitHub issue or email the repository owner.
