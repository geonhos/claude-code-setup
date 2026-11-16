# implementer report — prune step 5: --via removed; gate shrink found already done
status: done
## Changed files
- bin/harness — `--via` arm removed from ask_parse_args (new inode, bash -n ok); comment example reworded
- tests/progress.test.sh — no-op block removed; `--via x` added to the usage-error loop (rc 1, exit 1 logged, nothing sent)
- tests/gate.test.sh — `--via` example → `--fresh`; check that conductor.md `disallowedTools` lists Agent/Workflow/Monitor/NotebookEdit
- claude/agents/conductor.md — prose: frontmatter removes subagent tools, gate does not
- docs/wiki: decisions/0012-gate-shrink.md (new), 0011 (step 5 line), index.md (0012, 0005 and 0011 hooks), log.md
## Findings / Decisions
- Commits: 868d83c (--via), 8f1b148 + 252d863 (gate/test), docs commit. Commit 2 skipped: no code to move.
- The gate was already shrunk before this task (3556e27 allowlists, 0be020e dead tools + matcher, 4d9b627 scanner, 3bd6c55 denied.list). Policy tables/messages already sit together at gate lines 84-121; gh/git branch/herdr already at the target lists; no jq, no Agent/mcp cases; matcher is `Edit|Write|Read|Grep|Glob|Bash`; install.test asserts it. So commit 3's trims were no-ops; the gate script was NOT modified (552 → 513 lines is from earlier commits).
- (b) precondition holds: conductor.md `disallowedTools: Agent, Workflow, Monitor, NotebookEdit`; no mcp__filesystem prefix added (no such server configured).
- Every "You may run directly" form is covered by gate.test.sh or gate-denied.list controls; no new per-form tests needed. conductor.md list already matches the gate; deny text unchanged, so conductor-shell-one-command.md untouched.
- lib/harness-metrics.sh has no `via` reader; old rows with `via` are harmless.
- README has no gate line count or command list to fix.
## Verification
- bash tests/{harness,progress,metrics,headless,gate,install,wiki}.test.sh singly → all PASS (gate 458/0)
- `./install.sh --test` → rc 0 on second run; first run had headless-bg fail under parallel load, passes singly (68/0) — flaky
## Open questions
- Commit 2/3 were effectively empty because the shrink had landed earlier; confirm ADR 0012 wording ("552 → 513") is the framing you want.
## Notes
- headless-bg suite flaked once in a parallel `./install.sh --test` and passed singly (ask: prune-5, run 1 vs 2).
