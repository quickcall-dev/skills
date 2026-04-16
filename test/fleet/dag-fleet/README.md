# Fleet Orchestrator — Test Suite

Everything related to verifying the fleet skill lives here.

## Layout

| Path | What it is | When to read it |
|--|--|--|
| `harness.md` | **Primary doc.** Outer-judge / inner-haiku-Claude test harness — setup, the 4 reproducer scenarios, per-Phase-item targeted checks, cleanup, judging principles. | Always. Start here when running any test pass. |
| `legacy-guide.md` | Original `TESTING.md` from the skill author — sonnet-based, slash-command-driven, 11-test checklist with echo-loop tasks. Kept for reference; superseded by `harness.md` for active use. | When you want the original 11-test matrix or the orphan-process notes from the skill author. |
| `results/` | Dated test-run reports. Each file is a snapshot of "what passed/failed against which build". | After every run; diff the latest against the prior to see regressions. |
| `results/2026-04-08-baseline.md` | First run, against the unmodified skill. Establishes the baseline FAIL set that Phase 0 fixes must flip to PASS. | Before starting any fix, to know what "broken" looks like. |
| `fixtures-claude/` | Fake-worker fleet fixtures (dag, stuck, completion, cycle) + a `claude` shim that replaces the real CLI via `PATH`. Powers scenarios E–L in `harness.md` §5a. | When running scenarios E–L, or adding new non-claude regression tests. |
| `fixtures-claude/run-all.sh` | Driver that runs scenarios E–L in sequence, isolated, with a pass/fail summary. Takes the fleet skill dir as its one argument. | Between Phase changes to sanity-check the P0.1/P0.2/P0.3/P0.4/P2.1/P2.2/P3.1/P3.2 code paths end-to-end in ~2 minutes. |

## How to use

1. Read `harness.md` §0–3 once to understand the loop.
2. Pick the scenario(s) in §4–5 / §5a relevant to the change you're testing. A–D drive a real inner Haiku Claude and test status/steer/kill against a live worker; E–L (§5a) use fake workers from `fixtures-claude/` and test the Phase 0/2/3 orchestration paths that would be too slow/expensive with real claude.
3. Run them; judge by direct filesystem / `ps` / tmux inspection (never trust inner Claude's success messages — see §8). For E–L the fastest path is `bash fixtures-claude/run-all.sh ../../skills/dag-fleet`.
4. Write a new `results/YYYY-MM-DD-<short-name>.md` with the same structure as `2026-04-08-baseline.md`.
5. Diff against the previous result file. PASS count must monotonically increase; no scenario should regress.

## Cross-references

- Bugs being tested: `../problems.md`
- Fix plan being verified: `../implementation-plan.md`
- Skill under test: `../skills/`

## Hard rule

The harness only touches tmux sessions named `skill-test-fleet` (outer), `fleet` (A–D worker), and the `fleet-test-*` prefix (E–L fake-worker fixtures: `fleet-test-dag`, `fleet-test-stuck`, `fleet-test-completion`, `fleet-test-cycle`). Every other session on the host is off-limits — see `harness.md` §1 and §6 for the snapshot/diff guard that enforces this.
