---
type: troubleshooting
status: active
updated: 2026-10-21
sources: [claude/hooks/conductor-gate.sh, conductor session 2026-10-21 (3 denied compound commands)]
verified_by: human (conductor session 2026-10-21)
---
# Conductor shell: one allowed command per call

**Symptom.** The gate denies `herdr agent wait … | tail -5; harness status`, `harness close reviewer; echo rc=$?`, and `harness help 2>&1 | head` with "Conductor shell is limited to …", even though every part is allowed on its own.

**Cause.** The gate parses the whole command line. `tail`, `head`, `echo` and redirections are not on the allowlist, and `;`/`&&` chains are checked as a unit. Only `jq` is allowed as a pipe consumer.

**Fix.** Send one allowed command per Bash call, and send independent ones in parallel. Use `| jq …` to trim output. To read files, use the Read tool under `.harness/` or `docs/` instead of `cat | head`.
