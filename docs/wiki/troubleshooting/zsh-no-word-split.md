---
type: troubleshooting
status: active
updated: 2026-11-27
sources: ["#282", ask 1795741083-62392-3475]
verified_by: zsh -c 'S="a.sh b.sh"; printf "[%s]\n" $S' prints one line, bash prints two
---
# zsh does not word-split an unquoted $VAR

**Symptom.** A review helper given several suites in one variable ran only the first and reported "0 fails" for mutants that break a later suite (#276 review: the M2 rerun with separate words showed lane 2 FAIL).

**Cause.** The Bash tool runs commands in the user's shell, zsh on this machine. zsh does not split unquoted parameter expansions (`SH_WORD_SPLIT` off), so `S="harness.test.sh lane.test.sh"; bash mut2.sh M2 '<expr>' $S` passes one argument. Inside the bash script the unquoted `$R/tests/$s` then split into `tests/harness.test.sh lane.test.sh`: bash ran the first suite with the second as its argument. bash's own `$S` splits, which is why the habit looks safe.

**Fix.** Write the words out (`... harness.test.sh lane.test.sh`), or use `${=S}` / an array in zsh. In the script, quote the path (`"$R/tests/$s"`) so a joined argument fails as "no such file" instead of running a different suite, and print the suite name per run; check that the output lists each suite before trusting a "0 fails".

**Evidence.** Reviewer ask 1795741083-62392-3475 (#276); repro command in `verified_by`.
