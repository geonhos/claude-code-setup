---
type: decision
status: active
updated: 2026-11-03
sources: [.harness/setup-review.md, .harness/progress.jsonl, 0001, 0007, 0009, 0010]
verified_by: harness metrics + tests/headless*.test.sh
---
# 0011: One runner: the detached headless session

**Context.** [0001](0001-keep-herdr-panes-despite-subagent-model.md) chose panes so the user could watch and intervene. The progress log shows 0 interventions and 100% headless asks since 2026-10-29; the pane runner has had no ask since 2026-10-28 yet was still the default, so a fresh `harness init` repo needed herdr (against [0010](0010-herdr-optional-gate-by-checkout.md)). Abnormal-exit rate after 10-23: pane 13% vs headless 15%, so the case is cost and shape (pane runner ≈550-600 lines, 13 branch points), not reliability.

**Decision.** One runner: the detached headless session (`claude -p`, [0007](0007-headless-runner-pilot.md), [0009](0009-headless-implementer.md)). Waiting is read-only (`harness wait`, prune step 2); a herdr pane is a viewer only. The pane runner, `close_after_ask`, the idle-TTL reap, `/clear` scheduling and the late-report archive will be removed in prune step 3. Defaults flipped now: `HARNESS_RUNNER_DEFAULT=headless`, the config template names `runner` and `viewer` explicitly, herdr is optional in README and `install.sh`.

**Prune plan (user-approved option A, 2026-11-01).**
1. Headless default, wrong docs fixed, this decision (this PR).
2. `harness wait` + background ask + exit-3 + sleep-aware deadline fixes replace pane watching and polling.
3. Remove the pane runner, close_after_ask, TTL reap, `/clear` scheduling, late-report archive.
4. Remove routing, retro, `--worktree` and `doctor` outright.
5. Shrink the conductor gate.
6. One `.harness` root lookup: done; `harness_root` lives only in `lib/harness-root.sh`, sourced by both hooks, `bin/harness` and `bin/harness-verify`.
7. Consolidate docs (README rewrite, wiki pages superseded in step 3).

**Consequences.** Fresh repos need no herdr. Typed intervention in a running worker is gone (user accepted 2026-11-01). The troubleshooting pages about pane sessions and 0002/0003/0005/0006 become superseded at step 3. Rule behind this effort (`AGENTS.md`): no new mode without removing one.

Step 3 done 2026-11-02: pane runner, `harness spawn`, `close_after_ask`, idle-TTL reap, `/clear` scheduling, late-report archive and the `runner` config key are removed; 0002, 0003, 0006 and five pane troubleshooting pages are superseded.

Step 4 done 2026-11-02: routing log and route hook, retro, `--worktree` (registry, locks, `max_parallel`) and doctor removed; `--via` is a no-op until step 5; 0004 and 0008 superseded.

Step 5 done 2026-11-03: `--via` removed; the gate trims had already landed (3556e27, 0be020e, 4d9b627, 3bd6c55: 552 → 513 lines), see [ADR 0012](0012-gate-shrink.md).

Step 6 done 2026-11-03: `harness_root` is defined once in `lib/harness-root.sh`; the gate, the resume hook, `bin/harness` and `bin/harness-verify` source it. A hook without the lib: the gate denies only the conductor, resume exits silently.

Step 7 done 2026-11-03: README rewritten for a fresh clone; architecture.md rewritten with inline mermaid and `docs/diagrams/` removed; six superseded or stale troubleshooting pages deleted (ADRs kept); uncited plans/specs/research deleted. The prune plan is complete.
