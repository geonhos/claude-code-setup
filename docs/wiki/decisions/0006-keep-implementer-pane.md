---
type: decision
status: active
updated: 2026-10-23
sources: [commit perf(harness) keep the implementer pane, docs/wiki/decisions/0003-pane-lifecycle-defaults.md]
verified_by: tests/harness.test.sh (default: implementer pane kept)
---
# 0006 — Keep the implementer pane between asks

**Context.** ADR 0003 closed the implementer pane after every exit-0 ask because its context is reset anyway. Metrics 2026-09-24..10-22 show implementer median 202 s, and each ask paid a fresh Claude start plus re-reading the docs on top of that.

**Decision.** `close_after_ask.implementer` defaults to `never`. Context is still cleared with `/clear` before every implementer ask, so keeping the pane loses nothing. `on_success` remains available via config or `HARNESS_CLOSE_AFTER_ASK_IMPLEMENTER`.

**Status.** Supersedes only the implementer default of 0003; its idle TTL (30 min) and close safety rules stand.

**Consequences.**
- The idle TTL still reaps the pane 30 min after the last collected report.
- A pane started before a hook/frontmatter change keeps the old hooks: close it by hand, see [respawn-after-hook-change](../gotchas/respawn-after-hook-change.md).
- `--keep` after an exit-0 implementer ask now really keeps context (the `was closed` note only appears under `on_success`).
