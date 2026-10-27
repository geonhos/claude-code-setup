---
type: gotcha
status: active
updated: 2026-10-27
sources: [ask 1792643421-12588-9450, ask 1792644961-69735-4647, ask 1792672554-53823-31362, ask 1792674241-84663-18593, bin/harness-verify:34-49, bin/harness:1316-1319]
verified_by: tests/verify.test.sh (done: subdir cwd writes marker at toplevel)
---
# Where `.harness/` lives is decided in more than one place

**Symptom.** An ask exits 3 although the report exists and the Stop hook ran cleanly; no `.harness/done/<role>.<ask-id>` appears. Seen when a worker ended its turn after `cd <subdir>`.

**Cause.** The conductor (`bin/harness`) uses `.harness/` in its own cwd. The Stop hook gets the *worker's* last Bash cwd and has to find the same directory again. Stray `.harness/config.json` dirs (old `ensure_config`, `tests/.harness`) made a plain `.harness/` an unreliable marker. The README also documents the location. Change one definition and state silently splits.

**Fix (in place since v14 (PR #18)).** `enter_root` walks up from the hook cwd to the git toplevel and stops at the first dir containing `.harness/asks/` (only `harness ask` writes it); `mark_done` warns on stderr when it finds no ask; workers never create `.harness/`. If you change where `.harness/` lives, change `bin/harness`, `enter_root` and the README together, and keep the subdir tests in `tests/verify.test.sh`.
