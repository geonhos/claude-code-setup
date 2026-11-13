---
name: analyze
description: Conductor only. Delegate a read-only investigation (unknown code, design questions, plans, "what/why/where") to the analyst worker and relay its report. Use when the answer needs source code read but not changed.
argument-hint: <what to find out, and what decision it feeds>
---

# /analyze: delegate to the analyst worker (opus)

If you are a worker session (HARNESS_ROLE=worker, or your system prompt names
you analyst, implementer, reviewer or solo), ignore this skill and do the
investigation yourself (`harness ask` refuses to run in a worker session anyway).

## Steps

1. Write a self-contained brief to `.harness/task-analyst.md` from
   `$ARGUMENTS` and the conversation. The analyst has no other context. Cover:
   - **Goal**: the question to answer and the decision it feeds.
   - **Area**: files, directories or symbols to start from, if known.
   - **Constraints**: read-only: do not modify files, do not commit.
   - **Done criteria**: what the report must contain: file paths with line
     ranges, current behaviour, options with trade-offs when asked.
   - Long detail goes to `.harness/<topic>-detail.md`; the report summarises
     it and names the file.
   - **Steps**: a `## Steps` numbered list, one line per step (the viewer dashboard shows it).
2. Run with the Bash tool's `run_in_background: true` **and** `timeout: 7200000` (the Bash tool's maximum; without it the call is killed at the tool's default timeout, long before the 60-90 min wait ends) (the task notification wakes you when the run ends):

   ```
   harness ask analyst 'Read .harness/task-analyst.md and do it.'
   ```

   Every ask starts a fresh session; add `--keep` for a follow-up that needs the
   analyst's previous conversation. Keep the instruction in single quotes.
3. Handle the exit code as conductor.md's "Exit codes from `harness ask`"
   section says: 2 a tool call was denied, no report: re-ask with a changed brief; 3 no report:
   ask it to write the report; 4 still working: `harness wait analyst` (background, `timeout: 7200000`),
   then `harness report analyst`.
4. Relay the substance of the report, not the report verbatim. Read any
   `.harness/*-detail.md` it points at yourself (the gate allows `.harness/`).
