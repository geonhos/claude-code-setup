---
type: gotcha
status: active
updated: 2026-10-23
sources: [commit 5ea7475, .harness/progress.jsonl reviewer asks 2026-10-21 exit 3 ×4]
verified_by: human (conductor session 2026-10-21)
---
# Workers keep the prompt and hooks they were started with

**Symptom.** After the prompt or hooks in `claude/agents/*.md` change (the implementer pane is now kept up to 30 min, ADR 0006, so it may predate the edit), a worker keeps the old ones. After hooks change in agent frontmatter, every ask to an existing worker exits 3: "Stop hook never signalled completion; a report exists".

**Cause.** Claude Code loads the agent prompt and frontmatter hooks at session start. `/clear` does not reload them. `bin/harness-verify` itself is symlinked, so a change *inside* an existing hook takes effect at once. A *new* hook entry does not.

**Fix.** `harness close <role>` (or `harness close --legacy` for old unscoped names), then the next `harness ask` respawns the worker. Collect the pending report first with `harness report <role>`.
