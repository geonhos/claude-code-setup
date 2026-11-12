---
name: review
description: Conductor only. Delegate judging a diff (a commit range, a branch against main, or the working tree) to the reviewer worker and relay its findings and VERDICT. Use before calling a change done or opening a PR.
argument-hint: <commit range | branch | "working tree"> [focus]
---

# /review: delegate to the reviewer worker (opus)

If you are a worker session (HARNESS_ROLE=worker, or your system prompt names
you analyst, implementer, reviewer or solo), ignore this skill and review the
diff yourself (`harness ask` refuses to run in a worker session anyway).

## Steps

1. Write a self-contained brief to `.harness/task-reviewer.md` from
   `$ARGUMENTS` and the conversation. The reviewer has no memory by design.
   Cover:
   - **What to compare**: base and head (`main..HEAD`, `abc123..def456`) or
     "working tree vs HEAD". The reviewer runs
     `harness-verify run all --base <ref>` against it.
   - **Intent**: one paragraph on what the change should do, or the path of
     the spec/plan under `docs/`.
   - **Focus**, if any: correctness, tests, docs/code agreement, security.
   - **Constraints**: read-only: do not fix, do not commit.
   - **Report**: findings ordered by severity, each with `file:line` and why;
     the **last line must be `VERDICT: PASS` or `VERDICT: FAIL`**.
   - **Steps**: a `## Steps` numbered list, one line per step (the viewer dashboard shows it).
2. Run with the Bash tool's `run_in_background: true` **and** `timeout: 7200000` (the Bash tool's maximum; without it the call is killed at the tool's default timeout, long before the 60-90 min wait ends) (the task notification wakes you when the run ends):

   ```
   harness ask reviewer 'Read .harness/task-reviewer.md and do it.'
   ```

3. Exit codes: `0` = PASS. `5` = `VERDICT: FAIL`: hand the findings to
   `/implement`, then `/review` again; after 2 rounds, ask the user. `3` = no
   final VERDICT line, ask it to rewrite the report ending with one. Others
   as in conductor.md.
4. Relay findings and verdict. Anything the reviewer marks as a judgment call
   goes to the user.
