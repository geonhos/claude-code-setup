---
type: troubleshooting
status: active
updated: 2026-11-03
sources: [ask 1793598046-17520-20103, ask 1793598659-2974-29323, ask 1793687725-86282-3617, lib/harness-metrics.sh:45, e31cb23]
verified_by: human (no check yet)
---
# wiki-lint does not notice dangling citations

**Symptom.** After a suite or page was deleted, wiki pages still cite it (`tests-inherit-worker-env.md` cited `tests/route.test.sh`) and `harness wiki-lint` passes.

**Cause.** wiki-lint checks only that `sources` is a non-empty `[list]` (`lib/harness-metrics.sh:45`). It never checks that cited paths or index links exist (`lib/harness-metrics.sh:30-61`).

**Fix.** Until a check exists: before deleting a test, page or script, `grep -rn <slug-or-path> docs/ AGENTS.md README.md` and fix every hit (done by hand in e31cb23 and again in prune step 7, PR #47). Three recurrences so far (analyst-17520, implementer-2974, analyst-86282), so a lint on `sources:` entries that look like repo paths is a hook/test candidate; not built.

**Evidence.** Asks 1793598046-17520-20103, 1793598659-2974-29323, 1793687725-86282-3617.
