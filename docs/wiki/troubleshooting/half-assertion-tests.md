---
type: troubleshooting
status: active
updated: 2026-11-03
sources: [ask 1793234470-88835-27188, ask 1793592694-69856-23170, ask 1793579541-93754-11838, ask 1793581034-11731-12201, ask 1793600199-57068-4004, 747593a, bee6a4d, tests/harness-split.test.sh:110-119]
verified_by: tests/harness-split.test.sh:110-119 (lint bites on '] && [')
---
# Half-assertions: a test line that checks less than it claims

**Symptom.** A suite stays green while the behaviour it names is broken or false.

**Cause.** Three shapes:
1. `check "name" [ a ] && [ b ]` runs `check "name" [ a ]` and treats `[ b ]` as a separate command, so only `a` is asserted (plain-`&` mutant exposed it at `tests/headless-bg.test.sh:65`). One such line hid a false claim: once fully asserted, `tests/progress.test.sh:235` failed because the design says the opposite (`lib/harness-headless.sh:212`).
2. A corrected half-assertion on unchanged behaviour passes on base too, so the "fails on base" rule cannot see it.
3. A fallback test that leaves the primary source in place never reaches the fallback: 15b3 kept `analyst.session`, so `hl_last_session` never ran (`tests/headless.test.sh:303-309`, fixed in bee6a4d by removing the file first).

**Fix.** (1) Use one condition or `${var:-/nonexistent}`; the lint added in 747593a (`tests/harness-split.test.sh:110-119`) rejects `] && [`, `] && !`, `] || !` and `not_grep -q`; `# lint-skip` opts out. (2) Prove the test with a mutant of the code, not a base run. (3) Remove the primary source before testing the fallback.

**Evidence.** Asks 1793234470-88835-27188, 1793592694-69856-23170, 1793579541-93754-11838, 1793581034-11731-12201, 1793600199-57068-4004.
