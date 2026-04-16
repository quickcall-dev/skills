# autoresearch: optimize string counter

## Setup
1. Read `solution.py` — it counts vowels in a string.
2. Read `results.tsv` for prior experiment history.
3. Run `python3 eval.py` to establish a baseline.

## Rules
- Goal: **maximize** the score (correctness + speed bonus).
- Make ONE change per experiment. Keep changes focused.
- Do NOT modify `eval.py` — it is immutable.

## The experiment loop
LOOP FOREVER:
1. Read results.tsv for context on what's been tried.
2. Make ONE change to `solution.py`.
3. `git add -A && git commit -m "short description"`
4. Run: `python3 eval.py`
5. Record in results.tsv (tab-separated): `commit	metric	status	description`
6. If metric improved: keep the commit.
7. If worse or crash: `git reset --hard HEAD~1` and log as discard/crash.
8. Go to step 1.

**NEVER STOP.** Run until manually interrupted.
