# Developer Flow — How Agents Should Use /doc

## The Core Problem

Developers don't think in terms of "now I will create experiment 023 and write plan 01 to it." They think:
- "Let's investigate X"
- "Here's what I'm going to do"
- "I found something interesting"
- "Let me save where I'm at"

The skill must bridge this gap. Scripts handle file creation. SKILL.md teaches the agent to recognize these moments and act.

## Flow 1: Starting New Work

**User says:** "Let's investigate why Cursor sessions have NULL timestamps"

**Agent should:**
1. Run `/doc expt "cursor-null-timestamps"` → creates `experiments/025-cursor-null-timestamps/`
2. Remember this experiment index (25) for the rest of the conversation
3. Tell the user: "Created experiment 025. I'll track plans, findings, and checkpoints here."

**No user action needed beyond describing what they want to do.**

## Flow 2: Planning

**User says:** "plan this" / "write a plan" / enters plan mode / "how should we approach this"

**Agent should:**
1. Write the plan content directly to the experiment's `plans/` folder via `/doc plan`
2. NOT use `.claude/plan.md` or ephemeral plan mode storage
3. If the plan evolves mid-conversation, create a new plan file (02, 03, etc.) — don't overwrite

**User says:** "update the plan" / "revise the approach"

**Agent should:**
1. Create a NEW plan file (next number), not edit the old one
2. Old plans are immutable history

## Flow 3: During Investigation

**User says:** "interesting, log this" / "this is a finding" / agent discovers something significant

**Agent should:**
1. Run `/doc finding` with no index (uses conversation's active experiment)
2. Write the finding content into the created file
3. Include evidence, data, links to code

**User says:** "let me save where I'm at" / "checkpoint" / conversation is wrapping up

**Agent should:**
1. Run `/doc ckpt` — summarize progress, blockers, next steps
2. This is the agent's responsibility at natural stopping points, not just when asked

**User says:** "research X" / "look into Y" / "what does the literature say about Z"

**Agent should:**
1. Run `/doc research` to create prompt + response files
2. Write the research prompt into the prompt file
3. Do the research
4. Write results into the response file

## Flow 4: Context Awareness (No Index Required)

**Rule: The agent tracks the active experiment per conversation.**

Resolution when no index is given:
1. **This conversation created an experiment** → use it (agent memory, not a file)
2. **User referenced an experiment by name/number** → use it
3. **User's cwd is inside an experiment dir** → use it
4. **None of the above** → ask: "Which experiment? Latest is NNN-name."

For bash scripts specifically (which have no conversation memory):
- Scripts still require an index argument
- The SKILL.md instructs the agent to ALWAYS pass the index
- The agent resolves context → passes the right index to the script
- Scripts never guess — they're deterministic

## Flow 5: Graduation

**User says:** "this is important, we should remember this" / "graduate this finding"

**Agent should:**
1. Run `/doc learn` with the experiment index, domain, and title
2. Write the distilled insight (not the raw finding — the lesson learned)
3. Link back to the original finding

## Flow 6: Continuing Previous Work

**User says:** "let's pick up experiment 19" / "continue the manual reads investigation"

**Agent should:**
1. Read `.meta.json` to understand state
2. Read latest checkpoint to understand where things left off
3. Set this as the active experiment for the conversation
4. Continue from where things stopped

## What the Agent Should Do Automatically

1. **Create experiment** when the user starts a new investigation (don't wait to be asked)
2. **Write checkpoints** at natural stopping points (end of conversation, before context switch)
3. **Track the active experiment** throughout the conversation
4. **Pass index to scripts** so they stay parallel-safe and deterministic
5. **Never overwrite** — always create new numbered files

## What the Agent Should NOT Do

1. Don't create experiments for trivial questions
2. Don't checkpoint every 5 minutes — only at real stopping points
3. Don't guess the experiment if ambiguous — ask
4. Don't use plan mode / `.claude/plan.md` — write directly to experiment plans/
