---
type: decision
status: active
updated: 2026-10-21
sources: [docs/superpowers/plans/2026-10-21-gate-opt-in.md, .harness/review-critique-detail.md §1.4-1.5, claude/hooks/conductor-gate.sh:10-30]
verified_by: tests/gate.test.sh
---
# 0005 — Gate only inside herdr, fail closed on bad input

**Decision.** `conductor-gate.sh` checks, in order:
1. `HARNESS_ROLE=worker` → allow (unchanged).
2. `HERDR_ENV` is not `1` → allow. Outside a herdr pane `harness ask` dies
   (`bin/harness`, "run Claude inside a herdr pane"), so a gated conductor
   there can neither delegate nor work.
3. jq missing → deny (unchanged).
4. Hook input that does not parse, or has no `tool_name` → **deny** (was allow).

The global `settings.agent = "conductor"` stays (user choice, 2026-10-21); the
`HERDR_ENV` guard is the opt-out for sessions outside herdr. The PreToolUse
matcher is unchanged: `WebFetch`, `Skill` and non-filesystem MCP tools do not
read the local tree, and the gate is a routing nudge, not a security boundary.

**Why.** The critique (§1.4) found the gate allowed what it could not parse,
and (§1.5) that the global conductor made every session outside herdr useless.

**Status.** Active. Shrinking the 529-line parser toward `permissions` rules
(Top 10 #4b) is a separate design.

**Consequences.**
- A session started outside herdr is ungated even though it runs the conductor
  prompt; the prompt tells it to work directly there.
- Env-based checks trust inherited env. A Claude daemon started in a worker
  pane hands `HARNESS_ROLE=worker` to every session it hosts, gate off — see
  gotcha [daemon inherits worker env](../troubleshooting/daemon-inherits-worker-env.md).
  `HERDR_ENV` does not help there: it is inherited too.
