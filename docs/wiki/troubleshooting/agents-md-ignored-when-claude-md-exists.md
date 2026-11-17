---
type: troubleshooting
status: active
updated: 2026-11-17
sources: [https://code.claude.com/docs/en/memory#agents-md, "#146"]
verified_by: tests/install.test.sh "no CLAUDE.md at repo root"; probe 2026-11-17 on Claude Code 2.1.325 (commands under Evidence)
---
# AGENTS.md is ignored when a CLAUDE.md exists

**Symptom.** Rules written only in `AGENTS.md` never reach Claude Code sessions; the model answers NONE when asked for a marker line placed in `AGENTS.md`.

**Cause.** Claude Code (>= v2.1.277) reads `AGENTS.md` natively only when no `CLAUDE.md` exists in the working directory or above it. Any `CLAUDE.md`, even a one-line neutral one, hides `AGENTS.md`.

**Fix.** This repo has no `CLAUDE.md` on purpose; `AGENTS.md` holds everything, including the `## Claude Code` section. Do not create one (for example with `/init`). If one is needed, its first line must be `@AGENTS.md` (the import never double-loads). Do not symlink one to the other: Edit/Write refuse to write through it and Windows breaks it.

**Evidence.** Probe from a work folder with no `CLAUDE.md` in any parent and no `~/.claude/CLAUDE.md`: a unique `Probe marker: PROBE-263bf5c2` line was appended to `AGENTS.md`, then `claude -p "Reply with the probe marker from your project instructions, or NONE"` (env stripped as in `lib/harness-headless.sh`):
- no agent: marker returned
- `--agent conductor`: marker returned
- `--agent analyst` with `HARNESS_ROLE=worker`: marker returned
- control, a `CLAUDE.md` containing one neutral line (no import), no agent: `NONE`
