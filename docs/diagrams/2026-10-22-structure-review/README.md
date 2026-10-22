# Harness diagrams

Snapshot of `feature/v13-verify-speed`, 2026-10-22. Line refs: H = `bin/harness`,
V = `bin/harness-verify`, G = `claude/hooks/conductor-gate.sh`, I = `install.sh`.
Source: analyst structure review (`.harness/structure-detail.md`). These drift with
the code; re-check line numbers before relying on them.

- [01 Dispatch flow](01-dispatch.md) — user prompt → skill → `harness ask` → worker → report
- [02 Worker execution](02-worker.md) — spawn, context reset, completion check, exit codes, pane lifecycle
- [03 Hooks](03-hooks.md) — conductor hooks (settings.json) and worker hooks (agent frontmatter)
- [04 Structure review](04-review.md) — weaknesses, herdr fit, speed

Rendered page: https://claude.ai/artifact/CjGTaXks4MpNBvtSCxorPd
