# herdr Conductor Setup — Design

Date: 2026-10-12
Status: approved (design), pending implementation plan

## Goal

Make the Fable main session a pure conductor. It receives work, decides which
kind of worker the work needs, delegates through herdr, and reads only short
worker reports. Two requirements drive every decision:

1. Save Fable tokens. Fable must not read or analyze source itself.
2. Optimize herdr use. Fable gives instructions; the work itself always runs
   in a subagent that Fable creates (or reuses) through herdr.

Skills: none of our own. The user's installed `superpowers` plugin is the
only skill set. This repo ships configuration, one hook, one CLI, and three
agent definitions.

## Non-goals

- No plugin, no marketplace, no `/ship`, `/plan`, `/retro`, learning loop.
  The v6 plugin content is deleted (git history keeps it).
- No worker worktree isolation in this iteration. `harness spawn --worktree`
  is a documented follow-up.
- No automatic quality gates from reports (review Critical = 0 etc.).
  The conductor reads the report and decides.

## Where it lives

User level, not project level. Fable must be gated in every project the user
opens (budget-book and others), and `superpowers` already lives at user
level. `install.sh` wires this repo into `~/.claude`.

```
claude-code-setup/
├── install.sh                   # symlinks + settings.json merge (jq) + herdr integration install claude
├── bin/harness                  # herdr wrapper CLI: spawn / ask / status / close
├── claude/
│   ├── hooks/conductor-gate.sh  # PreToolUse gate
│   └── agents/
│       ├── conductor.md         # conductor system prompt, selected by settings.agent
│       ├── solo.md              # escape hatch: empty body = default system prompt, all tools
│       ├── analyst.md           # opus   · analysis / planning · memory: project
│       ├── implementer.md       # sonnet · implementation + tests · memory: project
│       └── reviewer.md          # opus   · diff review
├── tests/gate.test.sh           # hook allow/deny tests with sample stdin JSON (bash 3.2)
└── README.md
```

`install.sh` does, idempotently:

- `ln -sf` each `claude/agents/*.md` into `~/.claude/agents/`.
- `ln -sf bin/harness` into a `PATH` dir (`~/.local/bin`; warns if it is not on
  PATH).
- Merge into `~/.claude/settings.json` with `jq` (backup first):
  - `hooks.PreToolUse` entry → `conductor-gate.sh` (matcher
    `Edit|Write|NotebookEdit|Read|Grep|Glob|Bash|Agent|Workflow|Monitor|mcp__filesystem__.*`).
  - `promptCacheTtl: "1h"`, `subagentPromptCacheTtl: "1h"`.
  - Merge `env.BASH_DEFAULT_TIMEOUT_MS=600000` and `env.BASH_MAX_TIMEOUT_MS=1800000`
    so `harness ask` is not killed by the Bash tool's 2-minute default.
  Existing keys and other hooks are preserved. The hook entry is identified
  by its command path so re-running does not duplicate it.
- Merge `agent: "conductor"` into settings so plain `claude` sessions start as
  the conductor; `claude --agent <worker>` (used by `harness spawn`) overrides
  it.
- Run `herdr integration install claude` so herdr reads Claude Code lifecycle
  state (idle / working / blocked / done) from a hook instead of heuristics.
- Add `.harness/` to `~/.config/git/ignore` (global gitignore) if absent.

## Roles

`HARNESS_ROLE` environment variable:

| value | meaning |
|-------|---------|
| unset or `conductor` | Fable conductor. Gate active. |
| `worker` | herdr worker. Gate passes everything. |

Default is conductor so forgetting to set anything still enforces. Workers
always get `worker` because `harness spawn` passes `--env HARNESS_ROLE=worker` to `herdr pane split`. A human who wants a plain manual session
runs `HARNESS_ROLE=worker claude --agent solo`: gate off, and `solo.md` has an
empty body, so Claude Code keeps its default system prompt and all tools.
`HARNESS_ROLE=worker claude` alone only turns the gate off; the session still
runs the conductor agent (settings.agent applies).

Per-project opt-out: a project that should not be gated selects `solo` and
sets the variable in its own settings (project settings override the
user-level `agent`; the hook sees the variable like any other environment
value):

```json
{ "agent": "solo", "env": { "HARNESS_ROLE": "worker" } }
```

The conductor must run inside a herdr pane. Outside herdr the gate is still
active but `harness` refuses to run, so Fable can do nothing but talk.

## Requirement 1 — Fable token economy

Token cost is driven by what enters Fable's context, so the design works in
two layers: restrict input, then keep the cache warm.

**Restrict input (the gate).** Fable cannot read source. It reads worker
reports only. Every report follows a fixed template capped at 40 lines, so
context growth per delegated task is bounded and predictable.

**Prompt cache.**

- On a subscription plan the main conversation already has a 1h TTL. The
  settings still set `promptCacheTtl: "1h"` and `subagentPromptCacheTtl: "1h"`
  so behaviour does not change if the account moves to API billing.
- `agents/conductor.md` contains only static text. Nothing in it changes
  during a session, so the system-prompt prefix stays cache-stable.
- The gate's deny reasons are fixed strings per rule (no timestamps, no
  paths echoed back) for the same reason.

**Worker-side reuse.**

- `analyst` and `implementer` declare `memory: project`. Claude Code stores
  their memory in `.claude/agent-memory/<name>/` in the target project and
  injects `MEMORY.md` (first 200 lines) into each run. Codebase structure
  learned once is not re-derived per task. This directory may be committed
  in the target project.
- All three agents declare `experimental.cacheTtl: 1h`. It is ignored while
  on subscription credits and takes effect under API billing.
- `harness ask <agent>` reuses a live worker of that name instead of
  spawning a new one. A long-lived worker keeps its own conversation cache
  warm across tasks.

## Requirement 2 — herdr optimization and forced delegation

### The gate (`claude/hooks/conductor-gate.sh`)

PreToolUse hook. Reads stdin JSON (`tool_name`, `tool_input`). If
`HARNESS_ROLE=worker`, exit 0 immediately. Otherwise apply the table.
Decisions use the current JSON contract:

```json
{"hookSpecificOutput":{"hookEventName":"PreToolUse",
  "permissionDecision":"deny","permissionDecisionReason":"..."}}
```

| Tool | Conductor rule |
|------|----------------|
| `Edit`, `Write`, `NotebookEdit` | allow if `file_path` is under `docs/` and ends in `.md`, or is under `.harness/`. Else deny. |
| `Read`, `Grep`, `Glob` | allow if path is under `.harness/`, under `docs/`, or ends in `.md`. Else deny. (`Grep`/`Glob` use `path`; missing path = deny, except `Glob` whose `pattern` starts with `docs/` or `.harness/`.) |
| `Agent`, `Workflow` | deny. |
| `Bash` | allow if the command matches one of: `harness ...`, read-only `herdr` (status, pane list|get|layout, agent list|get|wait), `gh ...` (allowlist: pr create/view/list/status/checks/comment/edit/merge, issue view/list/create/comment, run list/view without `--log*`, repo view, auth status, browse; never `api`), `git status`, `git log ...`, `git diff --stat ...`, `git branch` (list-only), `git show --stat ...`, `cat .harness/...`, `ls .harness...`, `ls docs...` (never `-R`). File-tool paths are re-checked after symlink resolution; without `jq` the gate denies (fail closed). See `2026-10-18-gate-hardening-design.md`. Compound commands (`;`, `&&`, `\|`, `>`) are allowed only if every segment matches. Else deny. `jq` only as a non-first pipeline segment with no file arguments; `cat`/`ls` arguments may not contain quotes, `$`, braces, globs, `~` or `..`; git may not use patch/output/delete/move/copy/unified/raw/check options; unquoted `#` is denied. |
| `Monitor`, `mcp__filesystem__*` | `Monitor` deny; filesystem MCP read tools follow the Read rule, write tools the Write rule. |
| anything else | allow (MCP tools, Skill, TodoWrite, AskUserQuestion, etc.) |

Path checks are prefix checks after normalising to repo-relative form (strip
`cwd`). Absolute paths outside `cwd` are denied for the file tools.

Deny reasons are the forcing mechanism. Each names the next action:

- Edit/Write on source → "Conductor cannot edit source. Delegate:
  `harness ask implementer '<instruction>'`."
- Read/Grep/Glob on source → "Conductor does not read source. Delegate:
  `harness ask analyst '<question>'` and read its report."
- Agent/Workflow → "Native subagents inherit the Fable model. Use
  `harness ask <analyst|implementer|reviewer> '...'` instead."
- Bash → "Conductor shell is limited to harness/herdr/gh/read-only git.
  Delegate command execution to a worker."

Hook exit code is always 0 with JSON on stdout (never exit 2), so a hook
bug cannot silently block everything; a parse failure falls through to
allow and logs one line to stderr.

### `harness` CLI (`bin/harness`)

Bash, bash-3.2 compatible (no `declare -A`; see memory note). Requires
`jq` and `herdr`. Refuses to run unless `HERDR_ENV=1` (herdr skill rule).

```
harness spawn  <agent> [--direction right|down]
harness ask    <agent> '<instruction>' [--timeout MS]
harness report <agent>
harness status
harness close  <agent>
```

- `spawn`: if a live agent named `<agent>` exists, print its pane id and
  exit 0. Otherwise read `herdr pane layout --pane "$HERDR_PANE_ID"`; wide
  pane → `--direction right`, else `down` (user flag overrides). Then:
  1. `herdr pane split --current --direction <d> --cwd "$PWD" --env HARNESS_ROLE=worker --no-focus`
     → new pane id from `.result.pane.pane_id`. `--env` sets the variable on
     the pane shell, so Claude started there inherits it.
  2. Record `<agent> <pane>` in `.harness/panes`.
  3. `herdr agent start <agent> --kind claude --pane <id> -- --agent <agent>`.
  4. On failure, print the pane screen (60 lines), close the pane, unregister it, and exit 1.
- `ask`: refuses with exit 4 when the worker is already `working`. `spawn` if needed. Remove any stale `.harness/reports/<agent>.md`.
  Submit `herdr agent prompt <agent> "<instruction>" --wait --timeout <MS>`
  (default 600000). On settled state:
  - `idle`/`done`: if the report file exists, `cat` it to stdout and exit 0.
    If not, print the last 60 lines of `herdr agent read` with a warning
    and exit 3.
  - `blocked`: print the last 60 lines of `herdr agent read` and exit 2 so
    the conductor can ask the user what to answer.
  - `agent_prompt_stalled` / `timeout`: print `agent get` + 60 lines of
    output and exit 4. Do not resubmit.
- `report <agent>`: prints the existing report or exits 3.
- `status`: `herdr agent list` filtered to the three agent names, one line
  each with state and pane.
- `close <agent>`: `herdr pane close` on the pane hosting that agent.
  Only closes panes `harness` created (recorded in `.harness/panes`).

The conductor's Bash allowlist admits `harness ...`, so Fable can call all
four.

### Worker agents (`claude/agents/*.md`)

Frontmatter common to all three:

```yaml
name: <analyst|implementer|reviewer>
description: ...
model: <opus|sonnet|opus>
experimental:
  cacheTtl: 1h
```

`analyst` and `implementer` add `memory: project`. `reviewer` does not
(review should not carry assumptions across diffs).

Body (system prompt) common contract:

- You are a herdr worker. `HARNESS_ROLE=worker`. You have full tool access.
- When your task is complete, write `.harness/reports/<your-name>.md` using
  this exact template, then reply with exactly one line `REPORT: <path>`:

```markdown
# <agent> report — <one-line task summary>
status: done | partial | blocked
## Changed files
- path — one line why          (omit section for analyst)
## Findings / Decisions
- ≤ 8 bullets, one line each
## Verification
- command run → result         (tests, lint, manual check)
## Open questions
- ≤ 3 bullets, or "none"
```

- Keep the report under 40 lines. Put long detail in a separate file under
  `.harness/` and link it.
- Never ask the conductor to read source. Answer the question in the report.

Per-agent additions:

- `analyst`: explore, explain, propose approaches, write plans. Writes plans
  to `docs/superpowers/plans/` when asked. Does not edit source.
- `implementer`: implement the instruction, run the relevant tests and
  lint, commit only when the instruction says to.
- `reviewer`: review `git diff <base>...HEAD` (base given in the
  instruction, default `main`). Report findings with severity
  Critical/Major/Minor and file:line. Does not fix.

### Conductor agent (`claude/agents/conductor.md`)

Short, static. The body replaces the default system prompt, so it also
carries basic operating guidance. Core rules:

1. You are the conductor. You do not read or edit source. The gate will
   deny it; the deny reason tells you which worker to use.
2. Classify each request: unknown code or design question → `analyst`;
   change to make → `implementer`; verify a change → `reviewer`.
3. Delegate with `harness ask <agent> '<instruction>'`. Write the
   instruction so the worker needs nothing else: goal, files or area,
   constraints, done criteria.
4. Read only the report. Decide: done, iterate (new `harness ask`), or ask
   the user.
5. `superpowers` flows stay. Where a skill says to dispatch with the
   `Agent` tool, use `harness ask implementer` instead. Where a skill says
   to read code, use `harness ask analyst`.
6. Exit codes: 2 = worker blocked, show the user the output and ask; 3 = no
   report, re-prompt the worker to write it; 4 = stalled or timeout, check
   `harness status` before anything else.

### Hook contract notes

- The gate is a user-level hook, so it also fires inside workers. That is
  why role detection is the first line of the script.
- Plugin and settings hooks compose; `superpowers` hooks are untouched.

## Error handling summary

| Situation | Behaviour |
|-----------|-----------|
| Not inside herdr (`HERDR_ENV` unset) | `harness` prints "run Claude inside a herdr pane" and exits 1. Gate still active. |
| Worker blocked on a permission prompt | `ask` exits 2 with the screen text; conductor asks the user. |
| Worker finished without a report | `ask` exits 3 with the last 60 lines; conductor re-prompts "write the report". |
| Hook input unparseable | allow + one stderr line. |
| `jq` or `herdr` missing | `install.sh` fails early with the missing tool named. |

## Testing

- `tests/gate.test.sh`: feeds sample PreToolUse JSON through the gate for
  each table row (allow and deny cases, both roles, compound Bash). Runs on
  macOS `/bin/bash` 3.2. Run by `install.sh --test` and by hand.
- `harness`: manual round trip inside a herdr pane in this repo:
  `harness ask analyst "List the top-level files and what each is for."`
  must return a report and exit 0. Also confirm `memory: project` is
  honoured when the worker is started via `--agent` (the docs do not state
  this for main sessions); if not, fall back to a `memory:` line in the
  agent body pointing at the same directory.
- `install.sh` run twice must leave `~/.claude/settings.json` with exactly
  one gate hook entry.

## Follow-ups (not in this spec)

- `harness spawn --worktree` using `herdr worktree` helpers.
- Report-driven gates (block "done" when reviewer reports Critical > 0).
- Optional `effort:` tuning for the conductor via `claude --agent`.
