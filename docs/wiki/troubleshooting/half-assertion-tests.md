---
type: troubleshooting
status: active
updated: 2026-11-23
sources: [ask 1793234470-88835-27188, ask 1793592694-69856-23170, ask 1793579541-93754-11838, ask 1793581034-11731-12201, ask 1793600199-57068-4004, 747593a, bee6a4d, ask 1795354538-9955-23718, "#206", 10f2575, tests/headless-implementer.test.sh:75, "#81", "#82", "#83", tests/dash.test.sh:245-262, tests/lane.test.sh:191-203, tests/harness-split.test.sh:110-119]
verified_by: tests/harness-split.test.sh:110-119 (lint bites on '] && [')
---
# Half-assertions: a test line that checks less than it claims

**Symptom.** A suite stays green while the behaviour it names is broken or false.

**Cause.** Seven shapes:
1. `check "name" [ a ] && [ b ]` runs `check "name" [ a ]` and treats `[ b ]` as a separate command, so only `a` is asserted (plain-`&` mutant exposed it at `tests/headless-bg.test.sh:65`). One such line hid a false claim: once fully asserted, `tests/progress.test.sh:235` failed because the design says the opposite (`lib/harness-headless.sh:212`).
2. A corrected half-assertion on unchanged behaviour passes on base too, so the "fails on base" rule cannot see it.
3. A fallback test that leaves the primary source in place never reaches the fallback: 15b3 kept `analyst.session`, so `hl_last_session` never ran (`tests/headless.test.sh:303-309`, fixed in bee6a4d by removing the file first).
4. The expected value comes from the code under test: display widths checked against the lib's own table hid missing ranges (#82; U+1F7E0 drew 23 cols at W=20). Hard-code expected values or use an independent reference (tests/dash.test.sh:245).
5. The input is not what the test names: U+3008 and U+2329 look the same, so a U+2329 case used U+3008 and passed on the old code (#83). Write such characters as byte escapes (`printf '\xe2\x8c\xa9'`) and check them with `od`.
6. A tool normalises the asserted value: git stores `git worktree add` paths as realpath, so checking `git worktree list` missed a symlinked-parent bug (#81; the section passed on aec662b). Assert on the path the user typed (tests/lane.test.sh:191-203).
7. A dedupe keyed on a field one source lacks passes a one-item-per-source test: the #197 denial dedupe keyed on `tool_input`, which the real input-less `permission_denied` events lack; the first fix tested one such event plus one result, so repeated events slipped through. Feed repeated identical items in both sources (tests/headless-implementer.test.sh:75: 2 input-less events + 2 identical results → one entry; fixed in 10f2575).

**Fix.** (1) Use one condition or `${var:-/nonexistent}`; the lint added in 747593a (`tests/harness-split.test.sh:110-119`) rejects `] && [`, `] && !`, `] || !` and `not_grep -q`; `# lint-skip` opts out. (2) Prove the test with a mutant of the code, not a base run. (3) Remove the primary source before testing the fallback. (4-6) Take expected values and inputs from outside the code and tools under test. (7) Repeat identical items in every source a dedupe merges.

**Evidence.** Asks 1793234470-88835-27188, 1793592694-69856-23170, 1793579541-93754-11838, 1793581034-11731-12201, 1793600199-57068-4004.
