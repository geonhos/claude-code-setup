---
type: decision
status: active
updated: 2026-11-28
sources: ["#305", mods/harness-workers/hooks/model.ts, tests/mod.test.sh, tests/fixtures/status-v1.json]
verified_by: tests/mod.test.sh
---
# 0019: worker progress is a mod in this repository, reading `status --json`

**Context.** The user had to run `/watch` or `harness watch` to see a worker; the conductor shows nothing while a worker runs. Measured for #305: `/watch` was used on about 6 % of asks, always through herdr; of 13 real `open-watch` calls (2026-11-16 to 2026-11-27) none opened Ghostty or Terminal.app. Since 2026-11-13, 208 runs, 74 (36 %) overlapped another run (a lane implementer with a primary analyst or reviewer), so one pane per ask clutters. The gap is not failure; the progress is out of sight.

**Decision.**
- D1: a Claude Code mod, `mods/harness-workers/`, draws a band above the conductor's prompt: one row per running worker or one finished within 60 s, across all work folders; a `▸`/`▾` toggle (the mod's own state) expands the step list; toast on every exit, native notification on failure only.
- D2: the mod reads only `harness status --json --all` (contract version 1). A version other than 1, a failed run or bad output draws a dim `harness-workers: <reason>` row; nothing breaks silently.
- D3: the current step comes from STEP markers the workers write; the mod shows `step` as is and never marks a stale step as certain.
- D4: the mod lives in this repository so that it cannot drift from the command: `tests/mod.test.sh` runs a contract test of its parser against `tests/fixtures/status-v1.json`, the file `tests/dash.test.sh` compares the real command with.
- D5: installation is the user's `/plugin marketplace add <checkout>` and `/plugin install harness-workers@my-claude-harness`; `install.sh` does not edit plugin settings.

**Removed in exchange.** The Ghostty and Terminal.app backends of `harness open-watch` (0 of 13 uses; amendment in 0013). Issue #315 was named in the brief without further detail; nothing else was removed here.

**Rejected alternatives.**
- `statusLine`: edits a user setting (one line) and is unconfirmed outside the terminal.
- Auto-opened pane per ask: clutter at 36 % overlap; herdr or tmux only.
- A browser page: a server to run for one viewer.
- A separate repository: the mod and the status contract would drift.

**Status.** Active.

**Consequences.**
- The mod depends on a young Claude Code mod API (checked against 2.1.332; the minimum version is stated in its README). An API change breaks the band, not the harness.
- The step list is only as good as the workers' marker adherence; without markers the band shows the `now` text.
- A change to a field the mod reads fails `tests/mod.test.sh` (field list `hooks/fields.txt`) before commit. The list proves a path exists in the golden, not that the parser reads it.
- Not verified on screen by the implementer; the user checks it.
