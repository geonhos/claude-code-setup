# Progress Log and Context Reset — Implementation Plan

Spec: `docs/superpowers/specs/2026-10-18-progress-and-context-reset-design.md`
Branch: `feature/v7-herdr-conductor`. TDD per task (failing test first),
macOS `/bin/bash` 3.2, awk over associative arrays, fake herdr for tests.

1. **Live `/clear` probe** (no code): one temporary herdr pane running
   `claude --agent analyst` with `HARNESS_ROLE=worker`; `herdr agent prompt
   <name> '/clear'` without `--wait`; poll `herdr agent get`; then a prompt
   that must come back in the analyst report format. Close the pane. Write
   `.harness/clear-probe.md` with the observed state sequence and timings.
   If `/clear` does not keep the agent prompt, the reset path becomes
   respawn-only; say so in the report and continue.
2. Per-ask log + `progress.jsonl` line in `bin/harness ask` (all exit
   paths), with `tests/progress.test.sh`.
3. Rotation (200 files / 14 days / 1 MB gz).
4. `progress.md` generation, `.harness/goal.md`.
5. `ctx` reading: transcript path from session id, usage parsing; `harness
   status` column; `ctx_before/after` in the jsonl.
6. Reset logic: implementer clear-or-respawn per ask; analyst/reviewer
   threshold (`HARNESS_CTX_RESET`), `--fresh`, `--keep`; spawn env
   `CLAUDE_CODE_AUTO_COMPACT_WINDOW`. Fake herdr must support the session-id
   change on `/clear`.
7. `claude/hooks/conductor-resume.sh` + install.sh SessionStart merge +
   install tests.
8. conductor.md, implementer.md, README.
9. Commit per task or in a few logical commits.
