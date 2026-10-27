---
type: troubleshooting
status: active
updated: 2026-10-27
sources: [ask 1792676397-36997-12668, commit 7bfe1ed, tests/harness-lib.sh:7, tests/route.test.sh:5]
verified_by: tests/route.test.sh
---
# Test suites inherit `HARNESS_ROLE=worker`

**Symptom.** A suite passes in a plain shell but fails when an implementer (or the Stop hook) runs it: conductor-only paths refuse with "for the conductor; a worker ...", the gate allows everything.

**Cause.** Workers run with `HARNESS_ROLE=worker`, and `install.sh --test` and every suite inherit it.

**Fix.** A suite that runs `bin/harness`, a hook or the gate must clear the role: `env -u HARNESS_ROLE` (as `tests/harness-lib.sh` does) or `unset HARNESS_ROLE` at the top, and set it explicitly only in worker cases.
