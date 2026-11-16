# implementer report — v22 PR C: headless group → lib/harness-headless.sh
status: done
## Changed files
- lib/harness-headless.sh — new: runner_of, use_hl, hl_*, ask_headless, report_headless, close_headless (317 lines + 3-line header)
- bin/harness — group removed (old lines 1692–2009); loader list now `defaults metrics worktree headless`
- tests/harness-split.test.sh — dropped-entry mutant updated to the new list (it hard-coded the old list)
- AGENTS.md, README.md, docs/wiki/log.md — Layout + log line
## Findings / Decisions
- Range is the contiguous block from the "headless runner (decision 0007)" comment to close_headless's `}`; the design's 1844–2160 refs were stale (branch is at 2043 lines).
- Nothing shared needed to move; helpers like has_uncollected stay in bin/harness (call-time resolution).
- bin/harness-run and bin/harness-view untouched.
- Two commits (70a85f2 refactor, 86af8ef docs), not pushed.
## Verification
- Purity: `git show HEAD~2:bin/harness | sed -n 1692,2008p | diff - <(tail -n +4 lib/harness-headless.sh)` → identical (no diff)
- Line counts: bin/harness 2043 → 1725; lib/harness-headless.sh 320
- tests/harness-split.test.sh 33/0 (new file picked up by all_listed); headless 112/0; worktree 151/0
- ./install.sh --test → rc 0, all suites PASS
## Open questions
- none
