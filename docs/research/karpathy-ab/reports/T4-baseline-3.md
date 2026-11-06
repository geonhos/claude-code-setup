# implementer report — prune step 5: --via removed, gate policy block, ADR 0012
status: done
## Changed files
- bin/harness — `--via` arm removed from ask_parse_args (new inode, mv); comment reworded
- tests/progress.test.sh, tests/gate.test.sh — no-op cases removed; `--via x` added to the usage-error loop (rc 1, logged, nothing sent); gate `--via` allow probe dropped
- claude/hooks/conductor-gate.sh — labelled POLICY TABLES block (comments only; 513 → 521 lines)
- docs/diagrams/04-gate-decision-flow.mmd — dropped Agent/Workflow/Monitor/mcp/jq/segment nodes
- docs/wiki/decisions/0012-gate-shrink.md (new), 0011, index, log — ADR, step 5 note, hooks
## Findings / Decisions
- Commit 3 was already satisfied by earlier steps: gate has pr-only gh, regex `git branch` list-only, herdr `pane get|current`, no Agent/Workflow/Monitor/NotebookEdit/mcp/jq cases; conductor.md `disallowedTools` already lists the four tools; "You may run directly" already matches the gate and MSG_BASH. Only the stale diagram needed a change.
- install.sh MATCHER is already `Edit|Write|Read|Grep|Glob|Bash`; no change, install suite green.
- All nine "run directly" forms are covered by gate.test.sh or gate-denied.list (which the gate suite loops over); no tests added.
- Policy tables were already contiguous after the prologue; commit 2 only adds a label banner.
- No reader of `via` in lib/harness-metrics.sh; old rows are unaffected. README has no gate line count; none changed.
- The ADR says gate 552 → 521 lines (552 is from the analyst's study, which predates earlier trims).
## Verification
- bash -n + tests/gate.test.sh before gate save → 453/0; harness, progress, metrics, headless, install, wiki singly → green
- `./install.sh --test` (parallel) → rc recorded green; "kill: No such process" noise is pre-existing
## Open questions
- none
