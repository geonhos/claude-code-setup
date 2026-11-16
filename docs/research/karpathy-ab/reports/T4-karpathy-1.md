# implementer report — prune step 5: --via removed, gate tables labelled, ADR 0012
status: done
## Changed files
- bin/harness — `--via` arm removed from ask_parse_args (new inode); unknown option now ASK_BAD, exit 1
- tests/progress.test.sh — no-op cases replaced by one "--via refused: rc 1, no exit.json" case
- tests/gate.test.sh — `--via` allow probe → `--keep`; 11 "ydr" tests for every "You may run directly" form
- claude/hooks/conductor-gate.sh — POLICY TABLES block (messages + BASH_ALLOW/GH_ALLOW/GIT_DENY) labelled; no behaviour change
- claude/agents/conductor.md — intro states `disallowedTools` removes Agent/Workflow/Monitor/NotebookEdit
- docs/wiki: decisions/0012-gate-shrink.md (new), 0011 (step 5 line), index.md (0012, 0011, 0005 hooks), log.md
## Findings / Decisions
- Commits: de13cf2 (--via), 8db28c6 (tables), 3337b3e (trim), plus docs commit; branch chore/prune-5-gate-shrink, not pushed
- Most of options b, c, d were ALREADY done in the current gate (gh limited to pr subcommands, git branch regex, herdr pane get|current only, no Agent/Workflow/mcp__filesystem cases, MATCHER already `Edit|Write|Read|Grep|Glob|Bash`; no JQ_DENY, no `git show --stat`). Commit 3 is therefore tests + conductor.md wording only; no gate code removed.
- conductor.md `disallowedTools` already lists the 4 tools, so nothing added; mcp__filesystem__* not needed (no block exists, no server configured).
- Gate is 517 lines (552 → 517), not ~420: path helpers stay; stated honestly in ADR 0012.
- lib/harness-metrics.sh has no `via` reader; old rows with `via` are ignored.
- 0011's step-4 line still says "--via is a no-op until step 5" (history, left as written).
- README has no gate line count or command list to fix; conductor-shell-one-command.md untouched (deny text unchanged).
## Verification
- bash -n + tests/gate.test.sh singly before the gate save → PASS 454, later 465
- progress/harness/metrics/headless/install/wiki suites singly → all PASS
- `./install.sh --test` (parallel) → rc 0, all suites PASS
## Open questions
- none
