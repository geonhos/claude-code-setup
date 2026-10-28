---
type: troubleshooting
status: active
updated: 2026-10-28
sources: [ask 1792731600-29108-22965, transcript 46cb17a4 05:04:32Z]
verified_by: tests/headless.test.sh (in-place rewrite); tests/harness-split.test.sh
---
# Rewriting a bin/ script in place breaks the processes running it

**Symptom.** A headless analyst run ended with "gone without a result" (exit 3) at 05:04:34Z and never wrote `exit.json`, though claude itself was healthy.

**Cause.** `bin/` is symlinked into PATH, so a worker's edit hits scripts that conductor and runner processes are executing. Bash reads a script by byte offset as it goes; an in-place write (`open(p, 'w')`, `> file`, same inode) makes the running shell continue in the middle of the new text. The implementer had rewritten `bin/harness-run` that way while it sat in `wait`.

**Fix.** The bodies of `bin/harness`, `harness-run`, `harness-view` and `harness-verify` are one `{ ...; exit $?; }` group, so bash parses the whole file first. Still edit with the Edit tool or write a temp file and `mv` it (new inode); never `>` onto a `bin/*` file. A new script in `bin/` must use the same wrapper.

**lib/ files.** `bin/harness` sources `lib/harness-*.sh` eagerly at the top of the brace group, from an explicit list. bash 3.2 `source` reads the whole file into memory before running it (design experiment: a sourced file that overwrote itself mid-run kept printing its original lines; run directly it executed the injected text), so the same protection holds, but only while sourcing stays eager and lib files hold definitions only. Never source a lib file lazily (e.g. inside `ask_finish`): it could load a half-written file.

**Evidence.** ask 1792731600-29108-22965; transcript 46cb17a4 at 05:04:32Z; test "in-place rewrite" in `tests/headless.test.sh`; lib/: `tests/harness-split.test.sh` (overwrites bin/harness and every lib file mid-run), `.harness/harness-split-design.md` §4.
