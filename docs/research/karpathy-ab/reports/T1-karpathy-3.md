# implementer report — v14 step 1: Stop hooks run from git toplevel
status: done
## Changed files
- bin/harness-verify — enter_root cd's to git toplevel (cwd outside git unchanged); mark_done warns on stderr if .current is missing
- bin/harness — exit-3 hint also names "Stop hook ran from a directory without .harness (check the worker cwd)"
- tests/verify.test.sh — new subdir tests for stop/done markers and the warning; rewrote the old "sub:" block
- docs/wiki/inbox/2026-10-22-* — two inbox notes committed untouched (second commit)
## Findings / Decisions
- The old "sub:" block asserted cwd-as-root (state in subdir); it encoded the reversed design, so I flipped it to toplevel.
- format subcommand: absolute paths are made relative to ROOT (now toplevel), so they still resolve; tested.
- Side effect: baseline/run/detect also use toplevel now (they call enter_root too); consistent with bin/harness.
- Warning fires only for worker sessions when the .current file doesn't exist; exit stays 0.
## Verification
- tests/verify.test.sh red first (12 fails), then 148/0
- ./install.sh --test → all suites pass (no FAILED line)
- Branch feature/v14-speed-stability; commits f063088, a148267; not pushed
## Open questions
- none
