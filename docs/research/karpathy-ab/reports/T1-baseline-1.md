# implementer report — Stop hooks run from git toplevel, warn on missing .current
status: done
## Changed files
- bin/harness-verify — enter_root moves to git toplevel after cd; mark_done warns on stderr (exit 0) if <role>.current missing
- bin/harness — exit-3 hint now also names "Stop hook ran from a directory without .harness (check worker's cwd)"
- tests/verify.test.sh — subdir tests flipped to toplevel; new done/stop-from-subdir and warn tests
- docs/wiki/inbox/* — two inbox notes committed untouched (second commit)
## Findings / Decisions
- Old "sub:" tests asserted root=cwd (deliberate earlier design); flipped to toplevel per task
- Config (.claude/harness.json) is now read from toplevel too, since enter_root is shared
- New tests fail without the fix (11 FAILs on old bin)
## Verification
- bash tests/verify.test.sh → PASS 147 / FAIL 0; ./install.sh --test → all suites FAIL 0
## Open questions
- none
