---
type: troubleshooting
status: active
updated: 2026-10-21
sources: [commit 2e1764a, reviewer report 2026-10-21 (docker alpine coreutils check)]
verified_by: tests/harness.test.sh (fake GNU/BSD stat on PATH)
---
# `stat -f %m` is not portable

**Symptom.** On Linux, no ask ever completes: every ask waits out the grace period and exits 3.

**Cause.** On BSD/macOS, `stat -f %m` is the mtime. On GNU, `-f` means filesystem mode and prints multi-line junk. A `stat -f %m f || stat -c %Y f` fallback never reaches the second form because the first one "succeeds".

**Fix.** Prefer the bash builtins `-nt`/`-ot` for comparisons. When an epoch is needed, try `stat -c %Y` first, then `stat -f %m`, and accept the result only if it is all digits.
