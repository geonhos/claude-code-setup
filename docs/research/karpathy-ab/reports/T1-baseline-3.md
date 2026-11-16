# implementer report — Stop hooks run from git toplevel, warn on missing .current
status: done
## Changed files
- bin/harness-verify — enter_root moves to git toplevel; mark_done warns on stderr (rc 0) when .current missing; cmd_format resolves relative file against hook cwd before moving
- bin/harness — exit-3 hint also names "Stop hook ran from a directory without .harness (check the worker's cwd)"
- tests/verify.test.sh — new subdir tests (done/stop/format/warn); old "root is the cwd" block rewritten to "root is toplevel"
## Findings / Decisions
- Old tests "sub:" asserted root=cwd in a repo subdir; rewritten to the new toplevel semantics (config, state, files now at toplevel)
- Outside git, behaviour unchanged (cwd stays root)
## Verification
- ./install.sh --test → all suites pass (verify 151, harness 299)
- 2 local commits on feature/v14-speed-stability (code; inbox notes), not pushed
## Open questions
- none
