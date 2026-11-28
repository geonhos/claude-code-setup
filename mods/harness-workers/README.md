# harness-workers

A Claude Code mod that shows the progress of harness workers above the prompt of the conductor
session, without typing anything. It reads only `harness status --json --all` (status contract
version 1, `docs/reference.md`; golden `tests/fixtures/status-v1.json`).

```
 ▸ ● implementer #305  2/7 Add failing tests · 4m12s
   ● analyst     main  → Read lib/harness-dash.sh · 1m03s
   ✓ reviewer    #301  exit 0 · PASS · 3m40s
```

- One row per worker that is running or finished within the last 60 s, across all work folders.
  `●` running, `✓` exit 0, `✗` any other exit or a dead worker. Nothing is drawn when there is none.
- The `▸`/`▾` button at the left of the first row expands the band to each worker's step list
  (done `✓`, current `▸` with the `now` text, pending `·`). The state lasts for the session. When the
  rows do not fit `maxRows`, the current step of each worker has priority. Whenever a worker is hidden and
  `maxRows` is at least 2, the last row is `+N more`; with `maxRows` 1 only the first header is drawn.
- Korean text comes from the brief the conductor writes (both optional, English names and no instruction
  line without them): a `Title-ko: <Korean one-liner>` line above the first `## ` heading, and a
  `[ko: <Korean step name>]` suffix at the end of a `## Steps` item. The expanded band draws
  `지시: <title>` under the header (it counts toward `maxRows`); step names use the Korean name, else
  the English text, collapsed and expanded. The current action (`→ …`) stays English and sits under the
  current step. They reach the mod as `title_ko` and `steps[].ko` of `harness status --json` (additive,
  `version` stays 1; `null` when absent). The `[ko: …]` suffix is cut from `steps[].text`.
- A toast on every worker exit; a native notification only when it failed (rc ≠ 0, dead, verify fail).
- If the status format is not version 1, `harness status` fails or times out, one dim row
  `harness-workers: <reason>` is drawn and polling continues slowly.
- It does nothing when the session is not inside a harness checkout (no `.harness/asks` in the cwd or an
  ancestor up to the git root), or when `HARNESS_ROLE=worker`.
- Polling: every 3 s while a worker runs, every 30 s otherwise, one loop and one run at a time (a
  run that a session end or reload leaves behind can overlap the next loop's first run); a 1 s clock
  tick only while a worker runs. It draws only: it never writes a file or puts text into the conversation.

## Known limits

- After a hot reload of the mod (a changed module while a session runs) the new copy starts its own loop
  at once, and the old copy's loop runs on until the old copy unloads (the host documents `clock.after`
  loops as running on). For that overlap you may see a duplicate toast. The API gives the old copy no
  unload signal, so nothing retires it earlier.
- A session started outside a checkout polls only after a `/clear` or resume; a `cd` inside the session does not start it.
- A failed start (the environment, the cwd or the file check throws) is shown as
  `harness-workers: start gate failed: <message>` and retried every 30 s; it needs no `/clear`.

## Install

Add the marketplace from the **primary** checkout, the folder where `./install.sh` was run, not from a
lane folder (`harness lane`): a folder marketplace is read live from that folder, and `harness lane rm`
deletes lane folders.

```
/plugin marketplace add ~/workspace/my-claude-harness
/plugin install harness-workers@my-claude-harness
```

Uninstall: `/plugin uninstall harness-workers@my-claude-harness`, then
`/plugin marketplace remove my-claude-harness`.

## Minimum version

Claude Code 2.1.332: the mod API (`ui.render` on `AbovePrompt` with `bodyColumns`, `$.clock.after/every`,
`$.process.run`, `$.ui.toast/notify`, `$.session.cwd`, `$.fs.exists`, `$.env.get`) was checked against
the types of that release; earlier releases were not tried. The harness itself supports >= 2.1.277.

## Tests

`bash tests/mod.test.sh` from the repository root (also part of `./install.sh --test`). The manifest and
field-path checks always run; `claude plugin validate` and the unit and contract tests run only when the
real `claude` binary is found and is at least 2.1.332.

## Troubleshooting

- Nothing appears: no worker is running or recently finished, or the session is not in a harness checkout.
- `harness-workers: harness status did not run`: `harness` is neither on PATH nor in `~/.local/bin`; run `./install.sh`.
- `harness-workers: status format v2 is not supported`: update the mod from the checkout.
