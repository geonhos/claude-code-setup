# implementer report — parallel test suites, no clear sleep, scoped implementer runs
status: done
## Changed files
- install.sh — `--test` starts all suites at once, buffers output per suite, prints blocks in finish order, lists failed suites; `HARNESS_TEST_SERIAL=1` runs serially
- tests/harness.test.sh, tests/retro.test.sh — set HARNESS_CLEAR_INTERVAL=0 in setup (bin/harness default untouched)
- claude/agents/implementer.md — run only affected suites while iterating; Stop hook does the full run
- AGENTS.md, README.md — test section describes parallel run and serial switch
- docs/wiki/log.md — one line
## Findings / Decisions
- Suites already use mktemp -d and per-suite FAKE_DIR; no shared /tmp, port or pane-name collision found, no test changes needed beyond B
- bash 3.2: `&` plus polling for per-suite `.rc` files (written atomically via mv); no `wait -n`
- E: commit happens before the Stop hook, so "commit after hook passes" is impossible. Chosen wording: commit after affected suites pass; if the hook blocks, fix in a new commit. The hook's full run gates the ask; harness waits for it
- Commits: 2 (A+B, E+docs)
## Verification
- `./install.sh --test` x3 → all green, 89.3 / 90.2 / 87.4 s (was ~195 s)
- `HARNESS_TEST_SERIAL=1 ./install.sh --test` → all green, 173.8 s
- `harness wiki-lint docs/wiki` → clean
## Open questions
- none
