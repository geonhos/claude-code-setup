---
type: decision
status: active
updated: 2026-11-01
sources: [.harness/herdr-optional-design.md, .harness/pr2-gate-design.md, PR #36, claude/hooks/conductor-gate.sh, bin/harness]
verified_by: tests/gate.test.sh, tests/harness.test.sh, tests/install.test.sh
---
# 0010: herdr optional; the harness acts only in a harness checkout

**Context.** 0005 step 1 turned the gate off outside herdr because `harness ask` died there.
PR #36 removed that: headless asks run without herdr (background, `viewer: auto|pane|none`).
The user rejected the alternative "gate every session in every repo" (2026-10-30): the
harness must never interfere with repos that do not use it.

**Decision.**
1. herdr is optional for headless runs (PR 1, #36, done). The pane runner still needs herdr.
2. A *harness checkout* is the nearest dir with `.harness/asks/`, from the cwd up to the dir
   holding `.git` (outside git: the cwd only); the same rule as harness-verify `enter_root`.
   `harness init` creates it; `ask` and `spawn` refuse without it.
3. The gate, route and resume hooks are no-ops outside a harness checkout, checked before
   jq and parsing. Inside one, the gate keys on agent_type / agent_id / HARNESS_ROLE (0005
   steps 2-4; steps 2-3 now apply only inside a checkout). No env switch: `HERDR_ENV` is ignored.
4. The conductor agent is set per repo by `harness init` (`.claude/settings.local.json`,
   per user and untracked; `--shared` writes `.claude/settings.json`; `"agent": "conductor"`;
   `--no-agent` skips it; a symlinked file stays a symlink, a `.bak` is made once). The global `agent` key is gone:
   `install.sh` removes a previous `agent: conductor` once, `harness doctor --fix` too.
5. `harness doctor [--fix]` lists and removes pollution of older versions (stray
   `.harness/` without `asks/`); it skips directories holding unknown files.
6. `harness wait <role|ask-id>` blocks until the run ends (exit 0 done, 3 no ask / runner died, 4 timeout; never collects) and `harness watch` is a human-terminal viewer (refused without a tty and denied to the conductor by the gate). A background `harness ask` waits exactly the headless cap, so its Bash notification wakes the conductor; `harness report` while alive says `still running (<n>s); harness wait <role> blocks until done`. The Stop hook blocks a worker that stops without a fresh report (twice per ask, `[no-report]` opts out).

**Status.** Active (PR 3, prune step 2).

**Consequences.**
- A fresh clone is ungated until `harness init`.
- A conductor in a `--worktree` checkout is gated (worktrees get `.harness/asks/`).
- Outside a checkout the conductor prompt and its disallowedTools still apply only if
  the session was started with `--agent conductor`; plain sessions are untouched.
- A stray `.harness/config.json` without `asks/` no longer gates or logs anything.
