---
type: troubleshooting
status: active
updated: 2026-11-23
sources: [ask 1795065904-88000-10413, ask 1795071884-55567-28410, "#180", "#186", "#205", "#225", install.sh:39-40, install.sh:120-123]
verified_by: human (read install.sh)
---
# A base worktree made during the suite fails worktree-guard

**Symptom.** `./install.sh --test` or `harness-verify run all` ends with `FAILED: the test run registered temp worktrees of <repo>` and `FAILED suites: worktree-guard` while every other suite is green. The listed path ends in `/base` (`/tmp/rv169.log`: `.../tmp.coCCbfiAh0/base`; `/tmp/rv165-verify.log`).

**Cause.** The guard snapshots the `git worktree list` paths under `/var/folders`, `/tmp` and `/var/tmp` before the run (install.sh:39-40) and fails on any new one after it (install.sh:120-123). It cannot tell a test's leak from the reviewer's own `git worktree add "$(mktemp -d)/base"` (claude/agents/reviewer.md:33) made while the suite runs.

**Fix.** In a review, run the suite first and create the base worktree only after it (claude/agents/reviewer.md:33 says so since #173). A head worktree made before the suite starts is already in the snapshot and is safe. Verify the head in a worktree, never by checking out in the live checkout (issue #225, the #215 review on 2026-11-23).

**Evidence.** Two reviews on 2026-11-19 (#165 round, #169 round) hit it. Promoted to claude/agents/reviewer.md:33 (#205).
