---
name: watch
description: Conductor only. Print the command the user runs in another terminal tab to watch a worker live (redraw dashboard). Never runs `harness watch` itself.
argument-hint: <role> [issue#]
---

# /watch: tell the user how to watch a worker

If you are a worker session (HARNESS_ROLE=worker, or your system prompt names
you analyst, implementer, reviewer or solo), ignore this skill.

`harness watch` needs a human terminal and the conductor gate denies it for you, so
this skill only prints the command; never run it.

1. Take the role (`analyst`, `implementer` or `reviewer`) and an optional issue number from the arguments.
2. Find where the role runs:
   - an implementer in a work folder: `harness lane ls` (or `harness lane <issue#>`) shows the absolute folder path;
   - analyst, reviewer, or an implementer started with `--no-lane`: the primary folder.
3. Print the command for the user to run in another terminal tab:
   - primary folder: `harness watch <role>`
   - work folder: `harness -C <absolute work-folder path> watch <role>`
4. Add one line: it shows the brief, steps and tool calls of the live run and keeps the final frame until Ctrl-C; `harness watch <role> -n 40` prints the last 40 lines of a finished run instead.
