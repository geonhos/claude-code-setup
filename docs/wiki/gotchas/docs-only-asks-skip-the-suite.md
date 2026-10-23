---
type: gotcha
status: active
updated: 2026-10-23
sources: [ee449dd, ask 216eaa9e (129 s ask, 87 s Stop-hook suite), .harness/clear-and-weight-detail.md §2]
verified_by: tests/verify.test.sh (docs-only, wiki, mixed, agents md cases)
---
# The Stop hook skips the suite only for `docs/` and `.harness/` changes

**Symptom.** An implementer ask that only edits `AGENTS.md`, `README.md` or `claude/agents/*.md` still pays the full ~50 s suite, while the same edit under `docs/` finishes at once with verify `skipped (docs-only)`.

**Cause.** `harness-verify` classifies the paths changed since the ask's baseline (committed since baseline HEAD + staged + unstaged + untracked). All under `docs/` or `.harness/` → skip; any under `docs/wiki/` → only `harness wiki-lint` runs (a bad page fails like a test failure); anything else → lint + tests. Tests read `AGENTS.md`, `README.md` and the agent prompts, so they are code. The baseline is per ask: source committed by an earlier ask never counts as "since baseline", so a commit/push-only ask is docs-only unless it adds new changes.

**Fix.** None needed. Do not widen the docs set (`*.md`) without checking which tests read the file. Put docs-only notes in `docs/` to get the fast path.
