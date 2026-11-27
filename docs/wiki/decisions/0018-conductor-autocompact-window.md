---
type: decision
status: active
updated: 2026-11-27
sources: ["#276", bin/harness:settings_merge, lib/harness-headless.sh, claude/agents/conductor.md]
verified_by: tests/harness.test.sh, tests/install.test.sh
---
# 0018: the conductor compacts at 400000 tokens; `harness init` writes the key

**Context.** The conductor session had no auto-compact setting, so it used the default window (about 967K tokens on a native-1M model; Claude Code 2.1.332, analyst report for #276). Every request re-reads the whole context. Measured on 2,242 interactive requests since 2026-11-01 (raw counts, which double-count fork copies): 55.0 / 37.0 / 25.6 / 18.3 % were above 200k / 300k / 400k / 500k tokens. Deduped by message id: 2,058 requests; above 300k / 400k / 500k 40.3 / 27.8 / 19.9 %. No conductor session reached the default threshold (largest 731,994 tokens). Of 5 interactive auto compactions, 4 were idle compactions (about 1 h idle, at least 200k tokens; on by default and unchanged here). Workers already run with `CLAUDE_CODE_AUTO_COMPACT_WINDOW=160000` (`lib/harness-headless.sh`); the environment variable beats any settings key.

**Decision.** (user, 2026-11-27)
- D1: `autoCompactWindow: 400000` for the conductor (documented settings key: tokens, at least 100000, capped at the model window). Frontmatter `autoCompactWindow` has no effect when the session runs as that agent, so it goes in settings.
- D2: `harness init` writes it into the file that receives `agent` (`.claude/settings.local.json`; `--shared`: `.claude/settings.json`; `--no-agent` skips it). An existing value in that file is kept and reported; a second run changes nothing. In a work folder (lane) `autoCompactWindow` is never written to the tracked `settings.json` (decision 0016: no git-visible change): the key goes to the local file unless the tracked file already has a value. Local settings outrank project settings.
- D3: the conductor prompt ("Progress and resuming") says to update `goal.md` and end the report with a `/clear` suggestion when a piece of work (one PR) ends; `goal.md` and the progress file come back through the SessionStart hook.
- D4: workers are unchanged.

**Status.** Active.

**Consequences.**
- The compaction point is expected near 370k tokens. This is an assumption (a fixed headroom inferred from workers), not verified. Supporting evidence only: on Claude Code 2.1.332 `/context` shows "Autocompact buffer 33k" with a 400k window (about 367k). It stays unconfirmed until a real `compact_boundary` is seen.
- init writes the key only for the conductor session: not with `--no-agent`, not when the target file keeps another `agent`, and not when the tracked `.claude/settings.json` already carries a value (local would override a team value); it prints one line saying so.
- Checkouts initialised before #276 get the key when `harness init` runs again.

**Correction (2026-11-27, #283).** D2 first said the tracked `settings.json` is never edited in a work folder; that was too wide: `init --shared` there still writes `agent: conductor` into the tracked file when absent (predates #276, unchanged). Only `autoCompactWindow` stays out of it. Also, when the tracked file names a foreign agent and the local file does not name the conductor, the local file gets no window either (it would reach a non-conductor session); init prints the usual "autoCompactWindow not set" note.

**Verify after rollout.** `/autocompact` prints the window. Cheap check, verified on 2.1.332: `claude -p "/autocompact"` prints the effective window and its source ("400k tokens (from settings)"; "160k tokens (from CLAUDE_CODE_AUTO_COMPACT_WINDOW)" for workers). A `compact_boundary` with trigger `auto` near 370k and no 55-minute idle gap before it shows the window works (as opposed to an idle compaction).
