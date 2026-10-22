# claude-code-setup

A conductor/worker harness for Claude Code. The conductor session cannot read or
edit source; it delegates through `harness ask` to analyst / implementer /
reviewer workers running in herdr panes, and reads only their reports. Hooks
gate the conductor's shell, verify worker output and resume from progress logs.
`install.sh` symlinks everything into `~/.claude` and `~/bin`.

## Layout
- `bin/` — `harness` (CLI: ask, spawn, report, close, status, retro, metrics) and `harness-verify`
- `claude/agents/` — conductor, analyst, implementer, reviewer, solo prompts
- `claude/hooks/` — conductor-gate, conductor-route, conductor-resume (SessionStart)
- `claude/skills/` — /analyze, /implement, /review (conductor-only)
- `tests/` — `*.test.sh` suites plus `fake-herdr`
- `docs/` — `wiki/` (durable knowledge), `superpowers/plans/`, `research/`

## Test
`./install.sh --test` runs every suite, in parallel (`HARNESS_TEST_SERIAL=1` runs them one
at a time; `HARNESS_TESTS_DIR` points it at another suite directory). All must pass before a commit; workers run only the affected suites while
iterating and the implementer Stop hook runs the full set.

## Shell rule
Scripts must run on macOS default bash 3.2: no `declare -A`, no `mapfile`, no
`${var^^}`. Use awk for maps. BSD vs GNU `stat`/`date`: see the wiki gotchas.

## Wiki
Lives in `docs/wiki/`. **Read `docs/wiki/index.md` before working; open a page
only when it is relevant to the task.**

- `gotchas/*.md` symptom → cause → fix → evidence, one trap per page
- `decisions/NNNN-*.md` ADRs: context / decision / status / consequences
- `log.md` append-only, one line per change; `inbox/` unreviewed lessons
  (from a report's `## Learned`), never listed in the index

Page frontmatter (required except in inbox):
```
type: gotcha|decision|runbook|playbook
status: draft|active|stale|superseded
updated: YYYY-MM-DD
sources: [ask-id | commit | file:line | url]
verified_by: <test name | command | human>
```
Every page needs one index line: `- [title](path) — hook (status, updated)`.
Limits: index ≤80 lines, pages ≤150. `harness wiki-lint` checks this in the tests.

**Do not record what can be derived from code** (structure, signatures, git
history). Record traps, reasons and decisions that the code does not show.
A report's `## Learned` bullets (≤2) must each cite evidence (ask-id, commit,
file:line or log).

### Promotion ladder
1. `docs/wiki/inbox/` — unreviewed lesson with evidence
2. wiki page — after review
3. `AGENTS.md` (cross-agent rules) or, for Claude-specific ones, `.claude/rules/`
   or one line in an agent prompt — after 2+ recurrences
4. `SKILL.md` — for a repeated procedure
5. hook or test — for a rule that must always hold

Promotions happen only through a human-approved PR.

Failed asks queue retro candidates (`.harness/retro/`); `harness retro` batches
them into one analyst ask whose lessons go to `docs/wiki/inbox/` (decision 0004).
`harness metrics` reports ask/exit/duration rates and wiki health; run it before
proposing harness changes.
