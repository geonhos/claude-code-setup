# 01 Dispatch flow

```mermaid
sequenceDiagram
  autonumber
  actor U as User
  participant R as route hook
  participant C as Conductor
  participant S as Skill
  participant H as harness ask
  participant D as herdr
  participant W as Worker pane
  participant V as Stop hook
  U->>C: prompt
  R-->>R: routing.jsonl (event=prompt)
  C->>S: /analyze · /implement · /review
  S->>S: write .harness/task-ROLE.md
  S->>H: harness ask ROLE 'Read task…' --via skill
  H->>H: spawn or reuse, maybe_reset (/clear)
  H->>H: asks/ROLE.current (ask_id)
  H->>D: herdr agent prompt NAME --wait
  D->>W: deliver prompt
  W->>W: work, write reports/ROLE.md
  W->>V: turn ends
  V->>V: (implementer) lint + test, block on fail
  V-->>H: done/ROLE.ASKID marker
  loop poll every 2 s
    H->>H: marker ≥ report mtime ≥ ask start?
  end
  H->>H: log/, progress.jsonl, progress.md, retro/, inbox
  H-->>C: stdout = report + exit code
  C-->>U: summary
```

## Files written along the way

| File | Writer | Reader |
|---|---|---|
| `.harness/routing.jsonl` | route hook (prompt), ask_finish (delegate) | `harness metrics` |
| `.harness/task-<role>.md` | skill (conductor) | worker, log copy |
| `.harness/asks/<role>.current` | ask_inner H:958 | completion check |
| `.harness/reports/<role>.md` | worker | harness → conductor |
| `reports/implementer.md.pending` | `harness-verify stop` (hidden while verifying) | restore / INTERRUPTED |
| `.harness/done/<role>.<ask-id>` | Stop hook V:239 | ask_complete H:1062 |
| `.harness/log/<stamp>-<role>.md` | record_progress H:378 | humans, retro |
| `.harness/progress.jsonl`, `progress.md` | record_progress, write_progress_md H:609 | metrics, maybe_reset, SessionStart |
| `.harness/retro/<ask-id>.json` | retro_on_ask H:485 (abnormal exit) | `harness retro` |
| `docs/wiki/inbox/*.md` | queue_learned H:681 (`## Learned`) | human review |
