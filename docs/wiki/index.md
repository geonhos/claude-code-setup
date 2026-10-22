# Wiki index

Read this first. Open a page only when it is relevant. Schema and promotion rules: `AGENTS.md` → Wiki.

## Gotchas
- [herdr idle is not done](gotchas/herdr-idle-is-not-done.md) — completion = Stop-hook marker, idle only a fallback (active, 2026-10-21)
- [Respawn after hook change](gotchas/respawn-after-hook-change.md) — new frontmatter hooks need `harness close` + respawn (active, 2026-10-21)
- [herdr names are global](gotchas/herdr-names-are-global.md) — names are `<role>-<repo8>`, cwd check → exit 6 (active, 2026-10-21)
- [ask --timeout is ms](gotchas/ask-timeout-is-milliseconds.md) — `--timeout 1200` = 1.2s (active, 2026-10-21)
- [GNU stat -f](gotchas/gnu-stat-f.md) — use `-nt`/`-ot` or `stat -c %Y` first (active, 2026-10-21)
- [Conductor shell: one command](gotchas/conductor-shell-one-command.md) — no `;`, `tail`, `echo`; pipe only to jq (active, 2026-10-21)
- [Deadline restore race](gotchas/deadline-restore-race.md) — false INTERRUPTED when ask hits the deadline mid-verify (active, 2026-10-21)
- [AGENTS.md needs a CLAUDE.md import](gotchas/agents-md-ignored-when-claude-md-exists.md) — CLAUDE.md must start with `@AGENTS.md`; no symlink (active, 2026-10-21)
- [Daemon inherits worker env](gotchas/daemon-inherits-worker-env.md) — a Claude daemon started in a worker pane makes every hosted session a worker, gate off (active, 2026-10-21)

## Decisions
- [0001 Keep herdr panes](decisions/0001-keep-herdr-panes-despite-subagent-model.md) — subagent `model:` works; panes kept for visibility (active, 2026-10-21)
- [0002 Stop-hook completion](decisions/0002-completion-by-stop-hook-marker.md) — marker ≥ report ≥ ask start (active, 2026-10-21)
- [0003 Pane lifecycle](decisions/0003-pane-lifecycle-defaults.md) — implementer closes on success, 30 min idle TTL (superseded by 0006, 2026-10-23)
- [0004 Failure-only retros](decisions/0004-failure-only-batched-retros.md) — queue on failure, one batched analyst ask, reviewer FAIL never queues (active, 2026-10-21)
- [0005 Gate only inside herdr](decisions/0005-gate-only-inside-herdr.md) — `HERDR_ENV`≠1 → allow; unparseable input → deny; global conductor kept (active, 2026-10-21)
- [0006 Keep implementer pane](decisions/0006-keep-implementer-pane.md) — `close_after_ask.implementer` default `never`; idle TTL still reaps (active, 2026-10-23)
