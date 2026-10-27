---
type: troubleshooting
status: active
updated: 2026-10-27
sources: [ask 1792736624-54926-6076, ask 1792742736-43975-21167, tests/worktree.test.sh:36-38]
verified_by: /bin/bash -c 'n=$(grep -c x /nonexistent 2>/dev/null); [ "$n" -lt 1 ]' → "integer expression expected", rc 2
---
# A test wait loop that exits at once

**Symptom.** A parallel test fails 1 in 4 runs (2/8 seen) on a registry assertion; the wait helper returned without waiting.

**Cause.** (1) The loop waited on the wrong state (pid file) instead of the state the assertion reads (registered pane). (2) `grep -c pat missing-file` prints nothing, so `[ "$(grep -c …)" -lt N ]` is a bash error (rc 2), the `while` condition is false and the loop ends immediately. zsh treats "" as 0, so it only fails under bash.

**Fix.** (Fixed for `wait_panes` in tests/worktree.test.sh in v19, PR #24; keep the pattern for new helpers.) Barrier on exactly what the next check reads, and default the count: `n=$(grep -c … 2>/dev/null); [ "${n:-0}" -lt N ]`, or `cat f 2>/dev/null | grep -c`.
