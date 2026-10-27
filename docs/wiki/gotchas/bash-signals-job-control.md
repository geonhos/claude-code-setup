---
type: gotcha
status: active
updated: 2026-10-27
sources: [ask 1792643029-7208-28291, ask 1792569832-86883-26522, ask 1792734325-48033-8131, tests/retro.test.sh:114, bin/harness-run:46, tests/headless.test.sh 16e]
verified_by: human (review repros 1792643029, 1792734325)
---
# INT does not go where you expect in non-interactive bash

**Symptom.** A Ctrl-C/INT test hangs or is a no-op (exit 0 instead of 130); a runner's trap never fires when the terminal sends a signal.

**Cause.** Two bash 3.2 rules. (1) A job started with `&` from a non-interactive shell ignores SIGINT, and bash cannot trap a signal ignored on entry. (2) With `set -m` (job control, used by `bin/harness-run` to give the pipeline its own process group) each foreground command gets its own process group and the tty, so tty signals reach it, not the script's traps. (3) With `set -m` and `stty tostop`, a background pipeline that writes to the tty is stopped by SIGTTOU and the run hangs until the watchdog kills it.

**Fix.** In tests send `kill -TERM`, or reset INT first (`perl -e '$SIG{INT}="DEFAULT"; exec @ARGV' …`). Before relying on a trap in a `set -m` script, check which process group holds the tty. `bin/harness-run` ignores TTOU/TTIN (`trap '' TTOU TTIN`, v19; test headless 16e).
