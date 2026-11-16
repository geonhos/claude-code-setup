# implementer report — prune step 5: --via removed; gate shrink (already done)
status: done
## Changed files
- bin/harness — `--via` arm removed from ask_parse_args (new inode via mv); comment updated
- tests/progress.test.sh — no-op block removed; `--via x` added to the usage-error loop (rc 1, exit-1 row, nothing sent)
- tests/gate.test.sh — dropped the `harness ask --via` allow line
- docs/wiki/decisions/0012-gate-shrink.md (new), 0011 (step 5 done), index (0012; 0011/0005 hooks), log.md
## Findings / Decisions
- Commits 2 and 3 are NOT made: nothing left to change. Gate trim (options a,b,c,d,g, gate-denied.list) already landed in 3556e27/#30 (gate v21, 552 → 513 lines); the analyst plan was stale.
- Verified in the current gate: policy tables already sit in one block after the prologue (e done); GH_ALLOW is pr-only; `git branch` is a regex; herdr is `pane get|current`; no Agent/Workflow/NotebookEdit cases or mcp__filesystem block.
- conductor.md already has `disallowedTools: Agent, Workflow, Monitor, NotebookEdit`; MATCHER is already `Edit|Write|Read|Grep|Glob|Bash` (install.sh and install test agree); "You may run directly" matches the gate.
- Every "run directly" form is already covered by gate.test.sh or gate-denied.list controls; no tests added.
- No `via` reader in lib/harness-metrics.sh; old rows with a `via` field are ignored. No other `--via` remained outside historical ADR text.
- ADR 0012 states 552 → 513 honestly as v21's result, not this PR's. README has no gate line count; no change.
- `mcp__filesystem__*` is not in disallowedTools (none configured); noted as a consequence in ADR 0012.
## Verification
- bash tests/{harness,progress,metrics,headless,gate}.test.sh singly → all PASS
- `harness wiki-lint` → rc 0; `./install.sh --test` (parallel) → all suites green
## Open questions
- none
