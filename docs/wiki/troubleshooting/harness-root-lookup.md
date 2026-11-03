---
type: troubleshooting
status: active
updated: 2026-11-03
sources: [ask 1792643421-12588-9450, ask 1792644961-69735-4647, ask 1792672554-53823-31362, ask 1792674241-84663-18593, bin/harness-verify:34-49, bin/harness:1316-1319, lib/harness-root.sh, commit 7a5f750..07d94b5]
verified_by: tests/gate.test.sh (agree, defined-once), tests/verify.test.sh (subdir)
---
# Where `.harness/` lives is decided in more than one place

**Symptom.** An ask exits 3 although the report exists and the Stop hook ran cleanly; no `.harness/done/<role>.<ask-id>` appears. Seen when a worker ended its turn after `cd <subdir>`.

**Cause.** The conductor (`bin/harness`) uses `.harness/` in its own cwd. The Stop hook gets the *worker's* last Bash cwd and has to find the same directory again. Stray `.harness/config.json` dirs (old `ensure_config`, `tests/.harness`) made a plain `.harness/` an unreliable marker. The README also documents the location. Change one definition and state silently splits.

**Fix (one definition since prune step 6).** `harness_root` lives only in `lib/harness-root.sh`; change it there. `bin/harness`, `bin/harness-verify` and both hooks source it. `enter_root` only adds the cwd fallback and `IS_GIT`. A hook without its lib: the gate denies the conductor only (reason names `./install.sh`), the resume hook stays silent. `mark_done` warns on stderr when it finds no ask; workers never create `.harness/`. Keep the subdir tests in `tests/verify.test.sh` and `agree`/defined-once in `tests/gate.test.sh`.
