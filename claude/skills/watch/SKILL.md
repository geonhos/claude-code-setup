---
name: watch
description: Conductor only. Open the live dashboard of a worker in a new herdr/tmux pane or Terminal window via `harness open-watch`; print the command if that fails. Never runs `harness watch` itself.
argument-hint: <role> [issue#]
---

# /watch: open the worker dashboard

If you are a worker session (HARNESS_ROLE=worker, or your system prompt names
you analyst, implementer, reviewer or solo), ignore this skill.

`harness watch` needs a human terminal and the conductor gate denies it for you; run
`harness open-watch` instead, which launches it in a new pane or window. Only on /watch, never on ask.

1. Take the role (`analyst`, `implementer` or `reviewer`) and an optional issue number from the arguments.
2. Find where the role runs:
   - an implementer in a work folder: `harness lane ls` (or `harness lane <issue#>`) shows the absolute folder path;
   - analyst, reviewer, or an implementer started with `--no-lane`: the primary folder.
3. Run `harness open-watch <role>` (primary folder) or `harness -C <absolute work-folder path> open-watch <role>`. It tries herdr, tmux, then a macOS Terminal window, and prints one line saying where it opened.
4. Report that line. If the command fails or printed only a command ("no pane backend"), give the user the command to run in another tab: `harness [-C <absolute work-folder path>] watch <role>`.
5. Add one line: it shows the brief, steps and tool calls of the live run and keeps the final frame until Ctrl-C; `harness watch <role> -n 40` prints the last 40 lines of a finished run instead.
