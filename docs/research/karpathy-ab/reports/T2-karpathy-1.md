# implementer report — parallel test suites, no clear sleep, scoped worker runs
status: done
## Changed files
- install.sh — `--test` starts all suites in parallel, buffers output per suite, prints blocks in finish order with a header, lists failed suites; `HARNESS_TEST_SERIAL=1` runs serially
- tests/harness.test.sh, tests/retro.test.sh — `HARNESS_CLEAR_INTERVAL=0` in setup env (bin/harness default untouched)
- claude/agents/implementer.md — run only affected suites while iterating; Stop hook runs the full suite
- AGENTS.md, README.md — describe parallel run and the serial switch
- docs/wiki/log.md — one line
## Findings / Decisions
- No collisions found: every suite already uses its own `mktemp -d` (incl. FAKE_DIR/FAKE_LOG); no fixed /tmp paths, ports or shared pane names. No test changes needed.
- bash 3.2: `&` + `kill -0` poll + `wait <pid>` (no `wait -n`) so blocks print in finish order.
- E wording: commit after affected suites pass; the Stop hook (which runs after the commit) is the gate. If it blocks, fix in a new commit. This is how it works today (hook compares against the ask baseline), so nothing is left untested. AGENTS.md "All must pass before a commit" reworded to match.
- Wall time: ~98–110 s parallel (3 runs, machine busy), vs. 195 s before. The analyst's 86 s did not reproduce; harness.test.sh is the bound.
## Verification
- `./install.sh --test` ×3 → rc 0 each, all 8 suites 0 failures
- `HARNESS_TEST_SERIAL=1 ./install.sh --test` → all pass
- `harness wiki-lint docs/wiki` → clean (rc 0)
## Open questions
- none
