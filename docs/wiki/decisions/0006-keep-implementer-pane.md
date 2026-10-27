---
type: decision
status: active
updated: 2026-10-27
sources: [commit 32c22fd, docs/wiki/decisions/0003-pane-lifecycle-defaults.md, ask 1792712690-17681-13060]
verified_by: tests/harness.test.sh (default: implementer pane kept)
---
# 0006: Keep the implementer pane between asks

**Context.** decision 0003 closed the implementer pane after every exit-0 ask because its context is reset anyway. Metrics 2026-09-24..10-22 show implementer median 202 s, and each ask paid a fresh Claude start plus re-reading the docs on top of that.

**Decision.** `close_after_ask.implementer` defaults to `never`. Context is still cleared with `/clear` before every implementer ask, so keeping the pane loses nothing. `on_success` remains available via config or `HARNESS_CLOSE_AFTER_ASK_IMPLEMENTER`.

**Status.** Supersedes only the implementer default of 0003; its idle TTL (30 min) and close safety rules stand.

**Consequences.**
- The idle TTL still reaps the pane 30 min after the last collected report.
- A pane started before a change to an agent prompt or hooks keeps the old ones (`/clear` does not reload them): after merging such a change run `harness close implementer` (or `--all`), see [respawn-after-hook-change](../troubleshooting/respawn-after-hook-change.md).
- `--keep` after an exit-0 implementer ask now really keeps context (the `was closed` note only appears under `on_success`).
- Existing repos: a default the generated config writes out explicitly never reaches existing installs by itself, so `ensure_config` rewrites `.harness/config.json` once, only when it is byte-for-byte the old template (implementer `on_success`). A config you edited keeps `on_success`: change `close_after_ask.implementer` to `never` by hand. The migration derives the old text from the current `config_template`; `tests/harness-lifecycle.test.sh:117` hardcodes the old template to catch drift, so change both together.
