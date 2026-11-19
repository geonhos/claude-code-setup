# claude-code-setup

A conductor/worker harness for Claude Code. The conductor session cannot read or
edit source; it delegates through `harness ask` to analyst / implementer /
reviewer workers that run as detached headless Claude sessions (`claude -p`), and reads only their reports. Hooks
gate the conductor's shell, verify worker output and resume from progress logs.
`install.sh` symlinks everything into `~/.claude` and `~/.local/bin`.

## Working rules
- Language and style: text for people (chat, issues, PR summaries for the user, README.md) in Korean, 합니다체, following `claude/guides/korean-writing.md` (its six core rules are in the conductor prompt); machine-facing text (code, commits, PR titles/bodies, agent prompts, briefs, worker reports, wiki) in English. No AI stock phrases or filler; plain sentences: fact, conclusion, evidence.
- Every task is tracked by a GitHub issue; unhandled items (review Minors, follow-ups, open questions) become issues at once.
- Branch `feat|fix|docs/<issue#>-<slug>`; conventional commits in English with the Co-Authored-By trailer; PR body Summary / Test plan / `Fixes #N`; squash merge; the user merges.

## Harness rules
No new mode or mechanism without removing one; a mechanism with no reader after two weeks is removed.
`bin/harness` sources its `lib/` files eagerly from an explicit list (wiki: `in-place-edit-breaks-running-scripts`).

## Test
`./install.sh --test` runs every suite, in parallel (`HARNESS_TEST_SERIAL=1` runs them one
at a time; `HARNESS_TESTS_DIR` points it at another suite directory). All must pass before a commit; workers run only the affected suites while
iterating and the implementer Stop hook runs the full set.
Never run suites in a serial loop; run the affected suite(s) singly or `./install.sh --test` once (parallel, ~70 s).

## Shell rule
Scripts must run on macOS default bash 3.2: no `declare -A`, no `mapfile`, no
`${var^^}`. Use awk for maps. BSD vs GNU `stat`/`date`: see the wiki troubleshooting pages.

## Wiki
Lives in `docs/wiki/`. **Read `docs/wiki/index.md` before working; open a page
only when it is relevant to the task.**

- `troubleshooting/*.md`: symptom, cause, fix, evidence; one trap per page
- `how-to/*.md`: step-by-step procedures
- `decisions/NNNN-*.md`: context / decision / status / consequences
- `log.md` append-only, one line per change

Page frontmatter (required):
```
type: troubleshooting|decision|how-to
status: draft|active|stale|superseded
updated: YYYY-MM-DD
sources: [ask-id | commit | file:line | url]
verified_by: <test name | command | human>
```
Every page needs one index line: `- [title](path): hook (status, updated)`.
Limits: index ≤80 lines, pages ≤150. `harness wiki-lint` checks this in the tests.
Retention: decisions are kept forever (superseded ones keep a banner); troubleshooting pages are deleted when the trap's code is gone, and `log.md` records the deletion.

**Do not record what can be derived from code** (structure, signatures, git
history). Record traps, reasons and decisions that the code does not show.
A report's `## Notes` bullets (≤2) must each cite evidence (ask-id, commit,
file:line or log); `harness report` files each as a GitHub issue labelled `wiki`.

### Promotion ladder
1. a `wiki`-label GitHub issue: unreviewed lesson with evidence
2. wiki page: through a PR that closes the issue
3. `AGENTS.md` (cross-agent rules) or, for Claude-specific ones, `.claude/rules/`
   or one line in an agent prompt, after 2+ recurrences
4. `SKILL.md`: for a repeated procedure
5. hook or test: for a rule that must always hold

Promotions happen only through a human-approved PR.

`harness metrics` reports ask/exit/duration rates and wiki health; run it before
proposing harness changes.

## Claude Code (specific to Claude Code sessions)
Claude Code reads this file natively (>= 2.1.277) only while no `CLAUDE.md`, `.claude/CLAUDE.md` or
`CLAUDE.local.md` exists in the working directory or above; this repo has none on purpose (see the wiki trap
`agents-md-ignored-when-claude-md-exists`).

- **Roles.** The default session is the conductor: it cannot read or edit
  source and delegates through `/analyze`, `/implement` and `/review` to
  analyst / implementer / reviewer workers (detached headless Claude sessions,
  `claude -p`), reading only their
  reports. Workers run with `HARNESS_ROLE=worker` and full tools.
- **Gate.** `conductor-gate` restricts the conductor's shell and file edits.
- **Completion.** A headless worker is done when its process exits
  (`.harness/asks/<role>.exit.json`); the implementer's Stop hook first runs
  `harness-verify` lint/tests.
- **Wiki injection.** The SessionStart hook `conductor-resume` injects
  `.harness/progress.md` and the `(active,` lines of `docs/wiki/index.md` into
  the conductor. Workers and non-Claude agents get no injection: they must
  read `docs/wiki/index.md` themselves, as the Wiki section says.
