---
type: decision
status: active
updated: 2026-10-21
sources: [docs/research/2026-10-21-subagent-model-poc.md, commit 1978486, https://code.claude.com/docs/en/sub-agents]
verified_by: docs/research/2026-10-21-subagent-model-poc.md (modelUsage split)
---
# 0001 — Keep herdr worker panes although subagent `model:` works

**Context.** The herdr layer was justified by "native subagents inherit the conductor's (Fable) model". The PoC proved that false: a subagent with `model: sonnet` under an opus parent was billed on sonnet, and `inherit` billed opus only.

**Decision.** Keep the herdr panes. The user wants to watch and intervene in workers live, which subagents don't offer. The gate still denies the `Agent` tool for the conductor, and its message now gives the real reason (visibility + logging), not cost.

**Consequences.** We pay for screen-based state detection (see [herdr idle](../gotchas/herdr-idle-is-not-done.md)), get serial-per-role workers, and share the working tree. Revisit if pane observability turns out to be unused, or if Agent Teams split-pane covers it (critique §4).
