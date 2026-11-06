# implementer report — parallel test suites, scoped implementer runs
status: done
## Changed files
- install.sh — `--test` starts all suites in background, buffers output per suite, prints blocks in finish order with `=== tests/x.test.sh (exit N) ===` headers, lists failed suites; `HARNESS_TEST_SERIAL=1` runs serially
- tests/harness.test.sh, tests/retro.test.sh — `HARNESS_CLEAR_INTERVAL=0` (bin/harness default untouched)
- claude/agents/implementer.md — run only affected suites; Stop hook runs the full set
- AGENTS.md, README.md — describe parallel run, serial switch, scoped worker runs
- docs/wiki/log.md — one line
## Findings / Decisions
- No parallel collisions found: every suite uses `mktemp -d`; harness state is relative `.harness/`; fake-herdr state is under per-case FAKE_DIR. No test changes needed.
- Bash 3.2: `&` + polling `.done` markers (no `wait -n`); rc kept in files.
- E wording: commit happens after affected suites pass (before Stop); the Stop hook full run is the gate; on a block, fix in a new commit. Nothing is committed untested.
- Kept the wiki-lint step of `--test` at the end, after the suites.
## Verification
- `./install.sh --test` ×3 → all rc=0, 8 suites each; wall 125 / 123 / 127 s (machine loaded: user 64 s, sys 100 s; analyst measured 86 s)
- `HARNESS_TEST_SERIAL=1 ./install.sh --test` → pass, 380 s on this loaded machine (serial baseline not re-measured)
- `harness wiki-lint docs/wiki` → clean (rc 0)
## Open questions
- Parallel wall time (~125 s) is above the analyst's 86 s; bound by harness.test.sh, option C (split it) would help.
