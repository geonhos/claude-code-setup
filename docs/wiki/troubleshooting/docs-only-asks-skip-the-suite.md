---
type: troubleshooting
status: active
updated: 2026-10-27
sources: [ee449dd, fix(verify,harness) v15 round 2, ask 216eaa9e (129 s ask, 87 s Stop-hook suite), .harness/clear-and-weight-detail.md §2, ask 1792718047-26139-19519]
verified_by: tests/verify.test.sh (docs-only, wiki, mixed, agents md cases)
---
# The Stop hook skips the suite only for `docs/` and `.harness/` changes

**Symptom.** An implementer ask that only edits `AGENTS.md`, `README.md` or `claude/agents/*.md` still pays the full ~50 s suite, while the same edit under `docs/` finishes at once with verify `skipped (docs-only)`.

**Cause.** `harness-verify` classifies the paths changed since the ask's baseline (committed since baseline HEAD + staged + unstaged + untracked). All under `docs/` or `.harness/` → skip; any under `docs/wiki/` → only `harness wiki-lint` runs (a bad page fails like a test failure); anything else → lint + tests. Tests read `AGENTS.md`, `README.md` and the agent prompts, so they are code. The baseline is per ask: source committed by an earlier ask never counts as "since baseline", so an ask that only adds docs is docs-only. A commit/push-only ask with no new changes gives an empty path set, which runs the full suite (or is skipped by the state==base check); committing source that was already dirty when the ask started counts as code. Paths are listed with rename detection off, so `git mv bin/x.sh docs/x.sh` lists both paths and counts as code. Paths are taken from the git toplevel and compared with the conductor's ROOT (cwd): only `<ROOT>/docs/` and `<ROOT>/.harness/` count as docs, anything outside ROOT is code; a submodule pointer bump under `<ROOT>/docs/` counts as docs-only. `core.quotepath=off` still C-quotes paths containing `"`, `\` or control characters; such a path fails the `docs/*` match and counts as code (the safe direction).

**Fix.** None needed. Do not widen the docs set (`*.md`) without checking which tests read the file. Put docs-only notes in `docs/` to get the fast path.
