---
type: runbook
status: active
updated: 2026-10-27
sources: [ask 1792626580-18511-31125, ask 1792714556-77884-26975, ask 1792674245-84806-615]
verified_by: human (sessions 942b8f0b, c1c1bb80, fdd6bd08, 2298d3e1, 7d18f6cb, ed0cffdb)
---
# Reading worker transcripts to diagnose an ask

Transcripts: `~/.claude/projects/<cwd-slug>/<session>.jsonl`.

- **Stop-hook time.** The screen's "running Stop hook · Nm Ns" counts the whole turn. Use the `stop_hook_summary` entry's `durationMs` (942b8f0b: screen 10 m, hook 189.9 s). Its `cwd` also shows where the hook ran (see [harness root lookup](../gotchas/harness-root-lookup.md)).
- **Did /clear run?** A `continued-in` link = cleared. A lone `file-history-snapshot` at send time = submitted but not cleared.

## Known noise (not a bug)
- sonnet-5-5 workers call a lowercase `bash` tool ~1.6% of the time (9/564) and recover at once; opus 0/987. Do not chase it as a config bug.
