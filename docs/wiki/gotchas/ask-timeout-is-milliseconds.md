---
type: gotcha
status: active
updated: 2026-10-21
sources: [harness usage text "--timeout MS", conductor ask 2026-10-21 "after 1s" exit 4]
verified_by: human (conductor session 2026-10-21)
---
# `harness ask --timeout` is in milliseconds

**Symptom.** `harness ask implementer '…' --timeout 1200` exits 4 "still working … after 1s" right away.

**Cause.** The value is milliseconds (`--timeout MS`), and the default is 600000 (implementer 1740000). Passing seconds gives a ~1s deadline. The worker keeps running fine.

**Fix.** Pass ms (`--timeout 1200000`) and raise the Bash tool timeout above it. If you already got exit 4, don't re-send: wait with `herdr agent wait <role>-<repo8>`, then `harness report <role>`.
