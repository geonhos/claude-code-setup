# claude-code-setup — herdr conductor

A user-level Claude Code setup where the main session (Fable) is a
**conductor**: it reads only worker reports and delegates all analysis and
implementation to Claude workers running in [herdr](https://herdr.dev) panes.
Architecture diagrams: [docs/architecture.md](docs/architecture.md).

Why: Fable tokens are expensive. The conductor never loads source into its
context, and workers (`analyst` opus · `implementer` sonnet · `reviewer`
opus) — analyst and implementer carry project memory so they stop
re-discovering the codebase; the reviewer deliberately has none, so each
review starts without assumptions.

## Requirements

- macOS, `/bin/bash` 3.2 is enough
- `jq`, `herdr` ≥ 0.9, Claude Code ≥ 2.1.248
- `~/.local/bin` on `PATH`

## Install

```bash
git clone https://github.com/geonhos/claude-code-setup ~/workspace/claude-code-setup
cd ~/workspace/claude-code-setup
./install.sh
```

`install.sh` is idempotent. It symlinks `claude/agents/*.md` into
`~/.claude/agents/`, links `bin/harness` and `bin/harness-verify` into
`~/.local/bin`, merges one PreToolUse hook (the gate), one SessionStart hook
(`conductor-resume.sh`), `env.BASH_DEFAULT_TIMEOUT_MS`/`BASH_MAX_TIMEOUT_MS`
and `promptCacheTtl`/`subagentPromptCacheTtl: 1h` into
`~/.claude/settings.json` (backup kept), sets `agent: conductor` in
`~/.claude/settings.json` so every plain `claude` session starts as the
conductor (workers override it with `--agent <name>`), adds `.harness/` to
the global gitignore, and runs `herdr integration install claude`.

Run `./install.sh --test` to execute the test suites.

## Daily use

1. Open a herdr pane in your project and start `claude` as usual.
2. Give it work. When it tries to read or edit source, the gate denies the
   call and tells it which worker to use.
3. It runs `harness ask <worker> '<instruction>'`. A sibling pane opens with
   a Claude worker; when the worker finishes, its report
   (`.harness/reports/<worker>.md`, ≤ 40 lines) is printed back. The
   installer raises the Bash tool timeout (`BASH_DEFAULT_TIMEOUT_MS=600000`)
   so a long worker task does not get cut off.
4. You watch workers in their panes; the conductor only sees reports.

```
harness spawn  <agent> [--direction right|down]
harness ask    <agent> '<instruction>' [--timeout MS] [--fresh|--keep]   # exit 2 blocked · 3 no report · 4 still working · 5 verification failed
harness report <agent>                                   # print existing report (same exit codes as ask), 3 none, 4 still working
harness status
harness close  <agent>
```

## Progress log and context reset

Every `harness ask` (any exit code) writes `.harness/log/<ts>-<agent>.md`
(instruction, brief file contents, report or screen tail) and appends one JSON
line to `.harness/progress.jsonl` (ts, agent, session, instr, exit, verify,
dur_s, head_before/after, ctx_before/after, status, summary), then regenerates
`.harness/progress.md` (≤ 60 lines: goal, last 15 asks, open questions,
worker state). Write a one-paragraph `.harness/goal.md` to set the goal line.
Logging problems only warn on stderr; they never change an ask's result.

A `SessionStart` hook (`claude/hooks/conductor-resume.sh`, matcher
`startup|clear|compact`, installed by `install.sh`) injects `progress.md`
into the conductor's context; it stays silent for workers.

Rotation after each ask: newest 200 logs kept, logs older than 14 days
deleted, `progress.jsonl` over 1 MB rolled to `progress.jsonl.<ts>.gz`.
Knobs: `HARNESS_LOG_KEEP`, `HARNESS_LOG_DAYS`, `HARNESS_JSONL_MAX` (bytes).

Before an ask, a live worker's context is cleared with `/clear` (waits for a
new session id; if that does not happen within 10 s the pane is closed and
respawned): the implementer always, analyst/reviewer when their context
exceeds `HARNESS_CTX_RESET` tokens (default 120000) or with `--fresh`.
`--keep` skips the clear for one ask. Freshly spawned workers are never
cleared. Panes get `CLAUDE_CODE_AUTO_COMPACT_WINDOW=160000` as a late safety
net. `harness status` shows a `ctx` column (tokens read from the transcript
under `~/.claude/projects`, `-` when unknown; override the directory with
`HARNESS_PROJECTS_DIR`). Live probe: `/clear` keeps the `--agent` prompt and
settles in under a second.

## Verification loop

`.harness/` (reports, panes, verify state) lives in the directory where the
conductor runs; workers and hooks use that same directory (the hook `cwd`),
not the git toplevel.

The implementer does not judge its own work. `harness-verify` runs inside its
loop through hooks in `claude/agents/implementer.md`: a `PostToolUse` hook
formats each edited file and feeds back per-file lint errors, and a `Stop`
hook runs lint and tests over the changes and sends the worker back with the
failing output (up to `maxAttempts`, default 3; the report is hidden while
verifying and deleted on each failed attempt; at the cap it is kept). `harness ask implementer` (which needs `harness-verify` installed by
`./install.sh`, else exit 1) records a baseline first and exits **5**
(report plus a `verify: FAIL (<step>, <n> attempts)` line) when verification
gave up (`harness report` applies the same checks). The reviewer runs `harness-verify run all [--base <ref>]` (files changed versus
the merge base with `main`, plus uncommitted ones), smoke-checks the app if
configured, and ends its report with `VERDICT: PASS` or `VERDICT: FAIL`
(FAIL → exit 5; missing → exit 3).

Commands come only from explicit config, first hit wins per key:
`.harness/verify.local.json`, then `.claude/harness.json`. There is no
language or project-type detection; a missing key skips that step and no
config at all means `skipped` (the Stop hook allows). The conductor must run
in the directory that holds `.claude/harness.json` (the root is the cwd, not
the git toplevel). This repo uses `{"test": "./install.sh --test"}`.

```json
{ "format": "prettier --write {files}", "lint": "eslint {files}", "test": "npm test",
  "app": { "start": "npm run dev", "url": "http://localhost:3000" }, "maxAttempts": 3 }
```

`null` disables a step; `harness-verify detect` prints what was resolved.
It never blocks a worker when jq, git, or a config is missing.

## What the conductor may do directly

`harness`, `gh` (allowlist: `pr create|view|list|status|checks|comment|edit|merge`, `issue view|list|create|comment`, `run list|view` without `--log*`, `repo view`, `auth status`, `browse`; never `api`; `--body-file` only from `.harness/` or `docs/`; no `pr merge -d`, no `auth status --show-token`), read-only `herdr`
(`status`, `pane list|get|layout|current`, `agent list|get|wait|explain`,
`workspace list`, `tab list`), `jq` (as a pipe
consumer only), read-only `git` (`status`, `log`, `diff --stat`, `branch` (list-only), `show --stat`; no patch, output or delete flags), `ls` (never recursive), `cat`/`ls` under
`.harness/` and `docs/` (no quotes, globs or `$` in their arguments), and
writing Markdown under `docs/` and anything under `.harness/`. Everything else
is denied with a reason naming the worker to use.

## Known limits

The gate covers the built-in file/shell tools, `Monitor`, and the `filesystem`
MCP server. Other MCP servers that read files are not gated. File-tool
paths are checked again after symlink resolution. Without `jq` the gate
denies everything (fail closed) unless `HARNESS_ROLE=worker`. Instructions to workers must use single
quotes if they contain backticks or `$(`.

The conductor agent's body replaces Claude Code's default system prompt (that
is how `--agent` works), so the conductor relies on this file for its
operating guidance.

## Opt out

- Per project: `{ "agent": "solo", "env": { "HARNESS_ROLE": "worker" } }` in
  that project's `.claude/settings.json` (project settings override the
  user-level `agent`).
- One session: `HARNESS_ROLE=worker claude --agent solo`.

`HARNESS_ROLE=worker claude` alone only turns the gate off; the session still
runs the conductor agent.

## Layout

```
bin/harness                      herdr wrapper CLI
bin/harness-verify               format/lint/test checks used by worker hooks
claude/hooks/conductor-gate.sh   PreToolUse gate
claude/hooks/conductor-resume.sh SessionStart hook: injects .harness/progress.md
claude/agents/{analyst,implementer,reviewer}.md  worker definitions (model, memory, cacheTtl, report contract)
claude/agents/conductor.md       conductor system prompt (settings.agent)
claude/agents/solo.md            escape-hatch agent (empty body = default prompt)
install.sh                       installer (--test runs tests/)
tests/                           gate, harness (against tests/fake-herdr), verify, progress, install
docs/superpowers/                spec and plan
```
