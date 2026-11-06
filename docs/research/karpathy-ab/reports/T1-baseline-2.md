# implementer report — Stop hooks run from git toplevel (v14 step 1)
status: done
## Changed files
- bin/harness-verify — enter_root moves to git toplevel after cd to hook cwd; mark_done warns on stderr if no .current
- bin/harness — exit-3 hint also names "Stop hook ran from a directory without .harness"
- tests/verify.test.sh — subdir-cwd tests for done/stop/format, missing-.current warning
## Findings / Decisions
- Old "sub:" test block asserted the opposite (root = cwd); rewritten to expect toplevel
- format: relative tool paths are re-based from the original cwd (ORIG) to the toplevel
- Warning fires only for HARNESS_ROLE=worker and a missing .current; exit stays 0
## Verification
- TDD: new tests failed (8) before the fix, then bash tests/verify.test.sh → 147/0
- ./install.sh --test → all suites pass
- Commits: fix commit + inbox-notes commit on feature/v14-speed-stability (not pushed)
## Open questions
- none
