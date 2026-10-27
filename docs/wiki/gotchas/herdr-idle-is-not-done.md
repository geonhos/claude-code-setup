---
type: gotcha
status: active
updated: 2026-10-27
sources: [.harness/review-critique-detail.md §1.3, commit 5ea7475, commit 79a1964, https://raw.githubusercontent.com/herdrdev/herdr/v0.9.5/docs/next/website/src/content/docs/agent-automation.mdx]
verified_by: tests/harness-ask.test.sh (marker/idle/pending cases); live reviewer ask exit 0 after respawn 2026-10-21
---
# herdr "idle" does not mean the worker finished

**Symptom.** `harness ask` exits 3 ("finished but wrote no report") or 4 while the worker is in fact still busy, e.g. waiting on background subagents or running its Stop-hook verify. Before the fix, about 38% of 61 asks ended abnormally.

**Cause.** herdr infers Claude's state from screen regexes (`claude.toml` manifest). When nothing matches, it defaults to idle. `herdr agent prompt --wait` does not track turns. A worker that ends its turn to wait for background tasks shows as idle.

**Fix.** Completion is the Stop-hook marker; herdr idle is only a fallback with a 30 s grace — rule and ordering in [ADR 0002](../decisions/0002-completion-by-stop-hook-marker.md). Headless roles bypass this ([0007](../decisions/0007-headless-runner-pilot.md)).

**Still open.** Whether herdr reports `working` for the whole length of a long Stop hook is not verified. If it reports idle, the deadline restore can race on verifies longer than the ask timeout.
