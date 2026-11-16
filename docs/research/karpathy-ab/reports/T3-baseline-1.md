# implementer report — v22 PR C: headless group → lib/harness-headless.sh
status: done
## Changed files
- lib/harness-headless.sh — new; runner_of, use_hl, hl_*, ask/report/close_headless (+3-line header)
- bin/harness — group removed (2043 → 1725 lines); loader list now `defaults metrics worktree headless`
- tests/harness-split.test.sh — dropped-entry mutant hardcoded `worktree` as last entry; now drops whatever is last
- AGENTS.md, README.md, docs/wiki/log.md — layout + log line
## Findings / Decisions
- Group was main:bin/harness lines 1692–2008 (design's 1844–2160 was stale); no shared helpers needed to stay (is_headless etc. are inside the block, resolved at call time anyway)
- bin/harness-run and bin/harness-view untouched
- Line counts: bin/harness 2043→1725; lib/harness-headless.sh 320 (317 body + 3 header)
## Verification
- `git show main:bin/harness | sed -n 1692,2008p | diff - <(tail -n +4 lib/harness-headless.sh)` → empty (pure move)
- tests/harness-split.test.sh → PASS 33/0 (picks up the new file via all_listed)
- `./install.sh --test` → all suites 0 FAIL (headless 112/0); only harmless "kill: No such process" noise
- Two local commits on refactor/v22-split-c (code, docs); not pushed
## Open questions
- none
