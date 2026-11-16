---
type: troubleshooting
status: active
updated: 2026-11-16
sources: [#124, #125, PR #126, claude/hooks/conductor-gate.sh, tests/gate.test.sh]
verified_by: tests/gate.test.sh
---
# zsh extendedglob rewrites revs in `git show`

**Symptom.** A gate rule that allowed `git show --stat HEAD^` or `git show HEAD^:docs/x.md` looked safe, yet the command that reached the shell named other files (for example `main^:x.md` became `main.go`).

**Cause.** The rev reaches the shell unquoted, and under zsh extendedglob a mid-word `^` is a negation pattern that expands to matching file names. `~` is an exclusion operator but stays literal when the word has no other pattern characters, so `HEAD~1` passes through while `HEAD~1*` or `main~:x` can glob.

**Fix.** `commit_rev_ok` denies every `^` and accepts only `~N` (digits) suffixes. `git_show_ok` allows `~N` only in the `--stat`/`--name-only` form and denies `~` and `^` anywhere in a `rev:path` token. Use `~N` instead of `^` when asking for a parent.

**Evidence.** The zsh probe in `tests/gate.test.sh` (`zsh extendedglob expands main^:x.md`) shows the expansion; the `git show ... ^` deny checks fail on a gate that allows `^`.
