# Shrink inventory: get below 8,423 lines without removing features (#105)

## Goal
After restructuring (#63) the repo grew from 8,423 to 9,386 lines (git archive + wc -l over bin, lib, claude, tests, docs, AGENTS.md, CLAUDE.md, install.sh): source +473, prompts/skills +73, tests +658. The user wants a further shrink to ≤ 8,423 lines. User-facing features stay: work folders (`harness lane`, `-C`, guard), dashboard + `open-watch`/`/watch`, notify hook, gate short reads, Notes→wiki issues, review rules. Your list feeds the user's approval.

## Constraints
Read-only on the repo (primary checkout on main, 43fc5a7). Write only under `.harness/`. No commits.

## Steps
1. Per file line counts now (same method) and the biggest growth since db418dc (`git diff --stat db418dc..HEAD`).
2. Source candidates: dead code (functions with no caller, e.g. `last_ask_record`), duplicated helpers (path canonicalisation in gate vs lane, jq width code, quoting), branches no one reaches, over-long usage/help text, comments that restate code. For each: file:line, lines saved, risk.
3. Test candidates: duplicated setup that a shared helper could replace (tests/harness-lib.sh), assertions repeated across suites (e.g. gate cases covered both in gate.test.sh and gate-denied.list), tests of removed behaviour, very long golden blocks that could be shorter without losing what they prove. Keep tests that prove a reviewed bug fix (mutant/base-failing checks). For each: lines saved, what coverage is kept.
4. Prompts/skills/docs: duplicated rules between AGENTS.md, CLAUDE.md, conductor.md and skills (state each rule once).
5. Group into 2–4 PR-sized batches ordered by risk, with totals; show whether the sum reaches ≤ 8,423. If it cannot without removing a feature, say which feature would have to go and how much it would save.

## Done criteria
Report in Korean: per-batch table (item, file:line, lines saved, risk), total, whether the target is reachable. Full list in `.harness/shrink2-inventory.md`.

