---
type: decision
status: active
updated: 2026-10-21
sources: [docs/superpowers/plans/2026-10-21-retro-metrics.md, commits d3ff2ec b35120e 4046e75]
verified_by: tests/retro.test.sh
---
# 0004 — Failure-only, batched retros

**Decision.** `harness ask`/`report` queue `.harness/retro/<ask-id>.json` only on failure: exit other than 0 and 5 (143, an interrupt, excluded), implementer exit 5, implementer verify attempts ≥ 2, or a late report. A reviewer exit 5 (`VERDICT: FAIL`) never queues one: a FAIL is the reviewer doing its job, and the "second consecutive FAIL for the same range" variant needs branch state the harness does not track. `harness retro` sends all pending candidates to the analyst in one ask (`--via retro`, `--fresh`); on exit 0 they move to `.harness/retro/done/`, otherwise they stay. The ask-id is the filename, so a late report updates the same candidate.

**Why.** Success stories are noise and cost an analyst ask each. One batch per finished task groups causes and keeps the cost bounded. Candidates and the brief hold ids, numbers and paths only, never screen or prompt text, since both can carry secrets. Output goes to `docs/wiki/inbox/` (only if `docs/wiki` exists) and never edits pages, so promotion stays human-approved.

**Consequences.** `rotate_logs` keeps logs referenced by pending candidates. A retro ask never queues a candidate about itself. A repeated cause shows up as a "recurrence of <page>" note, counted by `harness metrics`, which feeds the 2+ recurrence promotion rule.
