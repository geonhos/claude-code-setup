# Wiki log (append-only, one line per change)

- 2026-10-21 · conductor · PR #13 + critique · created wiki: 7 gotchas, decisions 0001–0003, index
- 2026-10-21 · implementer · PR #14 · AGENTS.md canonical, CLAUDE.md imports it; added gotcha agents-md-ignored-when-claude-md-exists
- 2026-10-21 · implementer · plan retro-metrics · added decision 0004 failure-only batched retros; harness retro and metrics
- 2026-10-21 · conductor · v11 review fixes · decision 0004: exit 1/129/130 excluded, stable candidate paths, privacy brief, dry-run writes nothing
- 2026-10-21 · conductor · plan gate-opt-in · decision 0005 gate only inside herdr, fail closed on bad input; gotcha daemon-inherits-worker-env
- 2026-10-21 · implementer · retro review fixes · decision 0004: exit 1 after pre-flight queues a candidate; report snapshots pruned with their candidate
- 2026-10-21 · implementer · implementer asks wait 29 min · /implement passes --timeout 1740000 with Bash timeout 1800000 (p95 1706s); analyst/reviewer unchanged
- 2026-10-22 · implementer · verify speed · install.sh --test runs suites in parallel (HARNESS_TEST_SERIAL=1 for serial); harness/retro tests set HARNESS_CLEAR_INTERVAL=0; implementer runs affected suites, Stop hook runs all
- 2026-10-23 · implementer · v14b worker speed · decision 0006 keep implementer pane (default never), supersedes 0003 default; worker prompts cap advisor to one call per ask
- 2026-10-23 · implementer · role-aware ask timeout · harness ask defaults to 1740000 ms for implementer, 600000 for analyst/reviewer; --timeout no longer needed
- 2026-10-23 · implementer · v15 ask latency · Stop hook skips suite for docs/.harness-only asks (wiki → wiki-lint); harness suite split in 3 + glob discovery; /clear succeeds on new session id (60 polls), one retry, then respawn; progress.jsonl `clear` field
- 2026-10-23 · implementer · v16 headless runner pilot · decision 0007: runner.<role> headless (claude -p in a viewer pane, harness-run/harness-view), completion = exit.json, gate denies .harness/log/*.jsonl; pane mode unchanged
- 2026-10-23 · implementer · v16 round 2 · 0007: use_hl needs a live run, pending-retro streams kept, --keep session fallback, start-check failure is exit 1
- 2026-10-23 · implementer · v17 round 2 · gotcha in-place-edit-breaks-running-scripts; bin/* brace-wrapped; harness-run reaps the pipeline process group (TERM, 3 s, KILL; zombie runner = dead); close drops .session; exit.json grace ~3 s
- 2026-10-23 · implementer · v18 S1 · decision 0008: ask --worktree (headless analyst/reviewer, detached checkout under ~/.cache/harness/wt, registry .harness/wt, report/close by ask-id, max_parallel 3)
