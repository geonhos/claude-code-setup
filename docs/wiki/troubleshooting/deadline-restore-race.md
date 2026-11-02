---
type: troubleshooting
status: superseded
updated: 2026-11-02
sources: [commit 79a1964, .harness/progress.jsonl implementer ask dur_s 602 (2026-10-21 11:16:46), reviewer report round 2]
verified_by: tests/harness.test.sh (pending+working at deadline gives rc 4)
---
# `verify: INTERRUPTED` while the verify was still running

> Superseded 2026-11-02 by [0011](../decisions/0011-single-runner-headless.md): the pane-mode deadline restore is gone; a headless ask never kills the run at the deadline (exit 4, `harness wait`/`report`).

**Symptom.** `harness ask implementer` prints the report with `verify: INTERRUPTED` (exit 5), and 30s later the Stop hook's verify passes and the commit is clean.

**Cause.** At the ask deadline, harness moved `.pending` to report and declared the verify interrupted without checking whether the worker was still `working`. The ask ran 602s against a 600s default timeout. It is *not* the harness rewriting its own script mid-run (first guess, refuted by timestamps).

**Fix.** At the deadline, restore only when the worker is idle/done. If it is still working, exit 4 "still verifying" and leave `.pending` alone. The implementer default is its headless cap, 5400000 ms (lib/harness-defaults.sh); pass `--timeout` only to go beyond it.
