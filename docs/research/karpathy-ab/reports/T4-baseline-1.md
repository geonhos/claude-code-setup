# implementer report — prune step 5: --via removed, gate policy block, ADR 0012
status: done
## Changed files
- bin/harness — `--via` arm removed from ask_parse_args (new inode); now an unknown option (exit 1)
- tests/progress.test.sh — no-op cases replaced by "--via refused, rc 1, no run"; tests/gate.test.sh — `--via` allow probe → `--fresh`, + `cat .harness/progress.md` allow
- claude/hooks/conductor-gate.sh — labelled POLICY TABLES block (comment-only, new inode; 513 → 518 lines)
- docs/wiki: decisions/0012-gate-shrink.md (new), 0011 (step 5 done), 0005 (4b superseded), index.md, log.md
## Findings / Decisions
- Commits (branch chore/prune-5-gate-shrink, not pushed): 5cd1d80 --via, a99a1bf tables, then "trim allowlist" (test only), then docs ADR.
- Premise stale: options c, d, b, g, a and the denied-list loop were ALREADY on main (v21, PR #30): gh pr-only, git branch regex, herdr pane get|current, no Agent/MCP cases, MATCHER `Edit|Write|Read|Grep|Glob|Bash`, conductor.md `disallowedTools: Agent, Workflow, Monitor, NotebookEdit`. No JQ_DENY remains. Nothing to remove, so commit 3 only adds the one missing form test.
- Tables were already contiguous near the top; (e) became a labelled banner, no behaviour change.
- `mcp__filesystem__*` is not in disallowedTools (no prefix verification done); ADR notes the risk if such a server is added.
- lib/harness-metrics.sh never read `via`; no change. Gate line count did not shrink: 552 → 513 (v21) → 518.
- conductor.md "You may run directly" already matches the gate and deny text; conductor-shell-one-command.md untouched. README has no gate line count.
## Verification
- bash -n + tests/gate.test.sh (455 pass) before the gate mv; progress 74, harness, metrics, headless, install 199, wiki 28 pass
- ./install.sh --test (parallel) → all suites PASS (kill "No such process" noise is pre-existing)
## Open questions
- Confirm whether the 513→518 "N → M" wording in 0011/0012 is acceptable given the premise was already done.
