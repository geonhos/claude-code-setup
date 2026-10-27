---
type: gotcha
status: active
updated: 2026-10-27
sources: [ask 1792562994-34957-9151, ask 1792565478-50561-31913, commit 174e159, tests/harness-ask.test.sh:44]
verified_by: tests/harness-ask.test.sh (late marker within grace)
---
# Whole-second `date +%s` makes a 1 s grace (0,1] s

**Symptom.** A Stop-hook verify fails on a timing check the diff never touched (e.g. "late marker within grace: rc 0"); re-running the suite passes sometimes.

**Cause.** The harness compares epochs from `date +%s` (bash 3.2 has no sub-second clock). A grace of N s is really (N-1, N] s, so a 0.4 s sleep against a 1 s grace loses whenever the second ticks between the two reads.

**Fix.** Give timing tests a grace of ≥ 2 s (the harness uses 3 s). When a verify fails on an untouched timing check, look for a whole-second comparison against a sub-second sleep before looping the suite.
