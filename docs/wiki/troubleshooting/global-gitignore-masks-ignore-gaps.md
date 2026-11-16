---
type: troubleshooting
status: active
updated: 2026-11-16
sources: ["#78", ask 1794542929-18298-21804, commit 41b679b, tests/harness.test.sh:260-278]
verified_by: tests/harness.test.sh (init: all five patterns present)
---
# A global gitignore hides missing ignore entries

**Symptom.** After `harness init` in a fresh repo, `git status` stays clean although init wrote no exclude line for a harness path.

**Cause.** This machine's `~/.config/git/ignore` lists `.harness/` and `**/.claude/settings.local.json`, so git ignores them whether init does or not. A user without that file sees them as untracked.

**Fix.** Neutralise user config when checking what a repo ignores: `git -c core.excludesFile=/dev/null status`, or in tests `GIT_CONFIG_GLOBAL=/dev/null` plus `GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.excludesFile GIT_CONFIG_VALUE_0=/dev/null` (tests/harness.test.sh:260-271).

**Evidence.** Ask 1794542929-18298-21804 (/tmp/hi-test probe); gaps fixed in 41b679b.
