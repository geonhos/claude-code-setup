# implementer report — parallel test suites, clear-sleep zeroed, implementer prompt
status: done
## Changed files
- install.sh — `--test` starts all tests/*.test.sh in parallel, buffers output, prints blocks in finish order with `=== suite (exit N) ===` headers, lists failed suites; `HARNESS_TEST_SERIAL=1` runs serially
- tests/harness.test.sh, tests/retro.test.sh — `HARNESS_CLEAR_INTERVAL=0` in env (bin/harness default untouched)
- claude/agents/implementer.md — run only affected suites while iterating; Stop hook runs the full suite
- AGENTS.md, README.md, docs/wiki/log.md — parallel/serial docs, log line
## Findings / Decisions
- No shared state found: every suite already uses its own `mktemp -d`, fake-herdr state is under per-case WORK; no test changes needed
- bash 3.2: `&` + polling for per-suite `.rc` files, then `wait <pid>`; no `wait -n`
- E wording: commit after affected suites pass; Stop hook's full run is the gate; if it blocks, fix in a new commit (hook compares HEAD/tree to the baseline, so commits before stop are still verified)
## Verification
- `./install.sh --test` ×4 (1 timed + 3 consecutive) → all suites pass, no flakes; timed run 125.6 s real (machine under load; analyst measured ~86 s)
- `HARNESS_TEST_SERIAL=1 ./install.sh --test` → all pass
- `harness wiki-lint docs/wiki` → clean
## Open questions
- none
