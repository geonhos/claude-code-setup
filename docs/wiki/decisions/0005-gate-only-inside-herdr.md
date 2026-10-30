---
type: decision
status: active
updated: 2026-10-30
sources: [docs/superpowers/plans/2026-10-21-gate-opt-in.md, .harness/review-critique-detail.md §1.4-1.5, claude/hooks/conductor-gate.sh:10-30, ask 1793150496-56689-6967, commit d2e4bcb]
verified_by: tests/gate.test.sh
---
# 0005: Gate only inside herdr, fail closed on bad input

**Decision.** `conductor-gate.sh` checks, in order:
1. **Superseded by [0010](0010-herdr-optional-gate-by-checkout.md):** `HERDR_ENV` is not `1`: allow. Outside a herdr pane `harness ask` dies
   (`bin/harness`, "run Claude inside a herdr pane"), so a gated conductor
   there can neither delegate nor work.
2. jq missing: deny (amended by 0010: only inside a harness checkout).
3. Hook input that does not parse, or has no `tool_name`: **deny** (was allow; amended by 0010: only inside a harness checkout).
4. Hook input `agent_type` (v21): `conductor` → gated; any other agent → allow.
   Without `agent_type`, `HARNESS_ROLE=worker` → allow (older hosts).

The global `settings.agent = "conductor"` stays (user choice, 2026-10-21; superseded by 0010: per-repo via `harness init`); the
`HERDR_ENV` guard is the opt-out for sessions outside herdr (superseded by 0010: the opt-out is "not a harness checkout"). The PreToolUse
matcher is unchanged: `WebFetch`, `Skill` and non-filesystem MCP tools do not
read the local tree, and the gate is a routing nudge, not a security boundary.

**Why.** The critique (§1.4) found the gate allowed what it could not parse,
and (§1.5) that the global conductor made every session outside herdr useless.

**Status.** Active. Shrinking the 529-line parser toward `permissions` rules
(Top 10 #4b) is a separate design.

**Consequences.**
- **Superseded by 0010.** A session started outside herdr is ungated even though it runs the conductor
  prompt; the prompt tells it to work directly there.
- Env-based checks trust inherited env. A Claude daemon started in a worker
  pane hands `HARNESS_ROLE=worker` to every session it hosts, see
  troubleshooting page [daemon inherits worker env](../troubleshooting/daemon-inherits-worker-env.md).
  `HERDR_ENV` is inherited too. Since v21 (step 4 above) the gate keys on
  `agent_type`, so that daemon case stays gated; only the no-`agent_type` fallback
  still trusts env.
- Allowlists name flags; a catch-all like `git status( .*)?` leaks content
  (`git status -vv` prints the diff; found in the v21 review, fixed in d2e4bcb).
