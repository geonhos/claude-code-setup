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

## suites_pass_alone (added after rep 3)

In the batch, T2/T4 `suites_pass=0` came from failures in HUP tests only; the suites pass when run alone. Method for `suites_pass_alone`:
- For each of the 12 T2/T4 runs (n=1..3, both conditions): fresh `git clone --local --no-hardlinks` at the diff base (T2 `8c2d881`, T4 `77252a8`; for karpathy the clone also gets the principles commit, i.e. `karpathy-section.md` appended to AGENTS.md), origin removed.
- Apply the saved `runs/<run>.diff` with `git apply`.
- Run the task's suites one at a time, in the foreground, with no concurrency and not under nohup: T2 install, harness, retro; T4 progress, gate, harness, metrics, headless, wiki.
- `suites_pass_alone=1` only if every suite exits 0. Result: all 12 runs pass (1).
- T1/T3 rows: `suites_pass_alone` is a copy of `suites_pass` (no HUP failures there).
