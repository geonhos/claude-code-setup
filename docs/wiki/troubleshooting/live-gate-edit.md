---
type: troubleshooting
status: active
updated: 2026-11-17
sources: [ask 1793148917-30280-32482, commit 4d9b627, claude/hooks/conductor-gate.sh, decisions/0005-gate-only-inside-herdr.md, "#141", "#154"]
verified_by: tests/gate.test.sh
---
# A gate edit locks the conductor out, or silently opens it

**Symptom.** Right after a worker edits `claude/hooks/conductor-gate.sh`, every conductor tool call is denied, including `harness` and `cat .harness/...`, with no useful message.

**Cause.** The gate is live: `~/.claude/settings.json` points at the repo file, and only exit 2 blocks a call. A bash syntax error exits 2, so it denies everything. Every other failure fails open silently: exit 1, a crash such as an unbound variable under `set -u`, a missing script (127) and a timeout all let the tool call run, because the hook is registered without `onFailure: "block"` (probe on #141, Claude Code 2.1.326; not added, the gate stays registered globally). An unescaped `$(` inside a double-quoted message string was enough (commit 4d9b627 fixed it).

**Fix.** A broken gate may also stop gating without any message, so the suite matters as much as `bash -n`. Treat the gate like `bin/`: edit through a new inode (Edit tool or tmp + mv), run `bash -n` and `bash tests/gate.test.sh` before every save, and escape `\$(` and backticks in message strings. If the conductor is already locked out, fix the file from a worker pane; the conductor needs no restart.
