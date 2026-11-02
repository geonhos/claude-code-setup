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
   `$ARGUMENTS` and the conversation. The implementer starts a fresh session
   (it resumes after a non-zero exit such as 5). Cover:
   - **Goal**: the exact behaviour wanted, and what must not change.
   - **Files or area** to touch; the spec or plan under `docs/` to follow.
   - **Tests**: which to add or update, and the command that must pass.
   - **Commit**: whether to commit, the exact message (ending with the
     attribution lines given in this conversation), and whether to push.
     Say "do not commit" when unsure.
   - **Report**: files touched, how it verified, the commit hash.
2. Run with the Bash tool's `run_in_background: true` **and** `timeout: 7200000` (the Bash tool's maximum; without it the call is killed at the tool's default timeout, long before the 60-90 min wait ends) (the task notification wakes you when the run ends):

   ```
   harness ask implementer 'Read .harness/task-implementer.md and do it.' --via skill
   ```

   Why: harness waits for the run to end by default (5400000 ms, the implementer's run cap; analyst/reviewer 3600000), so no `--timeout` is needed and no polling loop. After a restart or compaction use `harness wait implementer` (background, `timeout: 7200000`), then `harness report implementer`.

   Use `--keep` only for a follow-up that needs its previous conversation. A fresh session starts every ask, except that an implementer whose last ask exited non-zero resumes its session automatically (`--fresh` starts clean). Exit 2 means a tool call was denied and no report was written: re-ask with a changed brief.
3. Handle the exit code as conductor.md's "Exit codes from `harness ask`"
   section says. In particular `5` means its lint/test checks failed after
   retries: send the printed failure back with another `/implement` (its
   context is kept automatically after a 5). After 2 failed rounds, ask the
   user.
4. For anything beyond a trivial change, follow with `/review` before calling
   the work done.
5. Relay the substance of the report, not the report verbatim.
