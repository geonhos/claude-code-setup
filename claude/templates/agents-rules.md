## Working rules
- Language and style: text for people (chat, issues, PR bodies, README.md) in Korean, 합니다체, following the `korean-writing` skill (`~/.claude/skills/korean-writing/SKILL.md`); machine-facing text (code, commits, PR titles in conventional-commit form, agent prompts, briefs, worker reports, wiki) in English. In a PR body, `## Summary`, `## Test plan` and `Fixes #N` stay English. No AI stock phrases or filler; plain sentences: fact, conclusion, evidence.
- Every task has a GitHub issue; unhandled items (review Minors, follow-ups, open questions) become issues at once.
- Branch `feat|fix|docs/<issue#>-<slug>`; conventional commits with the Co-Authored-By trailer; PR body Summary / Test plan / `Fixes #N`; squash merge; the user merges.
