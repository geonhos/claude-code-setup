# implementer report — parallel test suites, no clear sleep, scoped implementer runs
status: done
## Changed files
- install.sh — `--test` starts all 8 suites with `&`, buffers output per suite, prints blocks in finish order with a `=== tests/x ===` header, lists failed suites; `HARNESS_TEST_SERIAL=1` runs serially
- tests/harness.test.sh, tests/retro.test.sh — `HARNESS_CLEAR_INTERVAL=0` in setup env (bin/harness default unchanged)
- claude/agents/implementer.md — run only affected suites while iterating; Stop hook runs the full suite
- AGENTS.md, README.md — describe parallel run and serial switch
- docs/wiki/log.md — one log line
## Findings / Decisions
- No shared state found: every suite already uses its own `mktemp -d` and no ports or fixed /tmp paths are written, so no test needed changing for isolation.
- Bash 3.2 safe: `&` plus a polling loop over `.done` marker files. No `wait -n`; exit codes come from per-suite `.rc` files.
- Commit order: workers commit before the Stop hook runs, so the guarantee is "affected suites pass before commit; the hook's full run is the gate; a block is fixed in a new commit". The prompt and AGENTS.md say this.
- AGENTS.md "All must pass before a commit" kept, with the clarification added.
## Verification
- `./install.sh --test` ×3 → all pass, no flakes; 95.6 / 87.7 / 83.2 s (before: ~195 s)
- `HARNESS_TEST_SERIAL=1 ./install.sh --test` → pass, 168 s (down from ~195 s from the clear-sleep change)
- `harness wiki-lint docs/wiki` → clean (exit 0)
- Commits on feature/v13-verify-speed: 2 (perf(tests), docs(agents)); not pushed
## Open questions
- none
