@AGENTS.md

## Claude Code
Shared project rules live in `AGENTS.md` (imported above). Claude-only notes:

- **Roles.** The default session is the conductor: it cannot read or edit
  source and delegates through `/analyze`, `/implement` and `/review` to
  analyst / implementer / reviewer workers in herdr panes, reading only their
  reports. Workers run with `HARNESS_ROLE=worker` and full tools.
- **Gate.** `conductor-gate` restricts the conductor's shell and file edits;
  `conductor-route` is a UserPromptSubmit hook that only logs each prompt
  (and its leading skill token) to `.harness/routing.jsonl`; it does not steer.
- **Completion.** A worker is done when its Stop hook writes the done marker
  (the implementer's hook first runs `harness-verify` lint/tests); herdr idle
  is only a fallback.
- **Wiki injection.** The SessionStart hook `conductor-resume` injects
  `.harness/progress.md` and the `(active,` lines of `docs/wiki/index.md` into
  the conductor. Workers and non-Claude agents get no injection: they must
  read `docs/wiki/index.md` themselves, as `AGENTS.md` says.
