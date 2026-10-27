---
type: decision
status: active
updated: 2026-10-27
sources: [.harness/worktree-design.md, branch feature/v18-worktree-s1]
verified_by: tests/worktree.test.sh
---
# 0008: Worktree per ask (S1: headless analyst/reviewer)

**Context.** Per-role slots (`.harness/asks/<role>.*`, `reports/<role>.md`) allow one run per role, so same-role asks cannot run in parallel. Headless runs ([0007](0007-headless-runner-pilot.md)) are plain `claude -p` processes and can run in any directory.

**Decision.** `harness ask <analyst|reviewer> … --worktree [--base REF]` (headless runner only) creates `git worktree add --detach` at `~/.cache/harness/wt/<repo8>/<role>-<id8>` (never under `.harness/`: the conductor gate would then let it read source). The worktree is the run's root: its own `.harness/{asks,reports}`; the brief and `verify.local.json` are copied in, `.claude/agent-memory` is a symlink to the main one. Shared state stays in the main root: progress.jsonl (+ `wt`, `base`, `ask_id`), progress.md, logs (`-<id8>` in the name, raw stream via `log_dir=` in `.run`), routing, retro, panes (key `<role>@<id8>`). Registry `.harness/wt/<ask-id>.json`; `report`/`close` take the ask-id; `max_parallel` (default 3) refuses another with exit 4. Implementer, pane roles and `--keep` are usage errors (exit 1).

**Lifecycle.** Report collected (exit 0/5) and tree clean to `git worktree remove` + prune, viewer pane closed, report saved as `.harness/wt/<id>.report.md`. Otherwise kept. **Kept-with-patch policy (user decision, round 3):** a worktree with a saved patch is never auto-reaped (idle TTL, LOG_DAYS); it stays `kept` in `harness status` (with the patch path) until `harness close <ask-id>`, which needs `--force` only when the tree holds changes beyond the saved patch. The patch outlives the close (removed after HARNESS_LOG_DAYS). Clean kept entries without a patch are still reaped by the idle TTL. Copy-back is an allowlist (top-level `*.md`, not `goal.md`/`progress.md`/`task-*.md`, no symlinks); `HARNESS_WT_ROOT` rejects `..`; registry/git/pane locks carry an owner pid and are taken over only if the owner is dead or the lock is old (atomic rename).

**Status.** Active. S2 (implementer with a branch and merge) is not built.

**Consequences.** `.claude/agent-memory` is not ignored as a symlink (the ignore rule has a trailing slash): the dirty check filters it and it is removed before `git worktree remove`. A refused `close` on a dirty tree needs `--force`.

**v19 follow-ups.** The registry `base` is the diff and clean-check reference: commits made in the detached checkout make the tree not clean and are saved binary-safe in the patch (`diff --cached --binary <base>`); a saved patch is only replaced when a new non-empty one is written, never deleted by a later clean check. Locks: an owner is live only if `kill -0` succeeds and its command line contains `harness` (pid reuse); `HARNESS_LOCK_MAX_S` (default 120) is a hard ceiling after which a waiter takes over with a stderr warning. A takeover first takes a `<lock>.take` mutex, re-judges the lock stale, then removes it; nothing is ever renamed away or put back.
