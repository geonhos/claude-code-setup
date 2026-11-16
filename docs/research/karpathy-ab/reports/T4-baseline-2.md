# implementer report — prune step 5: --via removed, gate tables grouped, ADR 0012
status: done
## Changed files
- bin/harness — `--via` arm removed from ask_parse_args (unknown option now exit 1, logged)
- tests/progress.test.sh, tests/gate.test.sh — no-op cases replaced by a `--via` refusal check; "You may run directly" allow block (11 forms)
- claude/hooks/conductor-gate.sh — policy tables (messages, BASH_ALLOW, GH_ALLOW, GIT_DENY*) in one labelled block at the top; no behaviour change
- claude/agents/conductor.md — intro says disallowedTools removes native subagents (the gate no longer denies them)
- docs/wiki/decisions/0012-gate-shrink.md (new), 0011, index.md, log.md
## Findings / Decisions
- Options b, c, d were already applied by earlier gate commits (3556e27, 4d9b627, 0be020e): GH_ALLOW, branch regex, herdr pane get|current, no Agent/mcp cases, MATCHER `Edit|Write|Read|Grep|Glob|Bash`. Commit 3 is therefore tests + conductor.md wording only.
- conductor.md already had `disallowedTools: Agent, Workflow, Monitor, NotebookEdit`; `mcp__filesystem__*` is in neither gate nor frontmatter (no such server configured), so nothing added.
- Gate length: 513 → 518 lines (policy-block header); 552 baseline in the plan. install.sh/matcher test unchanged. Deny text unchanged, so conductor-shell-one-command.md untouched.
- Metrics code never reads `via`; old rows stay tolerated. README had no --via or gate line count.
- Commits: dc6668d, 9b80c9d, then tests/conductor.md, then docs (4 total, not pushed, no PR). Gate edited via tmp+mv with bash -n + gate suite first.
## Verification
- harness, progress, metrics, headless, gate (464), install (199) singly → all PASS; `harness wiki-lint` rc 0
- `./install.sh --test` once (parallel) → see below
## Open questions
- none
