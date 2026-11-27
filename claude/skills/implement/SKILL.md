---
name: implement
description: Conductor only. Delegate a change (code, tests, config, hooks, scripts, commits, pushes, anything outside docs/**/*.md and .harness/) to the implementer worker and relay its report. Use whenever a file the conductor cannot write must change.
argument-hint: <what to change; the commit message if it should commit>
---

# /implement: delegate to the implementer worker (sonnet)

If you are a worker session (HARNESS_ROLE=worker, or your system prompt names
you analyst, implementer, reviewer or solo), ignore this skill and make the
change yourself (`harness ask` refuses to run in a worker session anyway).

## Steps

1. Write a self-contained brief to `.harness/task-implementer.md` from
   `$ARGUMENTS` and the conversation. The implementer starts a fresh session. Cover:
   - **Goal**: the exact behaviour wanted, and what must not change.
   - **Files or area** to touch; the spec or plan under `docs/` to follow.
   - **Tests**: which to add or update, and the command that must pass.
   - **Commit**: whether to commit, the exact message (no Co-Authored-By or
     other attribution line), and whether to push.
     Say "do not commit" when unsure.
   - **Report**: files touched, how it verified, the commit hash.
   - **Steps**: a `## Steps` numbered list, one line per step (the viewer dashboard shows it).
2. Work folder: `harness lane <issue#>` (once per issue; it prints the absolute folder path), then pass
   `-C <that path>` to every harness call below (`harness -C <path> ask implementer ...`, `wait`, `report`).
   The brief goes to `<path>/.harness/task-implementer.md`. Run independent tasks in parallel, one folder each.
   Run it as conductor.md's Loop step 2 says (Bash `run_in_background: true` and `timeout: 7200000`; the task notification wakes you):

   ```
   harness -C <path> ask implementer 'Read .harness/task-implementer.md and do it.'
   ```

   The default wait is the implementer run cap (5400000 ms; analyst/reviewer 3600000). After a restart or compaction use `harness -C <path> wait implementer`, then `harness report implementer`. Use `--keep` only for a follow-up that needs its previous conversation.
3. Handle the exit code as conductor.md's "Exit codes from `harness ask`"
   section says. In particular `5` means its lint/test checks failed after
   retries: send the printed failure back with another `/implement`. After a 5
   a new ask starts a fresh session; add `--keep` when the fix needs the
   implementer's previous conversation. After 2 failed rounds, ask the user.
4. Big task (as conductor.md defines it): follow with `/review` before the PR.
   Small task: open the PR after the implementer's lint/test pass.
5. Relay the substance of the report, not the report verbatim.
