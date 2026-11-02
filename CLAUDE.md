@AGENTS.md

## Claude Code
Shared project rules live in `AGENTS.md` (imported above). Claude-only notes:

- **Roles.** The default session is the conductor: it cannot read or edit
  source and delegates through `/analyze`, `/implement` and `/review` to
  analyst / implementer / reviewer workers (detached headless Claude sessions,
  `claude -p`; a herdr pane is an optional viewer), reading only their
  reports. Workers run with `HARNESS_ROLE=worker` and full tools.
- **Gate.** `conductor-gate` restricts the conductor's shell and file edits.
- **Completion.** A headless worker is done when its process exits
  (`.harness/asks/<role>.exit.json`); the implementer's Stop hook first runs
  `harness-verify` lint/tests.
- **Wiki injection.** The SessionStart hook `conductor-resume` injects
  `.harness/progress.md` and the `(active,` lines of `docs/wiki/index.md` into
  the conductor. Workers and non-Claude agents get no injection: they must
  read `docs/wiki/index.md` themselves, as `AGENTS.md` says.
