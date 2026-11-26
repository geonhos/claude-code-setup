# claude-code-setup

A conductor/worker harness for Claude Code. The default session is the conductor: it cannot read
or edit source and delegates through `harness ask` (`/analyze`, `/implement`, `/review`) to
analyst / implementer / reviewer workers, detached headless sessions (`claude -p`,
`HARNESS_ROLE=worker`, full tools), and reads only their reports. `install.sh` symlinks everything
into `~/.claude` and `~/.local/bin`.

<!-- harness:rules begin -->
## Working rules
- Language and style: text for people (chat, issues, PR bodies, README.md) in Korean, 합니다체, following the `korean-writing` skill (`~/.claude/skills/korean-writing/SKILL.md`); machine-facing text (code, commits, PR titles in conventional-commit form, agent prompts, briefs, worker reports, wiki) in English. In a PR body, `## Summary`, `## Test plan` and `Fixes #N` stay English. No AI stock phrases or filler; plain sentences: fact, conclusion, evidence.
- Every task has a GitHub issue; unhandled items (review Minors, follow-ups, open questions) become issues at once.
- Branch `feat|fix|docs/<issue#>-<slug>`; conventional commits with the Co-Authored-By trailer; PR body Summary / Test plan / `Fixes #N`; squash merge; the user merges.
<!-- harness:rules end -->

## Harness rules
- No new mode or mechanism without removing one; a mechanism with no reader for two weeks is removed. Run `harness metrics` before proposing harness changes.
- `bin/harness` sources `lib/` eagerly from an explicit list (wiki: `in-place-edit-breaks-running-scripts`).
- Tests: `./install.sh --test` runs every suite in parallel (~70 s); all must pass before a commit. Workers run only the affected suite(s) while iterating and the implementer Stop hook runs the full set. Never run suites in a serial loop: run the affected suite(s) singly or `./install.sh --test` once.
- Shell: scripts must run on macOS default bash 3.2: no `declare -A`, `mapfile` or `${var^^}`; use awk for maps. BSD vs GNU `stat`/`date`: see the wiki troubleshooting pages.

## Wiki
Lives in `docs/wiki/`. **Read `docs/wiki/index.md` before working; open a page only when it is
relevant.** Do not record what can be derived from code (structure, signatures, git
history); record traps, reasons and decisions the code does not show.

- Page types: `troubleshooting/` (symptom, cause, fix, evidence; one trap per page), `how-to/`
  (procedures), `decisions/NNNN-*.md` (context, decision, status, consequences); `log.md` is
  append-only, one line per change.
- Frontmatter keys (required): `type: troubleshooting|decision|how-to`, `status: draft|active|stale|superseded`,
  `updated: YYYY-MM-DD`, `sources: [ask-id | commit | file:line | url]`, `verified_by: <test name | command | human>`.
- One index line per page: `- [title](path): hook (status, updated)`. Index ≤80 lines, pages ≤150;
  `harness wiki-lint` checks all of this in the tests.
- Decisions are kept forever (superseded ones keep a banner); a troubleshooting page is deleted
  when its trap's code is gone, recorded in `log.md`.
- Promotion ladder: 1 `wiki`-label issue (unreviewed lesson with evidence) → 2 wiki page, through
  a PR that closes the issue → 3 (after 2+ recurrences) `AGENTS.md` for cross-agent rules; for
  Claude-specific ones `.claude/rules/` or one line in an agent prompt → 4 `SKILL.md` for a
  repeated procedure → 5 hook or test for a rule that must always hold. Promotions (steps 2-5)
  happen only through a human-approved PR.

## Claude Code
Claude Code (>= 2.1.277) reads this file only while no `CLAUDE.md`, `.claude/CLAUDE.md` or
`CLAUDE.local.md` exists here or above; do not create one (wiki: `agents-md-ignored-when-claude-md-exists`).
- The six core `korean-writing` rules are also in the conductor prompt (`claude/agents/conductor.md`).
- `conductor-gate` restricts the conductor's shell and edits; the SessionStart hook
  `conductor-resume` injects `.harness/progress.md` and the active wiki lines into the conductor
  only. Workers and non-Claude agents get no injection: they must read `docs/wiki/index.md` themselves.
- A worker is done when its process exits (`.harness/asks/<role>.exit.json`); the implementer's
  Stop hook first runs `harness-verify` lint/tests.
