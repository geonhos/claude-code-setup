# claude-code-setup — herdr conductor

A user-level Claude Code setup where the main session (Fable) is a
**conductor**: it reads only worker reports and delegates all analysis and
implementation to Claude workers running in [herdr](https://herdr.dev) panes.

Why: Fable tokens are expensive. The conductor never loads source into its
context, and workers (`analyst` opus · `implementer` sonnet · `reviewer`
opus) carry project memory so they stop re-discovering the codebase.

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
`~/.claude/agents/`, links `bin/harness` into `~/.local/bin`, merges one
PreToolUse hook and `promptCacheTtl`/`subagentPromptCacheTtl: 1h` into
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
harness ask    <agent> '<instruction>' [--timeout MS]   # exit 2 blocked · 3 no report · 4 still working · 5 verification failed
harness report <agent>                                   # print existing report (same exit codes as ask), 3 none, 4 still working
harness status
harness close  <agent>
```

## Verification loop

`.harness/` (reports, panes, verify state) lives in the directory where the
conductor runs; workers and hooks use that same directory (the hook `cwd`),
not the git toplevel.

The implementer does not judge its own work. `harness-verify` runs inside its
loop through hooks in `claude/agents/implementer.md`: a `PostToolUse` hook
formats each edited file and feeds back per-file lint errors, and a `Stop`
hook runs lint and tests over the changes and sends the worker back with the
failing output (up to `maxAttempts`, default 3; the report is hidden while
verifying and deleted on failure). `harness ask implementer` records a baseline first and exits **5**
(report plus a `verify: FAIL (<step>, <n> attempts)` line) when verification
gave up (`harness report` applies the same checks). The reviewer runs `harness-verify run all [--base <ref>]` (files changed versus
the merge base with `main`, plus uncommitted ones), smoke-checks the app if
configured, and ends its report with `VERDICT: PASS` or `VERDICT: FAIL`
(FAIL → exit 5; missing → exit 3).

Commands per project, first hit wins per key: `.harness/verify.local.json`,
`.claude/harness.json`, then auto-detect (Makefile, package.json, pyproject,
Cargo.toml, go.mod, `install.sh --test`):

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
claude/agents/{analyst,implementer,reviewer}.md  worker definitions (model, memory, cacheTtl, report contract)
claude/agents/conductor.md       conductor system prompt (settings.agent)
claude/agents/solo.md            escape-hatch agent (empty body = default prompt)
install.sh                       installer (--test runs tests/)
tests/                           gate, harness (against tests/fake-herdr), verify, install
docs/superpowers/                spec and plan
```
