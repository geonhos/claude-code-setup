# implementer report — Stop hooks run from git toplevel, warn on missing .current
status: done
## Changed files
- bin/harness-verify — enter_root(cwd) hops to git toplevel when cwd has no .harness; mark_done warns on stderr if .current missing
- bin/harness — exit-3 hint also names "Stop hook ran from a directory without .harness"
- tests/verify.test.sh — done/stop from .harness and plain subdir; warning tests
## Findings / Decisions
- Deviation: hop to toplevel only if the hook cwd has no `.harness/` dir. Existing test "sub:" (verify.test.sh ~250) deliberately uses a subdir as root; an unconditional hop would break it.
- Hop applies only when enter_root gets a cwd arg (hooks: done/stop/format); run/baseline/detect unchanged.
- format uses absolute paths made root-relative, so it is unaffected.
- Warning only for worker sessions with valid role; exit stays 0.
## Verification
- tests/verify.test.sh → 152/0 (4 new failed first); ./install.sh --test → all pass
- Two commits made on feature/v14-speed-stability, not pushed; inbox notes committed in 2nd.
## Open questions
- none
