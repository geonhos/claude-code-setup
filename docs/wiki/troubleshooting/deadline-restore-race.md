---
type: troubleshooting
status: active
updated: 2026-10-27
sources: [commit 79a1964, .harness/progress.jsonl implementer ask dur_s 602 (2026-10-21 11:16:46), reviewer report round 2]
verified_by: tests/harness.test.sh (pending+working at deadline gives rc 4)
---
# `verify: INTERRUPTED` while the verify was still running

**Symptom.** `harness ask implementer` prints the report with `verify: INTERRUPTED` (exit 5), and 30s later the Stop hook's verify passes and the commit is clean.

**Cause.** At the ask deadline, harness moved `.pending` to report and declared the verify interrupted without checking whether the worker was still `working`. The ask ran 602s against a 600s default timeout. It is *not* the harness rewriting its own script mid-run (first guess, refuted by timestamps).

**Fix.** At the deadline, restore only when the worker is idle/done. If it is still working, exit 4 "still verifying" and leave `.pending` alone. The implementer default is 1740000 ms (bin/harness:71); pass `--timeout` only to go beyond it.
