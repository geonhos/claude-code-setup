---
type: decision
status: active
updated: 2026-11-03
sources: [.harness/gate-shrink-detail.md, .harness/spike-bprime/RESULTS.md, 3556e27, 0be020e, 4d9b627, 3bd6c55, 0011]
verified_by: tests/gate.test.sh (incl. tests/gate-denied.list)
---
# 0012: Gate shrink (prune step 5): keep a small gate, drop what was never used

**Context.** The 2026-10-28 analysis (`.harness/gate-shrink-detail.md` §1-3) replayed 881 conductor Bash calls through the 552-line gate: 754 allowed. Never used: `git show --stat`, `herdr status|pane list|layout|workspace|tab`, `gh issue|run|repo|auth|browse|pr status`, jq as a consumer (0 allowed; its one real try was denied), pipes (0), `2>&1` (0). Chaining with `;`/`&` was 5.8% of allowed calls. No filesystem MCP server is configured. The original 4b idea was to replace the gate with `permissions` rules plus a ~50-line gate ([0005](0005-gate-only-inside-herdr.md) consequences).

**Decision.** Keep the gate, trimmed to observed use; the analysis' plan options were applied over several commits, step 5 finishes the job:
- Applied earlier: allowlists trimmed to usage (`3556e27`: gh `pr create|view|list|checks|comment|edit|merge` only, list-only `git branch`, `herdr pane get|current`, no `git show`, no jq); Agent/Workflow/Monitor/NotebookEdit/`mcp__filesystem__*` cases dropped and the matcher narrowed to `Edit|Write|Read|Grep|Glob|Bash` (`0be020e`; conductor.md `disallowedTools` carries the first four); one-simple-command scanner replacing the segment splitter (`4d9b627`); `tests/gate-denied.list` of deny probes and controls (`3bd6c55`); agent_type keying ([0005](0005-gate-only-inside-herdr.md)).
- Step 5 (this PR): the `--via` no-op arm of `ask_parse_args` is gone (unknown option, exit 1); the policy tables (messages, `BASH_ALLOW`, `GH_ALLOW`, `GIT_DENY`) sit in one labelled block at the top.
- Kept on purpose: the path helpers (`rel`, `physrel`, `physical`, `readable`, `writable`, `raw_stream_rel`) and the Bash character allowlist. They stop `Read bin/harness`, `..`, a symlink under `docs/` pointing at source, and the raw `.harness/log/*.jsonl` streams, which hold source (0007); a name-level rule cannot express any of that.
- Rejected, option f ("permissions rules" instead of the hook): `permissions.deny/allow` live in user-scope settings, so they bind workers too. Workers need exactly the tools the conductor lacks, and a per-agent rule scope does not exist.
- Rejected, B' (native subagents instead of the headless runner; `.harness/spike-bprime/RESULTS.md`, 2026-11-03): subagents die when the conductor exits ("1 local agent couldn't be moved and was stopped"). The runner stays, so the gate stays.

**Status.** Active. Gate 552 → 515 lines (path helpers ~110, scanner and text checks ~110, gh/git ~110). `bin/harness` 720 → 719.

**Consequences.** Further shrink means moving a rule into the gate's data, not deleting code: each remaining helper has a deny probe in `tests/gate.test.sh` or `tests/gate-denied.list`. The conductor's "You may run directly" list in `claude/agents/conductor.md` must match `BASH_ALLOW`/`GH_ALLOW`; a new allowed form needs a gate test. Edit the gate by new inode with `bash -n` and the suite first ([live gate edit](../troubleshooting/live-gate-edit.md)). Supersedes the 4b consequence of 0005.
