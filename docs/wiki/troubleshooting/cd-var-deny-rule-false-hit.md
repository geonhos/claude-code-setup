---
type: troubleshooting
status: active
updated: 2026-11-23
sources: ["#203", session 2cc6a9e8, claude/agents/reviewer.md:33]
verified_by: headless probe (5 haiku runs, 2026-11-23)
---
# `cd "$VAR" && cmd file` denied citing `~/.ssh/**`

**Symptom.** `harness: note: 1 denied tool call(s)`: `grep reads 'AGENTS.md' after a cd whose target cannot be resolved, and a deny rule (~/.ssh/**) names that file under a directory it may run in`.

**Cause.** Claude Code (2.1.330), not a hook. After a `cd` whose target it cannot resolve (`$VAR`, `$(...)`, glob), it tests each relative path a later subcommand reads as if the cwd were under each Read deny rule's root; `Read(~/.ssh/**)` and `Read(~/.aws/**)` from `harness init` match any name. Not every `cd "$VAR"` triggers it; a worktree add + redirect + cd did.

**Fix.** Address the other tree by absolute path (`grep x "$W/AGENTS.md"`) or `git -C "$W" ...`; do not narrow the deny rules (decision 0014). The reviewer prompt says so (claude/agents/reviewer.md:33).

**Evidence.** Reviewer of PR #202, 2026-11-20 (session 2cc6a9e8): the original form was denied; in a probe with only `Read(~/.ssh/**)` denied, absolute-path and `git -C` forms were allowed every time. One occurrence so far.
