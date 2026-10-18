# Verification Loop — Design

Date: 2026-10-18
Status: approved (design)
Parent: `2026-10-12-herdr-conductor-setup-design.md` (lifts its non-goal
"no automatic quality gates" and follow-up "report-driven gates")
Research: `.harness/analyst-verify-research.md` (local; findings summarised here)

## Goal

Stop the implementer from judging its own work as done. Add computational
checks (format, lint, test) inside the implementer's loop, make the reviewer
run the code and give a machine-readable verdict, and surface failures to the
conductor through a distinct `harness ask` exit code.

## Facts this design relies on (verified by analyst)

- Agent frontmatter `hooks:` (PreToolUse/PostToolUse/Stop) fires when the
  agent runs as the main session via `claude --agent <name>`. Hook stdin has
  `agent_type` = the agent name.
- Stop hook blocks with stdout `{"decision":"block","reason":"..."}`; the
  continuation carries `stop_hook_active: true`. Claude Code caps consecutive
  continuations at 8 (reset by any tool call), so we keep our own counter.
- PostToolUse can return `{"decision":"block","reason":"..."}` and/or
  `hookSpecificOutput.additionalContext`; both reach the model. The edit is
  not undone.
- `herdr integration install claude` installs only a SessionStart hook;
  herdr's state is screen-scraped and `prompt --wait` does not track turns. A
  blocking Stop continues the same turn, but an idle flicker could settle
  early, so the Stop hook deletes the report before blocking.

## Components

### 1. `bin/harness-verify` (bash 3.2, installed to `~/.local/bin`)

```
harness-verify detect                 # print resolved commands as JSON
harness-verify format <file>          # PostToolUse entry (reads hook stdin if no arg)
harness-verify stop                   # Stop entry (reads hook stdin)
harness-verify run [lint|test|all]    # manual / reviewer; exit 0 pass, 1 fail
harness-verify baseline               # record start state (called by harness ask)
```

**Config resolution** (first hit wins, per key):

1. `.harness/verify.local.json` (personal, gitignored via `.harness/`)
2. `.claude/harness.json` (project, committed)
3. Auto-detect, in order: `Makefile` targets (`fmt|format`, `lint`, `test`)
   → `package.json` scripts (`format`, `lint`, `test`; runner from lockfile:
   pnpm/yarn/bun/npm) → `pyproject.toml` (ruff format / ruff check / pytest
   when configured) → `Cargo.toml` (cargo fmt / clippy / test) → `go.mod`
   (gofmt -w / go vet ./... / go test ./...) → executable `install.sh` that
   supports `--test` (test only).
4. Nothing found → that step is skipped; `stop` allows and records
   `"status":"skipped"`.

Schema:

```json
{
  "format": "prettier --write {files}",
  "lint":   "eslint {files}",
  "test":   "npm test",
  "app":    { "start": "npm run dev", "url": "http://localhost:3000" },
  "maxAttempts": 3
}
```

`{files}` expands to the shell-quoted changed files (format: the one edited
file; lint in `stop`: files changed since baseline). A command without
`{files}` runs as-is. `null` disables a step. `maxAttempts` default 3.

**State** under `.harness/verify/`:

- `<agent>.base` — HEAD sha + hash of `git status --porcelain` + `git diff`
  at ask start (written by `harness-verify baseline`, called from
  `harness ask` for implementer before prompting).
- `<agent>.attempts` — integer, reset by `baseline`.
- `<agent>.json` — last result: `{"status":"pass|fail|skipped","attempts":n,"step":"lint|test","tail":"<last 40 lines>"}`.

### 2. implementer hooks (frontmatter in `claude/agents/implementer.md`)

- `PostToolUse`, matcher `Edit|Write|MultiEdit` → `harness-verify format`.
  The script also checks `tool_name` itself (the analyst saw one matcher
  miss). Runs `format` on the file if configured; then file-scoped `lint` if
  the lint command uses `{files}`. Lint failure → `decision: block` with the
  first 40 lines. Missing config / non-repo file → exit 0 silently.
- `Stop` → `harness-verify stop`:
  1. If current state equals `.base` (nothing changed) → allow, status
     `skipped`.
  2. Run `lint` then `test`. Pass → write `pass`, allow.
  3. Fail and attempts < maxAttempts → increment attempts, delete
     `.harness/reports/implementer.md`, write `fail`, emit block with reason:
     step name, last 40 lines, and "fix and finish again; then rewrite the
     report".
  4. Fail and attempts ≥ maxAttempts → write `fail`, allow stop. The
     implementer prompt says: when verification gave up, report `status:
     partial` and include the failure.
  - Hook timeout: 600 s (default). A slower suite should be configured to a
    faster subset in `.claude/harness.json`.

### 3. reviewer (`claude/agents/reviewer.md`)

- Review `git diff <base>` against the working tree (includes uncommitted),
  not only `base...HEAD`.
- Run `harness-verify run all`. If `app` is configured, start it, wait for
  `url` to respond, do a smoke check (curl or Playwright if available), and
  stop it.
- Report's last line must be exactly `VERDICT: PASS` or `VERDICT: FAIL`.
  FAIL if any Critical/Major finding or verification failed.

### 4. `bin/harness ask`

- For `implementer`: call `harness-verify baseline` before prompting.
- After the report is collected (exit 0 path):
  - implementer: if `.harness/verify/implementer.json` has `status: fail`,
    print the report plus a `verify: FAIL (<step>, <n> attempts)` line and
    exit **5**.
  - reviewer: if the report's last non-empty line is `VERDICT: FAIL`, exit
    **5**. Missing VERDICT line → exit 3 (treated as no valid report).
- Other exit codes unchanged.

### 5. `claude/agents/conductor.md`

Add exit code 5: "verification failed (implementer gave up, or reviewer
FAIL). Send the failure/finding to implementer; after 2 rounds still
failing, ask the user."

### 6. `install.sh`

Symlink `bin/harness-verify` next to `bin/harness`. No settings.json change
(hooks live in agent frontmatter).

## Error handling

| Situation | Behaviour |
|-----------|-----------|
| No config, nothing detected | skip, status `skipped`, never block |
| `jq` missing in `harness-verify` | exit 0 with one stderr line (never block the worker) |
| Not a git repo | format only; stop skips |
| Stop hook timeout | Claude Code treats as non-blocking; result stays as last written |
| `stop_hook_active` loops | bounded by our `attempts` counter |

## Testing

- `tests/verify.test.sh` (bash 3.2, temp git repos): detection for each
  project type and precedence (local > project > detect); `{files}`
  expansion with spaces in names; `format` hook JSON on lint failure; `stop`:
  unchanged → skipped/allow, pass → allow, fail → block JSON + report
  deleted + attempts++, cap → allow + fail recorded; `baseline` resets.
- `tests/harness.test.sh` (fake herdr): implementer with verify fail →
  exit 5 and `verify: FAIL` line; reviewer `VERDICT: FAIL` → 5,
  `VERDICT: PASS` → 0, missing → 3; baseline called before prompt.
- `install.sh --test` runs the new suite; install test asserts the
  `harness-verify` symlink.
- Manual live check (one time, in a herdr pane): an implementer task that
  breaks a test → worker keeps fixing inside the same ask; `harness ask`
  does not settle early.

## Non-goals

CI, parallel workers/worktrees, progress log and context reset (#4),
gate changes.
