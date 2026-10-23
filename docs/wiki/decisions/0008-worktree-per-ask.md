---
type: decision
status: active
updated: 2026-10-23
sources: [.harness/worktree-design.md, branch feature/v18-worktree-s1]
verified_by: tests/worktree.test.sh
---
# 0008 — Worktree per ask (S1: headless analyst/reviewer)

**Context.** Per-role slots (`.harness/asks/<role>.*`, `reports/<role>.md`) allow one run per role, so same-role asks cannot run in parallel. Headless runs ([0007](0007-headless-runner-pilot.md)) are plain `claude -p` processes and can run in any directory.

**Decision.** `harness ask <analyst|reviewer> … --worktree [--base REF]` (headless runner only) creates `git worktree add --detach` at `~/.cache/harness/wt/<repo8>/<role>-<id8>` (never under `.harness/`: the conductor gate would then let it read source). The worktree is the run's root: its own `.harness/{asks,reports}`; the brief and `verify.local.json` are copied in, `.claude/agent-memory` is a symlink to the main one. Shared state stays in the main root: progress.jsonl (+ `wt`, `base`, `ask_id`), progress.md, logs (`-<id8>` in the name, raw stream via `log_dir=` in `.run`), routing, retro, panes (key `<role>@<id8>`). Registry `.harness/wt/<ask-id>.json`; `report`/`close` take the ask-id; `max_parallel` (default 3) refuses another with exit 4. Implementer, pane roles and `--keep` are usage errors (exit 1).

**Lifecycle.** Report collected (exit 0/5) and tree clean → `git worktree remove` + prune, viewer pane closed, report saved as `.harness/wt/<id>.report.md`. Otherwise kept until `harness close <ask-id> [--force]` or the idle-TTL reap of clean kept entries.

**Status.** Active. S2 (implementer with a branch and merge) is not built.

**Consequences.** `.claude/agent-memory` is not ignored as a symlink (the ignore rule has a trailing slash): the dirty check filters it and it is removed before `git worktree remove`. A refused `close` on a dirty tree needs `--force`.
