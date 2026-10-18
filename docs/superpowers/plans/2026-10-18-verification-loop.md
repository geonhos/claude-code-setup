# Verification Loop — Implementation Plan

Spec: `docs/superpowers/specs/2026-10-18-verification-loop-design.md`
Branch: `feature/v7-herdr-conductor`. TDD each task (failing test first),
macOS `/bin/bash` 3.2, awk instead of associative arrays.

1. `bin/harness-verify detect` + config resolution + auto-detect
   (tests/verify.test.sh, temp repos per project type, precedence).
2. `{files}` expansion and `run [lint|test|all]`.
3. `baseline`, state files, `stop` (skip / pass / fail-block / cap).
4. `format` (PostToolUse) incl. `tool_name` self-check and lint feedback JSON.
5. implementer.md frontmatter hooks + prompt text (partial on give-up).
6. reviewer.md: working-tree diff, `harness-verify run all`, app smoke,
   `VERDICT:` last line.
7. `bin/harness ask`: baseline for implementer, exit 5 rules, missing VERDICT
   → 3 (tests/harness.test.sh with fake herdr).
8. conductor.md exit code 5; install.sh symlink + test runner; README.
9. Commit (one commit per task is fine, or one at the end).
