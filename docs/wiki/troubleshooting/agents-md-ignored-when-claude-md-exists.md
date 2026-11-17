---
type: troubleshooting
status: active
updated: 2026-11-17
sources: [https://code.claude.com/docs/en/memory#agents-md, "#146", "#149", "#156"]
verified_by: tests/install.test.sh "no CLAUDE.md in the repo" (three names); probes 2026-11-17 on Claude Code 2.1.325 and 2.1.326 (under Evidence)
---
# AGENTS.md is ignored when a CLAUDE.md exists

**Symptom.** Rules written only in `AGENTS.md` never reach Claude Code sessions; the model answers NONE when asked for a marker line placed in `AGENTS.md`.

**Cause.** Claude Code (>= v2.1.277) reads `AGENTS.md` natively only when no `CLAUDE.md` exists in the working directory or above it. Any `CLAUDE.md`, `.claude/CLAUDE.md` or `CLAUDE.local.md` in the working directory or above hides `AGENTS.md`, even a one-line neutral one; the user-level `~/.claude/CLAUDE.md`, managed `CLAUDE.md` and `.claude/rules/` do not (probe 2026-11-17, Claude Code 2.1.326).

**Fix.** This repo has no `CLAUDE.md` on purpose; `AGENTS.md` holds everything, including the `## Claude Code` section. Do not create `CLAUDE.md`, `.claude/CLAUDE.md` or `CLAUDE.local.md` (for example with `/init`). The repo test sees only files present in the checkout it runs in, so an untracked `CLAUDE.local.md` on another machine is not caught. If one is needed, its first line must be `@AGENTS.md` (the import never double-loads). Do not symlink one to the other: Edit/Write refuse to write through it and Windows breaks it.

**Evidence.** Probe from a work folder with no `CLAUDE.md` in any parent and no `~/.claude/CLAUDE.md`: a unique `Probe marker: PROBE-263bf5c2` line was appended to `AGENTS.md`, then `claude -p "Reply with the probe marker from your project instructions, or NONE"` (env stripped as in `lib/harness-headless.sh`):
- no agent: marker returned
- `--agent conductor`: marker returned
- `--agent analyst` with `HARNESS_ROLE=worker`: marker returned
- control, a `CLAUDE.md` containing one neutral line (no import), no agent: `NONE`

**Check without a model answer (#156).** `claude -p --debug-file <file>` logs `no CLAUDE.md found; AGENTS.md loaded: <path>` when the built-in agents-md plugin loads `AGENTS.md`, and `$.fs.ancestors (cc-plugin-agents-md): CLAUDE.md, .claude/CLAUDE.md, CLAUDE.local.md found N of M directories` for the lookup. On 2.1.326 the load line was absent exactly in the cases where the model also did not see `AGENTS.md`: `proj/.claude/CLAUDE.md`, `proj/CLAUDE.local.md`, and `.claude/CLAUDE.md` in a parent directory. With none of them it was present.

**Limit.** The user-level case rests on the plugin debug line (scan 0 of N, `AGENTS.md` loaded) and the docs, not on a model answer: a scratch config directory could not log in. If a project sits under `$HOME` and `HOME` is a symlinked spelling of the real path, or `CLAUDE_CONFIG_DIR` points elsewhere while `~/.claude/CLAUDE.md` remains, that file did count in the probe (cases 2b, 2f, debug line only).
