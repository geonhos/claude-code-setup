---
type: troubleshooting
status: active
updated: 2026-10-28
sources: [ask 1793148917-30280-32482, commit 4d9b627, claude/hooks/conductor-gate.sh, decisions/0005-gate-only-inside-herdr.md]
verified_by: tests/gate.test.sh
---
# A gate edit locks the conductor out

**Symptom.** Right after a worker edits `claude/hooks/conductor-gate.sh`, every conductor tool call is denied, including `harness` and `cat .harness/...`, with no useful message.

**Cause.** The gate is live: `~/.claude/settings.json` points at the repo file, and it is fail-closed (decision 0005), so a script that exits non-zero denies everything. An unescaped `$(` inside a double-quoted message string was enough (commit 4d9b627 fixed it).

**Fix.** Treat the gate like `bin/`: edit through a new inode (Edit tool or tmp + mv), run `bash -n` and `bash tests/gate.test.sh` before every save, and escape `\$(` and backticks in message strings. If the conductor is already locked out, fix the file from a worker pane; the conductor needs no restart.
