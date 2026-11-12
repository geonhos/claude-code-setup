# Viewer dashboard (phase 1) — design

Date: 2026-11-12. Status: approved by user (phase 1 only).

## Problem
The herdr viewer pane (`harness watch <role>`) is an append-only scroll of one line per
tool call (`tail -F raw | harness-view`, lib/harness-headless.sh:517-554). It does not show
what the worker was asked, what it is doing now, or how far it is. The user finds it of
little value.

## Goal
While a run is live, `harness watch <role>` redraws a fixed-layout dashboard every 2 s:

```
implementer  <ask-id>  ⏱ 12m04s  turns 38  ctx 82k  sonnet
── Brief ───  title line of the brief
── Steps ───  numbered list from the brief's `## Steps` (no progress marks in phase 1);
              fallback: the brief's `##` headings
── Now ─────  whichever is later in the stream: last assistant text or last tool_use
              (Bash description preferred over command)
── Recent ──  last N lines of harness-view output (N fits pane height)
── Verify ──  not started | verifying… | pass | fail (<step>)
── Diff ────  git diff --stat against verify/<role>.base sha (implementer only; omitted otherwise)
```

When the run ends: draw a final frame with the result line (turns, duration, cost from
exit.json/result event) and the first lines of the report, then exit (pane close timing is
unchanged).

## Data sources (all existing; no new files or events)
- Brief: `.harness/task-<role>.md` only when `.harness/asks/<role>.prompt` names it; otherwise
  the prompt text itself (first line as title, no Steps).
- Header: `asks/<role>.current` (ask-id, start epoch → elapsed), stream `system/init` (model),
  last assistant `message.usage` (ctx tokens = input + cache_read + cache_creation), count of
  assistant turns.
- Now/Recent: stream jsonl; Recent reuses `bin/harness-view`.
- Verify: Stop `hook_started`/`hook_response` events in the stream, plus `verify/<role>.json`
  when present.
- Diff: `verify/<role>.base` sha.

## Rendering rules
- Pure function: `render(frame inputs) → text` sized to `tput lines`/`tput cols`
  (overridable by env for tests). The loop moves the cursor home (`\033[H`), prints each line followed by `\033[K`
  (no newline after the last line), then `\033[J`; it never clears the whole screen.
- While drawing: cursor hidden and autowrap off (`\033[?25l\033[?7l`); every exit path
  restores `\033[?7h\033[?25h` and prints a newline. Lines are cut to W-1 columns.
- Truncate lines to width. When height is short, shrink sections in this order of keeping:
  header, Now, Steps, Verify, Diff, Recent (Recent shrinks first, then Diff, then Brief title kept to 1 line).
- Steps capped at 10 lines; Now capped at 3 lines.
- bash 3.2, jq (already required). No new dependency.

## Removed mechanism
The live `tail -n +1 -F raw > fifo | harness-view` branch of `cmd_watch` is replaced by the
dashboard loop. The finished-run branch (`harness-view < raw | tail -n 40`) and `hl_view_tail`
stay as they are.

## Rule change
`/analyze`, `/implement`, `/review` skills: the brief must contain a `## Steps` numbered list
(one line per step).

## Out of scope (phase 2, after an adoption measurement)
Progress marks (✓/▶) from worker signals (Task tools via `CLAUDE_CODE_ENABLE_TODO_TOOLS=1`,
or a text marker). Evidence: docs/research/2026-11-12-todo-tools-ab.md on branch
`research/todo-tools-ab`: tools expose fine, overhead within noise, but unprompted use 0/4,
nudged 2/4 with one stale list.

## Testing
- Golden test of the render function on a fixture stream + brief + fixed size (fake-claude
  stream extended if needed): header, Steps from `## Steps`, heading fallback, Now from text and
  from tool_use, Verify states, truncation at small height/width.
- Update existing watch assertions in tests/headless*.test.sh, gate, install suites that
  depend on the old live output.
- `./install.sh --test` passes.
