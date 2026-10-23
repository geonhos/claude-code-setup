---
type: gotcha
status: active
updated: 2026-10-23
sources: [ask 1792733060, transcript 46cb17a4 05:04:32Z]
verified_by: tests/headless.test.sh (in-place rewrite)
---
# Rewriting a bin/ script in place breaks the processes running it

**Symptom.** A headless analyst run ended with "gone without a result" (exit 3) at 05:04:34Z and never wrote `exit.json`, though claude itself was healthy.

**Cause.** `bin/` is symlinked into PATH, so a worker's edit hits scripts that conductor and runner processes are executing. Bash reads a script by byte offset as it goes; an in-place write (`open(p, 'w')`, `> file`, same inode) makes the running shell continue in the middle of the new text. The implementer had rewritten `bin/harness-run` that way while it sat in `wait`.

**Fix.** The bodies of `bin/harness`, `harness-run`, `harness-view` and `harness-verify` are one `{ ...; exit $?; }` group, so bash parses the whole file first. Still edit with the Edit tool or write a temp file and `mv` it (new inode); never `>` onto a `bin/*` file. A new script in `bin/` must use the same wrapper.

**Evidence.** ask 1792733060; transcript 46cb17a4 at 05:04:32Z; test "in-place rewrite" in `tests/headless.test.sh`.
