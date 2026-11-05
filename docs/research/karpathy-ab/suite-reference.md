# Suite reference (fresh clones, no agent changes)

Each suite was run in a fresh `git clone --local --no-hardlinks` of the repo, checked out at the commit, origin removed. Run on 2026-11-05.

| task | suite | commit | pass | fail | failing tests |
|---|---|---|---|---|---|
| T2 | retro | 8c2d881 (base) | 159 | 0 | none |
| T2 | retro | 32f2ac6 (answer) | 159 | 0 | none |
| T4 | progress | 77252a8 (base) | 77 | 0 | none |
| T4 | progress | 395690c (answer) | 75 | 0 | none |

Notes:
- All four reference runs exit 0, so a `suites_pass=0` for T2/T4 in `runs.csv` comes from the agent's change or from another suite on the task's list (T2: install, harness; T4: gate, harness, metrics, headless, wiki), not from a broken retro/progress baseline.
- T4 progress has 2 fewer assertions at the answer commit (75) than at base (77).
