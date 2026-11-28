---
type: decision
status: active
updated: 2026-11-27
sources: [issue #67, issue #63 §8, decisions/0011-single-runner-headless.md, commit 74249a0, "#257", lib/harness-openwatch.sh:13-17, "#305"]
verified_by: tests/headless.test.sh, tests/gate.test.sh, tests/install.test.sh, tests/openwatch.test.sh (herdr backend)
---
# 0013: Remove herdr from the harness

**Context.** Headless has been the only runner since [0011](0011-single-runner-headless.md). The optional herdr viewer pane was used 3 times in the progress log. Requirement #63 §8 (a user decision) says the harness must not depend on herdr.

**Decision.** Remove herdr: `viewer_mode`, `hl_open_viewer`, `herdr_usable`, `pick_direction`, config key `viewer` and `HARNESS_VIEWER`, the pane column in `.run`/status/close, the gate allow for `herdr pane get|current`, the install.sh herdr step, `tests/fake-herdr`. `harness watch` and `bin/harness-view` stay.

**Status.** Active. Supersedes the viewer parts of [0007](0007-headless-runner-pilot.md) and [0011](0011-single-runner-headless.md) ("herdr is a viewer").

**Consequences.**
- The user watches a run with `harness watch <role>` in any terminal; a future `/watch` skill will print that command. (2026-11: `/watch` exists; `harness open-watch` opens a herdr/tmux pane or a Ghostty/Terminal window.)
- `.harness/config.json` keeps only `headless_max_minutes`; a leftover `viewer` key is ignored.
- Old `progress.jsonl` close lines with a `pane` field are still read by metrics (`by_runner` maps a missing runner to "pane").
- Decisions 0001-0011 keep their herdr wording as history.

**Amendment 2026-11-26 (user decision, #257).** Herdr was removed from the runner, the gate and `install.sh`. It stays allowed as the first backend of `harness open-watch`: when `HERDR_ENV` is set and `herdr` is on PATH, `lib/harness-openwatch.sh` (lines 22-26) opens the watch in a herdr pane, and falls through to tmux, Ghostty or Terminal if that fails. The sentence "the harness must not depend on herdr" holds: nothing needs herdr, and `harness watch` works in any terminal. `tests/openwatch.test.sh` covers the herdr backend.

**Amendment 2026-11-27 (#305).** The Ghostty and Terminal.app backends were removed (0 of 13 real uses); `harness open-watch` now tries herdr (`lib/harness-openwatch.sh` lines 13-17), then tmux.
