---
type: decision
status: active
updated: 2026-10-28
sources: [.harness/headless-design.md, .harness/headless-detail.md, branch feature/v16-headless-runner, ask 1792721195-60464-27462]
verified_by: tests/headless.test.sh
---
# 0007: Headless runner pilot: `claude -p` in a viewer pane

**Context.** Pane completion rests on a chain (Stop-hook marker, report mtime, herdr idle, grace) whose races produced the exit-3/4 false positives ([0002](0002-completion-by-stop-hook-marker.md)). Nobody types into the workers (interaction need ~0), but the user wants to watch them ([0001](0001-keep-herdr-panes-despite-subagent-model.md)).

**Decision.** Analyst first, reviewer next; the implementer follows in [0009](0009-headless-implementer.md).
- D1 `runner.<role>: pane|headless` in `.harness/config.json`; env `HARNESS_RUNNER_<ROLE>` wins; missing = pane. The config template is unchanged (the decision 0006 migration compares it byte for byte).
- D2 One kept viewer pane per headless role (plain shell, no herdr agent); each ask runs `harness-run <role> <ask-id> <root>` in it via `herdr pane run`. `harness-view` renders the stream.
- D3 `harness-run` / `harness-view` are separate bins: the conductor gate matches only `harness`, and `harness-run` refuses without `HARNESS_ROLE=worker`.
- D4 Completion = `.harness/asks/<role>.exit.json` carrying this ask-id (atomic write). No marker, idle, grace or `/clear`.
- D5 Never kill at the ask deadline: exit 4 "still running", collect with `harness report`. Dead run without exit file: exit 3. A run that never announces its pid within `HARNESS_HL_START_S` is an infra failure: exit 1 (as conductor.md says; queues a retro), not 4. Watchdog `headless_max_minutes` (default 60); it exits with its `harness-run` and only kills a pipeline that is still that runner's child.
- D6 Fresh session by default; `--keep` resumes the last session (`--resume <sid>`), no automatic resume after a failure (amended by 0009: the implementer resumes after a non-zero exit). `.session` is cleared at each ask start and written by the run itself at `init`; if the previous run recorded none, `--keep` says it falls back to the last successful session in progress.jsonl.
- D7 The agents' Stop hook stays; headless ignores its marker.
- D8 progress.jsonl gains `runner, cost_usd, turns, result, denials, stream_log, resume, startup_s`; `harness metrics` splits by `agent/runner` (missing = pane).
- D9 Raw stream in `.harness/log/<stamp>-<role>.jsonl`; the gate denies the conductor reading it.
- Which code path a role takes (`use_hl`): config says headless, or a headless run is alive (pid file + process name). A leftover `.run` or `exit.json` under `runner=pane` is pane behaviour; herdr answers never decide it.
- Streams a pending retro candidate names are never gzipped or deleted; retro briefs resolve `X.jsonl` to `X.jsonl.gz`.
- `harness close` refuses (exit 4) while a run is alive, unless `--force` (kills the process tree, logged `force_kill`).

**Status.** Active for analyst and reviewer. Pilot numbers (`harness metrics`, 28d): analyst headless 12 asks, 3 abnormal, median 269 s, p95 600 s, about $1.4 per ask; pane 18 asks, 15 abnormal, median 161 s. Reviewer headless 6 asks, 0 abnormal, median 229 s, about $0.70 per ask; pane 52 asks, 14 abnormal, median 167 s. Headless is slower per ask but far fewer abnormal exits.

**Consequences.** About +330 net lines while both runners exist. No typing into headless workers. Raw streams hold source, so the gate rule is load-bearing. Rollback = set `runner.analyst` back to `pane` (or `HARNESS_RUNNER_ANALYST=pane`), then `harness close analyst --force`; no data migration. `claude -p` waits for background-Bash notifications before it exits, so the pane-mode "turn ended, then idle, then exit 3" race cannot happen headless (probe: 2 turns, 24 s for a 15 s background sleep).
