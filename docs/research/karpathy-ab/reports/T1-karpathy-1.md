# implementer report — Stop hooks run from git toplevel
status: done
## Changed files
- bin/harness-verify — enter_root moves to git toplevel for a hook cwd; mark_done warns on stderr if .current missing
- bin/harness — exit-3 hint also names "Stop hook ran from a directory without .harness (check worker's cwd)"
- tests/verify.test.sh — 8 new checks (done/stop from subdir and from .harness, missing .current warning, non-worker silent)
## Findings / Decisions
- Existing "sub:" tests deliberately make a subdir with its own .harness the root; to keep that, toplevel move is skipped when the hook cwd already has .harness (nested root).
- Toplevel move applies only when a cwd is passed (hook stdin); CLI calls (baseline/run/detect) unchanged.
- Format hook also goes through enter_root; absolute/relative file paths still resolve under toplevel.
- Two commits made on feature/v14-speed-stability; not pushed. Inbox notes committed untouched.
## Verification
- bash tests/verify.test.sh → PASS 150 / FAIL 0 (new tests failed first)
- ./install.sh --test → all suites pass, 0 failures
## Open questions
- none
