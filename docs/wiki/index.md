# Wiki index

Read this first. Open a page only when it is relevant. Schema and promotion rules: `CLAUDE.md` → Wiki.

## Gotchas
- [herdr idle is not done](gotchas/herdr-idle-is-not-done.md) — completion = Stop-hook marker, idle only a fallback (active, 2026-10-21)
- [Respawn after hook change](gotchas/respawn-after-hook-change.md) — new frontmatter hooks need `harness close` + respawn (active, 2026-10-21)
- [herdr names are global](gotchas/herdr-names-are-global.md) — names are `<role>-<repo8>`, cwd check → exit 6 (active, 2026-10-21)
- [ask --timeout is ms](gotchas/ask-timeout-is-milliseconds.md) — `--timeout 1200` = 1.2s (active, 2026-10-21)
- [GNU stat -f](gotchas/gnu-stat-f.md) — use `-nt`/`-ot` or `stat -c %Y` first (active, 2026-10-21)
- [Conductor shell: one command](gotchas/conductor-shell-one-command.md) — no `;`, `tail`, `echo`; pipe only to jq (active, 2026-10-21)
- [Deadline restore race](gotchas/deadline-restore-race.md) — false INTERRUPTED when ask hits the deadline mid-verify (active, 2026-10-21)

## Decisions
- [0001 Keep herdr panes](decisions/0001-keep-herdr-panes-despite-subagent-model.md) — subagent `model:` works; panes kept for visibility (active, 2026-10-21)
- [0002 Stop-hook completion](decisions/0002-completion-by-stop-hook-marker.md) — marker ≥ report ≥ ask start (active, 2026-10-21)
- [0003 Pane lifecycle](decisions/0003-pane-lifecycle-defaults.md) — implementer closes on success, 30 min idle TTL (active, 2026-10-21)
