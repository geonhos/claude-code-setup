---
type: decision
status: active
updated: 2026-10-21
sources: [docs/superpowers/plans/2026-10-21-harness-hardening.md Task 4, commits e32e59c 0fec869 1481946]
verified_by: tests/harness.test.sh; live `harness close --legacy` and implementer auto-close (2026-10-21)
---
# 0003 — Pane lifecycle defaults

**Decision.** `.harness/config.json`: `close_after_ask` = implementer `on_success`, analyst/reviewer `never`; `idle_ttl_minutes` = 30, reaped at the start of `ask`/`spawn`/`status` (no daemon); `HARNESS_NO_AUTOCLOSE=1` disables both. A close never touches a worker that is working, blocked, has `.pending`, has an uncollected report, or belongs to another repo.

**Why.** The implementer's context is cleared every ask anyway, so keeping its pane buys nothing. The analyst and reviewer keep context for `--keep` follow-ups.

**Consequences.** `--keep` after an implementer exit 0 has no effect (a note is printed). Exit 5 never closes, so the fix loop keeps its context.
