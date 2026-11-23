---
type: how-to
status: active
updated: 2026-11-23
sources: [ask 1792626580-18511-31125, ask 1792714556-77884-26975, ask 1792674245-84806-615, ask 1793073010-64174-28688, "#74", "#75", "#76", bin/harness:120, ask 1793882024-36166-5476, ask 1793924540-67435-2319, ask 1794458645-18563-14584, ask 1795054725-54641-27030, "#172", "#198"]
verified_by: human (sessions 942b8f0b, c1c1bb80, fdd6bd08, 2298d3e1, 7d18f6cb, ed0cffdb)
---
# Reading worker transcripts to diagnose an ask

Transcripts: `~/.claude/projects/<cwd-slug>/<session>.jsonl`.

- **Stop-hook time.** The screen's "running Stop hook · Nm Ns" counts the whole turn. Use the `stop_hook_summary` entry's `durationMs` (942b8f0b: screen 10 m, hook 189.9 s). Its `cwd` also shows where the hook ran (see [harness root lookup](../troubleshooting/harness-root-lookup.md)).
- **Did /clear run?** A `continued-in` link = cleared. A lone `file-history-snapshot` at send time = submitted but not cleared.
- **Ask to PR round.** Ask-ids are `<epoch>-<pid>-<rand>` (bin/harness:1142), so map an ask to its PR round by merge time. Exception: PRs #13–#16 merged within seconds of each other (merge ct 1792625055–1792625096), so the epoch cannot separate them.
- **Ask-id to files.** Since #198 `grep -l <ask-id> .harness/log/*.md` finds the archive and `jq 'select(.ask_id=="<id>")' .harness/progress.jsonl` the row. For older ids `date -r <epoch> +%Y%m%d-%H%M%S` (BSD; GNU `date -d @<epoch>`) is the stream log stamp `.harness/log/<stamp>-<role>.jsonl.gz`. Logs older than 14 days are deleted (bin/harness:190).
- **What was the worker given?** `harness` copies the brief verbatim into `.harness/log/<stamp>-<role>.md` under `## Brief`, also for asks with no stream jsonl. The full system prompt and starting context are in the transcript's `prompt_snapshot` entry. Transcripts are pruned over time (session 8aec12d1, cited 2026-11-06, was gone by 2026-11-16).
- **Lost report?** Asks before 2026-11-05 have no `.harness/log` copy. Take the session id from `.harness/progress.jsonl` `.session`, open `<session>.jsonl` and copy the input of the Write/Bash tool call that writes `.harness/reports/<role>.md` (sessions 9a862e52, c96587fc). Later reports are in `.harness/log/<stamp>-<role>.md`.

## Known noise (not a bug)
- sonnet-5-5 workers call a lowercase `bash` tool ~1.6% of the time (9/564) and recover at once; opus 0/987. Do not chase it as a config bug.
- Headless workers have no TodoWrite tool (init `tools`, CLI 2.1.318–2.1.325; 0 calls in 93 streams). Do not build viewer features on it.
