---
type: decision
status: active
updated: 2026-10-21
sources: [docs/superpowers/plans/2026-10-21-harness-hardening.md Task 3, commits 5ea7475 2e1764a aaba018 79a1964]
verified_by: tests/harness-ask.test.sh; live reviewer ask exit 0 (2026-10-21)
---
# 0002: Ask completion = Stop-hook marker, not herdr idle

**Context.** Screen-regex idle produced false exit 3/4 on ~38% of asks.

**Decision.** `harness ask` writes `.harness/asks/<role>.current` (ask-id, start). The worker Stop hook writes `.harness/done/<role>.<ask-id>` unless it is blocking. An ask is complete when marker epoch ≥ report mtime ≥ ask start. herdr status is secondary: blocked to 2; idle with no marker and no `.pending` to 30s grace to 3; anything else waits until the deadline.

**Consequences.** A worker that genuinely finishes without a report now waits for the full timeout (exit 4) instead of 30s. Workers started before a hook change need a respawn. Same-second report/marker ordering is indistinguishable (accepted).

Not used for `runner=headless` roles; completion there = process exit (0007).
