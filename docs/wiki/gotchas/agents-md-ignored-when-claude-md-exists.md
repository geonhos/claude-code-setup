---
type: gotcha
status: active
updated: 2026-10-21
sources: [https://code.claude.com/docs/en/memory#agents-md]
verified_by: human (official doc; CLAUDE.md line 1 is `@AGENTS.md`)
---
# AGENTS.md is ignored when CLAUDE.md exists

**Symptom.** Rules written only in `AGENTS.md` never reach Claude Code sessions.

**Cause.** Claude Code (≥ v2.1.277) reads `AGENTS.md` only when no `CLAUDE.md` exists in the directory.

**Fix.** Keep `AGENTS.md` canonical and make `CLAUDE.md` start with `@AGENTS.md`, followed by Claude-only notes; the import never double-loads. Do not symlink one to the other: Edit/Write refuse to write through it and Windows breaks it.
