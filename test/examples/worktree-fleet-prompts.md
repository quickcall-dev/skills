# Worktree Fleet — Worker Prompts

Each worker runs in its own git worktree (separate branch). Files don't overlap.

## Setup

```bash
# Must be inside a git repo
cd /tmp && mkdir example-wt && cd example-wt && git init && git commit --allow-empty -m "init"
mkdir -p workers/{add-readme,add-license}
cp /path/to/test/examples/worktree-fleet.json fleet.json
```

## workers/add-readme/prompt.md

```
Create a README.md for a Python utility library called "minitools".
Include: project name, one-line description, installation (pip install minitools),
and a usage example showing string reversal. Keep it under 30 lines.
```

## workers/add-license/prompt.md

```
Create a LICENSE file with the MIT license.
Use the year 2026 and "Example Corp" as the copyright holder.
```

## Launch

```bash
bash skills/worktree-fleet/scripts/launch.sh .
bash skills/worktree-fleet/scripts/status.sh .
# After completion:
bash skills/worktree-fleet/scripts/merge.sh .
```
