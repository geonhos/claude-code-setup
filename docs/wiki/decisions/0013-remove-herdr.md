---
type: decision
status: active
updated: 2026-11-13
sources: [issue #67, issue #63 §8, decisions/0011-single-runner-headless.md, commit refactor(harness): remove herdr (#67)]
verified_by: tests/headless.test.sh, tests/gate.test.sh, tests/install.test.sh
---
# 0013: Remove herdr from the harness

**Context.** Headless has been the only runner since [0011](0011-single-runner-headless.md). The optional herdr viewer pane was used 3 times in the progress log. Requirement #63 §8 (a user decision) says the harness must not depend on herdr.

**Decision.** Remove herdr: `viewer_mode`, `hl_open_viewer`, `herdr_usable`, `pick_direction`, config key `viewer` and `HARNESS_VIEWER`, the pane column in `.run`/status/close, the gate allow for `herdr pane get|current`, the install.sh herdr step, `tests/fake-herdr`. `harness watch` and `bin/harness-view` stay.

**Status.** Active. Supersedes the viewer parts of [0007](0007-headless-runner-pilot.md) and [0011](0011-single-runner-headless.md) ("herdr is a viewer").

**Consequences.**
- The user watches a run with `harness watch <role>` in any terminal; a future `/watch` skill will print that command.
- `.harness/config.json` keeps only `headless_max_minutes`; a leftover `viewer` key is ignored.
- Old `progress.jsonl` close lines with a `pane` field are still read by metrics (`by_runner` maps a missing runner to "pane").
- Decisions 0001-0011 keep their herdr wording as history.
