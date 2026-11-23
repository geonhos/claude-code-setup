---
type: troubleshooting
status: active
updated: 2026-11-23
sources: [ask 1793276439, 20261029-085439-implementer.jsonl, ask 1795055465-13759-24283, "#170"]
verified_by: serial vs parallel timing in .harness/time-budget-detail.md
---
# Workers looping over test suites serially

**Symptom.** An implementer ask runs ~30 min (2019 s) and 54 % of it (3 loops, 338/378/376 s) is test execution. The follow-up fix ask spent 349 of 457 s the same way.

**Cause.** The implementer prompt forbade only the literal `./install.sh --test`. A `for t in ...; do bash tests/$t.test.sh; done` over 9-12 suites got around it and runs everything serially (~350 s) where the parallel run takes ~70 s. The Stop hook then runs the full set anyway.

**Fix.** Prompt rule in `claude/agents/implementer.md` and `reviewer.md` (and `AGENTS.md` Harness rules): while iterating run 1-2 affected suites singly; never loop over suites; for more than two suites run `./install.sh --test` once (parallel). Keep "pass those before you commit" in the suite bullet (claude/agents/implementer.md:40): the Stop hook gate runs after the commit and push, so that line is the only thing that orders tests before a commit. A #167 draft dropped it and its own implementer ran the last suite, `git commit` and `git push` in one Bash call (stream 20261119-112158-implementer.jsonl); review restored it.

**Evidence.** analyst ask 1793276439; `.harness/time-budget-detail.md` sections 1-3 (per-ask budget, long Bash calls, per-suite serial wall time).
