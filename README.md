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
harness ask    <agent> '<instruction>' [--timeout MS]   # exit 2 blocked · 3 no report · 4 still working
harness report <agent>                                   # print existing report, or exit 3
harness status
harness close  <agent>
```

## What the conductor may do directly

`harness`, `gh` (except `gh api` and `gh pr diff`), read-only `herdr`
(`status`, `pane list|get|layout|current`, `agent list|get|wait|explain`,
`workspace list`, `tab list`), `jq` (as a pipe
consumer only), read-only `git` (`status`, `log`, `diff --stat`, `branch`,
`show --stat`; no patch, output or delete flags), bare `ls`, `cat`/`ls` under
`.harness/` and `docs/` (no quotes, globs or `$` in their arguments), and
writing Markdown under `docs/` and anything under `.harness/`. Everything else
is denied with a reason naming the worker to use.

## Known limits

The gate covers the built-in file/shell tools, `Monitor`, and the `filesystem`
MCP server. Other MCP servers that read files are not gated. `gh api`,
`gh pr diff`, `gh alias` and `gh extension` are denied, but a global flag
before the subcommand (`gh -R o/r api ...`) is not caught, and `gh pr
checkout` can switch the branch. Instructions to workers must use single
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
claude/hooks/conductor-gate.sh   PreToolUse gate
claude/agents/{analyst,implementer,reviewer}.md  worker definitions (model, memory, cacheTtl, report contract)
claude/agents/conductor.md       conductor system prompt (settings.agent)
claude/agents/solo.md            escape-hatch agent (empty body = default prompt)
install.sh                       installer (--test runs tests/)
tests/                           gate, harness (against tests/fake-herdr), install
docs/superpowers/                spec and plan
```
