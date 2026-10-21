---
type: gotcha
status: active
updated: 2026-10-21
sources: [.harness/review-critique-detail.md §1.3, commit 5ea7475, commit 79a1964, https://raw.githubusercontent.com/herdrdev/herdr/v0.9.5/docs/next/website/src/content/docs/agent-automation.mdx]
verified_by: tests/harness.test.sh (marker/idle/pending cases); live reviewer ask exit 0 after respawn 2026-10-21
---
# herdr "idle" does not mean the worker finished

**Symptom.** `harness ask` exits 3 ("finished but wrote no report") or 4 while the worker is in fact still busy, e.g. waiting on background subagents or running its Stop-hook verify. Before the fix, about 38% of 61 asks ended abnormally.

**Cause.** herdr infers Claude's state from screen regexes (`claude.toml` manifest). When nothing matches, it defaults to idle. `herdr agent prompt --wait` does not track turns. A worker that ends its turn to wait for background tasks shows as idle.

**Fix.** Completion = Stop-hook marker `.harness/done/<role>.<ask-id>`, with marker epoch ≥ report mtime ≥ ask start. herdr idle is only a fallback: 30s grace, and only when there is no marker and no `.pending`. While `.pending` exists (verify running), never give up early. At the deadline, exit 4 "still verifying" if the worker is `working`.

**Still open.** Whether herdr reports `working` for the whole length of a long Stop hook is not verified. If it reports idle, the deadline restore can race on verifies longer than the ask timeout.
