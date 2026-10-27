---
type: troubleshooting
status: active
updated: 2026-10-21
sources: [session 7ad04a14 (ps eww of claude daemon pid 90516), claude/hooks/conductor-gate.sh:10]
verified_by: human (ps eww -p <daemon pid>)
---
# Claude daemon inherits a worker's env

**Symptom.** A session named `conductor` behaves as a worker. The gate never
denies, and `harness ask` exits 1 with "harness ask/spawn is for the conductor;
a worker (HARNESS_ROLE=worker) ...". `printenv` shows `HARNESS_ROLE=worker`, a
`HERDR_PANE_ID` that `herdr pane get` reports as `pane_not_found`, and `HERDR_ENV=1`.

**Cause.** Background/resumed sessions run under `claude daemon run`
(`--bg-pty-host`). The daemon keeps the env of the shell that first started it.
If that was a worker pane (spawned with `--env HARNESS_ROLE=worker`), every
session it hosts later inherits the worker role and the dead pane's ids.

**Fix.**
- Check `ps eww -p <daemon pid> | tr ' ' '\n' | grep HARNESS_ROLE`. The daemon
  pid is the parent of the session's `--bg-pty-host` process.
- Stop that daemon process and start the conductor again from a plain shell in
  a herdr pane, so a fresh daemon gets a clean env.
- A gate that trusts env (decision 0005) cannot detect this. Do not build on
  `HARNESS_ROLE` alone for anything security-like.

**Evidence.** 2026-10-21: daemon pid 90516 (started 12:21) had
`HARNESS_ROLE=worker HERDR_PANE_ID=w8:p9`. The conductor session forked from it
ran ungated, and the v11 review fixes (commit 174e159) landed without a reviewer.
