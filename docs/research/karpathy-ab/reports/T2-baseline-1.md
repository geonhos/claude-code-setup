# implementer report — parallel test suites, no clear sleep, scoped worker runs
status: done
## Changed files
- install.sh — `--test` starts all 8 suites with `&`, buffers output per suite, prints each block (`=== name (exit N) ===`) in finish order, lists failed suites; `HARNESS_TEST_SERIAL=1` runs them one by one
- tests/harness.test.sh, tests/retro.test.sh — `HARNESS_CLEAR_INTERVAL=0` in setup env
- claude/agents/implementer.md — run only affected suites while iterating; Stop hook runs the full suite
- AGENTS.md, README.md — describe parallel run, serial switch, no-shared-state rule
- docs/wiki/log.md — one line
## Findings / Decisions
- Shared-state check: every suite already uses `mktemp -d` (harness/retro/progress per case); no fixed /tmp, ports or pane names. No test changes needed beyond B.
- bash 3.2: `&` plus polling for per-suite `.rc` files (no `wait -n`); `set -u` needed `failed=""` init.
- E: Stop hook (harness-verify stop) runs the full suite after the worker stops; the old text said to run tests before reporting. Chosen: commit after affected suites pass, the hook's full run is the gate, on a block fix in a new commit and stop again; never report done before the hook passes. Nothing commits untested; the full run is just not run twice.
- AGENTS.md "All must pass before a commit" kept; the Stop hook is the full gate.
## Verification
- `./install.sh --test` ×3 → all suites 0 failures each time; wall 104 s, 118 s, 92 s (machine under load; was ~195 s serial, analyst measured 86 s)
- `HARNESS_TEST_SERIAL=1 ./install.sh --test` → no failures
- `bin/harness wiki-lint docs/wiki` → clean (no output, rc 0)
## Open questions
- Parallel wall time is bound by harness.test.sh (~70+ s); splitting it (option C) would help further.

