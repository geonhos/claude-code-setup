---
type: troubleshooting
status: active
updated: 2026-10-28
sources: [claude/hooks/conductor-gate.sh, conductor session 2026-10-21 (3 denied compound commands)]
verified_by: tests/gate.test.sh (list: git status && harness status)
---
# Conductor shell: one allowed command per call

**Symptom.** The gate denies `herdr agent wait … | tail -5; harness status`, `harness close reviewer; echo rc=$?`, and `harness help 2>&1 | head` with "Conductor shell is limited to …", even though every part is allowed on its own.

**Cause.** Since v21 the gate accepts exactly one simple command. Any unquoted `;`, `&`, `|`, `<`, `>` (so `2>&1` too), `#`, backtick, `$(` or newline denies the call, and `jq`, `tail`, `head`, `echo` are not on the allowlist. (Before v21 chains were split and checked per segment and `| jq` was allowed; usage showed 44 of 754 calls chained, 0 piped.)

**Fix.** Send one allowed command per Bash call, and send independent ones in parallel. To read files, use the Read tool under `.harness/` or `docs/` instead of `cat | head`.
