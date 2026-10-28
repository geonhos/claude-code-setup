# Wiki index

Read this first. Open a page only when it is relevant. Schema and promotion rules: the Wiki section of `AGENTS.md`. Inbox notes go stale fast: check `git log` for a fix before triaging one.

## Troubleshooting: ask completion and timeouts
- [herdr idle is not done](troubleshooting/herdr-idle-is-not-done.md): completion = Stop-hook marker, idle only a fallback (active, 2026-10-27)
- [Deadline restore race](troubleshooting/deadline-restore-race.md): false INTERRUPTED when ask hits the deadline mid-verify (active, 2026-10-27)
- [ask --timeout is ms](troubleshooting/ask-timeout-is-milliseconds.md): `--timeout 1200` = 1.2s; defaults are role-aware (active, 2026-10-27)
- [.harness root lookup](troubleshooting/harness-root-lookup.md): hook finds root by nearest `.harness/asks/`; change all definitions together (active, 2026-10-27)
- [Docs-only skip scope](troubleshooting/docs-only-asks-skip-the-suite.md): Stop hook skips the suite only for `docs/`/`.harness/`; wiki runs wiki-lint only (active, 2026-10-27)

## Troubleshooting: workers, panes and env
- [Respawn after hook change](troubleshooting/respawn-after-hook-change.md): new prompt/frontmatter hooks need `harness close` + respawn (active, 2026-10-23)
- [Spawn on a cold shell](troubleshooting/spawn-on-cold-shell.md): first ask after a reap exits 1 with the old report; v20 retries (active, 2026-10-28)
- [herdr names are global](troubleshooting/herdr-names-are-global.md): names are `<role>-<repo8>`, cwd check gives exit 6 (active, 2026-10-27)
- [Daemon inherits worker env](troubleshooting/daemon-inherits-worker-env.md): a Claude daemon started in a worker pane makes every hosted session a worker; gate now keys on agent_type (active, 2026-10-28)
- [AGENTS.md needs a CLAUDE.md import](troubleshooting/agents-md-ignored-when-claude-md-exists.md): CLAUDE.md must start with `@AGENTS.md`; no symlink (active, 2026-10-21)
- [Live gate edit](troubleshooting/live-gate-edit.md): a broken gate script denies everything; bash -n + suite before each save (active, 2026-10-28)
- [In-place edit breaks running scripts](troubleshooting/in-place-edit-breaks-running-scripts.md): bin/ is live; bodies are brace-wrapped, edit via new inode; lib/ is safe while sourced eagerly (active, 2026-10-28)

## Troubleshooting: conductor
- [Conductor shell: one command](troubleshooting/conductor-shell-one-command.md): exactly one simple command: no `;`, `&&`, `|`, redirects (active, 2026-10-21)

## Troubleshooting: shell portability and tests
- [GNU stat -f](troubleshooting/gnu-stat-f.md): use `-nt`/`-ot` or `stat -c %Y` first (active, 2026-10-21)
- [Whole-second timing](troubleshooting/whole-second-timing.md): `date +%s` grace N s is really (N-1,N] s; tests need ≥ 2 s (active, 2026-10-27)
- [bash signals and job control](troubleshooting/bash-signals-job-control.md): bg jobs ignore INT; `set -m` hands tty signals to children (active, 2026-10-27)
- [Tests inherit worker env](troubleshooting/tests-inherit-worker-env.md): suites run by a worker see `HARNESS_ROLE=worker`; unset it (active, 2026-10-27)
- [Test wait loops](troubleshooting/test-wait-loops.md): barrier on the asserted state; `grep -c` on a missing file breaks `-lt` (active, 2026-10-28)

## How-to
- [Transcript forensics](how-to/transcript-forensics.md): real Stop-hook time, did /clear run, known model noise (active, 2026-10-27)

## Decisions
- [0001 Keep herdr panes](decisions/0001-keep-herdr-panes-despite-subagent-model.md): subagent `model:` works; panes kept for visibility (active, 2026-10-23)
- [0002 Stop-hook completion](decisions/0002-completion-by-stop-hook-marker.md): marker ≥ report ≥ ask start (active, 2026-10-21)
- [0003 Pane lifecycle](decisions/0003-pane-lifecycle-defaults.md): 30 min idle TTL, close safety rules; implementer default replaced by 0006 (active, 2026-10-23)
- [0004 Failure-only retros](decisions/0004-failure-only-batched-retros.md): queue on failure, one batched analyst ask, reviewer FAIL never queues (active, 2026-10-21)
- [0005 Gate only inside herdr](decisions/0005-gate-only-inside-herdr.md): `HERDR_ENV`≠1 allows; unparseable input denies; global conductor kept; agent_type keys the gate (active, 2026-10-28)
- [0006 Keep implementer pane](decisions/0006-keep-implementer-pane.md): `close_after_ask.implementer` default `never`; idle TTL still reaps (active, 2026-10-27)
- [0007 Headless runner pilot](decisions/0007-headless-runner-pilot.md): `runner.<role>: headless` = `claude -p` in a viewer pane; completion = exit file (active, 2026-10-28)
- [0008 Worktree per ask](decisions/0008-worktree-per-ask.md): `ask --worktree` gives a headless analyst/reviewer its own detached checkout; ask-id addressing (active, 2026-10-23)
- [0009 Headless implementer](decisions/0009-headless-implementer.md): headless implementer: pinned permissions, exit 2 on denials, auto-resume after non-zero exit, 90 min cap (active, 2026-10-28)
