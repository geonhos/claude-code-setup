---
type: troubleshooting
status: active
updated: 2026-10-27
sources: [harness usage text "--timeout MS", conductor ask 2026-10-21 "after 1s" exit 4]
verified_by: human (conductor session 2026-10-21)
---
# `harness ask --timeout` is in milliseconds

**Symptom.** `harness ask implementer '…' --timeout 1200` exits 4 "still working … after 1s" right away.

**Cause.** The value is milliseconds (`--timeout MS`), and the default is the role's headless cap (analyst/reviewer 3600000, implementer 5400000). Passing seconds gives a ~1s deadline. The worker keeps running fine.

**Fix.** Pass ms (`--timeout 1200000`) and run the ask with `run_in_background: true`. If you already got exit 4, don't re-send: `harness wait <role>`, then `harness report <role>`. Defaults are role-aware, so `--timeout` is rarely needed.
