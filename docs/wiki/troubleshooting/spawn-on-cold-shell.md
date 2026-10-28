---
type: troubleshooting
status: active
updated: 2026-10-28
sources: [ask 1793060964-82426-noid, ask 1793087152-37562-noid, ask 1793088095-7126-31139, commit f6f8f99, bin/harness:338-345, bin/harness:500]
verified_by: tests/harness.test.sh (busy retry, stale report)
---
# First ask after a reap exits 1 at once, with the previous report in the log

**Symptom.** `harness ask <role>` returns 1 after about a second, the ask id ends in `-noid`, and the ask log's Report section shows the previous ask's report. A retry works.

**Cause.** `cmd_spawn` split a pane and ran `herdr agent start` while the new zsh was still loading (p10k instant prompt draws a prompt before `.zshrc` finishes). herdr answered `agent_pane_busy` and spawn gave up. The ask died before the old report was archived, so progress recording took it for this ask's report, and the real error went only to stderr.

**Fix (v20, commit f6f8f99).** Spawn retries `agent start` on `agent_pane_busy` (`HARNESS_SPAWN_RETRIES` × `HARNESS_SPAWN_RETRY_S`); a report counts only if written after the ask started; stderr is kept in the log under `## Errors`. If an exit 1 with `-noid` still appears, read `## Errors` in the ask log, not the Report section.
