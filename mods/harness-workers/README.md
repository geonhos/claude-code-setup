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
  rows do not fit `maxRows`, the current step of each worker has priority and the band ends in `+N more`.
- A toast on every worker exit; a native notification only when it failed (rc ≠ 0, dead, verify fail).
- If the status format is not version 1, `harness status` fails or times out, one dim row
  `harness-workers: <reason>` is drawn and polling continues slowly.
- It does nothing when `HARNESS_ROLE=worker` or when the session's cwd has no `.harness/asks`.
- Polling: every 3 s while a worker runs, every 30 s otherwise, never two runs at once; a 1 s clock
  tick only while a worker runs. It draws only: it never writes a file or puts text into the conversation.

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
real `claude` binary is found.

## Troubleshooting

- Nothing appears: no worker is running or recently finished, or the session is not in a harness checkout.
- `harness-workers: harness status did not run`: `harness` is neither on PATH nor in `~/.local/bin`; run `./install.sh`.
- `harness-workers: status format v2 is not supported`: update the mod from the checkout.
