# Progress Log and Worker Context Reset — Design

Date: 2026-10-18
Status: approved (design)
Parent: `2026-10-12-herdr-conductor-setup-design.md`
Research: `.harness/analyst-progress-research.md` (local)

## Goal

1. Keep a durable record of every delegated task so the conductor can resume
   after `/clear` or a crash, and so a report is never lost by the next ask
   overwriting it.
2. Stop worker context from growing without bound across tasks: reset the
   implementer before each task, and reset analyst/reviewer when their
   context passes a threshold.

## Facts this design relies on (verified by analyst, docs cited there)

- `/clear` is near-instant, keeps the system-prompt/tools cache layer,
  re-reads `memory: project` MEMORY.md, and starts a new session id.
  `/compact` is slow and lossy. Respawn costs 3–6 s.
- `herdr agent prompt '/clear' --wait` stalls (the agent never enters
  `working`). Send without `--wait`, then poll `herdr agent get` until
  `agent_session.value` changes and status is idle.
- Context size = last assistant `usage` in the transcript
  `~/.claude/projects/<encoded cwd>/<session id>.jsonl`
  (input + cache_creation + cache_read). Reading it takes ~10 ms.
- Under `claude --agent`, the agent's `autoCompactWindow` is ignored; the env
  `CLAUDE_CODE_AUTO_COMPACT_WINDOW` on the pane works.
- Agent frontmatter supports only PreToolUse/PostToolUse/Stop hooks;
  SessionStart must be a settings-level hook.
- One item is NOT yet verified live and is plan task 1: after `/clear`, the
  `--agent` system prompt is still in effect and herdr returns to `idle`.

## Components

### 1. Per-ask log (`bin/harness ask`)

After every ask (any exit code), write:

- `.harness/log/<YYYYMMDD-HHMMSS>-<agent>.md`: the instruction (and the
  brief file contents if the instruction names `.harness/task-*.md`), then
  the report verbatim (or the screen tail when there is no report).
- One JSON line appended to `.harness/progress.jsonl`:
  `{ts, agent, session, instr, exit, verify, dur_s, head_before, head_after,
  ctx_before, ctx_after, status, summary}` where `instr` is the first 160
  chars, `verify` is pass|fail|skipped|interrupted|null, `status` is the
  report's `status:` line, `summary` is the report's title line.

Rotation, run at the end of each ask: keep the newest 200 log files and
delete logs older than 14 days; when `progress.jsonl` exceeds 1 MB, rename
it to `progress.jsonl.<ts>.gz` (gzip) and start a new file.

### 2. `.harness/progress.md` (regenerated after each ask)

≤ 60 lines, generated from `progress.jsonl` and the current state:

```
# Progress — <cwd basename> (<branch>)
Goal: <contents of .harness/goal.md if present, else "(unset)">
## Recent asks (newest first, max 15)
- <ts> <agent> exit <n> verify <v> <head_before>..<head_after> — <summary>
## Open questions (from the newest report that has any)
- ...
## Workers
- implementer idle ctx 12k · analyst idle ctx 137k · reviewer -
```

The conductor may write `.harness/goal.md` (one paragraph) at the start of
a piece of work; the gate already allows `.harness/` writes.

### 3. Conductor resume (settings-level SessionStart hook)

`claude/hooks/conductor-resume.sh`, installed by `install.sh` as a
`SessionStart` hook (matcher `startup|clear|compact`). It exits 0 silently
when `HARNESS_ROLE=worker` or `.harness/progress.md` is missing; otherwise
it prints the file as `hookSpecificOutput.additionalContext` prefixed with
one line: "Harness progress (resume from here; verify with harness status)".
Identified in settings.json by its command path, idempotent like the gate.

### 4. Worker context reset

- `harness ask implementer ...`: before `harness-verify baseline`, send
  `/clear` to a live implementer (`herdr agent prompt implementer '/clear'`,
  no `--wait`), then poll `herdr agent get` every 0.5 s for up to 10 s until
  the session id changes and the status is idle. If that fails, `harness
  close implementer` and respawn. A freshly spawned worker needs no clear.
- `harness ask analyst|reviewer ...`: read the worker's context tokens; if
  above `HARNESS_CTX_RESET` (default 120000, roughly 60 % of a 200k window)
  or the ask carries `--fresh`, do the same clear-or-respawn.
- `harness ask --keep` disables the clear for one ask (for a deliberate
  follow-up that needs the previous conversation).
- `harness spawn` adds `--env CLAUDE_CODE_AUTO_COMPACT_WINDOW=160000` to the
  pane so auto-compaction stays a late safety net.
- `harness status` gains a `ctx` column (tokens, `k` suffix; `-` when
  unknown) read from the transcript via the session id in `herdr agent get`.
  Transcript path: `~/.claude/projects/` + cwd with `/` and `.` replaced by
  `-` + `/<session id>.jsonl`; unreadable → `-`.

### 5. Prompt and docs

- `conductor.md`: mention `--fresh`/`--keep`, `.harness/goal.md`, and that
  `.harness/progress.md` arrives at session start.
- `implementer.md`: state that each task starts with a cleared context, so
  everything it needs is in the instruction, the brief, git and memory.
- README: new files under `.harness/`, rotation, env knobs.

## Non-goals

Worker crash recovery via `--resume` (follow-up; the session id is logged so
it is possible later). Never use `--continue`. Parallel workers/worktrees.

## Testing

- `tests/progress.test.sh` (bash 3.2, fake herdr): log file and jsonl line
  per ask for exit 0/2/3/5 paths; progress.md content and the 60-line cap;
  rotation (201 logs → 200, old files by mtime, jsonl > 1 MB → gz);
  `ctx` parsing from a sample transcript and `-` when missing; implementer
  clear path (fake herdr: session id changes → proceed; never changes →
  respawn); `--fresh`, `--keep`, threshold for analyst.
- `tests/install.test.sh`: SessionStart hook present exactly once after two
  runs; hook prints nothing for workers and additionalContext otherwise.
- Plan task 1 (live, in the user's herdr session, one temporary pane, closed
  afterwards): send `/clear` to a `claude --agent analyst` pane via
  `herdr agent prompt` without `--wait`; confirm the session id changes,
  herdr returns to idle, and a follow-up prompt still answers as the agent
  (its report template proves the system prompt survived). Record the
  result in `.harness/clear-probe.md` before building task 4.
