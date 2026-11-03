# Wiki index

Read this first. Open a page only when it is relevant. Schema and promotion rules: the Wiki section of `AGENTS.md`. Inbox notes go stale fast: check `git log` for a fix before triaging one.

## Troubleshooting: ask completion and timeouts
- [herdr idle is not done](troubleshooting/herdr-idle-is-not-done.md): pane-runner completion; superseded by exit.json (superseded, 2026-11-02)
- [Deadline restore race](troubleshooting/deadline-restore-race.md): pane-mode deadline restore; headless never kills at the deadline (superseded, 2026-11-02)
- [ask --timeout is ms](troubleshooting/ask-timeout-is-milliseconds.md): `--timeout 1200` = 1.2s; defaults are role-aware (active, 2026-10-27)
- [Serial suite loop](troubleshooting/serial-suite-loop.md): workers looping over suites cost 5x the parallel run; run singly or `./install.sh --test` once (active, 2026-10-29)
- [.harness root lookup](troubleshooting/harness-root-lookup.md): hook finds root by nearest `.harness/asks/`; one definition in lib/harness-root.sh (active, 2026-11-03)
- [Docs-only skip scope](troubleshooting/docs-only-asks-skip-the-suite.md): Stop hook skips the suite only for `docs/`/`.harness/`; wiki runs wiki-lint only (active, 2026-10-27)

## Troubleshooting: workers, panes and env
- [Respawn after hook change](troubleshooting/respawn-after-hook-change.md): no long-lived panes any more (superseded, 2026-11-02)
- [Spawn on a cold shell](troubleshooting/spawn-on-cold-shell.md): `spawn` removed (superseded, 2026-11-02)
- [herdr names are global](troubleshooting/herdr-names-are-global.md): workers are not herdr agents any more (superseded, 2026-11-02)
- [Daemon inherits worker env](troubleshooting/daemon-inherits-worker-env.md): a Claude daemon started in a worker shell makes every hosted session a worker; gate keys on agent_type, still true for headless workers (active, 2026-11-02)
- [AGENTS.md needs a CLAUDE.md import](troubleshooting/agents-md-ignored-when-claude-md-exists.md): CLAUDE.md must start with `@AGENTS.md`; no symlink (active, 2026-10-21)
- [Live gate edit](troubleshooting/live-gate-edit.md): a broken gate script denies everything; bash -n + suite before each save (active, 2026-10-28)
- [In-place edit breaks running scripts](troubleshooting/in-place-edit-breaks-running-scripts.md): bin/ is live; bodies are brace-wrapped, edit via new inode; lib/ is safe while sourced eagerly (active, 2026-10-28)

## Troubleshooting: conductor
- [Conductor shell: one command](troubleshooting/conductor-shell-one-command.md): exactly one simple command: no `;`, `&&`, `|`, redirects (active, 2026-10-21)

## Troubleshooting: shell portability and tests
- [GNU stat -f](troubleshooting/gnu-stat-f.md): use `-nt`/`-ot` or `stat -c %Y` first (active, 2026-10-21)
- [Whole-second timing](troubleshooting/whole-second-timing.md): `date +%s` grace N s is really (N-1,N] s; tests need ≥ 2 s (stale, 2026-11-02)
- [bash signals and job control](troubleshooting/bash-signals-job-control.md): bg jobs ignore INT; `set -m` hands tty signals to children (active, 2026-10-27)
- [Tests inherit worker env](troubleshooting/tests-inherit-worker-env.md): suites run by a worker see `HARNESS_ROLE=worker`; unset it (active, 2026-10-27)
- [Test wait loops](troubleshooting/test-wait-loops.md): barrier on the asserted state; `grep -c` on a missing file breaks `-lt` (active, 2026-10-28)

## How-to
- [Transcript forensics](how-to/transcript-forensics.md): real Stop-hook time, did /clear run, known model noise (active, 2026-10-27)

## Decisions
- [0001 Keep herdr panes](decisions/0001-keep-herdr-panes-despite-subagent-model.md): subagent `model:` works; panes kept for visibility; superseded by 0011 (superseded, 2026-11-01)
- [0002 Stop-hook completion](decisions/0002-completion-by-stop-hook-marker.md): pane marker; superseded by exit.json (superseded, 2026-11-02)
- [0003 Pane lifecycle](decisions/0003-pane-lifecycle-defaults.md): pane idle TTL and close rules; removed in step 3 (superseded, 2026-11-02)
- [0004 Failure-only retros](decisions/0004-failure-only-batched-retros.md): removed in prune step 4; was: queue on failure, one batched analyst ask, reviewer FAIL never queues (superseded, 2026-11-02)
- [0005 Gate only inside herdr](decisions/0005-gate-only-inside-herdr.md): step 1 (HERDR_ENV) and the global conductor superseded, steps 2-3 scoped by 0010; agent_type keys the gate; 0012 supersedes the 4b consequence (active, 2026-11-03)
- [0006 Keep implementer pane](decisions/0006-keep-implementer-pane.md): kept implementer pane; no panes remain (superseded, 2026-11-02)
- [0007 Headless runner pilot](decisions/0007-headless-runner-pilot.md): `claude -p` detached; completion = exit file; `runner` key removed in step 3 (active, 2026-11-02)
- [0008 Worktree per ask](decisions/0008-worktree-per-ask.md): removed in prune step 4; was: `ask --worktree` gives a headless analyst/reviewer its own detached checkout; ask-id addressing (superseded, 2026-11-02)
- [0009 Headless implementer](decisions/0009-headless-implementer.md): headless implementer: pinned permissions, exit 2 on denials, auto-resume after non-zero exit, 90 min cap (active, 2026-11-02)
- [0010 Harness acts only in a checkout](decisions/0010-herdr-optional-gate-by-checkout.md): gate/resume key on .harness/asks (made by `harness init`); per-repo conductor agent; no HERDR_ENV switch; `harness wait`/`watch`; doctor and `--worktree` removed in step 4 (active, 2026-11-02)
- [0011 One runner: headless](decisions/0011-single-runner-headless.md): headless is the only runner; herdr is a viewer; prune plan steps 1-7, steps 3-6 done (active, 2026-11-03)
- [0012 Gate shrink](decisions/0012-gate-shrink.md): gate kept and trimmed to observed use (552 → 513 lines); permissions-rules and native-subagent options rejected (active, 2026-11-03)
