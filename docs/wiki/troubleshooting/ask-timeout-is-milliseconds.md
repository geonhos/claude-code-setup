---
type: troubleshooting
status: active
updated: 2026-11-27
sources: [harness usage text "--timeout MS", conductor ask 2026-10-21 "after 1s" exit 4, "#275", "#280", ask 1795739030-22568-32643, e8a25ca, tests/ask-args.test.sh:98]
verified_by: human (conductor session 2026-10-21)
---
# `harness ask --timeout` is in milliseconds

**Symptom.** `harness ask implementer '…' --timeout 1200` exits 4 "still working … after 1s" right away.

**Cause.** The value is milliseconds (`--timeout MS`), and the default is the role's headless cap (analyst/reviewer 3600000, implementer 5400000). Passing seconds gives a ~1s deadline. The worker keeps running fine. Test authors fall for it too: the leading-zero case in `tests/ask-args.test.sh` passed `--timeout 007`, i.e. 7 ms, so under parallel load the fake worker lost the race and the Stop hook failed twice in a row (#275, #280); e8a25ca made it `0007000` (:98).

**Fix.** Pass ms (`--timeout 1200000`) and run the ask with `run_in_background: true` and `timeout: 7200000`. If you already got exit 4, don't re-send: `harness wait <role>`, then `harness report <role>`. Defaults are role-aware, so `--timeout` is rarely needed.
